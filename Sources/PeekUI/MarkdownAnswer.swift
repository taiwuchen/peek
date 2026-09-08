import MarkdownUI
import SwiftUI

struct MarkdownAnswer: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.peek)
            .textSelection(.enabled)
    }
}

extension Theme {
    /// The library's basic theme with code blocks matching the panel's HUD material.
    @MainActor static var peek: Theme {
        Theme.basic
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .relativeLineSpacing(.em(0.2))
                        .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.9)) }
                        .padding(10)
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .markdownMargin(top: 0, bottom: 12)
            }
    }
}
