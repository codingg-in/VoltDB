import SwiftUI

struct TableDataView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    
    var database: String
    var tableName: String
    
    @State private var result: QueryResult? = nil
    @State private var columns: [ColumnInfo] = []
    @State private var primaryKeyColumns: [String] = []
    @State private var currentPage = 0
    @State private var pageSize = 100
    @State private var totalRows = 0
    @State private var filters: [FilterCondition] = []
    @State private var sortColumn: String? = nil
    @State private var sortAscending = true
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var stagedChanges = StagedChanges()
    
    private var totalPages: Int {
        max(1, Int(ceil(Double(totalRows) / Double(pageSize))))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Smart Filter Toolbar
            SmartFilterView(
                filters: $filters,
                columns: columns.map(\.name),
                onApply: {
                    currentPage = 0
                    loadData()
                }
            )
            
            Divider()
            
            // Main Grid or Status Area
            if isLoading && result == nil {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading \(tableName)...")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.error)
                    Text("Failed to Load Table Data")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button {
                        loadData()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(AppTheme.accent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            } else if let res = result, res.hasRows {
                DataGridView(
                    columns: res.columns,
                    rows: res.rows,
                    isEditable: true,
                    onCellEdit: { row, col, newValue in
                        handleCellEdit(row: row, col: col, newValue: newValue, res: res)
                    },
                    tableName: tableName
                )
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No records found in \(tableName)")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    if !filters.isEmpty {
                        Text("Try clearing the active filters")
                            .font(.caption)
                            .foregroundColor(AppTheme.textMuted)
                    }
                    
                    Button {
                        currentPage = 0
                        filters.removeAll()
                        loadData()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload Table")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.accent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            
            Divider()
            
            // Bottom Pagination and Navigation Bar
            HStack(spacing: 12) {
                // Page Navigation
                HStack(spacing: 6) {
                    Button {
                        if currentPage > 0 {
                            currentPage = 0
                            loadData()
                        }
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 9))
                            .frame(width: 22, height: 20)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage == 0 || isLoading)
                    .help("First Page")
                    
                    Button {
                        if currentPage > 0 {
                            currentPage -= 1
                            loadData()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("Prev")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage == 0 || isLoading)
                    
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, 6)
                    
                    Button {
                        if (currentPage + 1) < totalPages {
                            currentPage += 1
                            loadData()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled((currentPage + 1) >= totalPages || isLoading)
                    
                    Button {
                        if (currentPage + 1) < totalPages {
                            currentPage = totalPages - 1
                            loadData()
                        }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 9))
                            .frame(width: 22, height: 20)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled((currentPage + 1) >= totalPages || isLoading)
                    .help("Last Page")
                }
                
                // Total Rows Count
                Text("(\(totalRows.formatted()) rows total)")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                
                Spacer()
                
                // Sort Picker if columns loaded
                if !columns.isEmpty {
                    Menu {
                        Button("None") {
                            sortColumn = nil
                            loadData()
                        }
                        Divider()
                        ForEach(columns, id: \.name) { col in
                            Button("\(col.name) (Ascending)") {
                                sortColumn = col.name
                                sortAscending = true
                                loadData()
                            }
                            Button("\(col.name) (Descending)") {
                                sortColumn = col.name
                                sortAscending = false
                                loadData()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 9))
                            Text(sortColumn == nil ? "Sort: Default" : "Sort: \(sortColumn!) \(sortAscending ? "↑" : "↓")")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                }
                
                // Page Size Picker
                HStack(spacing: 4) {
                    Text("Rows:")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                    Picker("", selection: $pageSize) {
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("250").tag(250)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 75)
                    .onChange(of: pageSize) { _, _ in
                        currentPage = 0
                        loadData()
                    }
                }
                
                // Reload Button
                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 22, height: 20)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Reload Data")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.backgroundSecondary)
        }
        .background(AppTheme.backgroundPrimary)
        .onAppear {
            loadMetadataAndData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitChanges)) { _ in
            commitStagedChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rollbackChanges)) { _ in
            rollbackStagedChanges()
        }
    }
    
    // MARK: - Data Operations
    
    private func loadMetadataAndData() {
        Task {
            do {
                let cols = try await appState.dbManager.getColumns(database: database, table: tableName)
                let pks = cols.filter { $0.isPrimaryKey }.map { $0.name }
                
                await MainActor.run {
                    self.columns = cols
                    self.primaryKeyColumns = pks
                }
            } catch {
                print("Failed to introspect columns for \(database).\(tableName): \(error)")
            }
            
            loadData()
        }
    }
    
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                async let countTask = appState.dbManager.getRowCount(database: database, table: tableName)
                async let dataTask = appState.dbManager.getTableData(
                    database: database,
                    table: tableName,
                    page: currentPage,
                    pageSize: pageSize,
                    filters: filters,
                    sortColumn: sortColumn,
                    sortAscending: sortAscending
                )
                
                let (count, data) = try await (countTask, dataTask)
                
                await MainActor.run {
                    self.totalRows = count
                    self.result = data
                    self.isLoading = false
                    
                    if let activeId = tabState.activeTabId {
                        tabState.setResult(for: activeId, result: data)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = ErrorFormatter.format(error)
                    self.isLoading = false
                }
            }
        }
    }
    
    private func handleCellEdit(row: Int, col: Int, newValue: QueryResult.CellValue, res: QueryResult) {
        guard row < res.rows.count && col < res.columns.count else { return }
        
        let oldValue = res.rows[row][col]
        let colName = res.columns[col].name
        
        // Build primary key map for WHERE clause
        var pkValues: [String: QueryResult.CellValue] = [:]
        for pk in primaryKeyColumns {
            if let colIndex = res.columns.firstIndex(where: { $0.name == pk }), colIndex < res.rows[row].count {
                pkValues[pk] = res.rows[row][colIndex]
            }
        }
        
        // Fallback: If no explicit primary keys defined, include all unmodified original cell values
        if pkValues.isEmpty {
            for (index, c) in res.columns.enumerated() {
                if index < res.rows[row].count {
                    pkValues[c.name] = res.rows[row][index]
                }
            }
        }
        
        let change = CellChange(
            table: tableName,
            database: database,
            rowIndex: row,
            column: colName,
            oldValue: oldValue,
            newValue: newValue,
            changeType: .update,
            primaryKeyValues: pkValues
        )
        
        stagedChanges.add(change)
        
        // Update tab staged changes for status bar
        if let activeId = tabState.activeTabId,
           let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
            tabState.tabs[idx].stagedChanges = stagedChanges
        }
    }
    
    private func commitStagedChanges() {
        guard !stagedChanges.isEmpty else { return }
        let changesToApply = stagedChanges.changes
        
        isLoading = true
        Task {
            do {
                try await appState.dbManager.applyChanges(changesToApply)
                await MainActor.run {
                    stagedChanges.clear()
                    if let activeId = tabState.activeTabId,
                       let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
                        tabState.tabs[idx].stagedChanges = stagedChanges
                    }
                    loadData()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to commit changes: \(ErrorFormatter.format(error))"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func rollbackStagedChanges() {
        stagedChanges.clear()
        if let activeId = tabState.activeTabId,
           let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
            tabState.tabs[idx].stagedChanges = stagedChanges
        }
        loadData()
    }
}
