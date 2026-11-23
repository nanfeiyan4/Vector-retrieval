// Closed-loop load generator for vecserver (binary protocol) with recall@k report.
// Usage:
//   ./vecclient --host 127.0.0.1 --port 9000 --threads 8 --nq 1 --k 10 \
//               --queries query.f32 --nqtotal 20000 --gt gt.i32 [--warmup 1000] [--csv out.csv]
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

static long arg_i(int argc, char** argv, const char* n, long d) {
  for (int i = 1; i + 1 < argc; ++i) if (!strcmp(argv[i], n)) return atol(argv[i + 1]);
  return d;
}
static const char* arg_s(int argc, char** argv, const char* n, const char* d) {
  for (int i = 1; i + 1 < argc; ++i) if (!strcmp(argv[i], n)) return argv[i + 1];
  return d;
}
static bool arg_f(int argc, char** argv, const char* n) {
  for (int i = 1; i < argc; ++i) if (!strcmp(argv[i], n)) return true;
  return false;
}

static int connect_to(const char* host, int port) {
  for (int attempt = 0; attempt < 100; ++attempt) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_port = htons((uint16_t)port);
    inet_pton(AF_INET, host, &a.sin_addr);
    if (connect(fd, (sockaddr*)&a, sizeof(a)) == 0) {
      int one = 1;
      setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
      return fd;
    }
    close(fd);
    usleep(100000);
  }
  return -1;
}

static bool read_exact(int fd, void* b, size_t n) {
  size_t off = 0; char* p = (char*)b;
  while (off < n) {
    ssize_t r = ::read(fd, p + off, n - off);
    if (r <= 0) return false;
    off += (size_t)r;
  }
  return true;
}
static bool write_exact(int fd, const void* b, size_t n) {
  size_t off = 0; const char* p = (const char*)b;
  while (off < n) {
    ssize_t r = ::write(fd, p + off, n - off);
    if (r <= 0) return false;
    off += (size_t)r;
  }
  return true;
}

static double now_s() {
  using namespace std::chrono;
  return duration<double>(steady_clock::now().time_since_epoch()).count();
}

int main(int argc, char** argv) {
  const char* host = arg_s(argc, argv, "--host", "127.0.0.1");
  const int port = (int)arg_i(argc, argv, "--port", 9000);
  const int threads = (int)arg_i(argc, argv, "--threads", 4);
  const int nq = (int)arg_i(argc, argv, "--nq", 1);
  const int k = (int)arg_i(argc, argv, "--k", 10);
  const int dim = (int)arg_i(argc, argv, "--dim", 128);
  const long nqtotal = arg_i(argc, argv, "--nqtotal", 20000);
  const long warmup = arg_i(argc, argv, "--warmup", 0);
  const char* qpath = arg_s(argc, argv, "--queries", "query.f32");
  const char* gpath = arg_s(argc, argv, "--gt", "");
  const char* csvpath = arg_s(argc, argv, "--csv", "");

  FILE* f = fopen(qpath, "rb");
  if (!f) { perror(qpath); return 1; }
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  const int nq_all = (int)(sz / (sizeof(float) * dim));
  std::vector<float> queries((size_t)sz / sizeof(float));
  if (fread(queries.data(), 1, (size_t)sz, f) != (size_t)sz) { fprintf(stderr, "short read\n"); return 1; }
  fclose(f);

  int gt_k = 0;
  std::vector<int32_t> gt;
  if (gpath[0]) {
    FILE* g = fopen(gpath, "rb");
    if (!g) { perror(gpath); return 1; }
    fseek(g, 0, SEEK_END);
    long gsz = ftell(g);
    fseek(g, 0, SEEK_SET);
    int rows = nq_all;
    gt_k = (int)(gsz / (sizeof(int32_t) * (long)rows));
    gt.resize((size_t)rows * gt_k);
    if (fread(gt.data(), 1, (size_t)gsz, g) != (size_t)gsz) { fprintf(stderr, "short gt read\n"); return 1; }
    fclose(g);
  }

  const long requests_total = (long)std::ceil((double)nqtotal / nq);
  std::atomic<long> next_req{0};
  std::vector<std::vector<double>> lat(threads);
  std::vector<uint32_t> answers;  // [query][k], only if gt
  if (gt_k) answers.assign((size_t)nq_all * k, 0xFFFFFFFFu);
  std::atomic<long> errors{0};

  auto worker = [&](int t) {
    int fd = connect_to(host, port);
    if (fd < 0) { errors.fetch_add(1); return; }
    std::vector<float> buf((size_t)nq * dim);
    std::vector<uint32_t> ids((size_t)nq * k);
    uint32_t hdr[2];
    hdr[0] = (uint32_t)nq;
    hdr[1] = (uint32_t)k;
    std::vector<double>& L = lat[t];
    uint32_t rng = 12345u + (uint32_t)t * 7919u;
    long my_req = 0;
    for (;;) {
      long r = next_req.fetch_add(1);
      if (r >= requests_total) break;
      if (r < warmup && warmup > 0) { /* still send, but do not record */ }
      uint32_t qids[64];
      for (int j = 0; j < nq; ++j) {
        rng = rng * 1664525u + 1013904223u;
        uint32_t qi = (rng >> 8) % (uint32_t)nq_all;
        qids[j] = qi;
        memcpy(buf.data() + (size_t)j * dim, queries.data() + (size_t)qi * dim, sizeof(float) * dim);
      }
      double t0 = now_s();
      bool ok = write_exact(fd, hdr, sizeof(hdr)) &&
                write_exact(fd, buf.data(), buf.size() * sizeof(float)) &&
                read_exact(fd, ids.data(), ids.size() * sizeof(uint32_t));
      double t1 = now_s();
      if (!ok) { errors.fetch_add(1); break; }
      my_req++;
      if (r >= warmup) L.push_back((t1 - t0) * 1e6);
      if (gt_k) {
        for (int j = 0; j < nq; ++j) {
          uint32_t qi = qids[j];
          for (int c = 0; c < k; ++c) answers[(size_t)qi * k + c] = ids[(size_t)j * k + c];
        }
      }
    }
    close(fd);
  };

  std::vector<std::thread> ts;
  double t_start = now_s();
  for (int t = 0; t < threads; ++t) ts.emplace_back(worker, t);
  for (auto& th : ts) th.join();
  double t_end = now_s();
  double wall = t_end - t_start;

  std::vector<double> all;
  size_t total = 0;
  for (auto& L : lat) { total += L.size(); }
  all.reserve(total);
  for (auto& L : lat) all.insert(all.end(), L.begin(), L.end());
  if (all.empty()) { fprintf(stderr, "no samples\n"); return 1; }
  std::sort(all.begin(), all.end());
  auto pct = [&](double p) { return all[(size_t)std::min((double)all.size() - 1, p * (double)all.size())]; };
  double qps = (double)(total * (long)nq) / wall;
  double recall = -1.0;
  if (gt_k) {
    long hit = 0, cnt = 0;
    for (int q = 0; q < nq_all; ++q) {
      if (answers[(size_t)q * k] == 0xFFFFFFFFu) continue;
      cnt++;
      for (int c = 0; c < k; ++c) {
        for (int g = 0; g < std::min(k, gt_k); ++g) {
          if (answers[(size_t)q * k + c] == (uint32_t)gt[(size_t)q * gt_k + g]) { hit++; break; }
        }
      }
    }
    recall = cnt ? (double)hit / ((double)cnt * k) : 0.0;
  }
  printf("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%zu,%.4f,%ld\n",
         qps, pct(0.50), pct(0.90), pct(0.95), pct(0.99), all.back(), total, recall, errors.load());
  if (csvpath[0]) {
    FILE* c = fopen(csvpath, "a");
    if (c) {
      fprintf(c, "%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%zu,%.4f,%ld\n",
              qps, pct(0.50), pct(0.90), pct(0.95), pct(0.99), all.back(), total, recall, errors.load());
      fclose(c);
    }
  }
  return 0;
}
