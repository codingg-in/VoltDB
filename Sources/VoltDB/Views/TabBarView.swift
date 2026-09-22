import SwiftUI
import AppKit

struct TabBarView: View {
    @Environment(TabState.self) private var tabState
    @Environment(AppState.self) private var appState
    @Environment(SchemaState.self) private var schemaState
    @Environment(ThemeState.self) private var themeState
    @Environment(\.openWindow) private var openWindow
    
    var sidebarWidth: CGFloat = 240
    @Binding var isSidebarVisible: Bool
    @Binding var isRightPanelVisible: Bool
    var onRequestClose: ((EditorTab) -> Void)? = nil
    var onDisconnect: (() -> Void)? = nil
    var onTitleBarDoubleClick: (() -> Void)? = nil
    
    @State private var showConnectionsPopover: Bool = false
    @State private var showDatabasesPopover: Bool = false
    
    @State private var canScrollLeft: Bool = false
    @State private var canScrollRight: Bool = false
    
    init(
        sidebarWidth: CGFloat = 240,
        isSidebarVisible: Binding<Bool> = .constant(true),
        isRightPanelVisible: Binding<Bool> = .constant(false),
        onRequestClose: ((EditorTab) -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil,
        onTitleBarDoubleClick: (() -> Void)? = nil
    ) {
        self.sidebarWidth = sidebarWidth
        self._isSidebarVisible = isSidebarVisible
        self._isRightPanelVisible = isRightPanelVisible
        self.onRequestClose = onRequestClose
        self.onDisconnect = onDisconnect
        self.onTitleBarDoubleClick = onTitleBarDoubleClick
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Navigator section aligned with sidebar width
            HStack(spacing: 8) {
                // Traffic light clearance (macOS window controls)
                Spacer()
                    .frame(width: 72)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        handleTitleBarDoubleClick()
                    }
                
                // Capsule Navigator [ ☰ Sidebar | 🌐 Connections | 🛢 Database ]
                HStack(spacing: 2) {
                    // 1. Sidebar Toggle Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11))
                            .foregroundColor(isSidebarVisible ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(width: 24, height: 20)
                            .background(isSidebarVisible ? AppTheme.accent.opacity(0.15) : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help(isSidebarVisible ? "Hide Sidebar (⌘B)" : "Show Sidebar (⌘B)")
                    
                    Divider()
                        .frame(height: 12)
                    
                    // 2. Globe Connection List Popover Button
                    Button {
                        showConnectionsPopover.toggle()
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundColor(showConnectionsPopover ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(width: 24, height: 20)
                            .background(showConnectionsPopover ? AppTheme.accent.opacity(0.15) : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Switch Connection")
                    .popover(isPresented: $showConnectionsPopover, arrowEdge: .bottom) {
                        ConnectionsPopoverView(isPresented: $showConnectionsPopover, onDisconnect: onDisconnect)
                    }
                    
                    Divider()
                        .frame(height: 12)
                    
                    // 3. Quick Database Selector Popover Button
                    Button {
                        showDatabasesPopover.toggle()
                    } label: {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 11))
                            .foregroundColor(showDatabasesPopover ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(width: 24, height: 20)
                            .background(showDatabasesPopover ? AppTheme.accent.opacity(0.15) : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Select Database")
                    .popover(isPresented: $showDatabasesPopover, arrowEdge: .bottom) {
                        DatabasePickerPopoverView(isPresented: $showDatabasesPopover)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(AppTheme.backgroundTertiary)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
                
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        handleTitleBarDoubleClick()
                    }
            }
            .frame(width: isSidebarVisible ? max(180, sidebarWidth) : 180, alignment: .leading)
            .background(
                AppTheme.backgroundSecondary
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        handleTitleBarDoubleClick()
                    }
            )
            
            if isSidebarVisible {
                Rectangle()
                    .fill(AppTheme.border.opacity(0.25))
                    .frame(width: 1)
            }
            
            // Middle: Horizontal Tab Strip with Dynamic Left/Right Scroll Arrows
            ScrollViewReader { proxy in
                HStack(spacing: 2) {
                    // Left Scroll Arrow (ONLY when left scroll is possible)
                    if canScrollLeft {
                        Button {
                            scrollTab(direction: -1, proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 14, height: 22)
                                .background(AppTheme.backgroundTertiary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Scroll Tabs Left")
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tabState.tabs) { tab in
                                CapsuleTabButton(tab: tab, onRequestClose: onRequestClose)
                                    .id(tab.id)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .background(TabBarScrollViewAccessor(canScrollLeft: $canScrollLeft, canScrollRight: $canScrollRight))
                    }
                    .frame(height: 32)
                    
                    // Right Scroll Arrow (ONLY when right scroll is possible)
                    if canScrollRight {
                        Button {
                            scrollTab(direction: 1, proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 14, height: 22)
                                .background(AppTheme.backgroundTertiary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Scroll Tabs Right")
                    }
                }
                .onChange(of: tabState.activeTabId) { _, newId in
                    if let newId = newId {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
            
            Spacer(minLength: 8)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleTitleBarDoubleClick()
                }
            
            // Center / Right: Connection & DB Pill (Static Display)
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.connectionStatus == .connected ? AppTheme.success : (appState.connectionStatus == .connecting ? AppTheme.warning : AppTheme.error))
                    .frame(width: 6, height: 6)
                
                Text(appState.activeConnection?.name ?? "No Connection")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .leading)
                
                if appState.activeConnection?.isProduction == true {
                    Text("PROD")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.85))
                        )
                        .help("Production Environment")
                }
                
                Text("|")
                    .font(.system(size: 8))
                    .foregroundColor(AppTheme.textMuted.opacity(0.6))
                
                Text(databasePillText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(databasePillColor)
                    .lineLimit(1)
                    .frame(maxWidth: 85, alignment: .leading)
                
                // SSL Indicator
                if appState.activeConnection?.useSSL == true && appState.connectionStatus == .connected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7))
                        .foregroundColor(AppTheme.success)
                        .help("SSL Encrypted Connection")
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        appState.activeConnection?.isProduction == true ? Color.red.opacity(0.5) : AppTheme.border.opacity(0.5),
                        lineWidth: 1
                    )
            )
            
            // Right Side Actions: [ Search | + New Tab | Right Panel ]
            HStack(spacing: 4) {
                // 1. Search / Command Palette
                Button {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 24, height: 20)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Search / Command Palette (⌘P)")
                
                // 2. Add New Query Tab
                Button {
                    tabState.addNewQueryTab(database: appState.currentDatabase)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 24, height: 20)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("New Query Tab (⌘N)")
                
                // 3. Right Panel Toggle Button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRightPanelVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 10))
                        .foregroundColor(isRightPanelVisible ? AppTheme.accent : AppTheme.textSecondary)
                        .frame(width: 24, height: 20)
                        .background(isRightPanelVisible ? AppTheme.accent.opacity(0.15) : AppTheme.backgroundTertiary)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help(isRightPanelVisible ? "Hide Details Panel" : "Show Details Panel")
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
        }
        .frame(height: 36)
        .background(
            AppTheme.backgroundSecondary
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleTitleBarDoubleClick()
                }
        )
        .overlay(
            Rectangle()
                .fill(AppTheme.border.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func scrollTab(direction: Int, proxy: ScrollViewProxy) {
        guard let currentId = tabState.activeTabId,
              let currentIndex = tabState.tabs.firstIndex(where: { $0.id == currentId }) else {
            if let first = tabState.tabs.first {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(first.id, anchor: .center)
                }
            }
            return
        }
        
        let newIndex = min(max(0, currentIndex + direction * 2), tabState.tabs.count - 1)
        let targetTab = tabState.tabs[newIndex]
        tabState.activeTabId = targetTab.id
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(targetTab.id, anchor: .center)
        }
    }
    
    private func handleTitleBarDoubleClick() {
        if let onTitleBarDoubleClick = onTitleBarDoubleClick {
            onTitleBarDoubleClick()
            return
        }
        guard let window = NSApp.currentEvent?.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        window.performZoom(nil)
    }
    
    private var databasePillText: String {
        switch appState.connectionStatus {
        case .connected:
            return currentDatabaseDisplayName
        case .connecting:
            return "Connecting..."
        case .error:
            return "Error"
        case .disconnected:
            return "Disconnected"
        }
    }
    
    private var databasePillColor: Color {
        switch appState.connectionStatus {
        case .connected:
            return AppTheme.textSecondary
        case .connecting:
            return AppTheme.warning
        case .error:
            return AppTheme.error
        case .disconnected:
            return AppTheme.textMuted
        }
    }
    
    private var currentDatabaseDisplayName: String {
        if let tabDB = tabState.activeTab?.database, !tabDB.isEmpty {
            return tabDB
        }
        if !appState.currentDatabase.isEmpty {
            return appState.currentDatabase
        }
        return "default"
    }
}

// MARK: - Capsule Tab Button

private struct CapsuleTabButton: View {
    @Environment(TabState.self) private var tabState
    let tab: EditorTab
    var onRequestClose: ((EditorTab) -> Void)? = nil
    @State private var isHovering = false
    
    var isActive: Bool {
        tabState.activeTabId == tab.id
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Icon: <> symbol for query, table for table
            if tab.type == .query {
                Text("<>")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(AppTheme.accentLight)
            } else {
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#f1fa8c"))
            }
            
            Text(tab.title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(1)
            
            Button {
                if let onRequestClose = onRequestClose {
                    onRequestClose(tab)
                } else {
                    tabState.closeTab(id: tab.id)
                }
            } label: {
                if isHovering || isActive {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(isHovering ? AppTheme.backgroundHover : Color.clear))
                } else {
                    Circle()
                        .fill(AppTheme.textMuted.opacity(0.4))
                        .frame(width: 4, height: 4)
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            isActive
                ? AppTheme.backgroundTertiary
                : (isHovering ? AppTheme.backgroundHover.opacity(0.5) : Color.clear)
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? AppTheme.border.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabState.activeTabId = tab.id
        }
        .onHover { hover in
            isHovering = hover
        }
    }
}

// MARK: - Tab Bar Scroll View Accessor

private struct TabBarScrollViewAccessor: NSViewRepresentable {
    @Binding var canScrollLeft: Bool
    @Binding var canScrollRight: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            setup(for: view, coordinator: context.coordinator)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async {
            context.coordinator.updateScrollState()
        }
    }
    
    private func setup(for view: NSView, coordinator: Coordinator) {
        if let sv = view.enclosingScrollView {
            coordinator.attach(to: sv)
            return
        }
        var current: NSView? = view
        while current != nil {
            if let sv = current as? NSScrollView {
                coordinator.attach(to: sv)
                return
            }
            if let sv = current?.enclosingScrollView {
                coordinator.attach(to: sv)
                return
            }
            current = current?.superview
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: TabBarScrollViewAccessor
        weak var scrollView: NSScrollView?
        
        init(_ parent: TabBarScrollViewAccessor) {
            self.parent = parent
        }
        
        func attach(to sv: NSScrollView) {
            self.scrollView = sv
            sv.contentView.postsBoundsChangedNotifications = true
            sv.postsFrameChangedNotifications = true
            
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onScrollOrResize),
                name: NSView.boundsDidChangeNotification,
                object: sv.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onScrollOrResize),
                name: NSView.frameDidChangeNotification,
                object: sv
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onScrollOrResize),
                name: NSScrollView.didLiveScrollNotification,
                object: sv
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateScrollState()
            }
        }
        
        @objc func onScrollOrResize() {
            updateScrollState()
        }
        
        func updateScrollState() {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            let clipWidth = sv.contentView.bounds.width
            let docWidth = doc.frame.width
            let originX = sv.contentView.bounds.origin.x
            
            let overflow = docWidth - clipWidth
            let newCanLeft = overflow > 4 && originX > 2
            let newCanRight = overflow > 4 && originX < (overflow - 2)
            
            DispatchQueue.main.async {
                if self.parent.canScrollLeft != newCanLeft {
                    self.parent.canScrollLeft = newCanLeft
                }
                if self.parent.canScrollRight != newCanRight {
                    self.parent.canScrollRight = newCanRight
                }
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Window Frame Memory

final class WindowFrameMemory {
    private static var savedFrames: [ObjectIdentifier: NSRect] = [:]
    
    static func saveFrame(_ frame: NSRect, for window: NSWindow) {
        savedFrames[ObjectIdentifier(window)] = frame
    }
    
    static func getPreviousFrame(for window: NSWindow) -> NSRect? {
        return savedFrames[ObjectIdentifier(window)]
    }
}
