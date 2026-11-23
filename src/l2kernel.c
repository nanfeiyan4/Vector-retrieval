/* Standalone L2 distance kernel, used for static micro-architectural analysis
 * with llvm-mca when hardware PMU counters are unavailable (cloud VM). */
void l2_kernel(const float *a, const float *b, float *out, int dim) {
  float s = 0.f;
  for (int i = 0; i < dim; ++i) {
    float d = a[i] - b[i];
    s += d * d;
  }
  *out = s;
}
