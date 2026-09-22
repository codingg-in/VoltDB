import Foundation

/// Represents a staged change to a cell in the data grid.
struct CellChange: Identifiable, Hashable {
    let id = UUID()
    let table: String
    let database: String
    let rowIndex: Int
    let column: String
    let oldValue: QueryResult.CellValue
    let newValue: QueryResult.CellValue
    let changeType: ChangeType
    let primaryKeyValues: [String: QueryResult.CellValue]

    enum ChangeType: Hashable {
        case update
        case insert
        case delete
    }

    /// Generates the SQL statement for this change.
    func toSQL() -> String {
        let escDB = database.replacingOccurrences(of: "`", with: "``")
        let escTable = table.replacingOccurrences(of: "`", with: "``")
        let escColumn = column.replacingOccurrences(of: "`", with: "``")
        
        switch changeType {
        case .update:
            guard !primaryKeyValues.isEmpty else {
                return "-- ERROR: Cannot generate UPDATE without primary key columns (would affect ALL rows)"
            }
            let whereClause = primaryKeyValues.map {
                let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
                return "`\(escKey)` = \($0.value.sqlLiteral)"
            }.joined(separator: " AND ")
            return "UPDATE `\(escDB)`.`\(escTable)` SET `\(escColumn)` = \(newValue.sqlLiteral) WHERE \(whereClause);"

        case .insert:
            // For insert, primaryKeyValues contains all column values for the new row
            let columns = primaryKeyValues.keys.sorted().map {
                let escCol = $0.replacingOccurrences(of: "`", with: "``")
                return "`\(escCol)`"
            }.joined(separator: ", ")
            let values = primaryKeyValues.keys.sorted().map { primaryKeyValues[$0]!.sqlLiteral }.joined(separator: ", ")
            return "INSERT INTO `\(escDB)`.`\(escTable)` (\(columns)) VALUES (\(values));"

        case .delete:
            guard !primaryKeyValues.isEmpty else {
                return "-- ERROR: Cannot generate DELETE without primary key columns (would delete ALL rows)"
            }
            let whereClause = primaryKeyValues.map {
                let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
                return "`\(escKey)` = \($0.value.sqlLiteral)"
            }.joined(separator: " AND ")
            return "DELETE FROM `\(escDB)`.`\(escTable)` WHERE \(whereClause);"
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
        changes.map { $0.toSQL() }
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
