import Foundation
import Observation

@Observable
class SchemaState {
    var databases: [DatabaseInfo] = []
    var tablesByDatabase: [String: [TableInfo]] = [:]
    var columnsByTable: [String: [String]] = [:] // Key: "tableName" or "db.tableName" -> [columnNames]
    var allColumnsByDatabase: [String: [String]] = [:]
    var expandedNodes: Set<String> = []
    var filterText: String = ""
    var isLoading = false
    var showSystemDatabases = false
    var defaultDatabase: String = ""
    var dbManager: MySQLManager = MySQLManager.shared
    
    private var isFetchingDatabases = false
    private var loadingColumnsForDatabases = Set<String>()
    
    static let systemDatabases: Set<String> = ["information_schema", "performance_schema", "mysql", "sys"]
    
    init(dbManager: MySQLManager = MySQLManager.shared) {
        self.dbManager = dbManager
    }
    
    func loadDatabases(defaultDB: String = "") async {
        guard !isFetchingDatabases else { return }
        isFetchingDatabases = true
        defer { isFetchingDatabases = false }
        
        await MainActor.run {
            self.isLoading = true
            if !defaultDB.isEmpty {
                self.defaultDatabase = defaultDB
            }
        }
        
        do {
            let dbs = try await dbManager.getDatabases()
            await MainActor.run {
                self.databases = dbs
                self.isLoading = false
                
                // Auto-expand default database if specified
                let target = self.defaultDatabase.isEmpty ? defaultDB : self.defaultDatabase
                if !target.isEmpty {
                    self.expandedNodes.insert(target)
                }
            }
            
            // Pre-fetch tables & columns for default database
            let target = self.defaultDatabase.isEmpty ? defaultDB : self.defaultDatabase
            if !target.isEmpty {
                await loadTables(for: target)
            }
        } catch {
            print("Failed to load databases: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func loadTables(for database: String) async {
        do {
            let tables = try await dbManager.getTables(database: database)
            await MainActor.run {
                self.tablesByDatabase[database] = tables
            }
            // Load column metadata in background for instant autocomplete
            await loadAllColumns(for: database)
        } catch {
            print("Failed to load tables for \(database): \(error)")
        }
    }
    
    func loadAllColumns(for database: String) async {
        guard !database.isEmpty else { return }
        guard !loadingColumnsForDatabases.contains(database) else { return }
        loadingColumnsForDatabases.insert(database)
        defer { loadingColumnsForDatabases.remove(database) }
        do {
            let escapedDB = database
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let sql = """
            SELECT TABLE_NAME, COLUMN_NAME 
            FROM information_schema.columns 
            WHERE table_schema = '\(escapedDB)' 
            ORDER BY TABLE_NAME, ORDINAL_POSITION
            """
            let res = try await dbManager.executeQuery(sql)
            var tableCols: [String: [String]] = [:]
            var allCols: [String] = []
            var seenCols = Set<String>()
            
            for row in res.rows {
                if row.count >= 2,
                   case .string(let tbl) = row[0],
                   case .string(let col) = row[1] {
                    tableCols[tbl, default: []].append(col)
                    tableCols["\(database).\(tbl)", default: []].append(col)
                    if !seenCols.contains(col) {
                        seenCols.insert(col)
                        allCols.append(col)
                    }
                }
            }
            
            let capturedTableCols = tableCols
            let capturedAllCols = allCols
            
            await MainActor.run {
                for (tbl, cols) in capturedTableCols {
                    self.columnsByTable[tbl] = cols
                }
                self.allColumnsByDatabase[database] = capturedAllCols
            }
        } catch {
            print("Failed to load columns for \(database): \(error)")
        }
    }
    
    func toggleNode(_ nodeId: String) {
        if expandedNodes.contains(nodeId) {
            expandedNodes.remove(nodeId)
        } else {
            expandedNodes.insert(nodeId)
        }
    }
    
    func isExpanded(_ nodeId: String) -> Bool {
        return expandedNodes.contains(nodeId)
    }
    
    var userDatabases: [DatabaseInfo] {
        filteredDatabases.filter { !Self.systemDatabases.contains($0.name.lowercased()) }
    }
    
    var sysDatabases: [DatabaseInfo] {
        filteredDatabases.filter { Self.systemDatabases.contains($0.name.lowercased()) }
    }
    
    var filteredDatabases: [DatabaseInfo] {
        var list = databases
        if !filterText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
        }
        
        // Sort: Default database first, then alphabetical
        return list.sorted { db1, db2 in
            if !defaultDatabase.isEmpty {
                if db1.name.lowercased() == defaultDatabase.lowercased() { return true }
                if db2.name.lowercased() == defaultDatabase.lowercased() { return false }
            }
            let isSys1 = Self.systemDatabases.contains(db1.name.lowercased())
            let isSys2 = Self.systemDatabases.contains(db2.name.lowercased())
            if isSys1 != isSys2 {
                return !isSys1 // User dbs before system dbs
            }
            return db1.name.localizedCaseInsensitiveCompare(db2.name) == .orderedAscending
        }
    }
    
    func filteredTables(for database: String) -> [TableInfo] {
        let tables = tablesByDatabase[database] ?? []
        if filterText.isEmpty {
            return tables
        }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }
}
