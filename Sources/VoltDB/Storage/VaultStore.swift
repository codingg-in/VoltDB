import Foundation
import CryptoKit
import CommonCrypto
import Observation

/// Codable container for all encrypted secrets stored inside the vault.
public struct VaultPayload: Codable {
    public var passwords: [String: String] = [:]
    public var sshPassphrases: [String: String] = [:]
}

/// On-disk encrypted container format for the vault file.
private struct VaultEnvelope: Codable {
    let version: Int
    let saltBase64: String
    let ciphertextBase64: String
}

/// Securely stores credentials inside an AES-256-GCM encrypted vault file
/// protected by PBKDF2 key derivation from a user-defined Master Password.
@Observable
public final class VaultStore {
    public static let shared = VaultStore()
    
    public private(set) var isUnlocked: Bool = false
    public private(set) var hasVault: Bool = false
    
    private var cachedPayload: VaultPayload = VaultPayload()
    private var activeSymmetricKey: SymmetricKey? = nil
    private var currentSalt: Data? = nil
    
    private let vaultFileName = "vault.enc"
    private let pbkdf2Iterations: UInt32 = 600_000
    private let keyByteCount = 32 // 256 bits
    private let saltByteCount = 32
    
    private init() {
        checkVaultExistence()
    }
    
    // MARK: - File Path Resolution
    
    private var vaultFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = appSupport.appendingPathComponent("VoltDB", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(vaultFileName)
    }
    
    public func checkVaultExistence() {
        guard let url = vaultFileURL else {
            hasVault = false
            return
        }
        hasVault = FileManager.default.fileExists(atPath: url.path)
    }
    
    // MARK: - Master Password & Vault Lifecycle
    
    /// Initializes a new encrypted vault with the given Master Password.
    public func createVault(masterPassword: String) throws {
        guard !masterPassword.isEmpty else {
            throw NSError(domain: "VaultStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Master Password cannot be empty."])
        }
        guard masterPassword.count >= 8 else {
            throw NSError(domain: "VaultStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Master Password must be at least 8 characters long."])
        }
        
        let salt = generateRandomData(count: saltByteCount)
        let key = try deriveKey(from: masterPassword, salt: salt)
        
        self.currentSalt = salt
        self.activeSymmetricKey = key
        self.cachedPayload = VaultPayload()
        self.isUnlocked = true
        
        try persistVault()
        self.hasVault = true
    }
    
    /// Unlocks an existing vault using the provided Master Password.
    @discardableResult
    public func unlock(masterPassword: String) -> Bool {
        guard let url = vaultFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let fileData = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(VaultEnvelope.self, from: fileData),
              let salt = Data(base64Encoded: envelope.saltBase64),
              let combinedCiphertext = Data(base64Encoded: envelope.ciphertextBase64) else {
            return false
        }
        
        guard let key = try? deriveKey(from: masterPassword, salt: salt) else {
            return false
        }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedCiphertext)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let payload = try JSONDecoder().decode(VaultPayload.self, from: decryptedData)
            
            self.cachedPayload = payload
            self.currentSalt = salt
            self.activeSymmetricKey = key
            self.isUnlocked = true
            self.hasVault = true
            return true
        } catch {
            return false
        }
    }
    
    /// Locks the vault and clears all secrets from memory.
    public func lock() {
        // Overwrite cached password/passphrase values before dropping references
        for key in cachedPayload.passwords.keys {
            cachedPayload.passwords[key] = String(repeating: "\0", count: 64)
        }
        for key in cachedPayload.sshPassphrases.keys {
            cachedPayload.sshPassphrases[key] = String(repeating: "\0", count: 64)
        }
        self.cachedPayload = VaultPayload()
        self.activeSymmetricKey = nil
        self.currentSalt = nil
        self.isUnlocked = false
    }
    
    /// Updates the Master Password protecting the vault.
    public func changeMasterPassword(oldPassword: String, newPassword: String) throws {
        guard unlock(masterPassword: oldPassword) else {
            throw NSError(domain: "VaultStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Incorrect current Master Password."])
        }
        guard !newPassword.isEmpty else {
            throw NSError(domain: "VaultStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "New Master Password cannot be empty."])
        }
        guard newPassword.count >= 8 else {
            throw NSError(domain: "VaultStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "New Master Password must be at least 8 characters long."])
        }
        
        let newSalt = generateRandomData(count: saltByteCount)
        let newKey = try deriveKey(from: newPassword, salt: newSalt)
        
        self.currentSalt = newSalt
        self.activeSymmetricKey = newKey
        try persistVault()
    }
    
    /// Resets/deletes the entire vault.
    public func resetVault() {
        lock()
        if let url = vaultFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        hasVault = false
    }
    
    // MARK: - Credential CRUD (In-Memory + Auto-Persist)
    
    public func save(password: String, for connectionId: UUID) throws {
        cachedPayload.passwords[connectionId.uuidString] = password
        if isUnlocked && hasVault {
            try persistVault()
        }
    }
    
    public func retrieve(for connectionId: UUID) -> String? {
        return cachedPayload.passwords[connectionId.uuidString]
    }
    
    public func delete(for connectionId: UUID) {
        cachedPayload.passwords.removeValue(forKey: connectionId.uuidString)
        if isUnlocked && hasVault {
            try? persistVault()
        }
    }
    
    public func saveSSHPassphrase(_ passphrase: String, for connectionId: UUID) throws {
        cachedPayload.sshPassphrases[connectionId.uuidString] = passphrase
        if isUnlocked && hasVault {
            try persistVault()
        }
    }
    
    public func retrieveSSHPassphrase(for connectionId: UUID) -> String? {
        return cachedPayload.sshPassphrases[connectionId.uuidString]
    }
    
    public func deleteSSHPassphrase(for connectionId: UUID) {
        cachedPayload.sshPassphrases.removeValue(forKey: connectionId.uuidString)
        if isUnlocked && hasVault {
            try? persistVault()
        }
    }
    
    // MARK: - Cryptographic Helpers & File Serialization
    
    private func persistVault() throws {
        guard let key = activeSymmetricKey, let salt = currentSalt, let url = vaultFileURL else {
            throw NSError(domain: "VaultStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Vault cannot be written: missing key or path."])
        }
        
        let jsonData = try JSONEncoder().encode(cachedPayload)
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "VaultStore", code: 6, userInfo: [NSLocalizedDescriptionKey: "AES-GCM seal failed."])
        }
        
        let envelope = VaultEnvelope(
            version: 1,
            saltBase64: salt.base64EncodedString(),
            ciphertextBase64: combined.base64EncodedString()
        )
        
        let envelopeData = try JSONEncoder().encode(envelope)
        
        // Write atomic and enforce POSIX 0600 permissions
        try envelopeData.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    
    private func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw NSError(domain: "VaultStore", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid password encoding."])
        }
        
        var derivedKeyData = Data(count: keyByteCount)
        let status = derivedKeyData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw NSError(domain: "VaultStore", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "PBKDF2 key derivation failed."])
        }
        
        return SymmetricKey(data: derivedKeyData)
    }
    
    private func generateRandomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            fatalError("Failed to securely generate random bytes: OSStatus \(status)")
        }
        return Data(bytes)
    }
}
