import SwiftUI

struct SidebarTreeNode: View {
    @Environment(TabState.self) private var tabState
    @Environment(SchemaState.self) private var schemaState
    
    let table: TableInfo
    @State private var isHovering = false
    
    init(table: TableInfo) {
        self.table = table
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: table.type.icon)
                .font(.system(size: 11))
                .foregroundColor(table.type == .table ? AppTheme.accentLight : Color.yellow)
            Text(table.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isHovering ? AppTheme.backgroundHover : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            tabState.addTableViewTab(database: table.database, table: table.name)
        }
        .contextMenu {
            Button("View Data") {
                tabState.addTableViewTab(database: table.database, table: table.name)
            }
            
            Button("New Query") {
                // Assuming addNewQueryTab can take a pre-filled query, or just passing db
                tabState.addNewQueryTab(database: table.database)
            }
            
            Divider()
            
            Button("Copy Name") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(table.name, forType: .string)
            }
            
            Button("Copy Qualified Name") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("\(table.database).\(table.name)", forType: .string)
            }
            
            Divider()
            
            Button("Refresh") {
                Task {
                    await schemaState.loadTables(for: table.database)
                }
            }
        }
    }
}
