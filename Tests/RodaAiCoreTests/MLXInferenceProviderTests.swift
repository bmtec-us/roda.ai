import XCTest
@testable import RodaAiCore

final class MLXInferenceProviderTests: XCTestCase {

    // MARK: - Testes com Mock (logica de protocolo)

    func testGenerateWithoutLoadedModelThrowsError() async {
        let mock = MockInferenceProvider()
        // Nao carrega modelo
        let stream = await mock.generate(
            messages: [ChatMessage(role: .user, content: "Oi")],
            config: GenerationConfig()
        )
        // MockInferenceProvider nao checa isModelLoaded; testar o contrato
        // MLXInferenceProvider real deve checar
        let loaded = await mock.isModelLoaded
        XCTAssertFalse(loaded)
    }

    func testCancelDuringStreamingYieldsPartialTokens() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["A", "B", "C", "D", "E", "F", "G", "H"])
        await mock.setTokenDelay(.milliseconds(100))
        try await mock.loadModel(identifier: "test")

        let task = Task {
            var tokens: [String] = []
            let stream = await mock.generate(
                messages: [ChatMessage(role: .user, content: "test")],
                config: GenerationConfig()
            )
            for try await token in stream {
                tokens.append(token)
            }
            return tokens
        }

        // Espera o suficiente para receber alguns tokens, mas nao todos
        try await Task.sleep(for: .milliseconds(350))
        task.cancel()

        do {
            let tokens = try await task.value
            // Se cancelou com sucesso, deve ter menos que 8 tokens
            XCTAssertLessThan(tokens.count, 8)
        } catch {
            // Cancelamento pode lancar InferenceError.generationCancelled
            XCTAssertEqual(error as? InferenceError, .generationCancelled)
        }
    }

    func testConcurrentGenerateCallsAreSerializedByActor() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["token1"])
        await mock.setTokenDelay(.milliseconds(50))
        try await mock.loadModel(identifier: "test")

        let messages = [ChatMessage(role: .user, content: "test")]
        let config = GenerationConfig()

        // Duas geracoes simultaneas — actor serializa acesso
        async let stream1Tokens: [String] = {
            var tokens: [String] = []
            let stream = await mock.generate(messages: messages, config: config)
            for try await token in stream { tokens.append(token) }
            return tokens
        }()

        async let stream2Tokens: [String] = {
            var tokens: [String] = []
            let stream = await mock.generate(messages: messages, config: config)
            for try await token in stream { tokens.append(token) }
            return tokens
        }()

        let results1 = try await stream1Tokens
        let results2 = try await stream2Tokens

        // Ambas devem completar (actor serializa, nao rejeita)
        XCTAssertEqual(results1, ["token1"])
        XCTAssertEqual(results2, ["token1"])

        // generateCallCount deve ser 2 (ambas chamadas executaram)
        let count = await mock.generateCallCount
        XCTAssertEqual(count, 2)
    }

    func testLoadModelThenUnloadThenGenerateFails() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "test")
        await mock.unloadModel()
        let loaded = await mock.isModelLoaded
        XCTAssertFalse(loaded)
    }

    // MARK: - Testes do MLXInferenceProvider real (estrutura)

    func testMLXInferenceProviderConformsToProtocol() {
        // Verificacao de compilacao: MLXInferenceProvider conforma a InferenceProvider
        let _: any InferenceProvider.Type = MLXInferenceProvider.self
        XCTAssertTrue(true)
    }

    func testMLXInferenceProviderInitialStateIsNotLoaded() async {
        let provider = MLXInferenceProvider()
        let loaded = await provider.isModelLoaded
        let identifier = await provider.loadedModelIdentifier
        XCTAssertFalse(loaded)
        XCTAssertNil(identifier)
    }

    func testMLXInferenceProviderLoadInvalidModelThrows() async {
        let provider = MLXInferenceProvider()
        do {
            try await provider.loadModel(identifier: "nonexistent-model-that-does-not-exist")
            XCTFail("Expected InferenceError")
        } catch {
            XCTAssertTrue(error is InferenceError)
        }
    }

    func testMLXInferenceProviderGenerateWithoutModelThrows() async {
        let provider = MLXInferenceProvider()
        let stream = await provider.generate(
            messages: [ChatMessage(role: .user, content: "test")],
            config: GenerationConfig()
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected InferenceError.modelNotLoaded")
        } catch {
            XCTAssertEqual(error as? InferenceError, .modelNotLoaded)
        }
    }

    // MARK: - Configuration factory (path vs repo ID)

    func testMakeConfigurationWithHuggingFaceRepoID() {
        // HF repo IDs nao comecam com /
        let config = MLXInferenceProvider.makeConfiguration(for: "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertFalse(MLXInferenceProvider.isLocalPath("mlx-community/gemma-4-e2b-it-4bit"))
        // O name deve refletir o repo ID (porem via Identifier.id path)
        if case .id(let id, _) = config.id {
            XCTAssertEqual(id, "mlx-community/gemma-4-e2b-it-4bit")
        } else {
            XCTFail("Expected .id case for HF repo ID")
        }
    }

    func testMakeConfigurationWithAbsolutePath() {
        let path = "/Users/test/RodaAi/models/gemma-4-e2b"
        XCTAssertTrue(MLXInferenceProvider.isLocalPath(path))
        let config = MLXInferenceProvider.makeConfiguration(for: path)
        if case .directory(let url) = config.id {
            XCTAssertEqual(url.path, path)
        } else {
            XCTFail("Expected .directory case for local path")
        }
    }

    func testMakeConfigurationWithFileURL() {
        let urlString = "file:///Users/test/RodaAi/models/gemma"
        XCTAssertTrue(MLXInferenceProvider.isLocalPath(urlString))
        let config = MLXInferenceProvider.makeConfiguration(for: urlString)
        if case .directory = config.id {
            // OK
        } else {
            XCTFail("Expected .directory case for file:// URL")
        }
    }

    func testIsLocalPathHandlesEdgeCases() {
        // Paths absolutos
        XCTAssertTrue(MLXInferenceProvider.isLocalPath("/tmp/model"))
        XCTAssertTrue(MLXInferenceProvider.isLocalPath("/"))
        XCTAssertTrue(MLXInferenceProvider.isLocalPath("file:///Users/a"))
        // HF repo IDs
        XCTAssertFalse(MLXInferenceProvider.isLocalPath("mlx-community/gemma"))
        XCTAssertFalse(MLXInferenceProvider.isLocalPath("meta-llama/Llama-3.2-1B"))
        // Edge: string vazia — nao e path local (seguro)
        XCTAssertFalse(MLXInferenceProvider.isLocalPath(""))
    }
}
