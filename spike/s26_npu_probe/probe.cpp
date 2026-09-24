// Isolated device probe against RunAnywhere 0.20.19's native backend test ABI.
// Only the QHexRT vtable is called: no CPU/GPU backend is registered or selected.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>
#include "rac/features/llm/rac_llm_service.h"
#include "rac/qhexrt/rac_qhexrt.h"
extern "C" const rac_llm_service_ops_t g_qhexrt_llm_ops;
static long long now() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
}
int main(int argc, char** argv) {
  setbuf(stdout, nullptr);
  if (argc != 2) { fprintf(stderr, "Usage: probe MANIFEST\n"); return 2; }
  alarm(300); // Bound an unresponsive vendor runtime without touching any app.
  rac_qhexrt_device_info_t device{};
  int rc = rac_qhexrt_probe(&device);
  printf("NPU_PROBE rc=%d soc=%s arch=%d supported=%d\n", rc,
         device.soc_model, device.hexagon_arch, device.supported);
  if (rc || device.hexagon_arch != RAC_QHEXRT_HEXAGON_ARCH_V81 || !device.supported) return 3;
  void* handle = nullptr;
  auto start = now();
  rc = g_qhexrt_llm_ops.create(argv[1], nullptr, &handle);
  printf("NPU_LOAD rc=%d ms=%lld\n", rc, now()-start);
  if (rc || !handle) return 4;
  auto options = RAC_LLM_OPTIONS_DEFAULT;
  options.max_tokens = 48;
  options.temperature = 0;
  options.seed = 42;
  if (const char* penalty = getenv("PROBE_REPEAT_PENALTY")) {
    options.repetition_penalty = std::stof(penalty);
  }
  printf("NPU_OPTIONS repeat_penalty=%.2f\n", options.repetition_penalty);
  const char* prompts[] = {
    "Answer in one sentence: What is the capital of France?",
    "Meeting decision: Approve a budget of 42750 dollars. Maya must deliver the audit by October 16. Summarize the amount, owner and deadline in one sentence.",
    "Answer in one sentence: What is 17 plus 25?"
  };
  int failed = 0;
  for (int i=0; i<3; ++i) {
    rac_llm_result_t result{};
    start = now();
    rc = g_qhexrt_llm_ops.generate(handle, prompts[i], &options, &result);
    std::string text = result.text ? result.text : "";
    bool correct = !rc && !text.empty();
    if (i==0) correct &= text.find("Paris")!=std::string::npos;
    if (i==1) correct &= text.find("Maya")!=std::string::npos && text.find("16")!=std::string::npos &&
       (text.find("42750")!=std::string::npos || text.find("42,750")!=std::string::npos);
    if (i==2) correct &= text.find("42")!=std::string::npos;
    printf("NPU_CASE case=%d rc=%d wall_ms=%lld ttft_ms=%lld tokens=%d tps=%.2f correct=%d output=%s\n",
      i, rc, now()-start, (long long)result.time_to_first_token_ms,
      result.completion_tokens, result.tokens_per_second, correct, text.c_str());
    failed += !correct;
    rac_llm_result_free(&result);
  }
  printf("NPU_RESULT failed=%d\n", failed);
  // Vendor runtime recommends process exit between models. No soft reload.
  return failed ? 5 : 0;
}
