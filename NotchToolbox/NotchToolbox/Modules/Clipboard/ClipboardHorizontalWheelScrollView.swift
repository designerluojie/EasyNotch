import AppKit
import SwiftUI

enum ClipboardWheelScrollMapper {
    static func targetOffset(
        currentOffset: CGFloat,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        deltaX: CGFloat,
        deltaY: CGFloat
    ) -> CGFloat? {
        guard abs(deltaY) > abs(deltaX), deltaY != 0 else {
            return nil
        }

        let maxOffset = max(contentWidth - viewportWidth, 0)
        guard maxOffset > 0 else {
            return nil
        }

        let proposedOffset = currentOffset - deltaY
        return min(max(proposedOffset, 0), maxOffset)
    }
}

struct ClipboardHorizontalWheelScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    var onReachedEnd: (() -> Void)?

    init(onReachedEnd: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onReachedEnd = onReachedEnd
    }

    func makeNSView(context: Context) -> ClipboardMappedHorizontalScrollView {
        let scrollView = ClipboardMappedHorizontalScrollView()
        scrollView.onReachedEnd = onReachedEnd
        scrollView.update(rootView: content)
        return scrollView
    }

    func updateNSView(_ scrollView: ClipboardMappedHorizontalScrollView, context: Context) {
        scrollView.onReachedEnd = onReachedEnd
        scrollView.update(rootView: content)
    }
}

final class ClipboardMappedHorizontalScrollView: NSScrollView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    /// Fired once each time horizontal scrolling reaches near the right edge, so
    /// the owner can page in more items.
    var onReachedEnd: (() -> Void)?
    private var wasNearEnd = false
    private let nearEndThreshold: CGFloat = 120

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        documentView = hostingView

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func clipViewBoundsChanged() {
        guard let documentView else {
            return
        }

        // Only meaningful when the content actually overflows the viewport.
        let isScrollable = documentView.frame.width > contentSize.width + 1
        let nearEnd = isScrollable
            && contentView.bounds.maxX >= documentView.frame.width - nearEndThreshold

        if nearEnd, !wasNearEnd {
            onReachedEnd?()
        }
        wasNearEnd = nearEnd
    }

    override func layout() {
        super.layout()
        updateDocumentFrame()
    }

    override func scrollWheel(with event: NSEvent) {
        guard
            let documentView,
            let mappedOffset = ClipboardWheelScrollMapper.targetOffset(
                currentOffset: contentView.bounds.origin.x,
                viewportWidth: contentSize.width,
                contentWidth: documentView.frame.width,
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            )
        else {
            super.scrollWheel(with: event)
            return
        }

        contentView.scroll(to: NSPoint(x: mappedOffset, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }

    func update<Content: View>(rootView: Content) {
        hostingView.rootView = AnyView(rootView)
        updateDocumentFrame()
    }

    private func updateDocumentFrame() {
        let viewportSize = contentSize
        var fittingSize = hostingView.fittingSize
        fittingSize.height = max(fittingSize.height, viewportSize.height)
        hostingView.frame = CGRect(origin: .zero, size: fittingSize)
    }
}
