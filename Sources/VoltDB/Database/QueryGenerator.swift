import Foundation

struct QueryGenerator {
    
    static func formatCSVValue(_ val: QueryResult.CellValue) -> String {
        switch val {
        case .null:
            return ""
        case .string(let s):
            if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
                return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return s
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .data(let data):
            return data.base64EncodedString()
        }
    }
    
    static func generateInsertSQL(table: String, database: String = "", columns: [String], values: [QueryResult.CellValue]) -> String {
        let escDB = database.replacingOccurrences(of: "`", with: "``")
        let escTable = table.replacingOccurrences(of: "`", with: "``")
        let cols = columns.map { "`\($0.replacingOccurrences(of: "`", with: "``"))`" }.joined(separator: ", ")
        let vals = values.map { $0.sqlLiteral }.joined(separator: ", ")
        let targetTable = database.isEmpty ? "`\(escTable)`" : "`\(escDB)`.`\(escTable)`"
        return "INSERT INTO \(targetTable) (\(cols)) VALUES (\(vals));"
    }
    
    static func generateBulkInsertSQL(table: String, database: String = "", columns: [String], rows: [[QueryResult.CellValue]]) -> String {
        guard !rows.isEmpty else { return "" }
        let escDB = database.replacingOccurrences(of: "`", with: "``")
        let escTable = table.replacingOccurrences(of: "`", with: "``")
        let cols = columns.map { "`\($0.replacingOccurrences(of: "`", with: "``"))`" }.joined(separator: ", ")
        let targetTable = database.isEmpty ? "`\(escTable)`" : "`\(escDB)`.`\(escTable)`"
        let rowLiterals = rows.map { row in
            let vals = row.map { $0.sqlLiteral }.joined(separator: ", ")
            return "  (\(vals))"
        }.joined(separator: ",\n")
        return "INSERT INTO \(targetTable) (\(cols)) VALUES\n\(rowLiterals);"
    }
    
    static func generateUpdateSQL(table: String, database: String = "", column: String, newValue: QueryResult.CellValue, primaryKeys: [String: QueryResult.CellValue]) -> String {
        guard !primaryKeys.isEmpty else {
            return "-- ERROR: Cannot generate UPDATE without primary key columns (would affect ALL rows)"
        }
        let escDB = database.replacingOccurrences(of: "`", with: "``")
        let escTable = table.replacingOccurrences(of: "`", with: "``")
        let escColumn = column.replacingOccurrences(of: "`", with: "``")
        let whereClause = primaryKeys.map {
            let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
            return "`\(escKey)` = \($0.value.sqlLiteral)"
        }.joined(separator: " AND ")
        let targetTable = database.isEmpty ? "`\(escTable)`" : "`\(escDB)`.`\(escTable)`"
        return "UPDATE \(targetTable) SET `\(escColumn)` = \(newValue.sqlLiteral) WHERE \(whereClause);"
    }
    
    static func generateDeleteSQL(table: String, database: String = "", primaryKeys: [String: QueryResult.CellValue]) -> String {
        guard !primaryKeys.isEmpty else {
            return "-- ERROR: Cannot generate DELETE without primary key columns (would delete ALL rows)"
        }
        let escDB = database.replacingOccurrences(of: "`", with: "``")
        let escTable = table.replacingOccurrences(of: "`", with: "``")
        let whereClause = primaryKeys.map {
            let escKey = $0.key.replacingOccurrences(of: "`", with: "``")
            return "`\(escKey)` = \($0.value.sqlLiteral)"
        }.joined(separator: " AND ")
        let targetTable = database.isEmpty ? "`\(escTable)`" : "`\(escDB)`.`\(escTable)`"
        return "DELETE FROM \(targetTable) WHERE \(whereClause);"
    }
    
    static func copyRowAsInsert(table: String, database: String = "", columns: [String], row: [QueryResult.CellValue]) -> String {
        let tbl = table.isEmpty ? "table_name" : table
        return generateInsertSQL(table: tbl, database: database, columns: columns, values: row)
    }
    
    static func copyRowsAsInsert(table: String, database: String = "", columns: [String], rows: [[QueryResult.CellValue]]) -> String {
        let tbl = table.isEmpty ? "table_name" : table
        return generateBulkInsertSQL(table: tbl, database: database, columns: columns, rows: rows)
    }
    
    static func copyRowAsCSV(columns: [String], row: [QueryResult.CellValue]) -> String {
        return row.map { formatCSVValue($0) }.joined(separator: ",")
    }
    
    static func copyRowsAsCSV(columns: [String], rows: [[QueryResult.CellValue]], includeHeader: Bool = true) -> String {
        var lines: [String] = []
        if includeHeader {
            let header = columns.map { col in
                if col.contains(",") || col.contains("\"") || col.contains("\n") {
                    return "\"\(col.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return col
            }.joined(separator: ",")
            lines.append(header)
        }
        for row in rows {
            lines.append(row.map { formatCSVValue($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
    
    static func copyRowAsJSON(columns: [String], row: [QueryResult.CellValue]) -> String {
        var dict: [String: Any] = [:]
        for (index, col) in columns.enumerated() {
            guard index < row.count else { continue }
            switch row[index] {
            case .string(let s): dict[col] = s
            case .int(let i): dict[col] = i
            case .double(let d): dict[col] = d
            case .null: dict[col] = NSNull()
            case .data(let data): dict[col] = data.base64EncodedString()
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }
    
    static func copyRowsAsJSON(columns: [String], rows: [[QueryResult.CellValue]]) -> String {
        var list: [[String: Any]] = []
        for row in rows {
            var dict: [String: Any] = [:]
            for (index, col) in columns.enumerated() {
                guard index < row.count else { continue }
                switch row[index] {
                case .string(let s): dict[col] = s
                case .int(let i): dict[col] = i
                case .double(let d): dict[col] = d
                case .null: dict[col] = NSNull()
                case .data(let data): dict[col] = data.base64EncodedString()
                }
            }
            list.append(dict)
        }
        if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }
}
