// Vector search service: TCP server over hnswlib (HNSW), binary protocol.
// Usage:
//   ./vecserver --data base.f32 --index index.bin --dim 128 --ef 64 --M 16 --efc 200 \
//               --threads 8 --port 9000 [--rebuild] [--nodelay] [--busypoll US]
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>
#include <atomic>

#include "hnswlib/hnswlib.h"

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

static float* load_f32(const char* path, size_t* n, int dim) {
  FILE* f = fopen(path, "rb");
  if (!f) { perror(path); exit(1); }
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  *n = (size_t)sz / (sizeof(float) * dim);
  void* buf = nullptr;
  if (posix_memalign(&buf, 64, (size_t)sz) != 0) { fprintf(stderr, "alloc fail\n"); exit(1); }
  if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fprintf(stderr, "short read %s\n", path); exit(1); }
  fclose(f);
  return (float*)buf;
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

static std::atomic<uint64_t> g_requests{0};

static void serve_conn(int fd, hnswlib::HierarchicalNSW<float>* idx, int dim) {
  std::vector<float> qbuf;
  std::vector<uint32_t> ids;
  for (;;) {
    uint32_t hdr[2];
    if (!read_exact(fd, hdr, sizeof(hdr))) break;
    uint32_t nq = hdr[0], k = hdr[1];
    if (nq == 0 || nq > 4096 || k == 0 || k > 512) break;
    qbuf.resize((size_t)nq * dim);
    if (!read_exact(fd, qbuf.data(), qbuf.size() * sizeof(float))) break;
    ids.resize((size_t)nq * k);
    for (uint32_t i = 0; i < nq; ++i) {
      auto res = idx->searchKnn(qbuf.data() + (size_t)i * dim, k);
      for (int j = (int)k - 1; j >= 0; --j) {
        ids[(size_t)i * k + j] = (uint32_t)res.top().second;
        res.pop();
      }
    }
    if (!write_exact(fd, ids.data(), ids.size() * sizeof(uint32_t))) break;
    g_requests.fetch_add(1, std::memory_order_relaxed);
  }
  ::close(fd);
}

int main(int argc, char** argv) {
  const char* data_path = arg_s(argc, argv, "--data", "base.f32");
  const char* index_path = arg_s(argc, argv, "--index", "index.bin");
  const int dim = (int)arg_i(argc, argv, "--dim", 128);
  const int M = (int)arg_i(argc, argv, "--M", 16);
  const int efc = (int)arg_i(argc, argv, "--efc", 200);
  const int ef = (int)arg_i(argc, argv, "--ef", 64);
  const int nthreads = (int)arg_i(argc, argv, "--threads", 8);
  const int port = (int)arg_i(argc, argv, "--port", 9000);
  const int busypoll = (int)arg_i(argc, argv, "--busypoll", 0);
  const bool nodelay = arg_f(argc, argv, "--nodelay");
  const bool rebuild = arg_f(argc, argv, "--rebuild");
  const char* ready = arg_s(argc, argv, "--ready", "");

  hnswlib::L2Space space(dim);
  hnswlib::HierarchicalNSW<float>* idx = nullptr;

  FILE* test = fopen(index_path, "rb");
  bool have_index = (test != nullptr);
  if (test) fclose(test);

  if (have_index && !rebuild) {
    fprintf(stderr, "[server] loading index %s\n", index_path);
    idx = new hnswlib::HierarchicalNSW<float>(&space, index_path);
  } else {
    size_t n = 0;
    fprintf(stderr, "[server] loading base vectors %s\n", data_path);
    float* base = load_f32(data_path, &n, dim);
    fprintf(stderr, "[server] building index n=%zu M=%d efc=%d threads=%d\n", n, M, efc, nthreads);
    double t0 = (double)clock() / CLOCKS_PER_SEC;
    idx = new hnswlib::HierarchicalNSW<float>(&space, n, M, efc);
    std::vector<std::thread> builders;
    for (int t = 0; t < nthreads; ++t) {
      builders.emplace_back([&, t]() {
        for (size_t i = (size_t)t; i < n; i += (size_t)nthreads)
          idx->addPoint(base + i * dim, (hnswlib::labeltype)i);
      });
    }
    for (auto& b : builders) b.join();
    double t1 = (double)clock() / CLOCKS_PER_SEC;
    fprintf(stderr, "[server] index built in %.1f s (cpu), %zu points\n", t1 - t0, n);
    idx->saveIndex(index_path);
    fprintf(stderr, "[server] index saved to %s\n", index_path);
    free(base);
  }
  idx->setEf((size_t)ef);
  fprintf(stderr, "[server] ready: ef=%d threads=%d port=%d nodelay=%d busypoll=%d\n",
          ef, nthreads, port, (int)nodelay, busypoll);

  std::vector<int> fds;
  for (int t = 0; t < nthreads; ++t) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); exit(1); }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((uint16_t)port);
    if (bind(fd, (sockaddr*)&addr, sizeof(addr)) < 0) { perror("bind"); exit(1); }
    if (listen(fd, 1024) < 0) { perror("listen"); exit(1); }
    fds.push_back(fd);
  }
  if (ready[0]) {
    FILE* f = fopen(ready, "w");
    if (f) { fprintf(f, "ready\n"); fclose(f); }
  }

  std::vector<std::thread> workers;
  for (int t = 0; t < nthreads; ++t) {
    workers.emplace_back([&, t]() {
      for (;;) {
        int c = accept(fds[t], nullptr, nullptr);
        if (c < 0) continue;
        if (nodelay) {
          int one = 1;
          setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        }
        if (busypoll > 0) {
          int us = busypoll;
#ifdef SO_BUSY_POLL
          setsockopt(c, SOL_SOCKET, SO_BUSY_POLL, &us, sizeof(us));
#endif
        }
        serve_conn(c, idx, dim);
      }
    });
  }
  for (auto& w : workers) w.join();
  fprintf(stderr, "[server] served %llu requests\n", (unsigned long long)g_requests.load());
  return 0;
}
