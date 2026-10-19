// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WorksheetKit

/// Bold, italic, underline, strike through, superscript and subscript in a
/// text cell's editor. The text storage's attributes are what the user
/// sees and edits (typing continues the format before the caret, undo
/// restores it); the model's `textFormats` are read back from them after
/// every change, and applied to them when the model changes by itself.
extension CellTextView {
    /// The formats the storage shows, one per Unicode scalar; empty when plain.
    func storageFormats() -> TextFormats {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        var perUTF16 = [TextFormat](repeating: [], count: storage.length)
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            var f = TextFormat()
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { f.insert(.bold) }
                if traits.contains(.italic) { f.insert(.italic) }
            }
            if let u = attributes[.underlineStyle] as? Int, u != 0 { f.insert(.underline) }
            if let s = attributes[.strikethroughStyle] as? Int, s != 0 { f.insert(.strikethrough) }
            if let b = attributes[.baselineOffset] as? CGFloat {
                if b > 0 { f.insert(.raised) } else if b < 0 { f.insert(.lowered) }
            }
            for i in range.location..<NSMaxRange(range) { perUTF16[i] = f }
        }
        var out: TextFormats = []
        var utf16 = 0
        for scalar in storage.string.unicodeScalars {
            out.append(perUTF16[utf16])
            utf16 += scalar.utf16.count
        }
        return TextFormatting.isPlain(out) ? [] : out
    }

    /// The attributes of one format, on top of the cell's base font.
    static func attributes(_ f: TextFormat, base: NSFont) -> [NSAttributedString.Key: Any] {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if f.contains(.bold) { traits.insert(.bold) }
        if f.contains(.italic) { traits.insert(.italic) }
        let shifted = !f.intersection([.raised, .lowered]).isEmpty
        let size = base.pointSize * (shifted ? 0.7 : 1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        a[.underlineStyle] = f.contains(.underline) ? NSUnderlineStyle.single.rawValue : 0
        a[.strikethroughStyle] = f.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : 0
        a[.baselineOffset] = f.contains(.raised) ? base.pointSize * 0.35 : f.contains(.lowered) ? -base.pointSize * 0.2 : 0
        return a
    }

    /// Shows `formats` (from the model) when the storage shows something else.
    func applyFormats(_ formats: TextFormats, base: NSFont) {
        guard let storage = textStorage else { return }
        let scalars = Array(storage.string.unicodeScalars)
        let wanted = formats.count == scalars.count ? formats : []
        guard storageFormats() != wanted || storage.length > 0 && (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize != base.pointSize
        else { return }
        applyingFormats = true
        defer { applyingFormats = false }
        storage.beginEditing()
        var utf16 = 0
        for (i, scalar) in scalars.enumerated() {
            let n = scalar.utf16.count
            storage.setAttributes(Self.attributes(i < wanted.count ? wanted[i] : [], base: base),
                                  range: NSRange(location: utf16, length: n))
            utf16 += n
        }
        storage.endEditing()
        typingAttributes = Self.attributes(TextFormat(), base: base)
        invalidateIntrinsicContentSize()
    }

    /// Format › Bold and the like: toggles `flag` on the selection (one undo
    /// step), or for what is typed next when nothing is selected.
    func toggleFormat(_ flag: TextFormat, base: NSFont) {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        if range.length == 0 {
            var current = format(of: typingAttributes)
            current = current.contains(flag) ? current.subtracting(flag) : current.with(flag)
            typingAttributes = Self.attributes(current, base: base)
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        // On if any selected character lacks it, as word processors do.
        var allHave = true
        storage.enumerateAttributes(in: range) { a, _, stop in
            if !format(of: a).contains(flag) { allHave = false; stop.pointee = true }
        }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { a, r, _ in
            let f = format(of: a)
            storage.setAttributes(Self.attributes(allHave ? f.subtracting(flag) : f.with(flag), base: base), range: r)
        }
        storage.endEditing()
        didChangeText()
    }

    func format(of attributes: [NSAttributedString.Key: Any]) -> TextFormat {
        var f = TextFormat()
        if let font = attributes[.font] as? NSFont {
            if font.fontDescriptor.symbolicTraits.contains(.bold) { f.insert(.bold) }
            if font.fontDescriptor.symbolicTraits.contains(.italic) { f.insert(.italic) }
        }
        if let u = attributes[.underlineStyle] as? Int, u != 0 { f.insert(.underline) }
        if let s = attributes[.strikethroughStyle] as? Int, s != 0 { f.insert(.strikethrough) }
        if let b = attributes[.baselineOffset] as? CGFloat { if b > 0 { f.insert(.raised) } else if b < 0 { f.insert(.lowered) } }
        return f
    }
}
