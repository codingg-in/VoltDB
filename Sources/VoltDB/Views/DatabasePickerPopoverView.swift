import SwiftUI

struct DatabasePickerPopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(SchemaState.self) private var schemaState
    @Binding var isPresented: Bool
    
    @State private var searchText: String = ""
    @State private var hoveredDBName: String? = nil
    
    private var filteredDatabases: [DatabaseInfo] {
        if searchText.isEmpty {
            return schemaState.databases
        }
        let query = searchText.lowercased()
        return schemaState.databases.filter { $0.name.lowercased().contains(query) }
    }
    
    private var currentActiveDatabase: String {
        if let tabDB = tabState.activeTab?.database, !tabDB.isEmpty {
            return tabDB
        }
        if !appState.currentDatabase.isEmpty {
            return appState.currentDatabase
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textMuted)
                    .font(.system(size: 11))
                
                TextField("Search databases...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textPrimary)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(6)
            .padding(8)
            
            Divider()
                .background(AppTheme.border.opacity(0.3))
            
            // Database List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filteredDatabases.isEmpty {
                        VStack(spacing: 6) {
                            Text("No databases found")
                                .font(.caption)
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(filteredDatabases, id: \.name) { db in
                            let isSelected = db.name == currentActiveDatabase
                            let isHovered = hoveredDBName == db.name
                            
                            Button {
                                selectDatabase(db.name)
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "cylinder.split.1x2")
                                        .font(.system(size: 10))
                                        .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                                    
                                    Text(db.name)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textPrimary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(AppTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected
                                        ? AppTheme.accent.opacity(0.12)
                                        : (isHovered ? AppTheme.backgroundHover : Color.clear)
                                )
                                .cornerRadius(5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hover in
                                if hover {
                                    hoveredDBName = db.name
                                } else if hoveredDBName == db.name {
                                    hoveredDBName = nil
                                }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 220)
        .background(Color(hex: "#181825"))
    }
    
    private func selectDatabase(_ name: String) {
        if let activeId = tabState.activeTabId,
           let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
            tabState.tabs[idx].database = name
        }
        appState.currentDatabase = name
        
        Task {
            try? await appState.dbManager.useDatabase(name)
            await schemaState.loadTables(for: name)
            await schemaState.loadAllColumns(for: name)
        }
    }
}
