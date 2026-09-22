import SwiftUI

struct QueryWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(SchemaState.self) private var schemaState
    
    let tab: EditorTab
    
    @State private var queryText: String = ""
    @State private var showDestructiveConfirmation = false
    @State private var pendingDestructiveSQL: String = ""
    
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
            
            // Split Editor + Results
            VSplitView {
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
                    columnNames: schemaState.allColumnsByDatabase[activeDB] ?? [],
                    columnsByTable: schemaState.columnsByTable,
                    databaseNames: dbs
                )
                .frame(minHeight: 120)
                
                ResultsPanelView(
                    result: tabState.activeTab?.result ?? tab.result,
                    isLoading: tabState.activeTab?.isLoading ?? tab.isLoading,
                    isEditable: true,
                    onCellEdit: { row, col, newVal in
                        if let res = tabState.activeTab?.result {
                            if row < res.rows.count && col < res.rows[row].count {
                                var newRows = res.rows
                                newRows[row][col] = newVal
                                let updatedRes = QueryResult(
                                    columns: res.columns,
                                    rows: newRows,
                                    affectedRows: res.affectedRows,
                                    executionTime: res.executionTime,
                                    error: res.error,
                                    queryType: res.queryType
                                )
                                if let activeId = tabState.activeTabId {
                                    tabState.setResult(for: activeId, result: updatedRes)
                                }
                            }
                        }
                    },
                    tableName: tabState.activeTab?.tableName
                )
                .frame(minHeight: 150)
            }
        }
        .onAppear {
            queryText = tab.queryText
            let initDB = currentDB
            if !initDB.isEmpty {
                Task {
                    await schemaState.loadTables(for: initDB)
                    await schemaState.loadAllColumns(for: initDB)
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
        
        Task {
            let startTime = Date()
            do {
                var lastResult: QueryResult? = nil
                for stmt in statements {
                    let clean = SQLStatementExtractor.cleanSQLStatement(stmt)
                    if clean.isEmpty { continue }
                    lastResult = try await appState.dbManager.executeQuery(clean, database: targetDB)
                    if let err = lastResult?.error, !err.isEmpty {
                        break
                    }
                }
                
                let finalResult = lastResult
                await MainActor.run {
                    if let res = finalResult {
                        tabState.setResult(for: activeTab.id, result: res)
                    }
                    tabState.setLoading(for: activeTab.id, loading: false)
                }
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                let formatted = ErrorFormatter.format(error)
                let errorResult = QueryResult(
                    columns: [],
                    rows: [],
                    affectedRows: 0,
                    executionTime: elapsed,
                    error: formatted,
                    queryType: .other
                )
                await MainActor.run {
                    tabState.setResult(for: activeTab.id, result: errorResult)
                    tabState.setLoading(for: activeTab.id, loading: false)
                }
            }
        }
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
