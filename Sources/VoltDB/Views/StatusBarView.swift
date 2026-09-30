import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    
    @Environment(\.openWindow) private var openWindow
    
    init() {}
    
    private var statusInfoText: String {
        if !appState.currentDatabase.isEmpty {
            return appState.currentDatabase
        }
        return ""
    }
    
    var body: some View {
        ZStack {
            // Center: Output row count
            if let result = tabState.activeTab?.result {
                Text("\(result.rows.count) \(result.rows.count == 1 ? "row" : "rows")")
                    .foregroundColor(AppTheme.textPrimary)
                    .font(.system(size: 11, weight: .semibold))
            }
            
            // Left & Right content
            HStack {
                // Left: Database info + Execution time
                HStack(spacing: 6) {
                    if !statusInfoText.isEmpty {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        
                        Text(statusInfoText)
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                    
                    if let result = tabState.activeTab?.result {
                        if !statusInfoText.isEmpty {
                            Text("•")
                                .foregroundColor(AppTheme.textMuted)
                        }
                        
                        Text(String(format: "%.3fs", result.executionTime))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openWindow(id: "launcher")
                }
                
                Spacer()
                
                // Right: Staged changes + New Row button
                HStack(spacing: 8) {
                    if let activeTab = tabState.activeTab {
                        if activeTab.stagedChanges.count > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: "#eab308"))
                                    .frame(width: 6, height: 6)
                                Text("\(activeTab.stagedChanges.count) modified")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "#eab308"))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#6B5A1F").opacity(0.35))
                            .cornerRadius(4)
                            
                            Button {
                                NotificationCenter.default.post(name: .commitChanges, object: nil)
                            } label: {
                                Text("Commit (⌘S)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.success)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                NotificationCenter.default.post(name: .rollbackChanges, object: nil)
                            } label: {
                                Text("Discard")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.backgroundTertiary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 14)
                        }
                        
                        if activeTab.result != nil {
                            Button {
                                NotificationCenter.default.post(name: .addNewRow, object: nil)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("New Row")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AppTheme.backgroundTertiary)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Add New Row (⇧⌘N)")
                        }
                    }
                }
            }
        }
        .contentTransition(.identity)
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
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
