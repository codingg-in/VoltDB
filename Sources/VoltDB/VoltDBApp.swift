import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openLauncherWindow: (() -> Void)?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        KeyboardShortcutManager.setupGlobalShortcuts()
        
        if let window = NSApp.windows.first {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        
        // Watch for window close to re-open Connection Manager when all workspace windows are gone
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
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
}

/// Root view for each independent window session.
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
            .onAppear {
                (NSApp.delegate as? AppDelegate)?.openLauncherWindow = {
                    openWindow(id: "launcher")
                }
            }
    }
    
    private func connect(to targetId: UUID?, force: Bool = false) async {
        guard let targetId = targetId else { return }
        if !force {
            guard appState.connectionStatus != .connected && appState.connectionStatus != .connecting else { return }
        } else {
            if appState.connectionStatus == .connecting { return }
            if appState.connectionStatus == .connected && appState.activeConnection?.id == targetId { return }
        }
        
        appState.loadConnections()
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
        .defaultSize(width: 820, height: 575)
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
                .keyboardShortcut("n", modifiers: .command)
                
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
                .keyboardShortcut(.return, modifiers: [.command, .control, .shift])

                Button("Format SQL") {
                    NotificationCenter.default.post(name: .formatSQL, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandMenu("Data") {
                Button("Commit Changes") {
                    NotificationCenter.default.post(name: .commitChanges, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Rollback Changes") {
                    NotificationCenter.default.post(name: .rollbackChanges, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Divider()

                Button("Refresh Schema") {
                    NotificationCenter.default.post(name: .refreshSchema, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Open Anything (Command Palette)") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
                
                Divider()
                
                Button("Toggle Left Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                
                Button("Toggle Inspector Panel") {
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
}
