import AppKit
import Testing
@testable import PeekUI

@Test @MainActor func answerRendersAsOneSelectableString() {
    let text = AnswerText.attributed("""
    Q3 is **below** the trend.

    - Q3 is half of Q2.
    - Q4 recovers.

    1. First
    2. Second

    ```
    let x = 1
    ```
    """)
    let lines = text.string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines == ["Q3 is below the trend.", "•\tQ3 is half of Q2.", "•\tQ4 recovers.",
                      "1.\tFirst", "2.\tSecond", "let x = 1"])
    let bold = text.attribute(.font, at: (text.string as NSString).range(of: "below").location, effectiveRange: nil)
    #expect((bold as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
}

@Test @MainActor func answerKeepsTableRowsOnOneLine() {
    let text = AnswerText.attributed("""
    | Quarter | Revenue |
    | --- | --- |
    | Q3 | Low |
    """)
    let lines = text.string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines == ["Quarter\tRevenue", "Q3\tLow"])
}
