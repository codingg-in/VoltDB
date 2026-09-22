import SwiftUI

enum AppTheme {
    // Backgrounds
    static let backgroundPrimary = Color(hex: "#1e1e2e")
    static let backgroundSecondary = Color(hex: "#252535")
    static let backgroundTertiary = Color(hex: "#2a2a3c")
    static let backgroundHover = Color(hex: "#32324a")
    
    // Accents
    static let accent = Color(hex: "#3b82f6")
    static let accentLight = Color(hex: "#60a5fa")
    
    // Text
    static let textPrimary = Color(hex: "#e2e2e2")
    static let textSecondary = Color(hex: "#9ca3af")
    static let textMuted = Color(hex: "#6b7280")
    
    // Border
    static let border = Color(hex: "#3f3f5a")
    
    // Status Colors
    static let success = Color(hex: "#22c55e")
    static let error = Color(hex: "#ef4444")
    static let warning = Color(hex: "#f59e0b")
    static let info = Color(hex: "#3b82f6")
    
    // Staged Changes
    static let stagedChange = Color(hex: "#fbbf24").opacity(0.2)
    static let stagedInsert = Color(hex: "#22c55e").opacity(0.2)
    static let stagedDelete = Color(hex: "#ef4444").opacity(0.2)
    
    // Adaptive
    static func adaptiveBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? backgroundPrimary : .white
    }
    
    static func adaptiveText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? textPrimary : .black
    }
    
    // Fonts
    static let editorFont = Font.system(.body, design: .monospaced)
    static let editorNSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    
    // Dimensions
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 250
    static let sidebarMaxWidth: CGFloat = 400
    
    static let statusBarHeight: CGFloat = 28
    static let tabBarHeight: CGFloat = 36
}
