import AppKit

extension NSPasteboardItem {
    /// NSPasteboardItem has no NSCopying; copy every type's data so it survives `clearContents()`.
    func manualDeepCopy() -> NSPasteboardItem {
        let copy = NSPasteboardItem()
        for type in types {
            if let data = data(forType: type) {
                copy.setData(data, forType: type)
            }
        }
        return copy
    }
}
