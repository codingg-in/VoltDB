import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(ThemeState.self) private var themeState
    @Environment(\.openWindow) private var openWindow
    
    @State private var sidebarWidth: CGFloat = 240
    @State private var isDraggingDivider: Bool = false
    @State private var rightPanelWidth: CGFloat = 300
    @State private var isDraggingRightDivider: Bool = false
    @State private var isSidebarVisible: Bool = true
    @State private var isRightPanelVisible: Bool = false
    @State private var showCommandPalette = false
    @State private var pendingTabToClose: EditorTab? = nil
    @State private var showUnsavedChangesAlert: Bool = false
    @State private var currentWindow: NSWindow? = nil
    @State private var windowCloseDelegate: WorkspaceWindowDelegate? = nil
    
    init() {}
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified Full-Width Top Bar
            TabBarView(
                sidebarWidth: max(180, min(sidebarWidth, 450)),
                isSidebarVisible: $isSidebarVisible,
                isRightPanelVisible: $isRightPanelVisible,
                onRequestClose: { tab in
                    requestCloseTab(tab)
                },
                onDisconnect: {
                    closeAndDisconnectWorkspace()
                },
                onTitleBarDoubleClick: {
                    (NSApp.currentEvent?.window ?? currentWindow ?? NSApp.keyWindow)?.performZoom(nil)
                }
            )
            
            let currentSidebarWidth = max(180, min(sidebarWidth, 450))
            let currentRightWidth = max(240, min(rightPanelWidth, 600))
            
            HStack(spacing: 0) {
                // Left Sidebar (Smooth sliding with fixed-width content)
                ZStack(alignment: .trailing) {
                    SidebarView()
                        .frame(width: currentSidebarWidth)
                        .offset(x: isSidebarVisible ? 0 : -currentSidebarWidth)
                }
                .frame(width: isSidebarVisible ? currentSidebarWidth : 0)
                .clipped()
                
                // Draggable Divider
                Rectangle()
                    .fill(AppTheme.border.opacity(0.25))
                    .frame(width: isSidebarVisible ? 1 : 0)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .fill(isDraggingDivider ? AppTheme.accent : Color.clear)
                            .frame(width: isSidebarVisible ? 3 : 0)
                    )
                    .contentShape(Rectangle().inset(by: -3))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard isSidebarVisible else { return }
                                isDraggingDivider = true
                                sidebarWidth = max(180, min(sidebarWidth + value.translation.width, 450))
                            }
                            .onEnded { _ in
                                isDraggingDivider = false
                            }
                    )
                    .onHover { hovering in
                        if hovering && isSidebarVisible {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                
                // Center Work Area (Editor + Results + Bottom Status Bar)
                VStack(spacing: 0) {
                    ZStack {
                        AppTheme.backgroundPrimary
                        
                        if appState.connectionStatus == .connecting {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("Connecting to \(appState.activeConnection?.name ?? "Database")...")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        } else if case .error(let msg) = appState.connectionStatus {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.error)
                                Text("Connection Error")
                                    .font(.headline)
                                    .foregroundColor(AppTheme.textPrimary)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                
                                HStack(spacing: 12) {
                                    if let activeConn = appState.activeConnection {
                                        Button {
                                            Task {
                                                await appState.connect(config: activeConn)
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text("Retry Connection")
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(AppTheme.accent)
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Button {
                                        openWindow(id: "launcher")
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 11))
                                            Text("Open Connection Manager")
                                                .font(.system(size: 12))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(AppTheme.backgroundTertiary)
                                        .foregroundColor(AppTheme.textPrimary)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if let activeTab = tabState.activeTab {
                            if activeTab.type == .query {
                                QueryWorkspaceView(tab: activeTab)
                                    .id(activeTab.id)
                            } else if activeTab.type == .tableView {
                                TableViewerView(database: activeTab.database, tableName: activeTab.tableName ?? "")
                                    .id(activeTab.id)
                            }
                        } else {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Opening SQL Editor...")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .onAppear {
                                ensureEditorTabReady()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Divider()
                    
                    StatusBarView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Right Draggable Divider
                Rectangle()
                    .fill(AppTheme.border.opacity(0.25))
                    .frame(width: isRightPanelVisible ? 1 : 0)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .fill(isDraggingRightDivider ? AppTheme.accent : Color.clear)
                            .frame(width: isRightPanelVisible ? 3 : 0)
                    )
                    .contentShape(Rectangle().inset(by: -3))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard isRightPanelVisible else { return }
                                isDraggingRightDivider = true
                                rightPanelWidth = max(240, min(rightPanelWidth - value.translation.width, 600))
                            }
                            .onEnded { _ in
                                isDraggingRightDivider = false
                            }
                    )
                    .onHover { hovering in
                        if hovering && isRightPanelVisible {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                
                // Right Details Panel (Smooth sliding with fixed-width content)
                ZStack(alignment: .leading) {
                    DetailsPanelView(onClose: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isRightPanelVisible = false
                        }
                    })
                    .frame(width: currentRightWidth)
                    .offset(x: isRightPanelVisible ? 0 : currentRightWidth)
                }
                .frame(width: isRightPanelVisible ? currentRightWidth : 0)
                .clipped()
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSidebarVisible)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isRightPanelVisible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .background(AppTheme.backgroundPrimary)
        .overlay {
            if showCommandPalette {
                CommandPaletteView(isPresented: $showCommandPalette)
            }
        }
        .background(
            WindowAccessor { window in
                setupWorkspaceWindow(window)
            }
        )
        .onAppear {
            setupWorkspaceWindow(nil)
        }
        .onDisappear {
            tabState.saveSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            if let window = notif.object as? NSWindow, window.title != "VoltDB Connection Manager" && window.title != "VoltDB" {
                if self.currentWindow == nil || self.currentWindow == window {
                    setupWorkspaceWindow(window)
                }
            }
        }
        .onChange(of: appState.connectionStatus) { _, newStatus in
            currentWindow?.isDocumentEdited = (newStatus == .connected)
            if newStatus == .connected {
                ensureEditorTabReady()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeActiveTab)) { _ in
            guard isTargetWindowActive else { return }
            if let activeTab = tabState.activeTab {
                requestCloseTab(activeTab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
            guard isTargetWindowActive else { return }
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newQueryTab)) { _ in
            guard isTargetWindowActive else { return }
            tabState.addNewQueryTab(database: appState.currentDatabase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConnectionManager)) { _ in
            openWindow(id: "launcher")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            guard currentWindow?.isKeyWindow == true else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isSidebarVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRightPanel)) { _ in
            guard isTargetWindowActive else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isRightPanelVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousTab)) { _ in
            guard isTargetWindowActive else { return }
            tabState.selectPreviousTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextTab)) { _ in
            guard isTargetWindowActive else { return }
            tabState.selectNextTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notif in
            guard isTargetWindowActive else { return }
            if let index = notif.object as? Int {
                tabState.selectTab(at: index)
            }
        }
        .alert(
            "Do you want to save the changes made to '\(pendingTabToClose?.title ?? "Query")'?",
            isPresented: $showUnsavedChangesAlert,
            presenting: pendingTabToClose
        ) { tab in
            Button("Save...") {
                saveTabToFile(tab)
            }
            Button("Don't Save / Close", role: .destructive) {
                tabState.closeTab(id: tab.id)
                pendingTabToClose = nil
                if tabState.tabs.isEmpty {
                    tabState.addNewQueryTab(database: appState.currentDatabase)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingTabToClose = nil
            }
        } message: { tab in
            Text("Your changes will be lost if you close without saving.")
        }
    }
    
    private var isTargetWindowActive: Bool {
        guard let win = currentWindow else { return true }
        if win.isKeyWindow || win.isMainWindow { return true }
        if let keyWin = NSApp.keyWindow {
            return keyWin == win
        }
        return win.isVisible
    }
    
    private func hasUnsavedChanges(_ tab: EditorTab) -> Bool {
        if tab.type == .tableView {
            return tab.stagedChanges.count > 0
        } else {
            let sql = tab.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !sql.isEmpty
        }
    }
    
    private func requestCloseTab(_ tab: EditorTab) {
        if hasUnsavedChanges(tab) {
            pendingTabToClose = tab
            showUnsavedChangesAlert = true
        } else {
            tabState.closeTab(id: tab.id)
            if tabState.tabs.isEmpty {
                tabState.addNewQueryTab(database: appState.currentDatabase)
            }
        }
    }
    
    private func closeCurrentWorkspace() {
        let targetWindow = self.currentWindow
        targetWindow?.close()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let remainingWorkspaces = NSApp.windows.filter {
                $0 != targetWindow &&
                $0.isVisible && !$0.isMiniaturized &&
                $0.title != "VoltDB Connection Manager" &&
                $0.title != "VoltDB" &&
                !$0.title.isEmpty
            }
            let hasLauncher = NSApp.windows.contains {
                $0 != targetWindow && $0.isVisible &&
                ($0.title == "VoltDB Connection Manager" || $0.title == "VoltDB")
            }
            if remainingWorkspaces.isEmpty && !hasLauncher {
                openWindow(id: "launcher")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let launcher = NSApp.windows.first(where: {
                        $0.title == "VoltDB Connection Manager" || $0.title == "VoltDB"
                    }) {
                        launcher.center()
                        launcher.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
    }
    
    private func closeAndDisconnectWorkspace() {
        Task {
            await appState.disconnect()
            await MainActor.run {
                closeCurrentWorkspace()
            }
        }
    }
    
    private func saveTabToFile(_ tab: EditorTab) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Query"
        savePanel.prompt = "Save"
        savePanel.nameFieldStringValue = "\(tab.title.replacingOccurrences(of: " ", with: "_")).sql"
        savePanel.allowedContentTypes = [.init(filenameExtension: "sql") ?? .plainText]
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try tab.queryText.write(to: url, atomically: true, encoding: .utf8)
                tabState.closeTab(id: tab.id)
                pendingTabToClose = nil
                if tabState.tabs.isEmpty {
                    tabState.addNewQueryTab(database: appState.currentDatabase)
                }
            } catch {
                print("Failed to save query file: \(error)")
            }
        } else {
            pendingTabToClose = nil
        }
    }
    
    private func setupWorkspaceWindow(_ targetWindow: NSWindow? = nil) {
        DispatchQueue.main.async {
            guard let window = targetWindow ?? self.currentWindow ?? NSApp.windows.first(where: {
                $0.isVisible && $0.title != "VoltDB Connection Manager" && ($0.isKeyWindow || $0.isMainWindow)
            }) ?? NSApp.windows.first(where: { $0.isVisible && $0.title != "VoltDB Connection Manager" }) else { return }
            
            self.currentWindow = window
            
            let delegate = WorkspaceWindowDelegate(appState: appState, tabState: tabState, openLauncher: {
                openWindow(id: "launcher")
            })
            self.windowCloseDelegate = delegate
            window.delegate = delegate
            
            window.tabbingMode = .disallowed
            window.styleMask.insert([.resizable, .miniaturizable, .titled, .closable, .fullSizeContentView])
            window.minSize = NSSize(width: 850, height: 500)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.showsResizeIndicator = true
            
            window.title = "\(appState.activeConnection?.name ?? "VoltDB") - VoltDB"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            
            if let zoom = window.standardWindowButton(.zoomButton) {
                zoom.isHidden = false
                zoom.isEnabled = true
            }
            if let mini = window.standardWindowButton(.miniaturizeButton) {
                mini.isHidden = false
                mini.isEnabled = true
            }
            if let close = window.standardWindowButton(.closeButton) {
                close.isHidden = false
                close.isEnabled = true
            }
            
            window.isDocumentEdited = (appState.connectionStatus == .connected)
        }
    }
    
    private func ensureEditorTabReady() {
        tabState.restoreSession(for: appState.activeConnection?.id, defaultDatabase: appState.currentDatabase)
        if tabState.tabs.isEmpty {
            tabState.addNewQueryTab(database: appState.currentDatabase)
        }
    }
}

// MARK: - Window Close → Disconnect Delegate

final class WorkspaceWindowDelegate: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let tabState: TabState
    private let openLauncher: () -> Void
    private var isDisconnectingAndClosing = false
    
    init(appState: AppState, tabState: TabState, openLauncher: @escaping () -> Void) {
        self.appState = appState
        self.tabState = tabState
        self.openLauncher = openLauncher
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isDisconnectingAndClosing {
            tabState.saveSession()
            return true
        }
        
        let modifiedTabs = tabState.tabs.filter { $0.stagedChanges.count > 0 }
        if !modifiedTabs.isEmpty {
            let total = modifiedTabs.reduce(0) { $0 + $1.stagedChanges.count }
            let alert = NSAlert()
            alert.messageText = "Uncommitted Changes in Query Output"
            let names = modifiedTabs.map { "\($0.title) (\($0.stagedChanges.count))" }.joined(separator: ", ")
            alert.informativeText = "This workspace has \(total) uncommitted \(total == 1 ? "change" : "changes") in query output (\(names)).\n\nIf you close this window, these uncommitted changes will be permanently lost.\n\nDo you want to discard your changes and close?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard and Close")
            
            NSApp.activate(ignoringOtherApps: true)
            let res = alert.runModal()
            if res != .alertSecondButtonReturn {
                return false
            }
            
            // User confirmed discard
            for idx in tabState.tabs.indices {
                tabState.tabs[idx].stagedChanges.clear()
            }
        }
        
        tabState.saveSession()
        
        if appState.connectionStatus == .connected || appState.connectionStatus == .connecting {
            isDisconnectingAndClosing = true
            Task {
                await appState.disconnect()
                await MainActor.run {
                    sender.close()
                    self.checkAndOpenLauncherIfNeeded(excluding: sender)
                }
            }
            return false
        }
        
        self.checkAndOpenLauncherIfNeeded(excluding: sender)
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        tabState.saveSession()
        if appState.connectionStatus == .connected || appState.connectionStatus == .connecting {
            Task {
                await appState.disconnect()
            }
        }
        if let window = notification.object as? NSWindow {
            checkAndOpenLauncherIfNeeded(excluding: window)
        }
    }
    
    private func checkAndOpenLauncherIfNeeded(excluding window: NSWindow) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let remainingWorkspaces = NSApp.windows.filter {
                $0 != window &&
                $0.isVisible && !$0.isMiniaturized &&
                $0.title != "VoltDB Connection Manager" &&
                $0.title != "VoltDB" &&
                !$0.title.isEmpty
            }
            let hasLauncher = NSApp.windows.contains {
                $0 != window && $0.isVisible &&
                ($0.title == "VoltDB Connection Manager" || $0.title == "VoltDB")
            }
            if remainingWorkspaces.isEmpty && !hasLauncher {
                self?.openLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let launcher = NSApp.windows.first(where: {
                        $0.title == "VoltDB Connection Manager" || $0.title == "VoltDB"
                    }) {
                        launcher.center()
                        launcher.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
    }
}
