import AppKit

struct SyntaxColorScheme {
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let function: NSColor
    let type: NSColor
    let table: NSColor
    let column: NSColor
    let operator_: NSColor
    let identifier: NSColor
    let background: NSColor
    let text: NSColor
    let lineNumber: NSColor
    let currentLine: NSColor
    let selection: NSColor
    let cursor: NSColor
}

struct SyntaxColors {
    static func colors(for appearance: NSAppearance?) -> SyntaxColorScheme {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        if isDark {
            return SyntaxColorScheme(
                keyword: NSColor(hex: "#ff79c6") ?? .systemPink,     // Pink / Magenta (SELECT, FROM, WHERE)
                string: NSColor(hex: "#50fa7b") ?? .green,          // Vibrant green ('text', "text")
                number: NSColor(hex: "#f1fa8c") ?? .yellow,         // Golden yellow (123, 45.67)
                comment: NSColor(hex: "#6272a4") ?? .gray,          // Muted blue-gray (-- comment, /* */)
                function: NSColor(hex: "#bd93f9") ?? .magenta,      // Purple (COUNT, SUM, NOW)
                type: NSColor(hex: "#caa9fa") ?? .magenta,          // Lavender (VARCHAR, INT, DATETIME)
                table: NSColor(hex: "#ffb86c") ?? .orange,          // Warm amber / orange (table names)
                column: NSColor(hex: "#8be9fd") ?? .cyan,           // Soft cyan / sky blue (column names)
                operator_: NSColor(hex: "#f8f8f2") ?? .white,       // Off-white
                identifier: NSColor(hex: "#f8f8f2") ?? .white,      // Off-white
                background: NSColor(hex: "#181825") ?? .windowBackgroundColor,
                text: NSColor(hex: "#f8f8f2") ?? .textColor,        // Off-white
                lineNumber: NSColor(hex: "#6272a4") ?? .gray,
                currentLine: NSColor(hex: "#282a36") ?? .darkGray,
                selection: NSColor(hex: "#44475a") ?? .selectedTextBackgroundColor,
                cursor: NSColor(hex: "#f8f8f2") ?? .textInsertionPointColor
            )
        } else {
            return SyntaxColorScheme(
                keyword: NSColor(hex: "#d63384") ?? .systemPink,
                string: NSColor(hex: "#16a34a") ?? .green,
                number: NSColor(hex: "#b45309") ?? .orange,
                comment: NSColor(hex: "#6c757d") ?? .gray,
                function: NSColor(hex: "#7c3aed") ?? .purple,
                type: NSColor(hex: "#9333ea") ?? .purple,
                table: NSColor(hex: "#d97706") ?? .orange,          // Warm amber / orange
                column: NSColor(hex: "#0284c7") ?? .blue,           // Sky blue
                operator_: NSColor(hex: "#212529") ?? .black,
                identifier: NSColor(hex: "#212529") ?? .black,
                background: NSColor(hex: "#ffffff") ?? .textBackgroundColor,
                text: NSColor(hex: "#212529") ?? .textColor,
                lineNumber: NSColor(hex: "#adb5bd") ?? .gray,
                currentLine: NSColor(hex: "#f8f9fa") ?? .lightGray,
                selection: NSColor(hex: "#cfe2ff") ?? .selectedTextBackgroundColor,
                cursor: NSColor(hex: "#212529") ?? .textInsertionPointColor
            )
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
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
            return nil
        }
        
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue:  CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
