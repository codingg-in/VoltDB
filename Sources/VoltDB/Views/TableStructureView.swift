import SwiftUI

/// Displays the structure of a table: columns, indexes, and foreign keys.
struct TableStructureView: View {
    @Environment(AppState.self) private var appState
    let database: String
    let tableName: String

    @State private var columns: [ColumnInfo] = []
    @State private var indexes: [IndexInfo] = []
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedSection: StructureSection = .columns

    enum StructureSection: String, CaseIterable {
        case columns = "Columns"
        case indexes = "Indexes"
        case foreignKeys = "Foreign Keys"

        var icon: String {
            switch self {
            case .columns: return "list.bullet.rectangle"
            case .indexes: return "arrow.up.arrow.down"
            case .foreignKeys: return "link"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(StructureSection.allCases, id: \.self) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading structure...")
                    .font(.caption)
                Spacer()
            } else if let error {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                switch selectedSection {
                case .columns:
                    columnsTable
                case .indexes:
                    indexesTable
                case .foreignKeys:
                    foreignKeysTable
                }
            }
        }
        .background(AppTheme.backgroundPrimary)
        .task {
            await loadStructure()
        }
    }

    // MARK: - Columns Table

    private var columnsTable: some View {
        Table(columns) {
            TableColumn("") { col in
                if col.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption2)
                } else if col.key == .unique {
                    Image(systemName: "key")
                        .foregroundStyle(.blue)
                        .font(.caption2)
                } else if col.key == .multiple {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                }
            }
            .width(20)

            TableColumn("Name") { col in
                Text(col.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(col.isPrimaryKey ? .semibold : .regular)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Type") { col in
                Text(col.fullType)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Nullable") { col in
                Text(col.isNullable ? "YES" : "NO")
                    .font(.caption)
                    .foregroundStyle(col.isNullable ? .secondary : .primary)
            }
            .width(60)

            TableColumn("Default") { col in
                Text(col.defaultValue ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Key") { col in
                Text(col.key.displayName)
                    .font(.caption)
                    .foregroundStyle(col.isPrimaryKey ? .yellow : .secondary)
            }
            .width(70)

            TableColumn("Extra") { col in
                Text(col.extra.isEmpty ? "—" : col.extra)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
        }
    }

    // MARK: - Indexes Table

    private var indexesTable: some View {
        Group {
            if indexes.isEmpty {
                emptyState(title: "No Indexes", icon: "arrow.up.arrow.down")
            } else {
                Table(indexes) {
                    TableColumn("Name") { idx in
                        Text(idx.name)
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Columns") { idx in
                        Text(idx.columns.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Unique") { idx in
                        Image(systemName: idx.isUnique ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(idx.isUnique ? .green : .secondary)
                            .font(.caption)
                    }
                    .width(60)

                    TableColumn("Type") { idx in
                        Text(idx.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(80)
                }
            }
        }
    }

    // MARK: - Foreign Keys Table

    private var foreignKeysTable: some View {
        Group {
            if foreignKeys.isEmpty {
                emptyState(title: "No Foreign Keys", icon: "link")
            } else {
                Table(foreignKeys) {
                    TableColumn("Name") { fk in
                        Text(fk.name)
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Column") { fk in
                        Text(fk.column)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 100, ideal: 140)

                    TableColumn("Referenced Table") { fk in
                        Text(fk.referencedTable)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                    .width(min: 100, ideal: 160)

                    TableColumn("Referenced Column") { fk in
                        Text(fk.referencedColumn)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 100, ideal: 140)

                    TableColumn("On Update") { fk in
                        Text(fk.onUpdate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(80)

                    TableColumn("On Delete") { fk in
                        Text(fk.onDelete)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(80)
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load Data

    private func loadStructure() async {
        isLoading = true
        error = nil

        do {
            async let cols = appState.dbManager.getColumns(database: database, table: tableName)
            async let idxs = appState.dbManager.getIndexes(database: database, table: tableName)
            async let fks = appState.dbManager.getForeignKeys(database: database, table: tableName)

            columns = try await cols
            indexes = try await idxs
            foreignKeys = try await fks
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
