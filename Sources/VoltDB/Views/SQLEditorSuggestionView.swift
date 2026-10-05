import AppKit
import SwiftUI

// MARK: - Suggestion Model

enum SuggestionKind: Equatable {
    case keyword
    case function
    case table
    case column
    case dataType
    case database
    
    var badge: String {
        switch self {
        case .keyword: return "SQL"
        case .function: return "FUNC"
        case .table: return "TABLE"
        case .column: return "COL"
        case .dataType: return "TYPE"
        case .database: return "DB"
        }
    }
    
    var color: Color {
        switch self {
        case .keyword: return Color.pink
        case .function: return Color.purple
        case .table: return Color.orange
        case .column: return Color.cyan
        case .dataType: return Color.indigo
        case .database: return Color.green
        }
    }
}

struct SuggestionItem: Identifiable, Equatable {
    var id: String { "\(kind.badge)_\(text)" }
    let text: String
    let insertText: String
    let kind: SuggestionKind
}

// MARK: - Non-Activating Floating Panel

internal final class SuggestionPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.ignoresMouseEvents = false
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Suggestion Controller

@MainActor
final class SuggestionController: ObservableObject {
    var items: [SuggestionItem] = []
    var selectedIndex: Int = 0
    var wordRange: NSRange = NSRange(location: 0, length: 0)
    weak var textView: NSTextView?
    
    var isVisible: Bool {
        panel?.isVisible ?? false
    }
    
    public private(set) var isApplying: Bool = false
    private var panel: SuggestionPanel?
    private var hostingView: NSHostingView<SuggestionPopupView>?
    
    func show(items: [SuggestionItem], wordRange: NSRange, in textView: NSTextView) {
        guard !items.isEmpty, let window = textView.window else {
            hide()
            return
        }
        
        self.items = items
        self.selectedIndex = 0
        self.wordRange = wordRange
        self.textView = textView
        
        let cursor = textView.selectedRange().location
        let cursorRect = textView.firstRect(forCharacterRange: NSRange(location: cursor, length: 0), actualRange: nil)
        guard cursorRect.height > 0 else {
            hide()
            return
        }
        
        let popupWidth: CGFloat = 280
        let rowHeight: CGFloat = 28
        let visibleRows = min(items.count, 7)
        let popupHeight = CGFloat(visibleRows) * rowHeight + 12
        
        var x = cursorRect.origin.x
        var y = cursorRect.origin.y - popupHeight - 4
        
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            if y < screenFrame.minY + 20 {
                y = cursorRect.origin.y + cursorRect.height + 4
            }
            if x + popupWidth > screenFrame.maxX - 10 {
                x = screenFrame.maxX - popupWidth - 10
            }
            if x < screenFrame.minX + 10 {
                x = screenFrame.minX + 10
            }
        }
        
        let frame = NSRect(x: x, y: y, width: popupWidth, height: popupHeight)
        
        if panel == nil {
            let newPanel = SuggestionPanel()
            let newHosting = NSHostingView(rootView: makePopupView())
            newHosting.autoresizingMask = [.width, .height]
            newPanel.contentView = newHosting
            self.hostingView = newHosting
            self.panel = newPanel
        }
        
        panel?.setFrame(frame, display: true)
        updateView()
        
        if panel?.parent == nil {
            window.addChildWindow(panel!, ordered: .above)
        }
        panel?.orderFront(nil)
        panel?.displayIfNeeded()
    }
    
    private func makePopupView() -> SuggestionPopupView {
        SuggestionPopupView(
            items: self.items,
            selectedIndex: self.selectedIndex,
            onSelect: { [weak self] index in
                self?.selectedIndex = index
                self?.applySelected()
            }
        )
    }
    
    private func updateView() {
        guard let panel = panel, let hostingView = hostingView else { return }
        hostingView.rootView = makePopupView()
        hostingView.needsDisplay = true
        panel.displayIfNeeded()
    }
    
    func hide() {
        guard isVisible else { return }
        if let p = panel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        items = []
        selectedIndex = 0
    }
    
    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        updateView()
    }
    
    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        updateView()
    }
    
    func applySelected() {
        guard let textView = textView, selectedIndex >= 0, selectedIndex < items.count else {
            hide()
            return
        }
        let chosen = items[selectedIndex].insertText
        let range = wordRange
        hide()
        
        isApplying = true
        defer { isApplying = false }
        
        if textView.shouldChangeText(in: range, replacementString: chosen) {
            textView.replaceCharacters(in: range, with: chosen)
            let newCursor = range.location + (chosen as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            textView.didChangeText()
        }
    }
}

// MARK: - Suggestion Popup View

struct SuggestionPopupView: View {
    let items: [SuggestionItem]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: items.count > 7) {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button(action: {
                            onSelect(index)
                        }) {
                            HStack(spacing: 8) {
                                Text(item.kind.badge)
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(item.kind.color.opacity(0.18))
                                    .foregroundColor(item.kind.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                
                                Text(item.text)
                                    .font(AppTheme.editorFont)
                                    .foregroundColor(index == selectedIndex ? .white : Color(nsColor: .textColor))
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(index == selectedIndex ? AppTheme.accent.opacity(0.85) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < items.count {
                    withAnimation(.easeInOut(duration: 0.08)) {
                        proxy.scrollTo(items[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border.opacity(0.5), lineWidth: 1)
        )
    }
}
