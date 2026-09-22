import Foundation

/// Represents the result of executing a SQL query.
struct QueryResult: Identifiable {
    let id = UUID()
    let columns: [ColumnHeader]
    let rows: [[CellValue]]
    let affectedRows: Int
    let executionTime: TimeInterval
    let error: String?
    let queryType: QueryType

    /// A single column header in the result set.
    struct ColumnHeader: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let type: String
        let index: Int
    }

    /// Represents a cell value that may be NULL.
    enum CellValue: Hashable, CustomStringConvertible {
        case string(String)
        case int(Int64)
        case double(Double)
        case data(Data)
        case null

        var description: String {
            switch self {
            case .string(let s): return s
            case .int(let i): return String(i)
            case .double(let d): return String(d)
            case .data(let d): return "<\(d.count) bytes>"
            case .null: return "NULL"
            }
        }

        var stringValue: String? {
            switch self {
            case .null: return nil
            default: return description
            }
        }

        var isNull: Bool {
            if case .null = self { return true }
            return false
        }

        /// Returns an SQL-safe literal representation.
        var sqlLiteral: String {
            switch self {
            case .string(let s):
                let escaped = s
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "''")
                    .replacingOccurrences(of: "\0", with: "\\0")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\u{1A}", with: "\\Z")
                return "'\(escaped)'"
            case .int(let i): return String(i)
            case .double(let d): return String(d)
            case .data: return "'<binary>'"
            case .null: return "NULL"
            }
        }
    }

    /// The type of SQL query that was executed.
    enum QueryType {
        case select
        case insert
        case update
        case delete
        case ddl
        case other

        init(from sql: String) {
            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("SHOW") || trimmed.hasPrefix("DESCRIBE") || trimmed.hasPrefix("EXPLAIN") {
                self = .select
            } else if trimmed.hasPrefix("INSERT") {
                self = .insert
            } else if trimmed.hasPrefix("UPDATE") {
                self = .update
            } else if trimmed.hasPrefix("DELETE") {
                self = .delete
            } else if trimmed.hasPrefix("CREATE") || trimmed.hasPrefix("ALTER") || trimmed.hasPrefix("DROP") {
                self = .ddl
            } else {
                self = .other
            }
        }
    }

    /// Whether this result has tabular data to display.
    var hasRows: Bool {
        !columns.isEmpty && !rows.isEmpty
    }

    /// Whether this result represents an error.
    var isError: Bool {
        error != nil
    }

    /// Empty result with just a message.
    static func message(_ text: String, time: TimeInterval = 0) -> QueryResult {
        QueryResult(columns: [], rows: [], affectedRows: 0, executionTime: time, error: nil, queryType: .other)
    }

    /// Error result.
    static func error(_ message: String) -> QueryResult {
        QueryResult(columns: [], rows: [], affectedRows: 0, executionTime: 0, error: message, queryType: .other)
    }
}
