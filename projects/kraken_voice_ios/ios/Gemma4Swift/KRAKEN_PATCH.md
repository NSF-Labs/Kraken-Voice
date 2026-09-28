Source: VincentGourbin/gemma-4-swift-mlx revision
c6f8ab5820379898b1d437e8e5c463f376672613 (same baseline as FWPlanner).

Gemma4Attention initializes K/V projection and normalization modules only for
layers that own K/V weights. E2B's shared-KV layers omit those weights; the
unmodified baseline fails strict weight loading on layer 15. Their existing
forward path already consumes the source layer's KV cache. No replacement or
random model weights are generated. The package's unused test target is omitted.

Dependencies remain locked in both Xcode workspace Package.resolved files.

The per-layer projection uses MLXNN.Linear with its original scale applied after
the projection. This allows MLX's quantization pass to replace it with
QuantizedLinear. The original custom Module wasn't Quantizable and tried to load
packed 4-bit weights into a dense [8960,1536] matrix.

E2B downloads use model revision 238767527555cb75a05732a84dff5d6ba0dd6809
for both repository metadata and file URLs. The qualified safetensors SHA-256 is
038e39a37a7667373d2c3991375446b10c96ae1d717a68674870343db376b76e.

The text-only adapter now consumes prompt tokens in bounded chunks, respecting
GenerateParameters.prefillStepSize (64 in Kraken's non-streaming chat path).
Previously prepare returned the entire prompt unchanged, bypassing the MLX LLM
protocol's default chunked prefill. Each chunk evaluates its KV caches before
advancing. Chat releases its completed session; the iOS bridge bounds allocator
cache retention to 64 MiB. This reduces transient/retained memory but does not
set a hard whole-process memory cap.
