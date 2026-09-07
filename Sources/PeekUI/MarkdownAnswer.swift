import SwiftUI

struct MarkdownBlock: Equatable {
    let text: String
    let isCode: Bool

    static func parse(_ markdown: String) -> [Self] {
        var blocks: [Self] = []
        var lines: [String] = []
        var inCode = false
        var fence: String?
        func flush() {
            guard !lines.isEmpty else { return }
            blocks.append(Self(text: lines.joined(separator: "\n"), isCode: inCode))
            lines = []
        }
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if (!inCode && (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~"))) ||
                (inCode && fence.map { trimmed.hasPrefix($0) } == true) {
                flush()
                if inCode { fence = nil } else { fence = String(trimmed.prefix(3)) }
                inCode.toggle()
            } else if trimmed.isEmpty && !inCode {
                flush()
            } else {
                lines.append(line)
            }
        }
        flush()
        return blocks
    }
}

struct MarkdownAnswer: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                if block.isCode {
                    Text(block.text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                } else {
                    Text((try? AttributedString(markdown: block.text,
                        options: .init(interpretedSyntax: .full))) ?? AttributedString(block.text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
    }
}
