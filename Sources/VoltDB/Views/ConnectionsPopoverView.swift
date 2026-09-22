import SwiftUI

struct ConnectionsPopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(\.openWindow) private var openWindow
    @Binding var isPresented: Bool
    var onDisconnect: (() -> Void)? = nil
    
    @State private var searchText: String = ""
    @State private var hoveredConnId: UUID? = nil
    
    private var filteredActiveConnection: ConnectionConfig? {
        guard let active = appState.activeConnection else { return nil }
        if searchText.isEmpty { return active }
        let query = searchText.lowercased()
        if active.name.lowercased().contains(query) ||
            active.host.lowercased().contains(query) ||
            active.user.lowercased().contains(query) ||
            active.database.lowercased().contains(query) {
            return active
        }
        return nil
    }
    
    private var filteredSavedConnections: [ConnectionConfig] {
        let activeId = appState.activeConnection?.id
        let otherConns = appState.savedConnections.filter { $0.id != activeId }
        if searchText.isEmpty { return otherConns }
        let query = searchText.lowercased()
        return otherConns.filter { conn in
            conn.name.lowercased().contains(query) ||
            conn.host.lowercased().contains(query) ||
            conn.user.lowercased().contains(query) ||
            conn.database.lowercased().contains(query)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textMuted)
                    .font(.system(size: 12))
                
                TextField("Search connections", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.5)
            )
            .padding(10)
            
            Divider()
                .background(AppTheme.border.opacity(0.3))
            
            // Scrollable List
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Active Workspace Connection Section
                    if let active = filteredActiveConnection {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("CURRENT WORKSPACE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppTheme.textMuted)
                                Spacer()
                                connectionStatusBadge
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            
                            activeConnectionRow(active)
                        }
                    }
                    
                    // Other Saved Connections Section
                    let saved = filteredSavedConnections
                    if !saved.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SAVED CONNECTIONS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                            
                            ForEach(saved) { conn in
                                savedConnectionRow(conn)
                            }
                        }
                    } else if filteredActiveConnection == nil {
                        VStack(spacing: 8) {
                            Text("No matching connections")
                                .font(.caption)
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
            
            Divider()
                .background(AppTheme.border.opacity(0.3))
            
            // Bottom Footer: Manage Connections...
            Button {
                isPresented = false
                openWindow(id: "launcher")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Manage Connections...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(AppTheme.backgroundSecondary)
        }
        .frame(width: 330)
        .background(Color(hex: "#181825"))
    }
    
    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch appState.connectionStatus {
        case .connected:
            HStack(spacing: 4) {
                Circle().fill(AppTheme.success).frame(width: 5, height: 5)
                Text("Connected")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.success)
            }
        case .connecting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text("Connecting...")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.warning)
            }
        case .error(let msg):
            HStack(spacing: 4) {
                Circle().fill(AppTheme.error).frame(width: 5, height: 5)
                Text("Error")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.error)
            }
            .help(msg)
        case .disconnected:
            HStack(spacing: 4) {
                Circle().fill(AppTheme.textMuted).frame(width: 5, height: 5)
                Text("Disconnected")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
            }
        }
    }
    
    @ViewBuilder
    private func activeConnectionRow(_ conn: ConnectionConfig) -> some View {
        HStack(spacing: 8) {
            // Connection status / color dot
            Circle()
                .fill(appState.connectionStatus == .connected ? AppTheme.success : (appState.connectionStatus == .connecting ? AppTheme.warning : conn.color))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conn.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(conn.displaySubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if appState.connectionStatus == .connected {
                Button {
                    isPresented = false
                    onDisconnect?()
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.error)
                        .padding(4)
                        .background(AppTheme.error.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Disconnect & Close Workspace")
            } else {
                Button {
                    Task {
                        await appState.connect(config: conn)
                    }
                } label: {
                    Text(appState.connectionStatus == .connecting ? "Connecting..." : "Connect")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(appState.connectionStatus == .connecting)
                .help("Connect to database")
            }
            
            // MySQL Badge Tag
            Text("MYSQL")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hover in
            if hover {
                hoveredConnId = conn.id
            } else if hoveredConnId == conn.id {
                hoveredConnId = nil
            }
        }
    }
    
    @ViewBuilder
    private func savedConnectionRow(_ conn: ConnectionConfig) -> some View {
        let isHovered = hoveredConnId == conn.id
        
        Button {
            isPresented = false
            // Open this connection in its own separate workspace window
            openWindow(value: conn.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .connectToWorkspace, object: conn.id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .connectToWorkspace, object: conn.id)
            }
        } label: {
            HStack(spacing: 8) {
                // Connection status / color dot
                Circle()
                    .fill(conn.color)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(conn.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text(conn.displaySubtitle)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor(isHovered ? AppTheme.accent : AppTheme.textMuted)
                
                // MySQL Badge Tag
                Text("MYSQL")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? AppTheme.backgroundHover : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in New Workspace Window")
        .onHover { hover in
            if hover {
                hoveredConnId = conn.id
            } else if hoveredConnId == conn.id {
                hoveredConnId = nil
            }
        }
    }
}
