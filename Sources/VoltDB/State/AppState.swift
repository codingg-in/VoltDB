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
    var activeConnection: ConnectionConfig? = nil
    var connectionStatus: ConnectionStatus = .disconnected
    var isShowingConnectionManager = false
    var serverVersion: String = ""
    var currentDatabase: String = ""
    
    // Per-window database manager session
    let dbManager = MySQLManager()
    private var isConnecting = false
    
    init() {
        loadConnections()
    }
    
    deinit {
        let mgr = dbManager
        Task {
            await mgr.disconnect()
        }
    }
    
    func loadConnections() {
        self.savedConnections = ConnectionStore.shared.loadConnections()
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
