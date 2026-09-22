import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    
    @Environment(\.openWindow) private var openWindow
    
    init() {}
    
    private var statusInfoText: String {
        var parts: [String] = []
        if !appState.serverVersion.isEmpty {
            parts.append(appState.serverVersion)
        }
        if !appState.currentDatabase.isEmpty {
            parts.append(appState.currentDatabase)
        }
        if parts.isEmpty {
            switch appState.connectionStatus {
            case .connected: return "Connected"
            case .connecting: return "Connecting..."
            case .error: return "Error"
            case .disconnected: return "Disconnected"
            }
        }
        return parts.joined(separator: " • ")
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusInfoText)
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openWindow(id: "launcher")
            }
            
            Spacer()
            
            if let activeTab = tabState.activeTab {
                if activeTab.stagedChanges.count > 0 {
                    Text("\(activeTab.stagedChanges.count) changes")
                        .foregroundColor(AppTheme.accent)
                    
                    Button("Commit") {
                        NotificationCenter.default.post(name: .commitChanges, object: nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.success)
                    
                    Button("Rollback") {
                        NotificationCenter.default.post(name: .rollbackChanges, object: nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.error)
                    
                    Divider()
                        .frame(height: 14)
                }
                
                if let result = activeTab.result {
                    Text("\(result.rows.count) rows")
                    Text(String(format: "%.3fs", result.executionTime))
                }
            }
        }
        .transaction { $0.animation = nil }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .frame(height: AppTheme.statusBarHeight)
        .background(AppTheme.backgroundSecondary)
    }
    
    private var statusColor: Color {
        switch appState.connectionStatus {
        case .connected: return AppTheme.success
        case .error: return AppTheme.error
        case .connecting: return AppTheme.accent
        case .disconnected: return .gray
        }
    }
}
