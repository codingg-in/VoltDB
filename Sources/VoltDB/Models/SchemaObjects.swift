import Foundation

/// Represents a database on the server.
struct DatabaseInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

/// Represents a table or view in a database.
struct TableInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: TableType
    let rowCount: Int?
    let database: String

    enum TableType: String, Codable, Hashable {
        case table = "BASE TABLE"
        case view = "VIEW"
        case systemView = "SYSTEM VIEW"

        var icon: String {
            switch self {
            case .table: return "tablecells"
            case .view: return "eye"
            case .systemView: return "eye.trianglebadge.exclamationmark"
            }
        }

        var displayName: String {
            switch self {
            case .table: return "Table"
            case .view: return "View"
            case .systemView: return "System View"
            }
        }
    }
}

/// Represents a column in a table.
struct ColumnInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let isNullable: Bool
    let defaultValue: String?
    let key: ColumnKey
    let extra: String
    let ordinalPosition: Int
    let characterMaxLength: Int?
    let numericPrecision: Int?

    enum ColumnKey: String, Codable, Hashable {
        case primary = "PRI"
        case unique = "UNI"
        case multiple = "MUL"
        case none = ""

        var icon: String {
            switch self {
            case .primary: return "key.fill"
            case .unique: return "key"
            case .multiple: return "link"
            case .none: return ""
            }
        }

        var displayName: String {
            switch self {
            case .primary: return "PRIMARY"
            case .unique: return "UNIQUE"
            case .multiple: return "INDEX"
            case .none: return ""
            }
        }
    }

    /// Full type display string (e.g., "varchar(255)").
    var fullType: String {
        type
    }

    /// Whether this column is a primary key.
    var isPrimaryKey: Bool {
        key == .primary
    }
}

/// Represents an index on a table.
struct IndexInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let columns: [String]
    let isUnique: Bool
    let type: String
}

/// Represents a foreign key constraint.
struct ForeignKeyInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let column: String
    let referencedTable: String
    let referencedColumn: String
    let onUpdate: String
    let onDelete: String
}

/// A node in the sidebar schema tree.
enum SchemaTreeNode: Identifiable, Hashable {
    case database(DatabaseInfo)
    case tableGroup(database: String, type: TableInfo.TableType)
    case table(TableInfo)

    var id: String {
        switch self {
        case .database(let db): return "db:\(db.name)"
        case .tableGroup(let db, let type): return "group:\(db):\(type.rawValue)"
        case .table(let table): return "table:\(table.database).\(table.name)"
        }
    }

    var name: String {
        switch self {
        case .database(let db): return db.name
        case .tableGroup(_, let type):
            switch type {
            case .table: return "Tables"
            case .view: return "Views"
            case .systemView: return "System Views"
            }
        case .table(let table): return table.name
        }
    }

    var icon: String {
        switch self {
        case .database: return "cylinder"
        case .tableGroup(_, let type):
            switch type {
            case .table: return "tablecells"
            case .view, .systemView: return "eye"
            }
        case .table(let table): return table.type.icon
        }
    }
}
