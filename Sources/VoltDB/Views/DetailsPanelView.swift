import SwiftUI

struct DetailsPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(SchemaState.self) private var schemaState
    
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.accent)
                    Text("Inspector")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.backgroundSecondary)
            
            Divider()
                .background(AppTheme.border.opacity(0.3))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let activeTab = tabState.activeTab {
                        if activeTab.type == .tableView, let tableName = activeTab.tableName {
                            tableInspectorSection(database: activeTab.database, tableName: tableName)
                        } else {
                            queryInspectorSection(tab: activeTab)
                        }
                    } else {
                        emptyStateSection
                    }
                    
                    connectionInfoSection
                }
                .padding(12)
            }
        }
        .frame(width: 260)
        .background(AppTheme.backgroundSecondary)
    }
    
    // MARK: - Table Inspector
    
    @ViewBuilder
    private func tableInspectorSection(database: String, tableName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TABLE DETAILS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textMuted)
            
            VStack(spacing: 6) {
                detailRow(label: "Table", value: tableName, isMonospace: true)
                detailRow(label: "Database", value: database, isMonospace: true)
                
                if let tableInfo = schemaState.tablesByDatabase[database]?.first(where: { $0.name == tableName }) {
                    detailRow(label: "Type", value: tableInfo.type.displayName)
                    if let rows = tableInfo.rowCount {
                        detailRow(label: "Est. Rows", value: rows.formatted())
                    }
                }
                
                if let cols = schemaState.columnsByTable[tableName] ?? schemaState.columnsByTable["\(database).\(tableName)"] {
                    detailRow(label: "Columns", value: "\(cols.count)")
                }
            }
            .padding(8)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(6)
            
            // Staged changes info
            if let activeTab = tabState.activeTab, activeTab.stagedChanges.count > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UNCOMMITTED CHANGES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.warning)
                    
                    VStack(spacing: 4) {
                        detailRow(label: "Staged Changes", value: "\(activeTab.stagedChanges.count)")
                        if activeTab.stagedChanges.updateCount > 0 {
                            detailRow(label: "Updates", value: "\(activeTab.stagedChanges.updateCount)")
                        }
                        if activeTab.stagedChanges.insertCount > 0 {
                            detailRow(label: "Inserts", value: "\(activeTab.stagedChanges.insertCount)")
                        }
                        if activeTab.stagedChanges.deleteCount > 0 {
                            detailRow(label: "Deletes", value: "\(activeTab.stagedChanges.deleteCount)")
                        }
                    }
                    .padding(8)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                }
            }
        }
    }
    
    // MARK: - Query Inspector
    
    @ViewBuilder
    private func queryInspectorSection(tab: EditorTab) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUERY STATS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textMuted)
            
            VStack(spacing: 6) {
                detailRow(label: "Tab Name", value: tab.title)
                detailRow(label: "Context DB", value: tab.database.isEmpty ? (appState.currentDatabase.isEmpty ? "default" : appState.currentDatabase) : tab.database)
                
                if let res = tab.result {
                    if res.isError {
                        detailRow(label: "Status", value: "Error", color: AppTheme.error)
                    } else {
                        detailRow(label: "Status", value: "Success", color: AppTheme.success)
                        detailRow(label: "Runtime", value: String(format: "%.3f s", res.executionTime))
                        detailRow(label: "Rows Returned", value: "\(res.rows.count.formatted())")
                        detailRow(label: "Columns", value: "\(res.columns.count)")
                    }
                } else {
                    detailRow(label: "Status", value: tab.isLoading ? "Running..." : "Idle")
                }
            }
            .padding(8)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(6)
            
            // Quick Query Actions
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.textMuted)
                
                VStack(spacing: 4) {
                    Button {
                        NotificationCenter.default.post(name: .formatSQL, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10))
                            Text("Format SQL Script")
                                .font(.system(size: 11))
                            Spacer()
                            Text("⇧⌘I")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        NotificationCenter.default.post(name: .runCurrentQuery, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.accent)
                            Text("Run Current Statement")
                                .font(.system(size: 11))
                            Spacer()
                            Text("⌘↩")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Connection Info Section
    
    @ViewBuilder
    private var connectionInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SERVER INFO")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textMuted)
            
            VStack(spacing: 6) {
                if let conn = appState.activeConnection {
                    detailRow(label: "Connection", value: conn.name)
                    detailRow(label: "Host", value: "\(conn.host):\(conn.port)", isMonospace: true)
                    detailRow(label: "User", value: conn.user)
                    detailRow(label: "SSL", value: conn.useSSL ? "Enabled" : "Disabled", color: conn.useSSL ? AppTheme.success : AppTheme.textSecondary)
                    if conn.useSSHTunnel {
                        detailRow(label: "Tunnel", value: "\(conn.sshHost)", isMonospace: true)
                    }
                }
                
                if !appState.serverVersion.isEmpty {
                    detailRow(label: "Version", value: appState.serverVersion)
                }
            }
            .padding(8)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(6)
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.textMuted)
            Text("No Active Session")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func detailRow(label: String, value: String, isMonospace: Bool = false, color: Color = AppTheme.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: isMonospace ? .monospaced : .default))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }
}
