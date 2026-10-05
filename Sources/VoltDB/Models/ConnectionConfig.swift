import Foundation
import SwiftUI

/// Authentication mode for SSH Tunneling.
enum SSHAuthMode: String, Codable, CaseIterable {
    case password = "Password"
    case keyFile = "Private Key"
}

/// Represents a saved database connection configuration.
struct ConnectionConfig: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String
    var database: String
    var colorHex: String
    var useSSL: Bool
    var isProduction: Bool
    var group: String?
    
    // SSH Tunnel Configuration
    var useSSHTunnel: Bool
    var sshHost: String
    var sshPort: Int
    var sshUser: String
    var sshAuthMode: SSHAuthMode
    var sshKeyPath: String
    var sshPassphrase: String
    var sshStrictHostKeyChecking: Bool
    
    // SSL/TLS Configuration
    var sslCAPath: String
    
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "127.0.0.1",
        port: Int = 3306,
        user: String = "root",
        database: String = "",
        colorHex: String = "#3b82f6",
        useSSL: Bool = false,
        isProduction: Bool = false,
        group: String? = nil,
        useSSHTunnel: Bool = false,
        sshHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "",
        sshAuthMode: SSHAuthMode = .keyFile,
        sshKeyPath: String = "~/.ssh/id_rsa",
        sshPassphrase: String = "",
        sshStrictHostKeyChecking: Bool = true,
        sslCAPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.database = database
        self.colorHex = colorHex
        self.useSSL = useSSL
        
        let finalGroup: String? = group ?? (isProduction ? "Production" : nil)
        self.group = finalGroup
        let isProdGroup = finalGroup?.caseInsensitiveCompare("Production") == .orderedSame || finalGroup?.caseInsensitiveCompare("Prod") == .orderedSame
        self.isProduction = isProduction || isProdGroup
        
        self.useSSHTunnel = useSSHTunnel
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshAuthMode = sshAuthMode
        self.sshKeyPath = sshKeyPath
        self.sshPassphrase = sshPassphrase
        self.sshStrictHostKeyChecking = sshStrictHostKeyChecking
        self.sslCAPath = sslCAPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // CodingKeys excludes sshPassphrase from disk persistence
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, user, database, colorHex, useSSL, isProduction, group, tags
        case useSSHTunnel, sshHost, sshPort, sshUser, sshAuthMode, sshKeyPath
        case sshStrictHostKeyChecking
        case sslCAPath
        case createdAt, updatedAt
        case sshPassphrase // Kept optional in decoding for backward compatibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
        self.user = try container.decode(String.self, forKey: .user)
        self.database = try container.decode(String.self, forKey: .database)
        self.colorHex = try container.decode(String.self, forKey: .colorHex)
        self.useSSL = try container.decode(Bool.self, forKey: .useSSL)
        let isProd = try container.decode(Bool.self, forKey: .isProduction)
        let loadedGroup = try container.decodeIfPresent(String.self, forKey: .group)
        let legacyTags = try container.decodeIfPresent([String].self, forKey: .tags)
        let resolvedGroup = loadedGroup ?? legacyTags?.first ?? (isProd ? "Production" : nil)
        self.group = resolvedGroup
        let isProdGroup = resolvedGroup?.caseInsensitiveCompare("Production") == .orderedSame || resolvedGroup?.caseInsensitiveCompare("Prod") == .orderedSame
        self.isProduction = isProd || isProdGroup
        self.useSSHTunnel = try container.decode(Bool.self, forKey: .useSSHTunnel)
        self.sshHost = try container.decode(String.self, forKey: .sshHost)
        self.sshPort = try container.decode(Int.self, forKey: .sshPort)
        self.sshUser = try container.decode(String.self, forKey: .sshUser)
        self.sshAuthMode = try container.decode(SSHAuthMode.self, forKey: .sshAuthMode)
        self.sshKeyPath = try container.decode(String.self, forKey: .sshKeyPath)
        self.sshPassphrase = try container.decodeIfPresent(String.self, forKey: .sshPassphrase) ?? ""
        self.sshStrictHostKeyChecking = try container.decodeIfPresent(Bool.self, forKey: .sshStrictHostKeyChecking) ?? true
        self.sslCAPath = try container.decodeIfPresent(String.self, forKey: .sslCAPath) ?? ""
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(user, forKey: .user)
        try container.encode(database, forKey: .database)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(useSSL, forKey: .useSSL)
        try container.encode(isProduction, forKey: .isProduction)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encode(useSSHTunnel, forKey: .useSSHTunnel)
        try container.encode(sshHost, forKey: .sshHost)
        try container.encode(sshPort, forKey: .sshPort)
        try container.encode(sshUser, forKey: .sshUser)
        try container.encode(sshAuthMode, forKey: .sshAuthMode)
        try container.encode(sshKeyPath, forKey: .sshKeyPath)
        try container.encode(sshStrictHostKeyChecking, forKey: .sshStrictHostKeyChecking)
        try container.encode(sslCAPath, forKey: .sslCAPath)
        // Note: sshPassphrase is intentionally NOT encoded to disk
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    /// Whether this connection targets a remote host (non-localhost)
    var isRemoteHost: Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !h.isEmpty && h != "127.0.0.1" && h != "localhost" && h != "::1"
    }

    /// SwiftUI Color from the hex string.
    var color: Color {
        Color(hex: colorHex)
    }

    /// Display string for the connection subtitle.
    var displaySubtitle: String {
        if useSSHTunnel && !sshHost.isEmpty {
            return "\(user)@\(host):\(port) (via \(sshHost))"
        }
        return "\(user)@\(host):\(port)"
    }
    
    // MARK: - Group Management
    
    /// Display name of the group for this connection, or nil if ungrouped
    var displayGroup: String? {
        if let g = group?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            return g
        }
        if isProduction {
            return "Production"
        }
        return nil
    }
    
    /// Assigns this connection to a group (single group per connection)
    mutating func setGroup(_ newGroup: String?) {
        let trimmed = newGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let g = trimmed, !g.isEmpty {
            self.group = g
            let hex = ConnectionStore.shared.groupColorHex(for: g)
            if g.caseInsensitiveCompare("Production") == .orderedSame || g.caseInsensitiveCompare("Prod") == .orderedSame || hex.caseInsensitiveCompare("#ef4444") == .orderedSame {
                self.isProduction = true
            } else {
                self.isProduction = false
            }
        } else {
            self.group = nil
            self.isProduction = false
        }
    }
    
    
    /// Group color presets for user selection
    public struct GroupColorPreset: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let hex: String
        
        public init(id: String, name: String, hex: String) {
            self.id = id
            self.name = name
            self.hex = hex
        }
    }
    
    public static let groupColorPresets: [GroupColorPreset] = [
        GroupColorPreset(id: "red", name: "Red", hex: "#ef4444"),
        GroupColorPreset(id: "orange", name: "Orange", hex: "#f97316"),
        GroupColorPreset(id: "amber", name: "Amber", hex: "#f59e0b"),
        GroupColorPreset(id: "emerald", name: "Emerald", hex: "#10b981"),
        GroupColorPreset(id: "cyan", name: "Cyan", hex: "#06b6d4"),
        GroupColorPreset(id: "blue", name: "Blue", hex: "#3b82f6"),
        GroupColorPreset(id: "indigo", name: "Indigo", hex: "#6366f1"),
        GroupColorPreset(id: "purple", name: "Purple", hex: "#8b5cf6"),
        GroupColorPreset(id: "pink", name: "Pink", hex: "#ec4899"),
        GroupColorPreset(id: "slate", name: "Slate", hex: "#64748b")
    ]
    
    /// Returns the hex string for a group
    public static func groupHex(for groupName: String) -> String {
        ConnectionStore.shared.groupColorHex(for: groupName)
    }
    
    /// Returns visual styling (background, text, border) for a group badge
    public static func groupColor(for groupName: String) -> (bg: Color, text: Color, border: Color) {
        let hex = ConnectionStore.shared.groupColorHex(for: groupName)
        let baseColor = Color(hex: hex)
        return (
            bg: baseColor.opacity(0.18),
            text: baseColor,
            border: baseColor.opacity(0.55)
        )
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 124, 58, 237) // default purple
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preset Colors

extension ConnectionConfig {
    static let presetColors: [(name: String, hex: String)] = [
        ("Blue", "#3b82f6"),
        ("Cyan", "#06b6d4"),
        ("Teal", "#14b8a6"),
        ("Green", "#22c55e"),
        ("Yellow", "#eab308"),
        ("Orange", "#f97316"),
        ("Red", "#ef4444"),
        ("Pink", "#ec4899"),
        ("Purple", "#8b5cf6"),
        ("Gray", "#6b7280"),
    ]
}
