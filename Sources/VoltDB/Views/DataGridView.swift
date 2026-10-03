import SwiftUI
import AppKit

struct DataGridView: NSViewRepresentable {
    var columns: [QueryResult.ColumnHeader]
    var rows: [[QueryResult.CellValue]]
    var isEditable: Bool = false
    var stagedChanges: [CellChange] = []
    var insertedRowIndices: Set<Int> = []
    var onCellEdit: ((Int, Int, QueryResult.CellValue) -> Void)? = nil
    var onRowSelect: ((Int?) -> Void)? = nil
    var tableName: String? = nil
    var resultId: UUID? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        let tableView = EditableDataGridView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.onBlankAreaClicked = { [weak coordinator = context.coordinator] in
            guard let coord = coordinator, coord.parent.isEditable else { return }
            NotificationCenter.default.post(name: .addNewRow, object: nil)
        }
        
        context.coordinator.tableView = tableView
        
        scrollView.documentView = tableView
        
        tableView.doubleAction = #selector(Coordinator.doubleClickedCell)
        tableView.target = context.coordinator
        
        // Setup context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "View in Details Panel", action: #selector(Coordinator.openDetailsPanel), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
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
        
        context.coordinator.lastResultId = resultId
        context.coordinator.lastColumns = columns
        context.coordinator.lastRowCount = rows.count
        context.coordinator.lastStagedCount = stagedChanges.count
        context.coordinator.lastInsertedCount = insertedRowIndices.count
        
        updateColumns(tableView, coordinator: context.coordinator)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        
        let coordinator = context.coordinator
        coordinator.parent = self
        
        let isNewResult = resultId != nil && coordinator.lastResultId != resultId
        let columnsChanged = coordinator.lastColumns != columns
        let rowsCountChanged = coordinator.lastRowCount != rows.count
        let stagedChanged = coordinator.lastStagedCount != stagedChanges.count
        let insertedChanged = coordinator.lastInsertedCount != insertedRowIndices.count
        
        if isNewResult || columnsChanged || rowsCountChanged || stagedChanged || insertedChanged {
            coordinator.lastResultId = resultId
            coordinator.lastColumns = columns
            coordinator.lastRowCount = rows.count
            coordinator.lastStagedCount = stagedChanges.count
            coordinator.lastInsertedCount = insertedRowIndices.count
            coordinator.sortedRows = rows
            
            updateColumns(tableView, coordinator: coordinator)
            tableView.reloadData()
        }
    }
    
    private func updateColumns(_ tableView: NSTableView, coordinator: Coordinator) {
        let existingCols = tableView.tableColumns
        let needsRebuild = existingCols.count != columns.count || zip(existingCols, columns).contains {
            $0.0.identifier.rawValue != String($0.1.index) || $0.0.title != $0.1.name
        }
        
        guard needsRebuild else { return }
        
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
        var lastResultId: UUID? = nil
        var lastColumns: [QueryResult.ColumnHeader] = []
        var lastRowCount: Int = -1
        var lastStagedCount: Int = -1
        var lastInsertedCount: Int = -1
        
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
            let colName = parent.columns[colIndex].name
            
            // Check if this cell has staged changes
            let isModifiedCell = parent.stagedChanges.contains {
                $0.rowIndex == row && $0.column == colName
            }
            
            let cellViewId = NSUserInterfaceItemIdentifier("CustomHighlightCellView")
            var containerView = tableView.makeView(withIdentifier: cellViewId, owner: self) as? CustomHighlightCellView
            var textField: NSTextField?
            
            if containerView == nil {
                containerView = CustomHighlightCellView()
                containerView?.identifier = cellViewId
                
                let tf = NSTextField()
                tf.isBordered = false
                tf.drawsBackground = false
                tf.backgroundColor = .clear
                tf.delegate = self
                tf.focusRingType = .none
                tf.cell?.wraps = false
                tf.cell?.isScrollable = true
                tf.translatesAutoresizingMaskIntoConstraints = false
                containerView?.addSubview(tf)
                containerView?.textField = tf
                
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: containerView!.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: containerView!.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: containerView!.centerYAnchor)
                ])
                textField = tf
            } else {
                textField = containerView?.textField
            }
            
            textField?.isEditable = parent.isEditable
            textField?.isSelectable = true
            
            containerView?.isModifiedCell = isModifiedCell
            
            let rawStr = cellValue.description
            if cellValue.isNull {
                textField?.stringValue = "NULL"
                textField?.textColor = NSColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1.0)
                textField?.font = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
            } else if rawStr.uppercased() == "DEFAULT" {
                textField?.stringValue = "DEFAULT"
                textField?.textColor = NSColor(red: 0.15, green: 0.65, blue: 1.0, alpha: 1.0)
                textField?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            } else {
                textField?.stringValue = rawStr
                textField?.textColor = .labelColor
                textField?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            }
            
            textField?.tag = (row << 16) | colIndex
            
            return containerView
        }
        
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("CustomRowView")
            var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? CustomHighlightRowView
            if rowView == nil {
                rowView = CustomHighlightRowView()
                rowView?.identifier = identifier
            }
            rowView?.isInsertedRow = parent.insertedRowIndices.contains(row)
            return rowView
        }
        
        var editingInitialString: String? = nil
        var editingRow: Int = -1
        var editingCol: Int = -1
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            editingInitialString = textField.stringValue
            editingRow = textField.tag >> 16
            editingCol = textField.tag & 0xFFFF
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField, parent.isEditable else { return }
            let row = textField.tag >> 16
            let colIndex = textField.tag & 0xFFFF
            let newValueStr = textField.stringValue
            
            let existingValue: QueryResult.CellValue?
            if row < sortedRows.count && colIndex < sortedRows[row].count {
                existingValue = sortedRows[row][colIndex]
            } else {
                existingValue = nil
            }
            
            // Clean up editing tracking
            let initial = editingInitialString
            let prevRow = editingRow
            let prevCol = editingCol
            editingInitialString = nil
            editingRow = -1
            editingCol = -1
            
            // 1. If editing was explicitly tracked and text didn't change: no-op
            if let initial = initial, initial == newValueStr, row == prevRow, colIndex == prevCol {
                return
            }
            
            // 2. Direct comparison with existing cell value:
            // Prevents spurious edits when user double-clicks without typing
            if let existing = existingValue {
                // If cell was NULL and remains "NULL" or empty: no-op
                if existing.isNull && (newValueStr.uppercased() == "NULL" || newValueStr.isEmpty) {
                    return
                }
                // If cell was DEFAULT and remains "DEFAULT": no-op
                if existing.description.uppercased() == "DEFAULT" && newValueStr.uppercased() == "DEFAULT" {
                    return
                }
                // If textual value is identical to existing: no-op
                if !existing.isNull && existing.description == newValueStr {
                    return
                }
            }
            
            // Determine the new CellValue, respecting the existing type if possible
            let newCellValue: QueryResult.CellValue
            if newValueStr.uppercased() == "NULL" {
                newCellValue = .null
            } else if let existing = existingValue {
                switch existing {
                case .int:
                    if let intVal = Int64(newValueStr) {
                        newCellValue = .int(intVal)
                    } else {
                        newCellValue = .string(newValueStr)
                    }
                case .double:
                    if let dblVal = Double(newValueStr) {
                        newCellValue = .double(dblVal)
                    } else {
                        newCellValue = .string(newValueStr)
                    }
                case .string:
                    newCellValue = .string(newValueStr)
                default:
                    if let intVal = Int64(newValueStr) {
                        newCellValue = .int(intVal)
                    } else if let dblVal = Double(newValueStr), newValueStr.contains(".") {
                        newCellValue = .double(dblVal)
                    } else {
                        newCellValue = .string(newValueStr)
                    }
                }
            } else if let intVal = Int64(newValueStr) {
                newCellValue = .int(intVal)
            } else if let dblVal = Double(newValueStr), newValueStr.contains(".") {
                newCellValue = .double(dblVal)
            } else {
                newCellValue = .string(newValueStr)
            }
            
            // Final equality check against existing cell value
            if let existing = existingValue, newCellValue == existing {
                return
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
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = tableView else { return }
            let selectedRow = tableView.selectedRow
            parent.onRowSelect?(selectedRow >= 0 ? selectedRow : nil)
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
        
        // MARK: - Actions
        
        @objc func openDetailsPanel() {
            guard let tableView = tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            if row >= 0 {
                parent.onRowSelect?(row)
                NotificationCenter.default.post(name: .toggleRightPanel, object: nil)
            }
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

// MARK: - Custom Highlight Views for Rows and Cells

final class CustomHighlightRowView: NSTableRowView {
    var isInsertedRow: Bool = false {
        didSet {
            wantsLayer = true
            if isInsertedRow {
                layer?.backgroundColor = NSColor(red: 0.12, green: 0.26, blue: 0.14, alpha: 0.9).cgColor
            } else {
                layer?.backgroundColor = nil
            }
            needsDisplay = true
        }
    }
    
    override func drawBackground(in dirtyRect: NSRect) {
        if isInsertedRow {
            // Olive/Green row highlight for newly inserted rows
            NSColor(red: 0.12, green: 0.26, blue: 0.14, alpha: 0.9).setFill()
            bounds.fill()
        } else {
            super.drawBackground(in: dirtyRect)
        }
    }
}

final class CustomHighlightCellView: NSTableCellView {
    var isModifiedCell: Bool = false {
        didSet {
            wantsLayer = true
            if isModifiedCell {
                layer?.backgroundColor = NSColor(red: 0.42, green: 0.35, blue: 0.12, alpha: 0.95).cgColor
            } else {
                layer?.backgroundColor = nil
            }
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isModifiedCell {
            // Warm Mustard / Gold highlight for modified cell
            NSColor(red: 0.42, green: 0.35, blue: 0.12, alpha: 0.95).setFill()
            bounds.fill()
        }
        super.draw(dirtyRect)
    }
}

final class EditableDataGridView: NSTableView {
    var onBlankAreaClicked: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRowIndex = self.row(at: point)
        if clickedRowIndex == -1 && point.y >= 0 && event.clickCount == 2 {
            // Double-clicked on blank row / empty area in table!
            onBlankAreaClicked?()
            return
        }
        super.mouseDown(with: event)
    }
}



