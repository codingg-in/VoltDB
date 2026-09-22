import SwiftUI
import AppKit

extension Notification.Name {
    static let switchToTab = Notification.Name("VoltDB.switchToTab")
}

class KeyboardShortcutManager {
    static func setupGlobalShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Must have command key pressed
            if event.modifierFlags.contains(.command) {
                if let characters = event.charactersIgnoringModifiers?.lowercased() {
                    
                    // Cmd+W -> Close active tab in workspace (NEVER close workspace window)
                    if characters == "w" && !event.modifierFlags.contains(.shift) {
                        if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow {
                            let isLauncher = keyWindow.title == "VoltDB Connection Manager" ||
                                             keyWindow.title == "VoltDB" ||
                                             (!keyWindow.styleMask.contains(.resizable) && keyWindow.frame.width <= 850)
                            if isLauncher {
                                keyWindow.close()
                                return nil
                            } else {
                                NotificationCenter.default.post(name: .closeActiveTab, object: nil)
                                return nil // Always consume event so AppKit NEVER closes the workspace window!
                            }
                        }
                    }
                    
                    // Cmd+P -> Command Palette
                    if characters == "p" && !event.modifierFlags.contains(.shift) {
                        NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                        return nil // Consume event
                    }
                    
                    // Cmd+1 to Cmd+9 -> Switch to Tab
                    if let number = Int(characters), number >= 1 && number <= 9 {
                        NotificationCenter.default.post(name: .switchToTab, object: number - 1)
                        return nil // Consume event
                    }
                }
            }
            
            return event
        }
    }
}

struct VoltDBShortcuts: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Additional view-level shortcuts or handlers can be added here
            .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
                // Intercept logic for active views could go here
            }
    }
}

extension View {
    func voltDBShortcuts() -> some View {
        modifier(VoltDBShortcuts())
    }
}
