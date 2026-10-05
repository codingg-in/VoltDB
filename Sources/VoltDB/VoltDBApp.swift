import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openLauncherWindow: (() -> Void)?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Disable macOS window tabbing and tab bars
        NSWindow.allowsAutomaticWindowTabbing = false
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
        
        KeyboardShortcutManager.setupGlobalShortcuts()
        
        if let window = NSApp.windows.first {
            window.tabbingMode = .disallowed
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        
        removeTabBarMenuItems()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
        
        // Watch for window close to re-open Connection Manager when all workspace windows are gone
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        for state in TabState.activeInstances.allObjects {
            state.saveSession()
        }
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.tabbingMode = .disallowed
        }
        removeTabBarMenuItems()
    }
    
    @objc private func menuDidAddItem(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.removeTabBarMenuItems()
        }
    }
    
    private func removeTabBarMenuItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let blockedSelectors: Set<String> = [
            "toggleTabBar:",
            "toggleTabOverview:"
        ]
        let blockedTitles: Set<String> = [
            "Show Tab Bar",
            "Hide Tab Bar",
            "Show All Tabs"
        ]
        
        func cleanMenu(_ menu: NSMenu) {
            var indicesToRemove: [Int] = []
            for (idx, item) in menu.items.enumerated() {
                if let submenu = item.submenu {
                    cleanMenu(submenu)
                }
                let actionName = item.action != nil ? NSStringFromSelector(item.action!) : ""
                if blockedSelectors.contains(actionName) || blockedTitles.contains(item.title) {
                    indicesToRemove.append(idx)
                }
            }
            for idx in indicesToRemove.reversed() {
                menu.removeItem(at: idx)
            }
        }
        
        cleanMenu(mainMenu)
    }
    
    private func isLauncherWindow(_ window: NSWindow?) -> Bool {
        guard let window = window else { return false }
        if window.title == "VoltDB Connection Manager" || window.title == "VoltDB" {
            return true
        }
        if !window.styleMask.contains(.resizable) && window.frame.width <= 850 {
            return true
        }
        return false
    }
    
    @objc private func windowDidClose(_ notification: Notification) {
        let closingWindow = notification.object as? NSWindow
        
        // If the closing window is the Connection Manager launcher itself, DO NOT reopen it!
        // Closing the launcher should leave it closed.
        if isLauncherWindow(closingWindow) || closingWindow is NSPanel || closingWindow?.isSheet == true {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let remainingWorkspaces = NSApp.windows.filter {
                $0 != closingWindow &&
                $0.isVisible && !$0.isMiniaturized &&
                $0.title != "VoltDB Connection Manager" &&
                $0.title != "VoltDB" &&
                !$0.title.isEmpty &&
                !($0 is NSPanel)
            }
            let hasLauncher = NSApp.windows.contains {
                $0 != closingWindow && $0.isVisible &&
                ($0.title == "VoltDB Connection Manager" || $0.title == "VoltDB")
            }
            if remainingWorkspaces.isEmpty && !hasLauncher {
                self?.openLauncherWindow?()
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
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openLauncherWindow?()
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let (totalChanges, tabsWithChanges) = TabState.uncommittedChangesSummary()
        guard totalChanges > 0 else {
            return .terminateNow
        }
        
        let alert = NSAlert()
        alert.messageText = "Uncommitted Changes in Query Output"
        let tabsText = tabsWithChanges.joined(separator: ", ")
        alert.informativeText = "You have \(totalChanges) uncommitted \(totalChanges == 1 ? "change" : "changes") in query output (\(tabsText)).\n\nIf you quit VoltDB now, these uncommitted changes will be permanently lost.\n\nDo you want to discard your changes and quit?"
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard and Quit")
        
        // Cancel is default button (Return / Esc)
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = [.command]
        
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // User explicitly chose "Discard and Quit": clear staged changes to avoid duplicate window alerts
            for state in TabState.activeInstances.allObjects {
                for idx in state.tabs.indices {
                    state.tabs[idx].stagedChanges.clear()
                }
            }
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }
}

/// Root view for each independent window session.
@MainActor
struct WindowRootView: View {
    let connectionId: UUID?
    
    @State private var appState: AppState
    @State private var schemaState: SchemaState
    @State private var tabState = TabState()
    @Environment(ThemeState.self) private var themeState
    @Environment(\.openWindow) private var openWindow
    
    init(connectionId: UUID? = nil) {
        self.connectionId = connectionId
        let app = AppState()
        self._appState = State(initialValue: app)
        self._schemaState = State(initialValue: SchemaState(dbManager: app.dbManager))
    }
    
    var body: some View {
        ContentView()
            .environment(appState)
            .environment(schemaState)
            .environment(tabState)
            .frame(minWidth: 1000, minHeight: 600)
            .preferredColorScheme(themeState.resolvedColorScheme)
            .task(id: connectionId) {
                await connect(to: connectionId)
            }
            .onChange(of: connectionId) { _, newId in
                Task {
                    await connect(to: newId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .connectToWorkspace)) { note in
                if let targetId = note.object as? UUID, targetId == connectionId {
                    Task {
                        await connect(to: targetId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groupColorsChanged)) { _ in
                appState.loadGroupColors()
                appState.loadCustomGroups()
            }
            .onReceive(NotificationCenter.default.publisher(for: .connectionsChanged)) { _ in
                appState.loadConnections()
                if let activeId = appState.activeConnection?.id,
                   let updated = appState.savedConnections.first(where: { $0.id == activeId }) {
                    appState.activeConnection = updated
                }
            }
            .onAppear {
                (NSApp.delegate as? AppDelegate)?.openLauncherWindow = {
                    openWindow(id: "launcher")
                }
            }
    }
    
    private func connect(to targetId: UUID?, force: Bool = false) async {
        guard let targetId = targetId else { return }
        
        // Always refresh connections, custom groups, and group colors from disk
        appState.loadConnections()
        appState.loadCustomGroups()
        appState.loadGroupColors()
        
        if let config = appState.savedConnections.first(where: { $0.id == targetId }) {
            if appState.activeConnection?.id == targetId {
                appState.activeConnection = config
            }
        }
        
        if !force {
            guard appState.connectionStatus != .connected && appState.connectionStatus != .connecting else { return }
        } else {
            if appState.connectionStatus == .connecting { return }
            if appState.connectionStatus == .connected && appState.activeConnection?.id == targetId { return }
        }
        
        guard let config = appState.savedConnections.first(where: { $0.id == targetId }) else { return }
        
        await appState.connect(config: config)
        await MainActor.run {
            tabState.restoreSession(for: config.id, defaultDatabase: config.database)
            if tabState.tabs.isEmpty {
                tabState.addNewQueryTab(database: config.database)
            }
        }
    }
}

@main
struct VoltDBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var themeState = ThemeState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 1. Connection Manager Launcher (Fixed size, non-resizable, non-minimizable)
        WindowGroup("VoltDB Connection Manager", id: "launcher") {
            ConnectionManagerView()
                .environment(themeState)
                .onReceive(NotificationCenter.default.publisher(for: .openConnectionManager)) { _ in
                    openWindow(id: "launcher")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 840, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Connection Manager...") {
                    openWindow(id: "launcher")
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Button("New Query Tab") {
                    if let keyWindow = NSApp.keyWindow,
                       keyWindow.title != "VoltDB Connection Manager" && keyWindow.title != "VoltDB" {
                        NotificationCenter.default.post(name: .newQueryTab, object: nil)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Close Tab") {
                    if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow {
                        let isLauncher = keyWindow.title == "VoltDB Connection Manager" ||
                                         keyWindow.title == "VoltDB" ||
                                         (!keyWindow.styleMask.contains(.resizable) && keyWindow.frame.width <= 850)
                        if isLauncher {
                            keyWindow.close()
                        } else {
                            NotificationCenter.default.post(name: .closeActiveTab, object: nil)
                        }
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Button("Close Window") {
                    if let keyWindow = NSApp.keyWindow {
                        keyWindow.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                
                Divider()
                
                Button("New Window") {
                    openWindow(id: "launcher")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Query") {
                Button("Run Current Query") {
                    NotificationCenter.default.post(name: .runCurrentQuery, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Run All Queries") {
                    NotificationCenter.default.post(name: .runAllQueries, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])

                Button("Stop Running Query") {
                    NotificationCenter.default.post(name: .stopQuery, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Button("Explain Query") {
                    NotificationCenter.default.post(name: .explainQuery, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])

                Divider()

                Button("Format SQL") {
                    NotificationCenter.default.post(name: .formatSQL, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Toggle Comment") {
                    NotificationCenter.default.post(name: .toggleComment, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Data") {
                Button("New Row") {
                    NotificationCenter.default.post(name: .addNewRow, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                
                Divider()
                
                Button("Commit Changes") {
                    if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow {
                        let isLauncher = keyWindow.title == "VoltDB Connection Manager" ||
                                         keyWindow.title == "VoltDB" ||
                                         (!keyWindow.styleMask.contains(.resizable) && keyWindow.frame.width <= 850)
                        if isLauncher {
                            keyWindow.makeFirstResponder(nil)
                            NotificationCenter.default.post(name: .saveConnection, object: nil)
                        } else {
                            NotificationCenter.default.post(name: .commitChanges, object: nil)
                        }
                    } else {
                        NotificationCenter.default.post(name: .commitChanges, object: nil)
                    }
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Rollback Changes") {
                    NotificationCenter.default.post(name: .rollbackChanges, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .option])

                Divider()

                Button("Reload Data / Refresh Schema") {
                    NotificationCenter.default.post(name: .refreshSchema, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Previous Page") {
                    NotificationCenter.default.post(name: .previousPage, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Next Page") {
                    NotificationCenter.default.post(name: .nextPage, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("First Page") {
                    NotificationCenter.default.post(name: .firstPage, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("Last Page") {
                    NotificationCenter.default.post(name: .lastPage, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }

            CommandMenu("Navigate") {
                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .selectPreviousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .selectNextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("Select Database...") {
                    NotificationCenter.default.post(name: .toggleDatabasePicker, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Switch Connection...") {
                    NotificationCenter.default.post(name: .toggleConnectionsPicker, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .sidebar) {
                Button("Open Anything (Command Palette)") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
                
                Divider()
                
                Button("Toggle Left Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                
                Button("Toggle Details Panel") {
                    NotificationCenter.default.post(name: .toggleRightPanel, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        
        // 2. Full Workspace Window per connected database
        WindowGroup("VoltDB Workspace", for: UUID.self) { $connectionId in
            WindowRootView(connectionId: connectionId)
                .environment(themeState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let runQuery = Notification.Name("VoltDB.runQuery")
    static let runCurrentQuery = Notification.Name("VoltDB.runCurrentQuery")
    static let runAllQueries = Notification.Name("VoltDB.runAllQueries")
    static let formatSQL = Notification.Name("VoltDB.formatSQL")
    static let toggleComment = Notification.Name("VoltDB.toggleComment")
    static let commitChanges = Notification.Name("VoltDB.commitChanges")
    static let rollbackChanges = Notification.Name("VoltDB.rollbackChanges")
    static let refreshSchema = Notification.Name("VoltDB.refreshSchema")
    static let openCommandPalette = Notification.Name("VoltDB.openCommandPalette")
    static let newQueryTab = Notification.Name("VoltDB.newQueryTab")
    static let closeActiveTab = Notification.Name("VoltDB.closeActiveTab")
    static let openConnectionManager = Notification.Name("VoltDB.openConnectionManager")
    static let toggleSidebar = Notification.Name("VoltDB.toggleSidebar")
    static let toggleRightPanel = Notification.Name("VoltDB.toggleRightPanel")
    static let disconnectWorkspace = Notification.Name("VoltDB.disconnectWorkspace")
    static let connectToWorkspace = Notification.Name("VoltDB.connectToWorkspace")
    static let stopQuery = Notification.Name("VoltDB.stopQuery")
    static let addNewRow = Notification.Name("VoltDB.addNewRow")
    static let saveConnection = Notification.Name("VoltDB.saveConnection")
    static let groupColorsChanged = Notification.Name("VoltDB.groupColorsChanged")
    static let connectionsChanged = Notification.Name("VoltDB.connectionsChanged")
    static let selectPreviousTab = Notification.Name("VoltDB.selectPreviousTab")
    static let selectNextTab = Notification.Name("VoltDB.selectNextTab")
    static let explainQuery = Notification.Name("VoltDB.explainQuery")
    static let toggleDatabasePicker = Notification.Name("VoltDB.toggleDatabasePicker")
    static let toggleConnectionsPicker = Notification.Name("VoltDB.toggleConnectionsPicker")
    static let previousPage = Notification.Name("VoltDB.previousPage")
    static let nextPage = Notification.Name("VoltDB.nextPage")
    static let firstPage = Notification.Name("VoltDB.firstPage")
    static let lastPage = Notification.Name("VoltDB.lastPage")
}
