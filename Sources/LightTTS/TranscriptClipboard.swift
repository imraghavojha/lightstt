import AppKit

func writeTranscriptToClipboard(_ text: String) {
    let board = NSPasteboard.general
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    if !(UserDefaults.standard.object(forKey: "clipboardHistory") as? Bool ?? true) {
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }
    board.clearContents(); board.writeObjects([item])
}
