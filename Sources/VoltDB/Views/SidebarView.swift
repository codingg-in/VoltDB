import SwiftUI

struct SidebarView: View {
    @Environment(SchemaState.self) private var schemaState
    @Environment(TabState.self) private var tabState
    @Environment(AppState.self) private var appState
    
    init() {}
    
    var body: some View {
        @Bindable var bindableSchemaState = schemaState
        
        VStack(spacing: 0) {
            // Search TextField
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
                TextField("Search schema...", text: $bindableSchemaState.filterText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            
            if schemaState.isLoading {
                Spacer()
                ProgressView("Loading schemas...")
                    .controlSize(.small)
                Spacer()
            } else if schemaState.databases.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundColor(AppTheme.textMuted)
                    Text(appState.connectionStatus == .connected ? "No Databases Found" : "Not Connected")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .transaction { $0.animation = nil }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        // User Databases Section
                        let userDBs = schemaState.userDatabases
                        if !userDBs.isEmpty {
                            ForEach(userDBs, id: \.name) { db in
                                databaseNode(db)
                            }
                        }
                        
                        // System Databases Section (Collapsible)
                        let sysDBs = schemaState.sysDatabases
                        if !sysDBs.isEmpty {
                            DisclosureGroup("System Schemas (\(sysDBs.count))") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(sysDBs, id: \.name) { db in
                                        databaseNode(db)
                                    }
                                }
                                .padding(.leading, 8)
                            }
                            .foregroundColor(AppTheme.textMuted)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .background(AppTheme.backgroundSecondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSchema)) { _ in
            Task {
                await schemaState.loadDatabases(defaultDB: appState.currentDatabase)
            }
        }
        .onAppear {
            if appState.connectionStatus == .connected {
                tabState.restoreSession(for: appState.activeConnection?.id, defaultDatabase: appState.currentDatabase)
                Task {
                    await schemaState.loadDatabases(defaultDB: appState.currentDatabase)
                }
            }
        }
        .onChange(of: appState.connectionStatus) { _, newStatus in
            if newStatus == .connected {
                tabState.restoreSession(for: appState.activeConnection?.id, defaultDatabase: appState.currentDatabase)
                Task {
                    await schemaState.loadDatabases(defaultDB: appState.currentDatabase)
                }
            }
        }
        .transaction { $0.animation = nil }
    }
    
    @ViewBuilder
    private func databaseNode(_ db: DatabaseInfo) -> some View {
        let isDefault = !appState.currentDatabase.isEmpty && db.name.lowercased() == appState.currentDatabase.lowercased()
        
        DisclosureGroup(
            isExpanded: Binding(
                get: { schemaState.isExpanded(db.name) },
                set: { _ in
                    schemaState.toggleNode(db.name)
                    if schemaState.isExpanded(db.name) {
                        Task {
                            await schemaState.loadTables(for: db.name)
                        }
                    }
                }
            )
        ) {
            let tables = schemaState.filteredTables(for: db.name)
            if tables.isEmpty {
                Text("No tables found")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.leading, 8)
            } else {
                let regularTables = tables.filter { $0.type == .table }
                let views = tables.filter { $0.type == .view }
                
                if !regularTables.isEmpty {
                    DisclosureGroup("Tables (\(regularTables.count))") {
                        ForEach(regularTables, id: \.name) { table in
                            SidebarTreeNode(table: table)
                        }
                    }
                }
                
                if !views.isEmpty {
                    DisclosureGroup("Views (\(views.count))") {
                        ForEach(views, id: \.name) { view in
                            SidebarTreeNode(table: view)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isDefault ? "cylinder.split.1x2.fill" : "cylinder")
                    .foregroundColor(isDefault ? AppTheme.accent : AppTheme.textSecondary)
                Text(db.name)
                    .font(.system(size: 13, weight: isDefault ? .bold : .regular))
                    .foregroundColor(AppTheme.textPrimary)
                if isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppTheme.accent.opacity(0.15))
                        .cornerRadius(3)
                }
            }
            .contextMenu {
                Button("New Query in '\(db.name)'") {
                    tabState.addNewQueryTab(database: db.name)
                }
                Button("Refresh Tables") {
                    Task {
                        await schemaState.loadTables(for: db.name)
                    }
                }
            }
        }
    }
}
