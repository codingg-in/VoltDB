import Foundation
import SwiftUI
import Observation

enum ThemeMode: String {
    case system
    case dark
    case light
}

@Observable
class ThemeState {
    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "VoltDB.themeMode")
        }
    }
    
    init() {
        if let storedModeString = UserDefaults.standard.string(forKey: "VoltDB.themeMode"),
           let storedMode = ThemeMode(rawValue: storedModeString) {
            self.themeMode = storedMode
        } else {
            self.themeMode = .system
        }
    }
    
    var resolvedColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
    
    func toggleTheme() {
        switch themeMode {
        case .system: themeMode = .dark
        case .dark: themeMode = .light
        case .light: themeMode = .system
        }
    }
    
    var themeIcon: String {
        switch themeMode {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}
