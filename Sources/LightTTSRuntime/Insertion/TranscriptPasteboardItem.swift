import AppKit

/// Builds the item used for transcript clipboard delivery.
public func transcriptPasteboardItem(_ text: String, allowClipboardHistory: Bool)
    -> NSPasteboardItem
{
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    if !allowClipboardHistory {
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }
    return item
}
