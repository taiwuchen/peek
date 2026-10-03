import Foundation

/// Wraps an attached text file so the model sees its name alongside its contents.
func attachedText(name: String, text: String) -> String {
    "<file name=\"\(name)\">\n\(text)\n</file>"
}
