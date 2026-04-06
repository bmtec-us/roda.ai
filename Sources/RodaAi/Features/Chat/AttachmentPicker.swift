// Sources/RodaAi/Features/Chat/AttachmentPicker.swift
import SwiftUI
import UniformTypeIdentifiers
import RodaAiCore

struct AttachmentPicker: View {
    @Binding var selectedFileURL: URL?
    @Binding var extractedText: String?
    @Binding var error: FileProcessorError?
    @State private var isPresented = false

    let processor: any FileTextExtractor

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "paperclip")
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: supportedContentTypes
        ) { result in
            switch result {
            case .success(let url):
                selectedFileURL = url
                Task {
                    do {
                        extractedText = try await processor.extractText(from: url)
                    } catch let e as FileProcessorError {
                        error = e
                    }
                }
            case .failure:
                break
            }
        }
    }

    private var supportedContentTypes: [UTType] {
        [.pdf, .commaSeparatedText, .plainText, .sourceCode, .json, .xml, .html]
    }
}
