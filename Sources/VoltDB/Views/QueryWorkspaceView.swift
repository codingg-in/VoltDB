import SwiftUI

struct QueryWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(SchemaState.self) private var schemaState
    
    let tab: EditorTab
    
    @State private var queryText: String = ""
    @State private var showDestructiveConfirmation = false
    @State private var pendingDestructiveSQL: String = ""
    @State private var insertedRowIndices: Set<Int> = []
    @State private var primaryKeyColumns: [String] = []
    @State private var editorHeight: CGFloat? = nil
    @State private var dragStartHeight: CGFloat? = nil
    @State private var isDraggingSplitter: Bool = false
    @State private var isShowingCommitReviewSheet: Bool = false
    @State private var pendingCommitSQL: String = ""
    
    init(tab: EditorTab) {
        self.tab = tab
    }
    
    private var currentDB: String {
        if let tabDB = tabState.activeTab?.database, !tabDB.isEmpty { return tabDB }
        if !appState.currentDatabase.isEmpty { return appState.currentDatabase }
        if !tab.database.isEmpty { return tab.database }
        return ""
    }
    
    var body: some View {
        let activeDB = currentDB
        let tables = schemaState.tablesByDatabase[activeDB]?.map { $0.name } ?? []
        let cols = schemaState.allColumnsByDatabase[activeDB] ?? []
        let dbs = schemaState.databases.map { $0.name }
        
        VStack(spacing: 0) {
            // Editor Toolbar with Run, Format, DB context, Explain, Clear
            EditorToolbarView(
                currentDatabase: currentDB,
                queryText: tabState.activeTab?.queryText ?? tab.queryText,
                isLoading: tab.isLoading,
                onClear: {
                    queryText = ""
                    if let activeId = tabState.activeTabId {
                        tabState.updateQueryText(for: activeId, text: "")
                    }
                },
                onExplain: { format in
                    explainActiveQuery(format: format)
                }
            )
            
            // Split Editor + Results (Robust against sidebar resize)
            GeometryReader { geo in
                let currentEditorHeight = editorHeight ?? max(120, geo.size.height - 300)
                
                VStack(spacing: 0) {
                    SQLEditorView(
                        text: Binding(
                            get: { tabState.activeTab?.queryText ?? queryText },
                            set: { newText in
                                queryText = newText
                                if let activeId = tabState.activeTabId {
                                    tabState.updateQueryText(for: activeId, text: newText)
                                }
                            }
                        ),
                        tableNames: tables,
                        columnNames: cols,
                        columnsByTable: schemaState.columnsByTable,
                        databaseNames: dbs
                    )
                    .frame(height: max(80, min(currentEditorHeight, geo.size.height - 100)))
                    
                    // Draggable Divider
                    ZStack {
                        Color.clear
                            .frame(height: 8)
                        
                        Rectangle()
                            .fill(isDraggingSplitter ? AppTheme.accent : AppTheme.border.opacity(0.35))
                            .frame(height: isDraggingSplitter ? 2 : 1)
                    }
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if !isDraggingSplitter {
                                    isDraggingSplitter = true
                                    dragStartHeight = currentEditorHeight
                                    NSCursor.resizeUpDown.push()
                                }
                                let base = dragStartHeight ?? currentEditorHeight
                                editorHeight = max(80, min(base + value.translation.height, geo.size.height - 100))
                            }
                            .onEnded { _ in
                                isDraggingSplitter = false
                                dragStartHeight = nil
                                NSCursor.pop()
                            }
                    )
                    .onHover { hovering in
                        if hovering && !isDraggingSplitter {
                            NSCursor.resizeUpDown.push()
                        } else if !hovering && !isDraggingSplitter {
                            NSCursor.pop()
                        }
                    }
                    
                    ResultsPanelView(
                        result: tabState.activeTab?.result ?? tab.result,
                        isLoading: tabState.activeTab?.isLoading ?? tab.isLoading,
                        isEditable: true,
                        stagedChanges: tabState.activeTab?.stagedChanges.changes ?? tab.stagedChanges.changes,
                        insertedRowIndices: insertedRowIndices,
                        onCellEdit: { row, col, newVal in
                            if let res = tabState.activeTab?.result ?? tab.result {
                                handleCellEdit(row: row, col: col, newValue: newVal, res: res)
                            }
                        },
                        onRowSelect: { rowIndex in
                            tabState.selectedRowIndex = rowIndex
                        },
                        tableName: tabState.activeTab?.tableName
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            queryText = tab.queryText
            let initDB = currentDB
            if !initDB.isEmpty {
                Task {
                    await schemaState.loadTables(for: initDB)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runQuery)) { notif in
            guard tabState.activeTab?.id == tab.id else { return }
            if let customSQL = notif.object as? String, !customSQL.isEmpty {
                runQuerySQL(customSQL)
            } else {
                runCurrentQuery()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runCurrentQuery)) { notif in
            guard tabState.activeTab?.id == tab.id else { return }
            if let customSQL = notif.object as? String, !customSQL.isEmpty {
                runQuerySQL(customSQL)
            } else {
                runCurrentQuery()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runAllQueries)) { _ in
            guard tabState.activeTab?.id == tab.id else { return }
            runAllQueriesInActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopQuery)) { _ in
            guard tabState.activeTab?.id == tab.id else { return }
            stopCurrentQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addNewRow)) { _ in
            guard tabState.activeTab?.id == tab.id else { return }
            addNewRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitChanges)) { _ in
            guard tabState.activeTab?.id == tab.id else { return }
            commitStagedChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rollbackChanges)) { _ in
            guard tabState.activeTab?.id == tab.id else { return }
            rollbackStagedChanges()
        }
        .alert(
            "⚠️ Destructive Query on Production",
            isPresented: $showDestructiveConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                pendingDestructiveSQL = ""
            }
            Button("Execute Anyway", role: .destructive) {
                let sql = pendingDestructiveSQL
                pendingDestructiveSQL = ""
                forceRunQuerySQL(sql)
            }
        } message: {
            Text("This query contains a potentially destructive statement (DROP, TRUNCATE, DELETE or UPDATE without WHERE). You are connected to a PRODUCTION database.\n\nAre you sure you want to execute this?")
        }
        .sheet(isPresented: $isShowingCommitReviewSheet) {
            let activeChanges = tabState.activeTab?.stagedChanges
            CommitReviewSheetView(
                initialSQL: pendingCommitSQL.isEmpty ? (activeChanges?.toSQL().joined(separator: "\n\n") ?? "") : pendingCommitSQL,
                database: currentDB,
                tableName: tabState.activeTab?.tableName,
                changeCount: activeChanges?.count ?? 0,
                onApply: { finalSQL in
                    try await applyFinalCommitSQL(finalSQL)
                },
                onCancel: {
                    isShowingCommitReviewSheet = false
                    pendingCommitSQL = ""
                }
            )
            .id(pendingCommitSQL + "_\(activeChanges?.count ?? 0)")
        }
    }
    
    private func findEditorTextView() -> NSTextView? {
        if let focused = NSApp.keyWindow?.firstResponder as? NSTextView {
            return focused
        }
        guard let window = NSApp.keyWindow else { return nil }
        return findTextView(in: window.contentView)
    }
    
    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }
        if let tv = view as? EditorNSTextView { return tv }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) {
                return found
            }
        }
        return nil
    }
    
    private func getCurrentStatementOrSelection() -> String {
        guard let activeTab = tabState.activeTab, activeTab.type == .query else { return "" }
        let currentText = activeTab.queryText
        
        var queryToRun = ""
        if let textView = findEditorTextView() {
            let range = textView.selectedRange()
            if range.length > 0 {
                let full = textView.string as NSString
                if range.location + range.length <= full.length {
                    queryToRun = full.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                queryToRun = SQLStatementExtractor.extractCurrentStatement(from: textView.string, cursorPosition: range.location)
            }
        }
        
        if queryToRun.isEmpty {
            queryToRun = SQLStatementExtractor.extractCurrentStatement(from: currentText, cursorPosition: 0)
        }
        
        if queryToRun.isEmpty {
            queryToRun = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return queryToRun
    }
    
    private func runCurrentQuery() {
        let queryToRun = getCurrentStatementOrSelection()
        guard !queryToRun.isEmpty else { return }
        runQuerySQL(queryToRun)
    }
    
    private func runAllQueriesInActiveTab() {
        guard let activeTab = tabState.activeTab, activeTab.type == .query else { return }
        let fullText = activeTab.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else { return }
        runQuerySQL(fullText)
    }
    
    private func stopCurrentQuery() {
        guard let activeTab = tabState.activeTab else { return }
        // Cancel the Swift Task (cooperative cancellation)
        tabState.cancelRunningTask(for: activeTab.id)
        // Send KILL QUERY to MySQL server to abort the running SQL
        Task {
            await appState.dbManager.cancelRunningQuery()
        }
    }
    
    private func runQuerySQL(_ sql: String) {
        // Check for destructive statements on production connections
        if appState.activeConnection?.isProduction == true {
            let statements = SQLStatementExtractor.splitStatements(from: sql)
            let hasDestructive = statements.contains { stmt in
                isDestructiveStatement(SQLStatementExtractor.cleanSQLStatement(stmt))
            }
            if hasDestructive {
                pendingDestructiveSQL = sql
                showDestructiveConfirmation = true
                return
            }
        }
        forceRunQuerySQL(sql)
    }
    
    /// Bypasses the destructive query check — called after user confirms the alert.
    private func forceRunQuerySQL(_ sql: String) {
        let statements = SQLStatementExtractor.splitStatements(from: sql)
        if statements.isEmpty { return }
        guard let activeTab = tabState.activeTab, activeTab.type == .query else { return }
        
        let targetDB = currentDB
        tabState.setLoading(for: activeTab.id, loading: true)
        
        let task = Task { @MainActor in
            let startTime = Date()
            var detectedTable: String? = nil
            for stmt in statements.reversed() {
                if let t = SQLStatementExtractor.extractTableName(from: stmt) {
                    detectedTable = t
                    break
                }
            }
            do {
                var lastResult: QueryResult? = nil
                for stmt in statements {
                    // Check for cancellation between statements
                    if Task.isCancelled {
                        let elapsed = Date().timeIntervalSince(startTime)
                        let cancelledResult = QueryResult(
                            columns: [],
                            rows: [],
                            affectedRows: 0,
                            executionTime: elapsed,
                            error: "Query cancelled by user.",
                            queryType: .other
                        )
                        tabState.setResult(for: activeTab.id, result: cancelledResult)
                        tabState.setLoading(for: activeTab.id, loading: false)
                        tabState.clearRunningTask(for: activeTab.id)
                        return
                    }
                    
                    let clean = SQLStatementExtractor.cleanSQLStatement(stmt)
                    if clean.isEmpty { continue }
                    lastResult = try await appState.dbManager.executeQuery(clean, database: targetDB)
                    if let err = lastResult?.error, !err.isEmpty {
                        break
                    }
                }
                
                if Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let cancelledResult = QueryResult(
                        columns: [],
                        rows: [],
                        affectedRows: 0,
                        executionTime: elapsed,
                        error: "Query cancelled by user.",
                        queryType: .other
                    )
                    tabState.setResult(for: activeTab.id, result: cancelledResult)
                } else if let res = lastResult {
                    tabState.setResult(for: activeTab.id, result: res)
                    if let table = detectedTable {
                        if let activeId = tabState.activeTabId,
                           let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
                            tabState.tabs[idx].tableName = table
                        }
                        if let cols = try? await appState.dbManager.getColumns(database: targetDB, table: table) {
                            self.primaryKeyColumns = cols.filter { $0.isPrimaryKey }.map { $0.name }
                        }
                    }
                    self.insertedRowIndices.removeAll()
                }
                tabState.setLoading(for: activeTab.id, loading: false)
                tabState.clearRunningTask(for: activeTab.id)
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                let errorMsg: String
                if Task.isCancelled {
                    errorMsg = "Query cancelled by user."
                } else {
                    errorMsg = ErrorFormatter.format(error)
                }
                let errorResult = QueryResult(
                    columns: [],
                    rows: [],
                    affectedRows: 0,
                    executionTime: elapsed,
                    error: errorMsg,
                    queryType: .other
                )
                tabState.setResult(for: activeTab.id, result: errorResult)
                tabState.setLoading(for: activeTab.id, loading: false)
                tabState.clearRunningTask(for: activeTab.id)
            }
        }
        tabState.setRunningTask(for: activeTab.id, task: task)
    }
    
    // MARK: - Grid Editing and Staging
    
    private func addNewRow() {
        guard let res = tabState.activeTab?.result ?? tab.result, res.hasRows || !res.columns.isEmpty else { return }
        
        let targetTable = tabState.activeTab?.tableName ?? SQLStatementExtractor.extractTableName(from: tabState.activeTab?.queryText ?? queryText) ?? "result_table"
        
        var newRowValues: [QueryResult.CellValue] = []
        for col in res.columns {
            let colName = col.name.lowercased()
            let isPK = primaryKeyColumns.contains(where: { $0.lowercased() == colName })
            if colName == "id" || (isPK && (colName.hasSuffix("_id") || primaryKeyColumns.count == 1)) {
                newRowValues.append(.string("DEFAULT"))
            } else if colName.hasSuffix("_at") || colName.hasSuffix("_on") || colName.contains("time") {
                newRowValues.append(.string("DEFAULT"))
            } else {
                newRowValues.append(.null)
            }
        }
        
        let newRowIndex = res.rows.count
        var updatedRows = res.rows
        updatedRows.append(newRowValues)
        
        let updatedRes = QueryResult(
            columns: res.columns,
            rows: updatedRows,
            affectedRows: res.affectedRows,
            executionTime: res.executionTime,
            error: res.error,
            queryType: res.queryType
        )
        
        insertedRowIndices.insert(newRowIndex)
        
        var rowValuesDict: [String: QueryResult.CellValue] = [:]
        for (i, c) in res.columns.enumerated() {
            rowValuesDict[c.name] = newRowValues[i]
        }
        
        let change = CellChange(
            table: targetTable,
            database: currentDB,
            rowIndex: newRowIndex,
            column: "*",
            oldValue: .null,
            newValue: .null,
            changeType: .insert,
            primaryKeyValues: rowValuesDict,
            columnOrder: res.columns.map(\.name)
        )
        
        if let activeId = tabState.activeTabId,
           let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
            tabState.tabs[idx].stagedChanges.add(change)
            tabState.setResult(for: activeId, result: updatedRes)
        }
        
        tabState.selectedRowIndex = newRowIndex
    }
    
    private func handleCellEdit(row: Int, col: Int, newValue: QueryResult.CellValue, res: QueryResult) {
        guard row < res.rows.count && col < res.columns.count else { return }
        guard let activeId = tabState.activeTabId,
              let tabIdx = tabState.tabs.firstIndex(where: { $0.id == activeId }) else { return }
        
        let oldValue = res.rows[row][col]
        let colName = res.columns[col].name
        let targetTable = tabState.tabs[tabIdx].tableName ?? SQLStatementExtractor.extractTableName(from: tabState.activeTab?.queryText ?? queryText) ?? "result_table"
        
        var newRows = res.rows
        newRows[row][col] = newValue
        let updatedRes = QueryResult(
            columns: res.columns,
            rows: newRows,
            affectedRows: res.affectedRows,
            executionTime: res.executionTime,
            error: res.error,
            queryType: res.queryType
        )
        tabState.setResult(for: activeId, result: updatedRes)
        
        var currentStaged = tabState.tabs[tabIdx].stagedChanges
        
        if insertedRowIndices.contains(row) {
            if let existingIdx = currentStaged.changes.firstIndex(where: { $0.rowIndex == row && $0.changeType == .insert }) {
                var updatedPKs = currentStaged.changes[existingIdx].primaryKeyValues
                updatedPKs[colName] = newValue
                let updatedChange = CellChange(
                    table: targetTable,
                    database: currentDB,
                    rowIndex: row,
                    column: "*",
                    oldValue: .null,
                    newValue: .null,
                    changeType: .insert,
                    primaryKeyValues: updatedPKs,
                    columnOrder: res.columns.map(\.name)
                )
                currentStaged.changes[existingIdx] = updatedChange
            }
        } else {
            // Check if there is already an existing staged update for this cell
            if let existingIdx = currentStaged.changes.firstIndex(where: { $0.rowIndex == row && $0.column == colName && $0.changeType == .update }) {
                let existing = currentStaged.changes[existingIdx]
                if newValue == existing.newValue {
                    // Staged value is unchanged; preserve staged change!
                    return
                }
                if newValue == existing.oldValue || newValue.description == existing.oldValue.description {
                    // Reverted back to original database value: remove staged change
                    currentStaged.changes.remove(at: existingIdx)
                    tabState.tabs[tabIdx].stagedChanges = currentStaged
                    return
                }
                // Value changed to a different new value: preserve original oldValue!
                var updatedChange = existing
                updatedChange.newValue = newValue
                currentStaged.changes[existingIdx] = updatedChange
            } else {
                if oldValue == newValue || oldValue.description == newValue.description { return }
                
                var pkValues: [String: QueryResult.CellValue] = [:]
                for pk in primaryKeyColumns {
                    if let colIndex = res.columns.firstIndex(where: { $0.name == pk }), colIndex < res.rows[row].count {
                        pkValues[pk] = res.rows[row][colIndex]
                    }
                }
                if pkValues.isEmpty {
                    for (index, c) in res.columns.enumerated() {
                        if index < res.rows[row].count {
                            pkValues[c.name] = res.rows[row][index]
                        }
                    }
                }
                
                let change = CellChange(
                    table: targetTable,
                    database: currentDB,
                    rowIndex: row,
                    column: colName,
                    oldValue: oldValue,
                    newValue: newValue,
                    changeType: .update,
                    primaryKeyValues: pkValues,
                    columnOrder: res.columns.map(\.name)
                )
                currentStaged.add(change)
            }
        }
        
        tabState.tabs[tabIdx].stagedChanges = currentStaged
    }
    
    private func commitStagedChanges() {
        // End any active editing in NSTableView so the latest text is committed to stagedChanges
        (NSApp.keyWindow ?? NSApp.mainWindow)?.endEditing(for: nil)
        (NSApp.keyWindow ?? NSApp.mainWindow)?.makeFirstResponder(nil)
        
        DispatchQueue.main.async {
            guard let activeTab = self.tabState.activeTab, activeTab.stagedChanges.count > 0 else { return }
            let statements = activeTab.stagedChanges.toSQL()
            self.pendingCommitSQL = statements.joined(separator: "\n\n")
            self.isShowingCommitReviewSheet = true
        }
    }
    
    private func applyFinalCommitSQL(_ finalSQL: String) async throws {
        let statements = SQLStatementExtractor.splitStatements(from: finalSQL)
        let targetDB = currentDB.trimmingCharacters(in: .whitespacesAndNewlines)
        for stmt in statements {
            let clean = SQLStatementExtractor.cleanSQLStatement(stmt)
            if clean.isEmpty { continue }
            _ = try await appState.dbManager.executeQuery(clean, database: targetDB.isEmpty ? nil : targetDB)
        }
        
        await MainActor.run {
            if let activeId = tabState.activeTabId,
               let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
                tabState.tabs[idx].stagedChanges.clear()
            }
            self.insertedRowIndices.removeAll()
            self.isShowingCommitReviewSheet = false
            self.runCurrentQuery()
        }
    }
    
    private func rollbackStagedChanges() {
        guard tabState.activeTab != nil else { return }
        if let activeId = tabState.activeTabId,
           let idx = tabState.tabs.firstIndex(where: { $0.id == activeId }) {
            tabState.tabs[idx].stagedChanges.clear()
        }
        self.insertedRowIndices.removeAll()
        self.runCurrentQuery()
    }
    
    /// Detects SQL statements that could cause irreversible data loss.
    private func isDestructiveStatement(_ sql: String) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // DROP anything (DATABASE, TABLE, INDEX, etc.)
        if trimmed.hasPrefix("DROP ") { return true }
        // TRUNCATE TABLE
        if trimmed.hasPrefix("TRUNCATE ") { return true }
        // DELETE without WHERE
        if trimmed.hasPrefix("DELETE ") && !trimmed.contains("WHERE") { return true }
        // UPDATE without WHERE
        if trimmed.hasPrefix("UPDATE ") && !trimmed.contains("WHERE") { return true }
        return false
    }
    
    private func explainActiveQuery(format: String = "") {
        guard let activeTab = tabState.activeTab, activeTab.type == .query else { return }
        let targetSQL = getCurrentStatementOrSelection()
        let statements = SQLStatementExtractor.splitStatements(from: targetSQL)
        let rawStmt = statements.first ?? targetSQL
        let cleanStmt = SQLStatementExtractor.cleanSQLStatement(rawStmt)
        guard !cleanStmt.isEmpty else { return }
        
        let prefix = format.isEmpty ? "EXPLAIN" : "EXPLAIN \(format)"
        let explainSQL = "\(prefix) \(cleanStmt)"
        
        let targetDB = currentDB
        tabState.setLoading(for: activeTab.id, loading: true)
        
        Task {
            let startTime = Date()
            do {
                let result = try await appState.dbManager.executeQuery(explainSQL, database: targetDB)
                await MainActor.run {
                    tabState.setResult(for: activeTab.id, result: result)
                    tabState.setLoading(for: activeTab.id, loading: false)
                }
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                let formattedErr = ErrorFormatter.format(error)
                let errorResult = QueryResult(
                    columns: [],
                    rows: [],
                    affectedRows: 0,
                    executionTime: elapsed,
                    error: formattedErr,
                    queryType: .other
                )
                await MainActor.run {
                    tabState.setResult(for: activeTab.id, result: errorResult)
                    tabState.setLoading(for: activeTab.id, loading: false)
                }
            }
        }
    }
}

