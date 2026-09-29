import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    var text: String
    var wrap: Bool
    var lineNumbers: Bool
    var follow: Bool
    var query: String
    var matchIndex: Int
    var identity: String

    final class Coordinator {
        var text = ""
        var rendered = ""
        var query = ""
        var matchIndex = Int.min
        var identity = ""
        var lineNumbers = false
        var ranges: [NSRange] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textColor = .textColor
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.isVerticallyResizable = true
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        let coordinator = context.coordinator
        let changedIdentity = coordinator.identity != identity
        let changedText = coordinator.text != text || coordinator.lineNumbers != lineNumbers || changedIdentity
        let changedSearch = coordinator.query != query || coordinator.matchIndex != matchIndex || changedText
        let position = scroll.contentView.bounds.origin
        let selection = view.selectedRange()
        view.isHorizontallyResizable = !wrap
        view.textContainer?.widthTracksTextView = wrap
        view.textContainer?.containerSize = NSSize(width: wrap ? max(1, scroll.contentSize.width - 24) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = wrap ? [.width] : []
        if changedText {
            coordinator.rendered = lineNumbers ? Self.numbered(text) : text
            view.string = coordinator.rendered
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.textColor], range: NSRange(location: 0, length: storage.length))
            coordinator.text = text; coordinator.lineNumbers = lineNumbers; coordinator.identity = identity
            if !changedIdentity, NSMaxRange(selection) <= storage.length { view.setSelectedRange(selection) }
        }
        if changedSearch {
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
            coordinator.ranges = Self.ranges(in: coordinator.rendered, query: query)
            for range in coordinator.ranges { storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25), range: range) }
            if !coordinator.ranges.isEmpty {
                let count = coordinator.ranges.count
                let range = coordinator.ranges[((matchIndex % count) + count) % count]
                storage.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.5), range: range)
                view.scrollRangeToVisible(range)
            }
            coordinator.query = query; coordinator.matchIndex = matchIndex
        }
        if query.isEmpty && changedText {
            if follow { view.scrollToEndOfDocument(nil) }
            else if changedIdentity { view.scrollToBeginningOfDocument(nil) }
            else { scroll.contentView.scroll(to: position); scroll.reflectScrolledClipView(scroll.contentView) }
        }
    }

    nonisolated static func numbered(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let width = String(lines.count).count
        return lines.enumerated().map { i, line in
            String(repeating: " ", count: max(0, width - String(i + 1).count)) + "\(i + 1)  │  \(line)"
        }.joined(separator: "\n")
    }

    nonisolated static func ranges(in text: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let source = text as NSString
        var search = NSRange(location: 0, length: source.length)
        var result: [NSRange] = []
        while search.length > 0 {
            let range = source.range(of: query, options: [.caseInsensitive], range: search)
            guard range.location != NSNotFound, range.length > 0 else { break }
            result.append(range)
            let next = NSMaxRange(range)
            search = NSRange(location: next, length: source.length - next)
        }
        return result
    }
}
