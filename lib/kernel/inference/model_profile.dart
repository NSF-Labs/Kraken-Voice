/// Paired with Android ReleaseHardware/HexagonBridge. Other profiles require
/// device validation before they can be selected; there is no CPU fallback.
abstract final class ModelProfile {
  static const gpu = bool.fromEnvironment('KRAKEN_S24_GPU');
  static const npuBuild = '1.0.14-npu-sm8850+14';
  static const build = gpu ? '1.0.15-gpu-sm8650+15' : npuBuild;
  static const label = gpu
      ? 'Gemma 4 · Adreno GPU · S24'
      : 'Gemma 4 · Hexagon NPU · SM8850';
  static const npuFilename = 'gemma4-e2b-w4.gguf';
  static const filename = gpu ? 'gemma4-e2b-gpu.litertlm' : npuFilename;
  static const bytes = gpu ? 2008432640 : 2620370976;
  static const contextWindow = 4096;
  static const maxOutputTokens = 2048;
  static const url = gpu
      ? 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it-gpu.litertlm'
      : 'https://huggingface.co/h2loop-ai/gemma-4-e2b-hexagon/'
            'resolve/1bb2044c313769541558f2c27fa67561894d0f26/gemma4-e2b-w4.gguf';
}
