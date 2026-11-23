// Sanity probe: load the index directly and compare search results with ground truth.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "hnswlib/hnswlib.h"

static float* load(const char* p, size_t* n, int dim) {
  FILE* f = fopen(p, "rb");
  if (!f) { perror(p); exit(1); }
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  *n = (size_t)sz / (4 * dim);
  float* b = (float*)malloc((size_t)sz);
  if (fread(b, 1, (size_t)sz, f) != (size_t)sz) exit(1);
  fclose(f);
  return b;
}

int main(int argc, char** argv) {
  const int dim = 128;
  size_t nb = 0, nq = 0;
  float* base = load(argv[1], &nb, dim);
  float* query = load(argv[2], &nq, dim);
  const char* idxpath = argv[3];
  hnswlib::L2Space space(dim);
  hnswlib::HierarchicalNSW<float>* idx = new hnswlib::HierarchicalNSW<float>(&space, idxpath);
  fprintf(stderr, "index elements: %zu\n", idx->cur_element_count.load());
  idx->setEf(64);
  int k = 10;
  // brute force for query 0
  std::vector<std::pair<float, int>> bf;
  for (size_t i = 0; i < nb; ++i) {
    float s = 0;
    for (int d = 0; d < dim; ++d) {
      float t = base[i * dim + d] - query[d];
      s += t * t;
    }
    bf.push_back({s, (int)i});
  }
  std::partial_sort(bf.begin(), bf.begin() + k, bf.end());
  auto res = idx->searchKnn(query, k);
  printf("hnsw ids: ");
  std::vector<int> got;
  while (!res.empty()) { got.push_back((int)res.top().second); res.pop(); }
  for (auto it = got.rbegin(); it != got.rend(); ++it) printf("%d ", *it);
  printf("\nbrute ids: ");
  for (int i = 0; i < k; ++i) printf("%d ", bf[i].second);
  printf("\nlabel of base[0] sanity: top1 dist hnsw=%.3f brute=%.3f\n", 0.0, bf[0].first);
  return 0;
}
