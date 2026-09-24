#include "llama.h"
#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <string>
#include <vector>
#include <stdexcept>
#include <algorithm>

// All operations except cancellation run on the Kotlin bridge's single worker.
static llama_model *model = nullptr;
static llama_context *ctx = nullptr;
static std::atomic<bool> cancelled{false};
static bool initialized = false;
static void fail(JNIEnv *env, const char *message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}
static std::string bytes(JNIEnv *env, jbyteArray input) {
    std::string out(env->GetArrayLength(input), '\0');
    env->GetByteArrayRegion(input, 0, out.size(), reinterpret_cast<jbyte *>(out.data()));
    return out;
}
static void unload() {
    if (ctx) llama_free(ctx);
    if (model) llama_model_free(model);
    ctx = nullptr; model = nullptr;
}
static std::vector<llama_token> tokenize(const std::string &s, bool special) {
    const auto *vocab = llama_model_get_vocab(model);
    int n = llama_tokenize(vocab, s.data(), s.size(), nullptr, 0, false, special);
    std::vector<llama_token> out(std::abs(n));
    n = llama_tokenize(vocab, s.data(), s.size(), out.data(), out.size(), false, special);
    if (n < 0) throw std::runtime_error("Tokenization failed");
    out.resize(n); return out;
}
static std::vector<llama_token> promptTokens(const std::string &prompt) {
    // Exact pinned Gemma 4 single-user template with enable_thinking=false.
    // User content is tokenized separately so literal control strings remain text.
    auto out = tokenize("<bos><|turn>user\n", true);
    auto body = tokenize(prompt, false);
    auto tail = tokenize("<turn|>\n<|turn>model\n", true);
    out.insert(out.end(), body.begin(), body.end());
    out.insert(out.end(), tail.begin(), tail.end());
    return out;
}
extern "C" JNIEXPORT void JNICALL
Java_org_krak_1en_voice_HexagonBridge_nativeLoad(JNIEnv *env, jobject, jbyteArray path, jbyteArray libs) {
    try {
        unload();
        const auto dir = bytes(env, libs);
        if (!initialized) {
            const auto adsp = dir + ";/system/lib/rfsa/adsp;/vendor/lib/rfsa/adsp";
            setenv("ADSP_LIBRARY_PATH", adsp.c_str(), 1);
            llama_log_set([](ggml_log_level, const char *s, void *) {
                __android_log_write(ANDROID_LOG_INFO, "KrakenNPU", s);
            }, nullptr);
            ggml_backend_load((dir + "/libggml-cpu.so").c_str());
            ggml_backend_load((dir + "/libggml-hexagon.so").c_str());
            llama_backend_init();
            initialized = true;
        }
        auto htp = ggml_backend_dev_by_name("HTP0");
        if (!htp) throw std::runtime_error("Hexagon HTP0 is unavailable; CPU fallback is disabled");
        ggml_backend_dev_t devices[] = {htp, nullptr};
        auto mp = llama_model_default_params();
        mp.devices = devices; mp.n_gpu_layers = 99;
        model = llama_model_load_from_file(bytes(env, path).c_str(), mp);
        if (!model) throw std::runtime_error("Could not load the pinned Gemma Hexagon model");
        auto cp = llama_context_default_params();
        cp.n_ctx = 4096; cp.n_batch = 2048; cp.n_ubatch = 512;
        cp.n_seq_max = 1; cp.n_threads = 6; cp.n_threads_batch = 6;
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        cp.type_k = GGML_TYPE_F16; cp.type_v = GGML_TYPE_F16;
        ctx = llama_init_from_model(model, cp);
        if (!ctx) throw std::runtime_error("Could not initialize the Hexagon context");
        __android_log_write(ANDROID_LOG_INFO, "KrakenNPU", "READY profile=gemma4-hexagon-v81 backend=HTP0 context=4096 thinking=off");
    } catch (const std::exception &e) { unload(); fail(env, e.what()); }
}
extern "C" JNIEXPORT void JNICALL
Java_org_krak_1en_voice_HexagonBridge_nativeUnload(JNIEnv *, jobject) { unload(); }
extern "C" JNIEXPORT void JNICALL
Java_org_krak_1en_voice_HexagonBridge_nativeCancel(JNIEnv *, jobject) { cancelled = true; }
extern "C" JNIEXPORT void JNICALL
Java_org_krak_1en_voice_HexagonBridge_nativeResetCancel(JNIEnv *, jobject) { cancelled = false; }
extern "C" JNIEXPORT jint JNICALL
Java_org_krak_1en_voice_HexagonBridge_nativeCount(JNIEnv *env, jobject, jbyteArray prompt) {
    try {
        if (!model) throw std::runtime_error("Model is not loaded");
        return promptTokens(bytes(env, prompt)).size();
    } catch (const std::exception &e) { fail(env, e.what()); return 0; }
}
extern "C" JNIEXPORT void JNICALL
Java_org_krak_1en_voice_HexagonBridge_nativeGenerate(JNIEnv *env, jobject self, jbyteArray prompt, jint limit, jboolean autoContinue) {
    llama_sampler *sampler = nullptr;
    try {
        if (!ctx) throw std::runtime_error("Model is not loaded");
        auto tokens = promptTokens(bytes(env, prompt));
        if (limit < 1 || tokens.size() + limit > 4096)
            throw std::runtime_error("Prompt and output exceed the 4096-token context. Split the transcript into smaller sections.");
        llama_memory_clear(llama_get_memory(ctx), true);
        for (size_t start = 0; start < tokens.size(); start += 2048) {
            if (cancelled) return;
            auto batch = llama_batch_get_one(tokens.data()+start, std::min<size_t>(2048, tokens.size()-start));
            if (llama_decode(ctx, batch)) throw std::runtime_error("Hexagon prefill failed");
        }
        sampler = llama_sampler_init_greedy();
        const auto vocab = llama_model_get_vocab(model);
        auto callback = env->GetMethodID(env->GetObjectClass(self), "onBytes", "([B)V");
        std::string pending;
        bool ended = false;
        const int budget = autoContinue ? 4096 - static_cast<int>(tokens.size()) : limit;
        for (int i = 0; i <= budget && !cancelled; ++i) {
            auto token = llama_sampler_sample(sampler, ctx, -1);
            if (llama_vocab_is_eog(vocab, token)) { ended = true; break; }
            if (i == budget) break;
            if (autoContinue && i == limit) {
                __android_log_print(ANDROID_LOG_INFO, "KrakenNPU", "CONTINUING generated=%d remaining=%d (same KV state)", i, budget-i);
            }
            char small[256];
            int n = llama_token_to_piece(vocab, token, small, sizeof(small), 0, false);
            if (n < 0) {
                std::vector<char> large(-n);
                n = llama_token_to_piece(vocab, token, large.data(), large.size(), 0, false);
                if (n < 0) throw std::runtime_error("Token decoding failed");
                pending.append(large.data(), n);
            } else pending.append(small, n);
            // Emit complete UTF-8 codepoints only (JNI modified UTF-8 is unsuitable).
            size_t complete = 0;
            while (complete < pending.size()) {
                auto c = static_cast<unsigned char>(pending[complete]);
                size_t width = c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
                if (complete + width > pending.size()) break;
                complete += width;
            }
            if (complete) {
                auto data = env->NewByteArray(complete);
                env->SetByteArrayRegion(data, 0, complete, reinterpret_cast<const jbyte *>(pending.data()));
                env->CallVoidMethod(self, callback, data);
                env->DeleteLocalRef(data);
                if (env->ExceptionCheck()) { llama_sampler_free(sampler); return; }
                pending.erase(0, complete);
            }
            if (!cancelled) {
                auto batch = llama_batch_get_one(&token, 1);
                if (llama_decode(ctx, batch)) throw std::runtime_error("Hexagon decode failed");
            }
        }
        llama_sampler_free(sampler); sampler = nullptr;
        if (!ended && !cancelled) throw std::runtime_error(autoContinue
            ? "The response filled the model context. Try a shorter summary; any saved draft remains available."
            : "Response reached its token limit.");
    } catch (const std::exception &e) {
        if (sampler) llama_sampler_free(sampler);
        fail(env, e.what());
    }
}
