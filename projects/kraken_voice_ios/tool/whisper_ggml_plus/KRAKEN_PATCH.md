whisper_ggml_plus 1.5.2, restricted to the iOS files used by this project.
Simulator builds set whisper_context_params.use_gpu=false because the package's
precompiled iPhone Metal kernels cannot execute in Simulator. Hardware builds
retain the original use_gpu=true. Dart APIs and model bytes are unchanged.
