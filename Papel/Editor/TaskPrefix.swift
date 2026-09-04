import Foundation

/// A task item's prefix — `- [ ] ` or `- [x] `, marker through the gap after
/// the box — is one unit for the caret (#53). The circle stands in for it on
/// every paragraph, so there is nothing to edit inside it: Left from the
/// text's start lands before the marker, Right from there lands at the
/// text's start, a selection that reaches into it takes it whole, and
/// Backspace at the text's start removes it entirely. Nested indent before
/// the marker is not part of the unit. Pure text-in, range-out; the text
/// view applies the results.
enum TaskPrefix {
    /// The unit in the paragraph containing `location`, or nil when that
    /// paragraph is not a task item.
    static func unit(in text: NSString, at location: Int) -> NSRange? {
        guard location <= text.length else { return nil }
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        guard let match = MarkdownSyntaxStyler.listMarkerPattern.firstMatch(in: text as String, range: paragraph),
              match.range.location == paragraph.location,
              match.range(at: 3).location != NSNotFound else { return nil }
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
    /// at the text's start of a task item; nil anywhere else.
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
