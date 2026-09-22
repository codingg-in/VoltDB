import Foundation
import CryptoKit

struct PersistedTab: Codable {
    let id: UUID
    var title: String
    var type: String // "query" or "tableView"
    var queryText: String
    var database: String
    var tableName: String?
}

struct PersistedTabSession: Codable {
    var tabs: [PersistedTab]
    var activeTabId: UUID?
    var queryCounter: Int
}

/// On-disk encrypted container format for tab session persistence.
private struct EncryptedSessionEnvelope: Codable {
    let version: Int
    let ciphertextBase64: String
}

class TabSessionStore {
    static let shared = TabSessionStore()
    
    private let fileManager = FileManager.default
    private let sessionsDirectory: URL
    private let keyFileURL: URL
    private var sessionKey: SymmetricKey
    
    private init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voltDBFolder = appSupportURL.appendingPathComponent("VoltDB", isDirectory: true)
        sessionsDirectory = voltDBFolder.appendingPathComponent("sessions", isDirectory: true)
        keyFileURL = voltDBFolder.appendingPathComponent(".session.key")
        
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        
        // Initialize or load the secure session encryption key
        self.sessionKey = TabSessionStore.loadOrCreateKey(at: keyFileURL)
    }
    
    private static func loadOrCreateKey(at url: URL) -> SymmetricKey {
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        
        let newKey = SymmetricKey(size: .bits256)
        let rawData = newKey.withUnsafeBytes { Data($0) }
        try? rawData.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return newKey
    }
    
    private func sessionEncryptedFileURL(for connectionId: UUID?) -> URL {
        let filename = connectionId != nil ? "session_\(connectionId!.uuidString).enc" : "session_global.enc"
        return sessionsDirectory.appendingPathComponent(filename)
    }
    
    private func sessionLegacyFileURL(for connectionId: UUID?) -> URL {
        let filename = connectionId != nil ? "session_\(connectionId!.uuidString).json" : "session_global.json"
        return sessionsDirectory.appendingPathComponent(filename)
    }
    
    func saveSession(tabs: [EditorTab], activeTabId: UUID?, queryCounter: Int, connectionId: UUID?) {
        let persistedTabs = tabs.compactMap { tab -> PersistedTab? in
            return PersistedTab(
                id: tab.id,
                title: tab.title,
                type: tab.type == .query ? "query" : "tableView",
                queryText: tab.queryText,
                database: tab.database,
                tableName: tab.tableName
            )
        }
        
        let session = PersistedTabSession(
            tabs: persistedTabs,
            activeTabId: activeTabId,
            queryCounter: queryCounter
        )
        
        do {
            let jsonData = try JSONEncoder().encode(session)
            
            // Encrypt using AES-256-GCM authenticated encryption
            let sealedBox = try AES.GCM.seal(jsonData, using: sessionKey)
            guard let combined = sealedBox.combined else {
                print("Failed to seal session data: missing combined ciphertext")
                return
            }
            
            let envelope = EncryptedSessionEnvelope(
                version: 1,
                ciphertextBase64: combined.base64EncodedString()
            )
            let envelopeData = try JSONEncoder().encode(envelope)
            
            let encURL = sessionEncryptedFileURL(for: connectionId)
            try envelopeData.write(to: encURL, options: .atomic)
            // Restrict file to owner-only access (0600)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: encURL.path)
            
            // Clean up legacy plaintext file if it exists to prevent disk leaks
            let legacyURL = sessionLegacyFileURL(for: connectionId)
            if fileManager.fileExists(atPath: legacyURL.path) {
                try? fileManager.removeItem(at: legacyURL)
            }
        } catch {
            print("Failed to save encrypted tab session: \(error)")
        }
    }
    
    func loadSession(connectionId: UUID?) -> PersistedTabSession? {
        // 1. Try loading connection-specific session
        if let session = loadSessionFromFile(for: connectionId) {
            return session
        }
        
        // 2. Fallback to global session if connection-specific not found
        return loadSessionFromFile(for: nil)
    }
    
    private func loadSessionFromFile(for connectionId: UUID?) -> PersistedTabSession? {
        let encURL = sessionEncryptedFileURL(for: connectionId)
        if fileManager.fileExists(atPath: encURL.path) {
            do {
                let fileData = try Data(contentsOf: encURL)
                let envelope = try JSONDecoder().decode(EncryptedSessionEnvelope.self, from: fileData)
                if let ciphertextData = Data(base64Encoded: envelope.ciphertextBase64) {
                    let sealedBox = try AES.GCM.SealedBox(combined: ciphertextData)
                    let decryptedData = try AES.GCM.open(sealedBox, using: sessionKey)
                    return try JSONDecoder().decode(PersistedTabSession.self, from: decryptedData)
                }
            } catch {
                print("Failed to decrypt tab session at \(encURL.lastPathComponent): \(error)")
            }
        }
        
        // Backward-compatibility: load legacy unencrypted JSON file and migrate it
        let legacyURL = sessionLegacyFileURL(for: connectionId)
        if fileManager.fileExists(atPath: legacyURL.path) {
            do {
                let data = try Data(contentsOf: legacyURL)
                let session = try JSONDecoder().decode(PersistedTabSession.self, from: data)
                // Migrate to encrypted format immediately
                let tabs = session.tabs.map { tab in
                    EditorTab(
                        id: tab.id,
                        title: tab.title,
                        type: tab.type == "query" ? .query : .tableView,
                        queryText: tab.queryText,
                        database: tab.database,
                        tableName: tab.tableName,
                        stagedChanges: StagedChanges()
                    )
                }
                saveSession(tabs: tabs, activeTabId: session.activeTabId, queryCounter: session.queryCounter, connectionId: connectionId)
                return session
            } catch {
                print("Failed to load legacy tab session: \(error)")
            }
        }
        
        return nil
    }
}
