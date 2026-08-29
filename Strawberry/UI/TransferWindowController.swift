//
//  TransferWindowController.swift
//  Strawberry
//
//  Streams the Auto Media Sync rsync output into a plain scrolling text window.
//  Separate from the Sync Rules "Live Sync Log" (which is rule/record-bound).
//

import Cocoa

final class TransferWindowController: NSWindowController {
    static let shared = TransferWindowController()

    private var textView: NSTextView!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Auto Media Sync"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupTextView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTextView() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.1, alpha: 1)

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1)
        textView.textColor = NSColor(white: 0.9, alpha: 1)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView
        contentView.addSubview(scrollView)
        self.textView = textView
    }

    /// Clears the log and brings the window to the front.
    func clearAndShow() {
        textView.string = ""
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    /// Appends text and scrolls to the bottom. Must be called on the main thread.
    func append(_ text: String) {
        textView.string += text
        let end = NSRange(location: textView.string.count, length: 0)
        textView.scrollRangeToVisible(end)
    }
}
