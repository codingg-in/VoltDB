import SwiftUI
import AppKit

struct DataGridView: NSViewRepresentable {
    var columns: [QueryResult.ColumnHeader]
    var rows: [[QueryResult.CellValue]]
    var isEditable: Bool = false
    var onCellEdit: ((Int, Int, QueryResult.CellValue) -> Void)? = nil
    var tableName: String? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        
        context.coordinator.tableView = tableView
        
        scrollView.documentView = tableView
        
        tableView.doubleAction = #selector(Coordinator.doubleClickedCell)
        tableView.target = context.coordinator
        
        updateColumns(tableView, coordinator: context.coordinator)
        
        // Setup context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy Cell", action: #selector(Coordinator.copyCell), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Copy Row as CSV", action: #selector(Coordinator.copyRowCSV), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Row as JSON", action: #selector(Coordinator.copyRowJSON), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Row as INSERT", action: #selector(Coordinator.copyRowInsert), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Copy All as CSV (with Headers)", action: #selector(Coordinator.copyAllCSV), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy All as JSON", action: #selector(Coordinator.copyAllJSON), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy All as INSERT", action: #selector(Coordinator.copyAllInsert), keyEquivalent: ""))
        
        // Connect menu actions to coordinator
        for item in menu.items {
            item.target = context.coordinator
        }
        
        tableView.menu = menu
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        
        context.coordinator.parent = self
        context.coordinator.sortedRows = rows
        
        updateColumns(tableView, coordinator: context.coordinator)
        tableView.reloadData()
    }
    
    private func updateColumns(_ tableView: NSTableView, coordinator: Coordinator) {
        let existingCols = tableView.tableColumns
        for col in existingCols {
            tableView.removeTableColumn(col)
        }
        
        for (index, col) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = col.name
            column.isEditable = isEditable
            
            // Calculate proportional column width based on title & sample data
            let titleWidth = CGFloat(max(col.name.count * 9 + 28, 65))
            var maxContentLength = 0
            for row in rows.prefix(50) {
                if index < row.count {
                    let str = row[index].description
                    if str.count > maxContentLength { maxContentLength = str.count }
                }
            }
            let contentWidth = CGFloat(maxContentLength * 8 + 24)
            let idealWidth = min(max(titleWidth, contentWidth), 350)
            
            column.width = idealWidth
            column.minWidth = 45
            column.maxWidth = 600
            
            let sortDescriptor = NSSortDescriptor(key: String(index), ascending: true)
            column.sortDescriptorPrototype = sortDescriptor
            
            tableView.addTableColumn(column)
        }
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: DataGridView
        var sortedRows: [[QueryResult.CellValue]] = []
        weak var tableView: NSTableView?
        
        init(_ parent: DataGridView) {
            self.parent = parent
            self.sortedRows = parent.rows
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return sortedRows.count
        }
        
        @objc func doubleClickedCell(_ sender: NSTableView) {
            guard parent.isEditable else { return }
            let row = sender.clickedRow
            let col = sender.clickedColumn
            if row >= 0 && col >= 0 {
                sender.editColumn(col, row: row, with: nil, select: true)
            }
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn = tableColumn,
                  let colIndex = Int(tableColumn.identifier.rawValue),
                  colIndex < parent.columns.count,
                  row < sortedRows.count,
                  colIndex < sortedRows[row].count else { return nil }
            
            let cellValue = sortedRows[row][colIndex]
            
            let identifier = NSUserInterfaceItemIdentifier("Cell")
            var textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            
            if textField == nil {
                textField = NSTextField()
                textField?.identifier = identifier
                textField?.isBordered = false
                textField?.drawsBackground = false
                textField?.backgroundColor = .clear
                textField?.delegate = self
                textField?.focusRingType = .none
                textField?.cell?.wraps = false
                textField?.cell?.isScrollable = true
            }
            
            textField?.isEditable = parent.isEditable
            textField?.isSelectable = true
            
            if cellValue.isNull {
                textField?.stringValue = "NULL"
                textField?.textColor = .secondaryLabelColor
                textField?.font = NSFontManager.shared.convert(.systemFont(ofSize: NSFont.systemFontSize), toHaveTrait: .italicFontMask)
            } else {
                textField?.stringValue = cellValue.description
                textField?.textColor = .labelColor
                textField?.font = .systemFont(ofSize: NSFont.systemFontSize)
            }
            
            textField?.tag = (row << 16) | colIndex
            
            return textField
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField, parent.isEditable else { return }
            let row = textField.tag >> 16
            let colIndex = textField.tag & 0xFFFF
            
            let newValueStr = textField.stringValue
            let newCellValue: QueryResult.CellValue
            if newValueStr.uppercased() == "NULL" {
                newCellValue = .null
            } else if let intVal = Int64(newValueStr) {
                newCellValue = .int(intVal)
            } else if let dblVal = Double(newValueStr), newValueStr.contains(".") {
                newCellValue = .double(dblVal)
            } else {
                newCellValue = .string(newValueStr)
            }
            
            if row < sortedRows.count && colIndex < sortedRows[row].count {
                sortedRows[row][colIndex] = newCellValue
            }
            
            parent.onCellEdit?(row, colIndex, newCellValue)
        }
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sortDescriptor = tableView.sortDescriptors.first,
                  let key = sortDescriptor.key,
                  let colIndex = Int(key) else { return }
            
            let ascending = sortDescriptor.ascending
            
            sortedRows.sort { row1, row2 in
                let val1 = row1[colIndex].description
                let val2 = row2[colIndex].description
                return ascending ? val1 < val2 : val1 > val2
            }
            
            tableView.reloadData()
        }
        
        // MARK: - Row Selection Helper
        
        private func getTargetRows() -> [[QueryResult.CellValue]] {
            guard let tableView = tableView else { return [] }
            let clicked = tableView.clickedRow
            
            if clicked >= 0 && !tableView.selectedRowIndexes.contains(clicked) {
                if clicked < sortedRows.count {
                    return [sortedRows[clicked]]
                }
            } else if !tableView.selectedRowIndexes.isEmpty {
                return tableView.selectedRowIndexes.compactMap { idx in
                    idx < sortedRows.count ? sortedRows[idx] : nil
                }
            } else if clicked >= 0 && clicked < sortedRows.count {
                return [sortedRows[clicked]]
            } else if tableView.selectedRow >= 0 && tableView.selectedRow < sortedRows.count {
                return [sortedRows[tableView.selectedRow]]
            }
            return []
        }
        
        // MARK: - Copy Actions
        
        @objc func copyCell() {
            guard let tableView = tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            let col = tableView.clickedColumn >= 0 ? tableView.clickedColumn : tableView.selectedColumn
            guard row >= 0, row < sortedRows.count, col >= 0, col < sortedRows[row].count else { return }
            
            let val = sortedRows[row][col]
            let text = val.isNull ? "NULL" : val.description
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        
        @objc func copyRowCSV() {
            let rows = getTargetRows()
            guard !rows.isEmpty else { return }
            let cols = parent.columns.map { $0.name }
            let csv = rows.count == 1
                ? QueryGenerator.copyRowAsCSV(columns: cols, row: rows[0])
                : QueryGenerator.copyRowsAsCSV(columns: cols, rows: rows, includeHeader: true)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(csv, forType: .string)
        }
        
        @objc func copyRowJSON() {
            let rows = getTargetRows()
            guard !rows.isEmpty else { return }
            let cols = parent.columns.map { $0.name }
            let json = rows.count == 1
                ? QueryGenerator.copyRowAsJSON(columns: cols, row: rows[0])
                : QueryGenerator.copyRowsAsJSON(columns: cols, rows: rows)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(json, forType: .string)
        }
        
        @objc func copyRowInsert() {
            let rows = getTargetRows()
            guard !rows.isEmpty else { return }
            let cols = parent.columns.map { $0.name }
            let table = parent.tableName ?? "result_table"
            let sql = rows.count == 1
                ? QueryGenerator.copyRowAsInsert(table: table, database: "", columns: cols, row: rows[0])
                : QueryGenerator.copyRowsAsInsert(table: table, database: "", columns: cols, rows: rows)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(sql, forType: .string)
        }
        
        @objc func copyAllCSV() {
            guard !sortedRows.isEmpty else { return }
            let cols = parent.columns.map { $0.name }
            let csv = QueryGenerator.copyRowsAsCSV(columns: cols, rows: sortedRows, includeHeader: true)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(csv, forType: .string)
        }
        
        @objc func copyAllJSON() {
            guard !sortedRows.isEmpty else { return }
            let cols = parent.columns.map { $0.name }
            let json = QueryGenerator.copyRowsAsJSON(columns: cols, rows: sortedRows)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(json, forType: .string)
        }
        
        @objc func copyAllInsert() {
            guard !sortedRows.isEmpty else { return }
            let cols = parent.columns.map { $0.name }
            let table = parent.tableName ?? "result_table"
            let sql = QueryGenerator.copyRowsAsInsert(table: table, database: "", columns: cols, rows: sortedRows)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(sql, forType: .string)
        }
    }
}
