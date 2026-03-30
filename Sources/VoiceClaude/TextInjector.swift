import Cocoa
import Carbon

final class TextInjector {
    static func inject(text: String) {
        let pasteboard = NSPasteboard.general
        // Save original pasteboard contents
        let savedItems = savePasteboard(pasteboard)

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Handle CJK input method
        let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let needsSwitch = isCJKInputSource(originalSource)
        var asciiSource: TISInputSource?

        if needsSwitch {
            asciiSource = findASCIIInputSource()
            if let ascii = asciiSource {
                TISSelectInputSource(ascii)
                usleep(50_000) // 50ms for input source switch
            }
        }

        // Simulate Cmd+V
        simulatePaste()

        // Restore input source after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if needsSwitch {
                TISSelectInputSource(originalSource)
            }

            // Restore pasteboard after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                restorePasteboard(pasteboard, items: savedItems)
            }
        }
    }

    private static func isCJKInputSource(_ source: TISInputSource) -> Bool {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String? else {
            return false
        }
        let cjkKeywords = ["Chinese", "Pinyin", "Wubi", "Cangjie", "Zhuyin", "Japanese", "Korean",
                           "Hiragana", "Katakana", "Romaji", "Hangul", "SCIM", "TCIM",
                           "SimplifiedChinese", "TraditionalChinese"]
        return cjkKeywords.contains { id.contains($0) }
    }

    private static func findASCIIInputSource() -> TISInputSource? {
        let criteria: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsASCIICapable as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]
        guard let sources = TISCreateInputSourceList(criteria as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        // Prefer ABC or US keyboard
        let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        for pref in preferred {
            if let match = sources.first(where: { source in
                guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                      let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String? else { return false }
                return id == pref
            }) {
                return match
            }
        }
        return sources.first
    }

    private static func simulatePaste() {
        let vKeyCode: CGKeyCode = 9 // V key
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    private struct PasteboardItem {
        let types: [NSPasteboard.PasteboardType]
        let data: [NSPasteboard.PasteboardType: Data]
    }

    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [PasteboardItem] {
        var items: [PasteboardItem] = []
        guard let pbItems = pasteboard.pasteboardItems else { return items }
        for item in pbItems {
            var dataDict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataDict[type] = data
                }
            }
            items.append(PasteboardItem(types: item.types, data: dataDict))
        }
        return items
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [PasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        for item in items {
            let pbItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data[type] {
                    pbItem.setData(data, forType: type)
                }
            }
            pasteboard.writeObjects([pbItem])
        }
    }
}
