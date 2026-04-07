// Sources/RodaAi/Features/Chat/MessageBubble.swift
import Foundation
import SwiftUI
import RodaAiCore
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubble: View {
    let message: ChatMessage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUser: Bool { message.role == .user }

    private var imageAttachments: [Attachment] {
        message.attachments.filter { $0.mimeType.hasPrefix("image/") }
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Label("chat.assistant", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                renderedMessage
                    .padding(12)
                    .modifier(BubbleBackgroundModifier(isUser: isUser))
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var renderedMessage: some View {
        if isUser {
            VStack(alignment: .leading, spacing: 10) {
                if !imageAttachments.isEmpty {
                    ForEach(Array(imageAttachments.enumerated()), id: \.offset) { _, attachment in
                        AttachmentImageView(url: attachment.url)
                    }
                }

                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SelectableMessageText(text: message.content, parseMarkdown: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    AnimatedDots(reduceMotion: reduceMotion, color: .secondary)
                    Text("Pensando...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(assistantSegments.indices, id: \.self) { index in
                        switch assistantSegments[index] {
                        case .text(let text):
                            SelectableMessageText(text: text, parseMarkdown: true)
                        case .code(let code, let language):
                            CodeBlockView(code: code, language: language)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var assistantSegments: [AssistantSegment] {
        parseAssistantSegments(from: message.content)
    }

    private func parseAssistantSegments(from content: String) -> [AssistantSegment] {
        let pattern = "```([a-zA-Z0-9_+\\-.]*)?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(content)]
        }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = regex.matches(in: content, options: [], range: fullRange)

        if matches.isEmpty {
            return [.text(content)]
        }

        var result: [AssistantSegment] = []
        var cursor = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursor {
                let textRange = NSRange(location: cursor, length: matchRange.location - cursor)
                let plain = nsContent.substring(with: textRange)
                if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.text(plain))
                }
            }

            let language: String?
            if match.range(at: 1).location != NSNotFound {
                let rawLanguage = nsContent.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                language = rawLanguage.isEmpty ? nil : rawLanguage
            } else {
                language = nil
            }

            let code = nsContent.substring(with: match.range(at: 2))
            result.append(.code(code: code, language: language))

            cursor = matchRange.location + matchRange.length
        }

        if cursor < nsContent.length {
            let trailing = nsContent.substring(with: NSRange(location: cursor, length: nsContent.length - cursor))
            if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(trailing))
            }
        }

        return result.isEmpty ? [.text(content)] : result
    }
}

private enum AssistantSegment {
    case text(String)
    case code(code: String, language: String?)
}

private struct AttachmentImageView: View {
    let url: URL

    var body: some View {
        Group {
            if let image = loadImage() {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("Imagem anexada")
                        .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func loadImage() -> Image? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }
}

private struct SelectableMessageText: View {
    let text: String
    let parseMarkdown: Bool

    var body: some View {
        #if canImport(UIKit)
        IOSSelectableTextView(text: text, parseMarkdown: parseMarkdown)
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        if parseMarkdown,
           let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
           ) {
            Text(markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        #endif
    }
}

#if canImport(UIKit)
private struct IOSSelectableTextView: UIViewRepresentable {
    let text: String
    let parseMarkdown: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = makeAttributedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    private func makeAttributedText() -> NSAttributedString {
        if parseMarkdown,
           let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
           ) {
            return NSAttributedString(attributed)
        }

        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )
    }
}
#endif

/// Fundo da bolha: usuario = accent opaco, assistente = glass translucido.
private struct BubbleBackgroundModifier: ViewModifier {
    let isUser: Bool

    func body(content: Content) -> some View {
        if isUser {
            content
                .background(Color.accentColor.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            if #available(iOS 26, macOS 26, *) {
                content
                    .foregroundStyle(.primary)
                    .glassEffect(in: .rect(cornerRadius: 18))
            } else {
                content
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
