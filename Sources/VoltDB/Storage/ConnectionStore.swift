import Foundation

class ConnectionStore {
    static let shared = ConnectionStore()
    
    private let fileManager = FileManager.default
    private let connectionsDirectory: URL
    private let connectionsFileURL: URL
    
    private init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        connectionsDirectory = appSupportURL.appendingPathComponent("VoltDB", isDirectory: true)
        connectionsFileURL = connectionsDirectory.appendingPathComponent("connections.json")
        
        createDirectoryIfNeeded()
        deduplicateOnDiskIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: connectionsDirectory.path) {
            try? fileManager.createDirectory(at: connectionsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Deduplicates identical connections on load
    private func deduplicateOnDiskIfNeeded() {
        let loaded = loadConnections()
        var seenNames = Set<String>()
        var unique: [ConnectionConfig] = []
        var modified = false
        
        for conn in loaded {
            let key = "\(conn.name.lowercased())_\(conn.host)_\(conn.port)_\(conn.user)_\(conn.database)"
            if !seenNames.contains(key) {
                seenNames.insert(key)
                unique.append(conn)
            } else {
                modified = true
            }
        }
        
        if modified {
            saveConnections(unique)
        }
    }
    
    func loadConnections() -> [ConnectionConfig] {
        guard fileManager.fileExists(atPath: connectionsFileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: connectionsFileURL)
            let decoder = JSONDecoder()
            var configs = try decoder.decode([ConnectionConfig].self, from: data)
            var migrated = false
            for i in 0..<configs.count {
                if let vaultPass = VaultStore.shared.retrieveSSHPassphrase(for: configs[i].id) {
                    configs[i].sshPassphrase = vaultPass
                } else if !configs[i].sshPassphrase.isEmpty {
                    // Migrate from legacy unencrypted json to VaultStore
                    try? VaultStore.shared.saveSSHPassphrase(configs[i].sshPassphrase, for: configs[i].id)
                    migrated = true
                }
            }
            if migrated {
                // Re-save to strip plaintext sshPassphrase from connections.json
                saveConnections(configs)
            }
            return configs
        } catch {
            print("Failed to load connections: \(error)")
            return []
        }
    }
    
    func saveConnections(_ connections: [ConnectionConfig]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(connections)
            try data.write(to: connectionsFileURL, options: .atomic)
            // Restrict file to owner-only access (0600) — contains hostnames, usernames, SSH details
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: connectionsFileURL.path)
        } catch {
            print("Failed to save connections: \(error)")
        }
    }
    
    func addOrUpdateConnection(_ connection: ConnectionConfig) {
        var connections = loadConnections()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        saveConnections(connections)
    }
    
    func addConnection(_ connection: ConnectionConfig) {
        addOrUpdateConnection(connection)
    }
    
    func updateConnection(_ connection: ConnectionConfig) {
        addOrUpdateConnection(connection)
    }
    
    func deleteConnection(id: UUID) {
        var connections = loadConnections()
        connections.removeAll(where: { $0.id == id })
        saveConnections(connections)
    }
    
    func generateUniqueName(base: String = "MySQL Connection") -> String {
        let existing = loadConnections().map { $0.name.lowercased() }
        if !existing.contains(base.lowercased()) {
            return base
        }
        var counter = 2
        while existing.contains("\(base) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}
