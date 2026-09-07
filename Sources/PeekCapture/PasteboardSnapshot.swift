import AppKit

struct PasteboardSnapshot {
    let changeCount: Int
    let string: String?
    let items: [[NSPasteboard.PasteboardType: Data]]
}

@MainActor
func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
    PasteboardSnapshot(
        changeCount: pasteboard.changeCount,
        string: pasteboard.string(forType: .string),
        items: (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                contents[type] = item.data(forType: type)
            }
            return contents
        }
    )
}

@MainActor
func copiedString(from pasteboard: NSPasteboard, since snapshot: PasteboardSnapshot) -> String? {
    guard pasteboard.changeCount != snapshot.changeCount,
          let string = pasteboard.string(forType: .string), !string.isEmpty else { return nil }
    return string
}

@MainActor
func restorePasteboard(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
    guard pasteboard.changeCount != snapshot.changeCount else { return }
    pasteboard.clearContents()
    let items = snapshot.items.map { contents in
        let item = NSPasteboardItem()
        for (type, data) in contents {
            item.setData(data, forType: type)
        }
        return item
    }
    if !items.isEmpty {
        pasteboard.writeObjects(items)
    }
}
