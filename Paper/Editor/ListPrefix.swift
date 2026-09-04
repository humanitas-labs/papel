import Foundation

/// A list item's prefix — `- `, `1. `, or `- [ ] ` / `- [x] `, marker
/// through the gap after it (and after the box, for a task) — is one unit
/// for the caret (#53, #50). The rendered marker or the circle stands in
/// for it on every paragraph, so there is nothing to edit inside it: Left
/// from the text's start lands before the marker, Right from there lands at
/// the text's start, a selection that reaches into it takes it whole, and
/// Backspace at the text's start removes it entirely, leaving a plain line.
/// Nested indent and a quote prefix before the marker are not part of the
/// unit. Pure text-in, range-out; the text view applies the results.
enum ListPrefix {
    /// The unit in the paragraph containing `location`, or nil when that
    /// paragraph is not a list item.
    static func unit(in text: NSString, at location: Int) -> NSRange? {
        guard location <= text.length else { return nil }
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        guard let match = MarkdownSyntaxStyler.listMarkerPattern.firstMatch(in: text as String, range: paragraph),
              match.range.location == paragraph.location else { return nil }
        let marker = match.range(at: 1)
        return NSRange(location: marker.location, length: NSMaxRange(match.range) - marker.location)
    }

    /// `range` with no endpoint inside a unit. A selection widens to take
    /// the unit whole. A caret lands at the text's start, except one step
    /// left from there (`previous` at the unit's end, the caret one before
    /// it), which lands before the marker.
    static func snapped(_ range: NSRange, previous: NSRange?, in text: NSString) -> NSRange {
        guard range.length > 0 else {
            guard let unit = unit(in: text, at: range.location), isInside(range.location, unit) else { return range }
            if let previous, previous.length == 0, previous.location == NSMaxRange(unit),
               range.location == NSMaxRange(unit) - 1 {
                return NSRange(location: unit.location, length: 0)
            }
            return NSRange(location: NSMaxRange(unit), length: 0)
        }
        var start = range.location
        var end = NSMaxRange(range)
        if let unit = unit(in: text, at: start), isInside(start, unit) { start = unit.location }
        if let unit = unit(in: text, at: end), isInside(end, unit) { end = NSMaxRange(unit) }
        return NSRange(location: start, length: end - start)
    }

    /// The unit Backspace removes when the caret (`selection`, empty) sits
    /// at the text's start of a list item; nil anywhere else.
    static func backspaceRange(in text: NSString, selection: NSRange) -> NSRange? {
        guard selection.length == 0, let unit = unit(in: text, at: selection.location),
              selection.location == NSMaxRange(unit) else { return nil }
        return unit
    }

    /// Whether Delete at the caret (`selection`, empty) would eat into a
    /// unit: the caret sits right before the marker. Delete does nothing
    /// there.
    static func deleteForwardIsBlocked(in text: NSString, selection: NSRange) -> Bool {
        guard selection.length == 0, let unit = unit(in: text, at: selection.location) else { return false }
        return selection.location == unit.location
    }

    private static func isInside(_ location: Int, _ unit: NSRange) -> Bool {
        location > unit.location && location < NSMaxRange(unit)
    }
}

/// The indent a hard-wrapped list item's continuation carries, the run
/// marked `.pinned` at its paragraph's start, is one unit for the caret
/// too. It stays concealed on the active paragraph, so a caret inside it
/// would draw at the text's start while standing somewhere else: a
/// Backspace there would eat the newline and surface the spaces mid-line.
/// The caret lands at the text's start; Left from there lands before the
/// newline, on the line above; Backspace at the text's start removes the
/// newline and the indent together, joining the lines, and Delete before
/// the newline does the same. Attributes-in, range-out; the text view
/// applies the results.
enum ContinuationIndent {
    /// The unit in the paragraph containing `location`, or nil when that
    /// paragraph carries no pinned indent.
    static func unit(in storage: NSAttributedString, at location: Int) -> NSRange? {
        guard storage.length > 0, location <= storage.length else { return nil }
        let text = storage.string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        guard paragraph.length > 0, paragraph.location < storage.length else { return nil }
        var run = NSRange()
        guard storage.attribute(.pinned, at: paragraph.location, longestEffectiveRange: &run, in: paragraph) != nil,
              run.location == paragraph.location else { return nil }
        return run
    }

    /// `range` with no endpoint inside a unit, the unit's start included:
    /// a caret there stands after the newline with nothing to see. A
    /// selection widens to take the unit whole. A caret lands at the
    /// text's start, except one step left from there, which lands before
    /// the newline.
    static func snapped(_ range: NSRange, previous: NSRange?, in storage: NSAttributedString) -> NSRange {
        guard range.length > 0 else {
            guard let unit = unit(in: storage, at: range.location), range.location < NSMaxRange(unit) else { return range }
            if let previous, previous.length == 0, previous.location == NSMaxRange(unit),
               range.location == NSMaxRange(unit) - 1, unit.location > 0 {
                return NSRange(location: unit.location - 1, length: 0)
            }
            return NSRange(location: NSMaxRange(unit), length: 0)
        }
        var start = range.location
        var end = NSMaxRange(range)
        if let unit = unit(in: storage, at: start), start > unit.location, start < NSMaxRange(unit) { start = unit.location }
        if let unit = unit(in: storage, at: end), end > unit.location, end < NSMaxRange(unit) { end = NSMaxRange(unit) }
        return NSRange(location: start, length: end - start)
    }

    /// The newline and the indent, when the caret (`selection`, empty)
    /// sits at the text's start of a continuation; nil anywhere else.
    static func backspaceRange(in storage: NSAttributedString, selection: NSRange) -> NSRange? {
        guard selection.length == 0, let unit = unit(in: storage, at: selection.location),
              selection.location == NSMaxRange(unit), unit.location > 0 else { return nil }
        return NSRange(location: unit.location - 1, length: unit.length + 1)
    }

    /// The newline and the indent, when the caret (`selection`, empty)
    /// sits right before the newline a continuation follows; nil anywhere
    /// else.
    static func deleteForwardRange(in storage: NSAttributedString, selection: NSRange) -> NSRange? {
        guard selection.length == 0, selection.location < storage.length,
              (storage.string as NSString).character(at: selection.location) == 0x0A,
              let unit = unit(in: storage, at: selection.location + 1),
              unit.location == selection.location + 1 else { return nil }
        return NSRange(location: selection.location, length: unit.length + 1)
    }
}
