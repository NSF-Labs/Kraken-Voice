// Conformance LLMModel pour integration avec mlx-swift-lm (ChatSession, ModelContainer, etc.)

import Foundation
import MLX
import MLXFast
import MLXNN
import MLXLMCommon
import MLXLLM

/// Modele Gemma 4 conforme au protocol LLMModel de mlx-swift-lm.
/// Permet l'utilisation via MLXLMCommon.loadModelContainer() et ChatSession.
public class Gemma4LLMModel: Module, LLMModel, LoRAModel {
    @ModuleInfo(key: "language_model") public var languageModel: Gemma4LanguageModel

    public let config: Gemma4TextConfig
    public let modelType: String

    public var kvHeads: [Int]

    public init(config: Gemma4TextConfig) {
        self.config = config
        self.modelType = config.modelType

        self._languageModel.wrappedValue = Gemma4LanguageModel(config)
        self.kvHeads = Array(repeating: config.numKeyValueHeads, count: config.numHiddenLayers)

        super.init()
    }

    // MARK: - LoRAModel conformance

    /// Couches exposees pour l'application des adaptateurs LoRA (toutes les couches du transformer).
    public var loraLayers: [Module] {
        languageModel.model.layers.map { $0 as Module }
    }

    // MARK: - LLMModel conformance

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        let cacheArray: [KVCache?]? = cache?.map { $0 as KVCache? }
        return languageModel(inputs: inputs, cache: cacheArray)
    }

    public func newCache(parameters: GenerateParameters?) -> [any KVCache] {
        let kvBits: Float? = parameters?.kvBits != nil ? Float(parameters!.kvBits!) : nil
        return languageModel.makeCache(kvBits: kvBits)
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        WeightSanitizer.sanitize(weights: weights)
    }

    /// Bound prompt prefill work on phones. Returning the entire prompt here
    /// bypasses LLMModel's chunking and materializes every token at once.
    public func prepare(_ input: LMInput, cache: [KVCache], windowSize: Int? = nil) throws -> PrepareResult {
        let step = max(1, windowSize ?? 64)
        var remaining = input.text
        while remaining.tokens.size > step {
            try Task.checkCancellation()
            _ = self(remaining.tokens[..<step][.newAxis], cache: cache)
            // Finish each chunk before allocating the next chunk's graph.
            eval(cache)
            remaining = remaining[step...]
            MLX.Memory.clearCache()
        }
        return .tokens(remaining)
    }
}
