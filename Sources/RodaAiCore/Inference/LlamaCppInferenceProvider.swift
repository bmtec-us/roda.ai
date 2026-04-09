import Foundation
import LlamaSwift

/// Provedor de inferencia baseado em llama.cpp para modelos GGUF.
/// Permite executar arquiteturas que o MLX Swift ainda nao suporta
/// (ex: Gemma 4) via formato GGUF com quantizacao eficiente.
///
/// Ref: concurrency-model.md — actor custom.
public actor LlamaCppInferenceProvider: InferenceProvider {

    public var isModelLoaded: Bool { model != nil }
    public var loadedModelIdentifier: String?

    private var model: OpaquePointer?   // llama_model *
    private var context: OpaquePointer? // llama_context *

    private let contextSize: UInt32 = 4096
    private let batchSize: UInt32 = 512

    public init() {
        llama_backend_init()
    }

    // MARK: - Load

    public func loadModel(identifier: String) async throws(InferenceError) {
        RodaLog.inference.info("LlamaCpp loading: \(identifier, privacy: .public)")
        let startTime = ContinuousClock.now

        if model != nil {
            await unloadModel()
        }

        let ggufPath = findGGUFFile(at: identifier)
        guard let ggufPath else {
            throw InferenceError.modelNotFound(identifier: identifier)
        }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99 // Offload all layers to Metal GPU

        guard let m = llama_model_load_from_file(ggufPath, modelParams) else {
            throw InferenceError.modelCorrupted(
                identifier: identifier,
                reason: "llama_model_load_from_file falhou"
            )
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextSize
        ctxParams.n_batch = batchSize

        guard let ctx = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            throw InferenceError.modelCorrupted(
                identifier: identifier,
                reason: "llama_init_from_model falhou"
            )
        }

        model = m
        context = ctx
        loadedModelIdentifier = identifier

        let elapsed = startTime.duration(to: .now)
        RodaLog.inference.info(
            "LlamaCpp model loaded in \(String(describing: elapsed), privacy: .public)"
        )
    }

    // MARK: - Generate

    public func generate(
        messages: [ChatMessage],
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, any Error> {
        guard let model, let context else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        let capturedModel = model
        let capturedContext = context
        let maxTokens = config.maxTokens
        let temperature = config.temperature
        let topP = config.topP
        let repetitionPenalty = config.repetitionPenalty

        let prompt = formatChatPrompt(messages)

        return AsyncThrowingStream<String, any Error> { continuation in
            Task {
                do {
                    // Tokenize prompt
                    let tokens = try tokenize(
                        model: capturedModel,
                        text: prompt,
                        addBos: true
                    )

                    guard !tokens.isEmpty else {
                        continuation.finish(
                            throwing: InferenceError.tokenizationFailed(reason: "Prompt vazio")
                        )
                        return
                    }

                    // Clear KV cache (llama.cpp >=b4000 memory API)
                    llama_memory_clear(llama_get_memory(capturedContext), true)

                    // Decode prompt in batches
                    try decodeBatched(
                        context: capturedContext,
                        tokens: tokens,
                        batchSize: Int(batchSize)
                    )

                    // Generate tokens
                    let sampler = LlamaSampler(
                        temperature: temperature,
                        topP: topP,
                        repetitionPenalty: repetitionPenalty,
                        model: capturedModel
                    )
                    defer { sampler.free() }

                    let eosToken = llama_vocab_eos(llama_model_get_vocab(capturedModel))
                    var generatedCount = 0
                    var batch = llama_batch_init(1, 0, 1)
                    defer { llama_batch_free(batch) }

                    while generatedCount < maxTokens {
                        if Task.isCancelled {
                            continuation.finish(throwing: InferenceError.generationCancelled)
                            return
                        }

                        let newToken = sampler.sample(context: capturedContext)

                        if newToken == eosToken {
                            break
                        }

                        // Convert token to text
                        if let piece = tokenToPiece(
                            model: capturedModel,
                            token: newToken
                        ) {
                            continuation.yield(piece)
                        }

                        // Prepare next batch with the new token
                        batchClear(&batch)
                        batchAdd(
                            &batch,
                            token: newToken,
                            pos: Int32(tokens.count + generatedCount),
                            seqId: 0,
                            logits: true
                        )

                        let status = llama_decode(capturedContext, batch)
                        if status != 0 {
                            continuation.finish(
                                throwing: InferenceError.generationFailed(
                                    reason: "llama_decode retornou \(status)"
                                )
                            )
                            return
                        }

                        generatedCount += 1
                    }

                    continuation.finish()
                } catch let error as InferenceError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(
                        throwing: InferenceError.generationFailed(
                            reason: error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    // MARK: - Unload

    public func unloadModel() async {
        if let id = loadedModelIdentifier {
            RodaLog.inference.info("LlamaCpp unloading: \(id, privacy: .public)")
        }
        if let ctx = context {
            llama_free(ctx)
        }
        if let m = model {
            llama_model_free(m)
        }
        context = nil
        model = nil
        loadedModelIdentifier = nil
    }

    // MARK: - Helpers

    /// Encontra o arquivo .gguf dentro do diretorio do modelo.
    private func findGGUFFile(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        // Se o path aponta diretamente para um .gguf
        if path.hasSuffix(".gguf") && fm.fileExists(atPath: path) {
            return path
        }

        // Procura .gguf dentro do diretorio
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        // Prefere Q4_K_M, depois qualquer .gguf
        let ggufFiles = contents.filter { $0.pathExtension == "gguf" }
        if let preferred = ggufFiles.first(where: {
            $0.lastPathComponent.contains("Q4_K_M")
        }) {
            return preferred.path
        }
        return ggufFiles.first?.path
    }

    /// Formata mensagens de chat no formato esperado pelo modelo.
    /// Usa formato generico compativel com maioria dos modelos GGUF.
    private func formatChatPrompt(_ messages: [ChatMessage]) -> String {
        var prompt = ""
        for msg in messages {
            switch msg.role {
            case .system:
                prompt += "<|system|>\n\(msg.content)\n"
            case .user:
                prompt += "<|user|>\n\(msg.content)\n"
            case .assistant:
                prompt += "<|assistant|>\n\(msg.content)\n"
            }
        }
        prompt += "<|assistant|>\n"
        return prompt
    }

    /// Tokeniza texto usando o vocabulario do modelo.
    private func tokenize(
        model: OpaquePointer,
        text: String,
        addBos: Bool
    ) throws -> [llama_token] {
        let vocab = llama_model_get_vocab(model)
        let utf8 = Array(text.utf8)
        let maxTokens = utf8.count + (addBos ? 1 : 0) + 1

        var tokens = [llama_token](repeating: 0, count: maxTokens)
        let nTokens = llama_tokenize(
            vocab,
            text,
            Int32(utf8.count),
            &tokens,
            Int32(maxTokens),
            addBos,
            true // special tokens
        )

        guard nTokens >= 0 else {
            throw InferenceError.tokenizationFailed(
                reason: "llama_tokenize retornou \(nTokens)"
            )
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    /// Decodifica tokens em lotes.
    private func decodeBatched(
        context: OpaquePointer,
        tokens: [llama_token],
        batchSize: Int
    ) throws {
        var offset = 0
        while offset < tokens.count {
            let chunkSize = min(batchSize, tokens.count - offset)
            var batch = llama_batch_init(Int32(chunkSize), 0, 1)
            defer { llama_batch_free(batch) }

            for i in 0..<chunkSize {
                let isLast = (offset + i == tokens.count - 1)
                batchAdd(
                    &batch,
                    token: tokens[offset + i],
                    pos: Int32(offset + i),
                    seqId: 0,
                    logits: isLast // Only compute logits for the last token
                )
            }

            let status = llama_decode(context, batch)
            if status != 0 {
                throw InferenceError.generationFailed(
                    reason: "llama_decode batch falhou com status \(status)"
                )
            }
            offset += chunkSize
        }
    }

    /// Converte um token para texto.
    private func tokenToPiece(
        model: OpaquePointer,
        token: llama_token
    ) -> String? {
        let vocab = llama_model_get_vocab(model)
        var buffer = [CChar](repeating: 0, count: 256)
        let len = llama_token_to_piece(vocab, token, &buffer, 256, 0, true)
        guard len > 0 else { return nil }
        return String(cString: Array(buffer.prefix(Int(len))) + [0])
    }
}

// MARK: - Batch helpers (inline replacements for common/common.h utilities)

/// Resets the batch token count to 0. Equivalent to llama_batch_clear in common.h.
private func batchClear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

/// Appends a token to the batch. Equivalent to llama_batch_add in common.h.
private func batchAdd(
    _ batch: inout llama_batch,
    token: llama_token,
    pos: llama_pos,
    seqId: llama_seq_id,
    logits: Bool
) {
    let n = Int(batch.n_tokens)
    batch.token[n] = token
    batch.pos[n] = pos
    batch.n_seq_id[n] = 1
    batch.seq_id[n]?[0] = seqId
    batch.logits[n] = logits ? 1 : 0
    batch.n_tokens += 1
}

// MARK: - Sampler wrapper

/// Wrapper fino sobre llama_sampler para configurar temperatura, top-p, etc.
private struct LlamaSampler {
    private let chain: UnsafeMutablePointer<llama_sampler>?

    init(
        temperature: Float,
        topP: Float,
        repetitionPenalty: Float,
        model: OpaquePointer
    ) {
        let params = llama_sampler_chain_default_params()
        let ch = llama_sampler_chain_init(params)

        if repetitionPenalty != 1.0 {
            llama_sampler_chain_add(ch, llama_sampler_init_penalties(
                64,    // last_n
                repetitionPenalty,
                0.0,   // frequency penalty
                0.0    // presence penalty
            ))
        }

        if temperature > 0 {
            llama_sampler_chain_add(ch, llama_sampler_init_top_p(topP, 1))
            llama_sampler_chain_add(ch, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(ch, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        } else {
            llama_sampler_chain_add(ch, llama_sampler_init_greedy())
        }

        chain = ch
    }

    func sample(context: OpaquePointer) -> llama_token {
        guard let chain else { return -1 }
        return llama_sampler_sample(chain, context, -1)
    }

    func free() {
        if let chain {
            llama_sampler_free(chain)
        }
    }
}
