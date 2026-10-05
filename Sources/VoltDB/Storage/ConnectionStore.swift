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
            NotificationCenter.default.post(name: .connectionsChanged, object: nil)
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
    
    // MARK: - Custom Groups Persistence
    
    func loadCustomGroups() -> [String] {
        UserDefaults.standard.stringArray(forKey: "VoltDB_CustomGroups") ?? []
    }
    
    func addCustomGroup(_ group: String, colorHex: String? = nil) {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var groups = loadCustomGroups()
        if !groups.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            groups.append(trimmed)
            UserDefaults.standard.set(groups, forKey: "VoltDB_CustomGroups")
        }
        if let hex = colorHex {
            saveGroupColor(hex, for: trimmed)
        } else {
            NotificationCenter.default.post(name: .groupColorsChanged, object: nil)
        }
    }
    
    func deleteCustomGroup(_ group: String) {
        var groups = loadCustomGroups()
        groups.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame }
        UserDefaults.standard.set(groups, forKey: "VoltDB_CustomGroups")
        
        var colors = loadGroupColors()
        colors.removeValue(forKey: group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        UserDefaults.standard.set(colors, forKey: "VoltDB_GroupColors")
        
        var collapsed = loadCollapsedGroups()
        if collapsed.contains(group) {
            collapsed.remove(group)
            saveCollapsedGroups(collapsed)
        }
        
        NotificationCenter.default.post(name: .groupColorsChanged, object: nil)
    }
    
    func renameCustomGroup(from oldName: String, to newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty, trimmedOld.caseInsensitiveCompare(trimmedNew) != .orderedSame else { return }
        
        var groups = loadCustomGroups()
        if let idx = groups.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
            groups[idx] = trimmedNew
        } else if !groups.contains(where: { $0.caseInsensitiveCompare(trimmedNew) == .orderedSame }) {
            groups.append(trimmedNew)
        }
        UserDefaults.standard.set(groups, forKey: "VoltDB_CustomGroups")
        
        var colors = loadGroupColors()
        let oldKey = trimmedOld.lowercased()
        let newKey = trimmedNew.lowercased()
        if let existingColor = colors[oldKey] {
            colors[newKey] = existingColor
            colors.removeValue(forKey: oldKey)
            UserDefaults.standard.set(colors, forKey: "VoltDB_GroupColors")
        }
        
        var collapsed = loadCollapsedGroups()
        if collapsed.contains(trimmedOld) {
            collapsed.remove(trimmedOld)
            collapsed.insert(trimmedNew)
            saveCollapsedGroups(collapsed)
        }
        
        var connections = loadConnections()
        var changed = false
        for i in connections.indices {
            if connections[i].group?.caseInsensitiveCompare(trimmedOld) == .orderedSame {
                connections[i].setGroup(trimmedNew)
                changed = true
            }
        }
        if changed {
            saveConnections(connections)
        }
        
        NotificationCenter.default.post(name: .groupColorsChanged, object: nil)
        NotificationCenter.default.post(name: .connectionsChanged, object: nil)
    }
    
    // MARK: - Collapsed Groups Persistence
    
    func loadCollapsedGroups() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: "VoltDB_CollapsedGroups") ?? []
        return Set(array)
    }
    
    func saveCollapsedGroups(_ groups: Set<String>) {
        UserDefaults.standard.set(Array(groups), forKey: "VoltDB_CollapsedGroups")
    }
    
    // MARK: - Group Colors Persistence
    
    func loadGroupColors() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: "VoltDB_GroupColors") as? [String: String] ?? [:]
    }
    
    func saveGroupColor(_ hex: String, for group: String) {
        var colors = loadGroupColors()
        colors[group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = hex
        UserDefaults.standard.set(colors, forKey: "VoltDB_GroupColors")
        NotificationCenter.default.post(name: .groupColorsChanged, object: nil)
    }
    
    func removeGroupColor(for group: String) {
        var colors = loadGroupColors()
        colors.removeValue(forKey: group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        UserDefaults.standard.set(colors, forKey: "VoltDB_GroupColors")
        NotificationCenter.default.post(name: .groupColorsChanged, object: nil)
    }
    
    func groupColorHex(for group: String) -> String {
        let normalized = group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let saved = loadGroupColors()
        if let customHex = saved[normalized] {
            return customHex
        }
        switch normalized {
        case "prod", "production": return "#ef4444"
        case "staging", "stage": return "#f97316"
        case "dev", "development": return "#10b981"
        case "qa", "test", "testing": return "#8b5cf6"
        case "local", "localhost": return "#06b6d4"
        case "analytics", "bi", "data": return "#3b82f6"
        default:
            let hash = abs(normalized.unicodeScalars.reduce(0) { ($0 << 5) &+ $0 &+ Int($1.value) })
            let defaults = ["#0d9488", "#ec4899", "#eab308", "#6366f1", "#8b5cf6", "#64748b", "#f97316", "#14b8a6"]
            return defaults[hash % defaults.count]
        }
    }
}
