import Foundation

/// Represents a staged change to a cell in the data grid.
struct CellChange: Identifiable, Hashable {
    let id = UUID()
    let table: String
    let database: String
    let rowIndex: Int
    let column: String
    let oldValue: QueryResult.CellValue
    var newValue: QueryResult.CellValue
    let changeType: ChangeType
    let primaryKeyValues: [String: QueryResult.CellValue]
    let columnOrder: [String]

    init(
        table: String,
        database: String,
        rowIndex: Int,
        column: String,
        oldValue: QueryResult.CellValue,
        newValue: QueryResult.CellValue,
        changeType: ChangeType,
        primaryKeyValues: [String: QueryResult.CellValue],
        columnOrder: [String] = []
    ) {
        self.table = table
        self.database = database
        self.rowIndex = rowIndex
        self.column = column
        self.oldValue = oldValue
        self.newValue = newValue
        self.changeType = changeType
        self.primaryKeyValues = primaryKeyValues
        self.columnOrder = columnOrder
    }

    enum ChangeType: Hashable {
        case update
        case insert
        case delete
    }

    /// Generates the SQL statement for this change.
    func toSQL() -> String {
        let escDB = database.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "``")
        let escTable = table.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "``")
        let escColumn = column.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "``")
        
        let tableRef = escDB.isEmpty ? "`\(escTable)`" : "`\(escDB)`.`\(escTable)`"
        
        switch changeType {
        case .update:
            guard !primaryKeyValues.isEmpty else {
                return "-- ERROR: Cannot generate UPDATE without primary key columns (would affect ALL rows)"
            }
            let whereClause = primaryKeyValues.sorted(by: { $0.key < $1.key }).map {
                let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
                if $0.value.isNull {
                    return "`\(escKey)` IS NULL"
                } else {
                    return "`\(escKey)` = \($0.value.sqlLiteral)"
                }
            }.joined(separator: " AND ")
            return "UPDATE \(tableRef) SET `\(escColumn)` = \(newValue.sqlLiteral) WHERE \(whereClause);"

        case .insert:
            // For insert, primaryKeyValues contains column values for the new row.
            // Order columns according to columnOrder if provided (table schema order),
            // otherwise fallback to alphabetical order.
            let orderedKeys: [String]
            if !columnOrder.isEmpty {
                let inOrder = columnOrder.filter { primaryKeyValues.keys.contains($0) }
                let leftover = primaryKeyValues.keys.filter { !columnOrder.contains($0) }.sorted()
                orderedKeys = inOrder + leftover
            } else {
                orderedKeys = primaryKeyValues.keys.sorted()
            }
            
            // Columns whose value is "DEFAULT" are omitted from the INSERT so that
            // MySQL automatically assigns AUTO_INCREMENT IDs, CURRENT_TIMESTAMP,
            // and schema default values!
            let filteredKeys = orderedKeys.filter { key in
                let val = primaryKeyValues[key]!
                return val.description.uppercased() != "DEFAULT"
            }
            
            // If all columns were left as DEFAULT, insert default row
            if filteredKeys.isEmpty {
                return "INSERT INTO \(tableRef) () VALUES ();"
            }
            
            let columns = filteredKeys.map {
                let escCol = $0.replacingOccurrences(of: "`", with: "``")
                return "`\(escCol)`"
            }.joined(separator: ", ")
            
            let values = filteredKeys.map { key -> String in
                let val = primaryKeyValues[key]!
                return val.sqlLiteral
            }.joined(separator: ", ")
            
            return "INSERT INTO \(tableRef) (\(columns)) VALUES (\(values));"

        case .delete:
            guard !primaryKeyValues.isEmpty else {
                return "-- ERROR: Cannot generate DELETE without primary key columns (would delete ALL rows)"
            }
            let whereClause = primaryKeyValues.sorted(by: { $0.key < $1.key }).map {
                let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
                if $0.value.isNull {
                    return "`\(escKey)` IS NULL"
                } else {
                    return "`\(escKey)` = \($0.value.sqlLiteral)"
                }
            }.joined(separator: " AND ")
            return "DELETE FROM \(tableRef) WHERE \(whereClause);"
        }
    }
}

/// A collection of staged changes for a table view tab.
struct StagedChanges {
    var changes: [CellChange] = []

    var count: Int { changes.count }
    var isEmpty: Bool { changes.isEmpty }

    var updateCount: Int { changes.filter { $0.changeType == .update }.count }
    var insertCount: Int { changes.filter { $0.changeType == .insert }.count }
    var deleteCount: Int { changes.filter { $0.changeType == .delete }.count }

    mutating func add(_ change: CellChange) {
        // Remove any existing change for the same cell
        changes.removeAll { existing in
            existing.table == change.table &&
            existing.rowIndex == change.rowIndex &&
            existing.column == change.column
        }
        // Don't add if the value is back to original
        if change.oldValue != change.newValue || change.changeType != .update {
            changes.append(change)
        }
    }

    mutating func clear() {
        changes.removeAll()
    }

    /// Generate all SQL statements for the staged changes.
    func toSQL() -> [String] {
        var statements: [String] = []
        
        // Group updates by (database, table, rowIndex) preserving the order in which rows first appear
        var updateGroups: [String: [CellChange]] = [:]
        var updateGroupKeys: [String] = []
        var nonUpdateChanges: [CellChange] = []
        
        for change in changes {
            if change.changeType == .update {
                let key = "\(change.database)|\(change.table)|\(change.rowIndex)"
                if updateGroups[key] == nil {
                    updateGroups[key] = []
                    updateGroupKeys.append(key)
                }
                updateGroups[key]?.append(change)
            } else {
                nonUpdateChanges.append(change)
            }
        }
        
        // Output row updates grouped into a single UPDATE statement per record
        for key in updateGroupKeys {
            guard let rowUpdates = updateGroups[key], !rowUpdates.isEmpty else { continue }
            let first = rowUpdates[0]
            let escDB = first.database.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "``")
            let escTable = first.table.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "``")
            let tableRef = escDB.isEmpty ? "`\(escTable)`" : "`\(escDB)`.`\(escTable)`"
            
            guard !first.primaryKeyValues.isEmpty else {
                statements.append("-- ERROR: Cannot generate UPDATE without primary key columns (would affect ALL rows)")
                continue
            }
            
            let orderedUpdates: [CellChange]
            if !first.columnOrder.isEmpty {
                orderedUpdates = rowUpdates.sorted { c1, c2 in
                    let idx1 = first.columnOrder.firstIndex(of: c1.column) ?? Int.max
                    let idx2 = first.columnOrder.firstIndex(of: c2.column) ?? Int.max
                    return idx1 < idx2
                }
            } else {
                orderedUpdates = rowUpdates
            }
            
            let setAssignments = orderedUpdates.map { change in
                let escCol = change.column.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "``")
                return "`\(escCol)` = \(change.newValue.sqlLiteral)"
            }.joined(separator: ", ")
            
            let whereClause = first.primaryKeyValues.sorted(by: { $0.key < $1.key }).map {
                let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
                if $0.value.isNull {
                    return "`\(escKey)` IS NULL"
                } else {
                    return "`\(escKey)` = \($0.value.sqlLiteral)"
                }
            }.joined(separator: " AND ")
            
            statements.append("UPDATE \(tableRef) SET \(setAssignments) WHERE \(whereClause);")
        }
        
        // Output inserts and deletes
        for change in nonUpdateChanges {
            statements.append(change.toSQL())
        }
        
        return statements
    }

    /// Summary string for the status bar.
    var summary: String {
        var parts: [String] = []
        if updateCount > 0 { parts.append("\(updateCount) update\(updateCount == 1 ? "" : "s")") }
        if insertCount > 0 { parts.append("\(insertCount) insert\(insertCount == 1 ? "" : "s")") }
        if deleteCount > 0 { parts.append("\(deleteCount) delete\(deleteCount == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}
