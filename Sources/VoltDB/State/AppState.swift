import Foundation
import Observation

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

@Observable
class AppState {
    var savedConnections: [ConnectionConfig] = []
    var customGroups: [String] = []
    var activeConnection: ConnectionConfig? = nil
    var connectionStatus: ConnectionStatus = .disconnected
    var isShowingConnectionManager = false
    var serverVersion: String = ""
    var currentDatabase: String = ""
    
    // Per-window database manager session
    let dbManager = MySQLManager()
    private var isConnecting = false
    
    var groupColors: [String: String] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    
    init() {
        loadConnections()
        loadCustomGroups()
        loadGroupColors()
        setupNotificationObservers()
    }
    
    deinit {
        for obs in notificationObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        let mgr = dbManager
        Task {
            await mgr.disconnect()
        }
    }
    
    private func setupNotificationObservers() {
        let obs1 = NotificationCenter.default.addObserver(
            forName: .groupColorsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadGroupColors()
            self?.loadCustomGroups()
        }
        let obs2 = NotificationCenter.default.addObserver(
            forName: .connectionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.loadConnections()
            if let activeId = self.activeConnection?.id,
               let updated = self.savedConnections.first(where: { $0.id == activeId }) {
                self.activeConnection = updated
            }
        }
        notificationObservers = [obs1, obs2]
    }
    
    func loadConnections() {
        self.savedConnections = ConnectionStore.shared.loadConnections()
    }
    
    func loadCustomGroups() {
        self.customGroups = ConnectionStore.shared.loadCustomGroups()
    }
    
    func loadGroupColors() {
        self.groupColors = ConnectionStore.shared.loadGroupColors()
    }
    
    func groupColorHex(for group: String) -> String {
        let normalized = group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let customHex = groupColors[normalized] {
            return customHex
        }
        return ConnectionStore.shared.groupColorHex(for: group)
    }
    
    func setGroupColor(_ hex: String, for group: String) {
        ConnectionStore.shared.saveGroupColor(hex, for: group)
        loadGroupColors()
    }
    
    func createGroup(_ name: String, colorHex: String? = nil) {
        ConnectionStore.shared.addCustomGroup(name, colorHex: colorHex)
        loadCustomGroups()
        loadGroupColors()
    }
    
    func renameGroup(from oldName: String, to newName: String) {
        ConnectionStore.shared.renameCustomGroup(from: oldName, to: newName)
        loadConnections()
        loadCustomGroups()
        loadGroupColors()
    }
    
    func deleteGroup(_ name: String) {
        ConnectionStore.shared.deleteCustomGroup(name)
        // Also ungroup any connections that were in this group
        for conn in savedConnections where conn.group?.caseInsensitiveCompare(name) == .orderedSame {
            var updated = conn
            updated.setGroup(nil)
            ConnectionStore.shared.addOrUpdateConnection(updated)
        }
        loadConnections()
        loadCustomGroups()
        loadGroupColors()
    }
    
    func saveConnection(_ config: ConnectionConfig, password: String) {
        ConnectionStore.shared.addOrUpdateConnection(config)
        try? VaultStore.shared.save(password: password, for: config.id)
        if !config.sshPassphrase.isEmpty {
            try? VaultStore.shared.saveSSHPassphrase(config.sshPassphrase, for: config.id)
        } else {
            VaultStore.shared.deleteSSHPassphrase(for: config.id)
        }
        loadConnections()
        if activeConnection?.id == config.id {
            activeConnection = config
        }
    }
    
    func deleteConnection(id: UUID) {
        ConnectionStore.shared.deleteConnection(id: id)
        VaultStore.shared.delete(for: id)
        VaultStore.shared.deleteSSHPassphrase(for: id)
        loadConnections()
    }
    
    func connect(config: ConnectionConfig) async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        
        await MainActor.run {
            self.connectionStatus = .connecting
            self.activeConnection = config
            self.isShowingConnectionManager = false
        }
        
        let password = VaultStore.shared.retrieve(for: config.id) ?? ""
        
        do {
            try await dbManager.connect(config: config, password: password)
            let res = try? await dbManager.executeQuery("SELECT VERSION() AS ver")
            let version: String
            if let firstCell = res?.rows.first?.first {
                switch firstCell {
                case .string(let s): version = s
                case .int(let i): version = String(i)
                default: version = "MySQL"
                }
            } else {
                version = "MySQL"
            }
            
            await MainActor.run {
                self.connectionStatus = .connected
                self.serverVersion = version
                self.currentDatabase = config.database
                self.isShowingConnectionManager = false
                NotificationCenter.default.post(name: .refreshSchema, object: nil)
            }
        } catch {
            await MainActor.run {
                let formatted = ErrorFormatter.format(error, host: config.host, port: config.port)
                self.connectionStatus = .error(formatted)
                self.activeConnection = config
            }
        }
    }
    
    func disconnect() async {
        await dbManager.disconnect()
        await MainActor.run {
            self.connectionStatus = .disconnected
            self.serverVersion = ""
            self.currentDatabase = ""
            NotificationCenter.default.post(name: .refreshSchema, object: nil)
        }
    }
    
    func testConnection(config: ConnectionConfig, password: String) async -> Result<String, Error> {
        do {
            let version = try await dbManager.testConnection(config: config, password: password)
            return .success(version)
        } catch {
            return .failure(error)
        }
    }
}
