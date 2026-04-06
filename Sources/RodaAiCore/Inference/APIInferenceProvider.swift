import Foundation

/// Provedor de inferencia via API remota compativel com OpenAI.
/// Permite usar modelos na nuvem (OpenAI, Anthropic, Groq, etc.)
/// quando inferencia local nao e viavel ou como fallback.
///
/// Ref: concurrency-model.md — actor custom.
public actor APIInferenceProvider: InferenceProvider {

    public var isModelLoaded: Bool { currentModel != nil }
    public var loadedModelIdentifier: String?

    private var currentModel: String?

    /// Configuracao da API — injetada no init.
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKey: String = "",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Load

    public func loadModel(identifier: String) async throws(InferenceError) {
        RodaLog.inference.info("API provider loading model: \(identifier, privacy: .public)")
        currentModel = identifier
        loadedModelIdentifier = identifier
    }

    // MARK: - Generate (streaming via SSE)

    public func generate(
        messages: [ChatMessage],
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, any Error> {
        guard let modelId = currentModel else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        let capturedApiKey = apiKey
        let capturedSession = session

        let requestMessages = messages.map { msg -> [String: String] in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": modelId,
            "messages": requestMessages,
            "stream": true,
            "temperature": Double(config.temperature),
            "top_p": Double(config.topP),
            "max_tokens": config.maxTokens,
        ]

        return AsyncThrowingStream<String, any Error> { continuation in
            Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !capturedApiKey.isEmpty {
                        request.setValue(
                            "Bearer \(capturedApiKey)",
                            forHTTPHeaderField: "Authorization"
                        )
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await capturedSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(
                            throwing: InferenceError.generationFailed(
                                reason: "Resposta HTTP invalida"
                            )
                        )
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(
                            throwing: InferenceError.generationFailed(
                                reason: "API retornou HTTP \(httpResponse.statusCode)"
                            )
                        )
                        return
                    }

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: InferenceError.generationCancelled)
                            return
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))

                        if data == "[DONE]" { break }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(
                                with: jsonData
                              ) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String
                        else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch let error as InferenceError {
                    continuation.finish(throwing: error)
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                    } else {
                        continuation.finish(
                            throwing: InferenceError.generationFailed(
                                reason: error.localizedDescription
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Unload

    public func unloadModel() async {
        if let id = loadedModelIdentifier {
            RodaLog.inference.info("API provider unloading: \(id, privacy: .public)")
        }
        currentModel = nil
        loadedModelIdentifier = nil
    }
}
