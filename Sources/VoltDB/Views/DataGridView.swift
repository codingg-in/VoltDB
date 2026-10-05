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
        tableView.allowsColumnSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        
        let headerView = EditableTableHeaderView()
        tableView.headerView = headerView
        
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
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(Coordinator.copySelection), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Copy Cell Value", action: #selector(Coordinator.copyCell), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy as JSON", action: #selector(Coordinator.copyRowJSON), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy as TSV", action: #selector(Coordinator.copyRowTSV), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy as CSV", action: #selector(Coordinator.copyRowCSV), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy as INSERT", action: #selector(Coordinator.copyRowInsert), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Select Entire Column", action: #selector(Coordinator.selectClickedColumn), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Select Entire Row", action: #selector(Coordinator.selectClickedRow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "View in Details Panel", action: #selector(Coordinator.openDetailsPanel), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        
        let copyAllCSVItem = NSMenuItem(title: "Copy All as CSV (with Headers)", action: #selector(Coordinator.copyAllCSV), keyEquivalent: "c")
        copyAllCSVItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(copyAllCSVItem)

        let copyAllJSONItem = NSMenuItem(title: "Copy All as JSON", action: #selector(Coordinator.copyAllJSON), keyEquivalent: "j")
        copyAllJSONItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(copyAllJSONItem)

        menu.addItem(NSMenuItem(title: "Copy All as INSERT", action: #selector(Coordinator.copyAllInsert), keyEquivalent: ""))
        
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
        coordinator.tableView = tableView
        if tableView.delegate !== coordinator { tableView.delegate = coordinator }
        if tableView.dataSource !== coordinator { tableView.dataSource = coordinator }
        if tableView.target !== coordinator { tableView.target = coordinator }
        
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
            coordinator.selectedCellRange = nil
            coordinator.dragAnchorCell = nil
            coordinator.selectionMode = .cell
            
            updateColumns(tableView, coordinator: coordinator)
            tableView.reloadData()
        }
    }
    
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let tableView = scrollView.documentView as? NSTableView {
            tableView.window?.undoManager?.removeAllActions()
        }
    }
    
    private func updateColumns(_ tableView: NSTableView, coordinator: Coordinator) {
        let existingCols = tableView.tableColumns
        let expectedCount = columns.count + 1
        let needsRebuild = existingCols.count != expectedCount || (existingCols.first?.identifier.rawValue != "_row_num_")
        
        guard needsRebuild else { return }
        
        for col in existingCols {
            tableView.removeTableColumn(col)
        }
        
        // 1. Row number column (#)
        let rowNumCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("_row_num_"))
        rowNumCol.title = "#"
        rowNumCol.isEditable = false
        let digits = max(String(rows.count).count, 2)
        let numWidth = CGFloat(max(digits * 7 + 14, 28))
        rowNumCol.width = numWidth
        rowNumCol.minWidth = numWidth
        rowNumCol.maxWidth = numWidth
        rowNumCol.resizingMask = []
        rowNumCol.headerCell.alignment = .center
        tableView.addTableColumn(rowNumCol)
        
        // 2. Data columns
        for (index, col) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = col.name
            column.isEditable = isEditable
            
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
    
    enum SelectionMode {
        case cell
        case row
        case column
    }
    
    struct CellRange: Equatable {
        var minRow: Int
        var maxRow: Int
        var minCol: Int
        var maxCol: Int
        
        init(row1: Int, col1: Int, row2: Int, col2: Int) {
            self.minRow = min(row1, row2)
            self.maxRow = max(row1, row2)
            self.minCol = min(col1, col2)
            self.maxCol = max(col1, col2)
        }
        
        var isSingleCell: Bool {
            return minRow == maxRow && minCol == maxCol
        }
        
        var count: Int {
            return (maxRow - minRow + 1) * (maxCol - minCol + 1)
        }
        
        func contains(row: Int, col: Int) -> Bool {
            return row >= minRow && row <= maxRow && col >= minCol && col <= maxCol
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
        
        // Selection tracking: supports 2D cell blocks across rows and columns
        var selectionMode: SelectionMode = .cell
        var selectedCellRange: CellRange? = nil
        var dragAnchorCell: (row: Int, column: Int)? = nil
        
        init(_ parent: DataGridView) {
            self.parent = parent
            self.sortedRows = parent.rows
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return sortedRows.count
        }
        
        @objc func doubleClickedCell(_ sender: NSTableView) {
            let row = sender.clickedRow
            let col = sender.clickedColumn
            guard row >= 0 && col >= 0, col < sender.tableColumns.count else { return }
            
            let colIdentifier = sender.tableColumns[col].identifier.rawValue
            guard colIdentifier != "_row_num_" else { return }
            
            (sender as? EditableDataGridView)?.editCell(row: row, column: col)
        }
        
        func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
            guard parent.isEditable else { return false }
            guard let tableColumn = tableColumn, tableColumn.identifier.rawValue != "_row_num_" else { return false }
            return true
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn = tableColumn else { return nil }
            
            // 1. Row number cell (#)
            if tableColumn.identifier.rawValue == "_row_num_" {
                let cellId = NSUserInterfaceItemIdentifier("RowNumberCellView")
                var numView = tableView.makeView(withIdentifier: cellId, owner: self) as? RowNumberCellView
                if numView == nil {
                    numView = RowNumberCellView()
                    numView?.identifier = cellId
                }
                numView?.rowNumber = row + 1
                return numView
            }
            
            // 2. Data cell
            guard let colIndex = Int(tableColumn.identifier.rawValue),
                  colIndex < parent.columns.count,
                  row < sortedRows.count,
                  colIndex < sortedRows[row].count else { return nil }
            
            let cellValue = sortedRows[row][colIndex]
            let colName = parent.columns[colIndex].name
            
            let isModifiedCell = parent.stagedChanges.contains {
                $0.rowIndex == row && $0.column == colName
            }
            
            let tableColIdx = tableView.column(withIdentifier: tableColumn.identifier)
            let isColSelected = (selectionMode == .column && tableColIdx >= 0 && tableView.selectedColumnIndexes.contains(tableColIdx))
            let isCellSelected = (selectionMode == .cell && selectedCellRange?.contains(row: row, col: colIndex) == true)
            let isSingle = (selectedCellRange?.isSingleCell == true)
            
            let cellViewId = NSUserInterfaceItemIdentifier("CustomHighlightCellView")
            var containerView = tableView.makeView(withIdentifier: cellViewId, owner: self) as? CustomHighlightCellView
            var textField: NSTextField?
            
            if containerView == nil {
                containerView = CustomHighlightCellView()
                containerView?.identifier = cellViewId
                
                let tf = GridCellTextField()
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
            containerView?.isColumnSelected = isColSelected
            containerView?.isCellSelected = isCellSelected
            containerView?.isSingleCell = isSingle
            
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
        
        func updateVisibleCellSelections() {
            guard let tableView = tableView else { return }
            let selectedCols = tableView.selectedColumnIndexes
            let range = selectedCellRange
            let isCellMode = (selectionMode == .cell)
            let isColMode = (selectionMode == .column)
            let isSingle = (range?.isSingleCell == true)
            
            tableView.enumerateAvailableRowViews { rowView, row in
                if let customRow = rowView as? CustomHighlightRowView {
                    let rowInCellRange = (isCellMode && range != nil && row >= range!.minRow && row <= range!.maxRow)
                    if customRow.isCellSelectionMode != rowInCellRange {
                        customRow.isCellSelectionMode = rowInCellRange
                    }
                }
                for tableCol in 0..<tableView.numberOfColumns {
                    let colId = tableView.tableColumns[tableCol].identifier.rawValue
                    guard let dataCol = Int(colId) else { continue }
                    if let cellView = tableView.view(atColumn: tableCol, row: row, makeIfNecessary: false) as? CustomHighlightCellView {
                        let isCol = (isColMode && selectedCols.contains(tableCol))
                        let isCell = (isCellMode && range?.contains(row: row, col: dataCol) == true)
                        if cellView.isColumnSelected != isCol || cellView.isCellSelected != isCell || cellView.isSingleCell != isSingle {
                            cellView.isColumnSelected = isCol
                            cellView.isCellSelected = isCell
                            cellView.isSingleCell = isSingle
                        }
                    }
                }
            }
            
            tableView.headerView?.needsDisplay = true
        }
        
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("CustomRowView")
            var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? CustomHighlightRowView
            if rowView == nil {
                rowView = CustomHighlightRowView()
                rowView?.identifier = identifier
            }
            rowView?.isInsertedRow = parent.insertedRowIndices.contains(row)
            let inCellRange = (selectionMode == .cell && selectedCellRange != nil && row >= selectedCellRange!.minRow && row <= selectedCellRange!.maxRow)
            rowView?.isCellSelectionMode = inCellRange
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
            guard let textField = obj.object as? NSTextField else { return }
            textField.undoManager?.removeAllActions()
            textField.window?.undoManager?.removeAllActions(withTarget: textField)
            if let editor = textField.currentEditor() {
                textField.window?.undoManager?.removeAllActions(withTarget: editor)
                editor.undoManager?.removeAllActions()
            }
            let row = textField.tag >> 16
            let colIndex = textField.tag & 0xFFFF
            let newValueStr = textField.stringValue
            
            textField.isEditable = parent.isEditable
            textField.isSelectable = true
            
            guard parent.isEditable else { return }
            
            let existingValue: QueryResult.CellValue?
            if row < sortedRows.count && colIndex < sortedRows[row].count {
                existingValue = sortedRows[row][colIndex]
            } else {
                existingValue = nil
            }
            
            let initial = editingInitialString
            let prevRow = editingRow
            let prevCol = editingCol
            editingInitialString = nil
            editingRow = -1
            editingCol = -1
            
            if let initial = initial, initial == newValueStr, row == prevRow, colIndex == prevCol {
                return
            }
            
            if let existing = existingValue {
                if existing.isNull && (newValueStr.uppercased() == "NULL" || newValueStr.isEmpty) {
                    return
                }
                if existing.description.uppercased() == "DEFAULT" && newValueStr.uppercased() == "DEFAULT" {
                    return
                }
                if !existing.isNull && existing.description == newValueStr {
                    return
                }
            }
            
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
            
            if let existing = existingValue, newCellValue == existing {
                return
            }
            
            if row < sortedRows.count && colIndex < sortedRows[row].count {
                sortedRows[row][colIndex] = newCellValue
            }
            
            parent.onCellEdit?(row, colIndex, newCellValue)
        }
        
        // MARK: - 3-State Column Sorting (Ascending -> Descending -> Remove Sorting)
        
        func cycleSort(for colIndex: Int) {
            guard let tableView = tableView, colIndex < parent.columns.count else { return }
            let key = String(colIndex)
            
            let currentDesc = tableView.sortDescriptors.first { $0.key == key }
            
            if let current = currentDesc {
                if current.ascending {
                    // State 1 (Ascending) -> State 2 (Descending)
                    let newDescriptor = NSSortDescriptor(key: key, ascending: false)
                    tableView.sortDescriptors = [newDescriptor]
                    sortRows(by: colIndex, ascending: false)
                } else {
                    // State 2 (Descending) -> State 3 (Remove Sorting, restore original order)
                    removeSorting()
                }
            } else {
                // State 0 (Unsorted) -> State 1 (Ascending)
                let newDescriptor = NSSortDescriptor(key: key, ascending: true)
                tableView.sortDescriptors = [newDescriptor]
                sortRows(by: colIndex, ascending: true)
            }
        }
        
        func sortRows(by colIndex: Int, ascending: Bool) {
            sortedRows.sort { row1, row2 in
                guard colIndex < row1.count && colIndex < row2.count else { return false }
                let val1 = row1[colIndex].description
                let val2 = row2[colIndex].description
                
                if let num1 = Double(val1), let num2 = Double(val2) {
                    return ascending ? num1 < num2 : num1 > num2
                }
                return ascending ? val1.localizedStandardCompare(val2) == .orderedAscending : val1.localizedStandardCompare(val2) == .orderedDescending
            }
            tableView?.reloadData()
            updateVisibleCellSelections()
        }
        
        func removeSorting() {
            guard let tableView = tableView else { return }
            tableView.sortDescriptors = []
            sortedRows = parent.rows
            tableView.reloadData()
            updateVisibleCellSelections()
        }
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let descriptor = tableView.sortDescriptors.first,
               let key = descriptor.key,
               let colIndex = Int(key) {
                sortRows(by: colIndex, ascending: descriptor.ascending)
            } else {
                removeSorting()
            }
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = tableView else { return }
            let selectedRow = tableView.selectedRow
            parent.onRowSelect?(selectedRow >= 0 ? selectedRow : nil)
            
            // Only update single cell location if user used Up/Down arrows in cell mode
            if selectionMode == .cell, let range = selectedCellRange, range.isSingleCell {
                if selectedRow >= 0 && selectedRow != range.minRow {
                    selectedCellRange = CellRange(row1: selectedRow, col1: range.minCol, row2: selectedRow, col2: range.minCol)
                }
            }
            updateVisibleCellSelections()
        }
        
        // MARK: - Row Selection Helper
        
        private func getTargetRows() -> [[QueryResult.CellValue]] {
            guard let tableView = tableView else { return [] }
            let clicked = tableView.clickedRow
            
            if !tableView.selectedRowIndexes.isEmpty {
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
        
        // MARK: - Smart Copy & Selection
        
        @objc func copy(_ sender: Any?) {
            copySelection()
        }
        
        @objc func copySelection() {
            guard let tableView = tableView else { return }
            let pb = NSPasteboard.general
            
            // Case 1: Cell Selection Mode (1 cell or 2D block of N cells)
            if selectionMode == .cell, let range = selectedCellRange {
                if range.isSingleCell {
                    let r = range.minRow
                    let c = range.minCol
                    if r < sortedRows.count && c < sortedRows[r].count {
                        let val = sortedRows[r][c]
                        let text = val.isNull ? "NULL" : val.description
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                        return
                    }
                } else {
                    // Block of cells: export as JSON
                    let colNames = (range.minCol...range.maxCol).compactMap { c in
                        c < parent.columns.count ? parent.columns[c].name : nil
                    }
                    var rowsData: [[QueryResult.CellValue]] = []
                    for r in range.minRow...range.maxRow {
                        guard r < sortedRows.count else { continue }
                        var cellVals: [QueryResult.CellValue] = []
                        for c in range.minCol...range.maxCol {
                            if c < sortedRows[r].count {
                                cellVals.append(sortedRows[r][c])
                            } else {
                                cellVals.append(.null)
                            }
                        }
                        rowsData.append(cellVals)
                    }
                    let jsonText: String
                    if rowsData.count == 1 {
                        jsonText = QueryGenerator.copyRowAsJSON(columns: colNames, row: rowsData[0])
                    } else {
                        jsonText = QueryGenerator.copyRowsAsJSON(columns: colNames, rows: rowsData)
                    }
                    pb.clearContents()
                    pb.setString(jsonText, forType: .string)
                    return
                }
            }
            
            // Case 2: Column Selection Mode
            if selectionMode == .column || (!tableView.selectedColumnIndexes.isEmpty && selectedCellRange == nil) {
                let selectedTableCols = tableView.selectedColumnIndexes
                let colPairs = selectedTableCols.compactMap { colIdx -> (title: String, dataIdx: Int)? in
                    guard colIdx < tableView.tableColumns.count else { return nil }
                    let col = tableView.tableColumns[colIdx]
                    guard let dataIdx = Int(col.identifier.rawValue), dataIdx < parent.columns.count else { return nil }
                    return (col.title, dataIdx)
                }
                if !colPairs.isEmpty {
                    let colNames = colPairs.map { $0.title }
                    let rowsToExport: [[QueryResult.CellValue]]
                    if !tableView.selectedRowIndexes.isEmpty && tableView.selectedRowIndexes.count < sortedRows.count {
                        rowsToExport = tableView.selectedRowIndexes.compactMap { idx in
                            idx < sortedRows.count ? sortedRows[idx] : nil
                        }
                    } else {
                        rowsToExport = sortedRows
                    }
                    
                    let filteredRows = rowsToExport.map { row in
                        colPairs.map { pair in
                            pair.dataIdx < row.count ? row[pair.dataIdx] : .null
                        }
                    }
                    
                    let jsonText: String
                    if filteredRows.count == 1 {
                        jsonText = QueryGenerator.copyRowAsJSON(columns: colNames, row: filteredRows[0])
                    } else {
                        jsonText = QueryGenerator.copyRowsAsJSON(columns: colNames, rows: filteredRows)
                    }
                    pb.clearContents()
                    pb.setString(jsonText, forType: .string)
                    return
                }
            }
            
            // Case 3: Row Selection Mode (or fallback) -> Default to JSON
            copyRowsJSON()
        }
        
        private func copyRowsTSV() {
            let targetRows = getTargetRows()
            guard !targetRows.isEmpty else { return }
            
            let lines = targetRows.map { row in
                row.map { $0.isNull ? "NULL" : $0.description }.joined(separator: "\t")
            }.joined(separator: "\n")
            
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(lines, forType: .string)
        }
        
        @objc func copyCell() {
            guard let tableView = tableView else { return }
            let row = selectedCellRange?.minRow ?? (tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
            let col = selectedCellRange?.minCol ?? (tableView.clickedColumn >= 0 ? tableView.clickedColumn : 0)
            guard row >= 0, row < sortedRows.count, col >= 0, col < sortedRows[row].count else { return }
            
            let val = sortedRows[row][col]
            let text = val.isNull ? "NULL" : val.description
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        
        @objc func copySelectedColumns() {
            selectionMode = .column
            copySelection()
        }
        
        @objc func copyColumnName() {
            guard let tableView = tableView else { return }
            let clicked = tableView.clickedColumn
            guard clicked >= 0 && clicked < tableView.tableColumns.count else { return }
            let col = tableView.tableColumns[clicked]
            guard col.identifier.rawValue != "_row_num_" else { return }
            let name = col.title
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(name, forType: .string)
        }
        
        @objc func selectAllColumns() {
            guard let tableView = tableView else { return }
            var dataColIndexes = IndexSet()
            for (idx, col) in tableView.tableColumns.enumerated() {
                if col.identifier.rawValue != "_row_num_" {
                    dataColIndexes.insert(idx)
                }
            }
            selectionMode = .column
            selectedCellRange = nil
            dragAnchorCell = nil
            tableView.deselectAll(nil)
            tableView.selectColumnIndexes(dataColIndexes, byExtendingSelection: false)
            updateVisibleCellSelections()
        }
        
        @objc func selectClickedColumn() {
            guard let tableView = tableView else { return }
            let clicked = tableView.clickedColumn
            guard clicked >= 0 && clicked < tableView.tableColumns.count else { return }
            guard tableView.tableColumns[clicked].identifier.rawValue != "_row_num_" else { return }
            
            selectionMode = .column
            selectedCellRange = nil
            dragAnchorCell = nil
            tableView.deselectAll(nil)
            tableView.selectColumnIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            updateVisibleCellSelections()
        }
        
        @objc func selectClickedRow() {
            guard let tableView = tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : (selectedCellRange?.minRow ?? tableView.selectedRow)
            guard row >= 0, row < sortedRows.count else { return }
            selectionMode = .row
            selectedCellRange = nil
            dragAnchorCell = nil
            tableView.selectColumnIndexes(IndexSet(), byExtendingSelection: false)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            updateVisibleCellSelections()
        }
        
        @objc func sortColumnAscending() {
            guard let tableView = tableView else { return }
            let clicked = tableView.clickedColumn
            guard clicked >= 0 && clicked < tableView.tableColumns.count else { return }
            let col = tableView.tableColumns[clicked]
            guard let dataCol = Int(col.identifier.rawValue) else { return }
            
            let key = String(dataCol)
            tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: true)]
            sortRows(by: dataCol, ascending: true)
        }
        
        @objc func sortColumnDescending() {
            guard let tableView = tableView else { return }
            let clicked = tableView.clickedColumn
            guard clicked >= 0 && clicked < tableView.tableColumns.count else { return }
            let col = tableView.tableColumns[clicked]
            guard let dataCol = Int(col.identifier.rawValue) else { return }
            
            let key = String(dataCol)
            tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: false)]
            sortRows(by: dataCol, ascending: false)
        }
        
        @objc func removeSortMenuAction() {
            removeSorting()
        }
        
        @objc func copyRowTSV() {
            copyRowsTSV()
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
            copyRowsJSON()
        }
        
        private func copyRowsJSON() {
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

// MARK: - Row Number Cell View (#)

final class RowNumberCellView: NSTableCellView {
    var rowNumber: Int = 0 {
        didSet {
            textField?.stringValue = "\(rowNumber)"
            needsDisplay = true
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.backgroundColor = .clear
        tf.isEditable = false
        tf.isSelectable = false
        tf.alignment = .right
        tf.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        tf.textColor = .secondaryLabelColor
        tf.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tf)
        self.textField = tf
        
        NSLayoutConstraint.activate([
            tf.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            tf.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Subtle vertical separator line between row numbers and data
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        path.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        path.lineWidth = 1.0
        path.stroke()
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
    
    var isCellSelectionMode: Bool = false {
        didSet { needsDisplay = true }
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        if isCellSelectionMode {
            // Subtle guide tint when individual cell(s) are selected
            NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
            bounds.fill()
        } else {
            super.drawSelection(in: dirtyRect)
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

final class GridCellTextField: NSTextField {
    private let customUndoManager = UndoManager()
    
    override var undoManager: UndoManager? {
        return customUndoManager
    }
    
    deinit {
        customUndoManager.removeAllActions()
        window?.undoManager?.removeAllActions(withTarget: self)
    }
}

final class CustomHighlightCellView: NSTableCellView {
    var isModifiedCell: Bool = false {
        didSet { needsDisplay = true }
    }
    var isColumnSelected: Bool = false {
        didSet { needsDisplay = true }
    }
    var isCellSelected: Bool = false {
        didSet { needsDisplay = true }
    }
    var isSingleCell: Bool = false {
        didSet { needsDisplay = true }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // If this text field is currently being edited (has active field editor), allow text interaction
        if let tf = textField, let editor = tf.currentEditor(), window?.firstResponder == editor {
            return super.hitTest(point)
        }
        return self
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isModifiedCell {
            NSColor(red: 0.42, green: 0.35, blue: 0.12, alpha: 0.95).setFill()
            bounds.fill()
        } else if isColumnSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            bounds.fill()
        }
        
        super.draw(dirtyRect)
        
        if isCellSelected {
            // When editing, do not draw cell selection overlay over the active field editor
            let isEditing = textField?.currentEditor() != nil
            if !isEditing {
                NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
                bounds.fill()
                
                let borderRect = bounds.insetBy(dx: 0.5, dy: 0.5)
                let path = NSBezierPath(rect: borderRect)
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = isSingleCell ? 2.0 : 1.0
                path.stroke()
            }
        }
    }
}

// MARK: - Editable Table Header View Supporting 3-State Sorting & Drag Selection

final class EditableTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let tableView = tableView else { return }
        let selectedCols = tableView.selectedColumnIndexes
        guard !selectedCols.isEmpty else { return }
        
        for colIndex in selectedCols {
            guard colIndex < tableView.tableColumns.count,
                  tableView.tableColumns[colIndex].identifier.rawValue != "_row_num_" else { continue }
            let rect = headerRect(ofColumn: colIndex)
            if dirtyRect.intersects(rect) {
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                rect.fill(using: .sourceOver)
                
                let indicatorRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2.5)
                NSColor.controlAccentColor.setFill()
                indicatorRect.fill()
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let tableView = tableView as? EditableDataGridView else {
            super.mouseDown(with: event)
            return
        }
        
        window?.makeFirstResponder(tableView)
        
        let startPoint = convert(event.locationInWindow, from: nil)
        let colIndex = column(at: startPoint)
        guard colIndex >= 0, colIndex < tableView.tableColumns.count else {
            super.mouseDown(with: event)
            return
        }
        
        let col = tableView.tableColumns[colIndex]
        let coord = tableView.target as? DataGridView.Coordinator
        
        // 1. If clicked on "#" (row number column header): select all rows
        if col.identifier.rawValue == "_row_num_" {
            coord?.selectionMode = .row
            coord?.selectedCellRange = nil
            coord?.dragAnchorCell = nil
            tableView.selectColumnIndexes(IndexSet(), byExtendingSelection: false)
            tableView.selectAll(nil)
            coord?.updateVisibleCellSelections()
            return
        }
        
        // 2. Check if near divider for column resize
        let colRect = headerRect(ofColumn: colIndex)
        let isNearDivider = abs(startPoint.x - colRect.maxX) <= 4 || abs(startPoint.x - colRect.minX) <= 4
        if isNearDivider {
            super.mouseDown(with: event)
            return
        }
        
        let isShift = event.modifierFlags.contains(.shift)
        let isCmd = event.modifierFlags.contains(.command)
        
        var hasDragged = false
        var keepTracking = true
        
        while keepTracking {
            guard let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            let currentPoint = convert(nextEvent.locationInWindow, from: nil)
            
            switch nextEvent.type {
            case .leftMouseDragged:
                let dist = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
                if dist > 4 {
                    hasDragged = true
                    coord?.selectionMode = .column
                    coord?.selectedCellRange = nil
                    coord?.dragAnchorCell = nil
                    tableView.deselectAll(nil)
                    
                    let clampedX = min(max(0, currentPoint.x), bounds.width - 1)
                    let currentCol = column(at: NSPoint(x: clampedX, y: bounds.midY))
                    if currentCol >= 0 {
                        let rawLower = min(colIndex, currentCol)
                        let rawUpper = max(colIndex, currentCol)
                        var range = IndexSet()
                        for c in rawLower...rawUpper {
                            if c < tableView.tableColumns.count && tableView.tableColumns[c].identifier.rawValue != "_row_num_" {
                                range.insert(c)
                            }
                        }
                        tableView.selectColumnIndexes(range, byExtendingSelection: false)
                        coord?.updateVisibleCellSelections()
                        autoscroll(with: nextEvent)
                    }
                }
                
            case .leftMouseUp:
                keepTracking = false
                break
                
            default:
                break
            }
        }
        
        // If clicked (not dragged): 3-state sorting!
        if !hasDragged {
            coord?.selectionMode = .column
            coord?.selectedCellRange = nil
            coord?.dragAnchorCell = nil
            tableView.deselectAll(nil)
            
            if isCmd {
                var current = tableView.selectedColumnIndexes
                if current.contains(colIndex) { current.remove(colIndex) } else { current.insert(colIndex) }
                tableView.selectColumnIndexes(current, byExtendingSelection: false)
            } else if isShift {
                let anchor = tableView.selectedColumnIndexes.first ?? colIndex
                let range = IndexSet(integersIn: min(anchor, colIndex)...max(anchor, colIndex))
                tableView.selectColumnIndexes(range, byExtendingSelection: false)
            } else {
                tableView.selectColumnIndexes(IndexSet(integer: colIndex), byExtendingSelection: false)
                
                // Trigger 3-state column sorting on data column
                if let dataCol = Int(col.identifier.rawValue) {
                    coord?.cycleSort(for: dataCol)
                }
            }
            
            coord?.updateVisibleCellSelections()
        }
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let tableView = tableView else { return super.menu(for: event) }
        window?.makeFirstResponder(tableView)
        
        let point = convert(event.locationInWindow, from: nil)
        let colIndex = column(at: point)
        guard colIndex >= 0, colIndex < tableView.tableColumns.count else {
            return super.menu(for: event)
        }
        
        let col = tableView.tableColumns[colIndex]
        guard col.identifier.rawValue != "_row_num_" else { return nil }
        
        let colTitle = col.title
        let coord = tableView.target as? DataGridView.Coordinator
        
        if !tableView.selectedColumnIndexes.contains(colIndex) {
            coord?.selectionMode = .column
            coord?.selectedCellRange = nil
            coord?.dragAnchorCell = nil
            tableView.deselectAll(nil)
            tableView.selectColumnIndexes(IndexSet(integer: colIndex), byExtendingSelection: false)
            coord?.updateVisibleCellSelections()
        }
        
        let menu = NSMenu(title: "Column Menu")
        
        let copyColItem = NSMenuItem(title: "Copy Column \"\(colTitle)\"", action: #selector(DataGridView.Coordinator.copySelectedColumns), keyEquivalent: "c")
        copyColItem.target = tableView.target
        menu.addItem(copyColItem)
        
        let copyColNameItem = NSMenuItem(title: "Copy Column Name", action: #selector(DataGridView.Coordinator.copyColumnName), keyEquivalent: "")
        copyColNameItem.target = tableView.target
        menu.addItem(copyColNameItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let selectAllColsItem = NSMenuItem(title: "Select All Columns", action: #selector(DataGridView.Coordinator.selectAllColumns), keyEquivalent: "a")
        selectAllColsItem.keyEquivalentModifierMask = [.command, .option]
        selectAllColsItem.target = tableView.target
        menu.addItem(selectAllColsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let sortAscItem = NSMenuItem(title: "Sort Ascending (\(colTitle))", action: #selector(DataGridView.Coordinator.sortColumnAscending), keyEquivalent: "")
        sortAscItem.target = tableView.target
        menu.addItem(sortAscItem)
        
        let sortDescItem = NSMenuItem(title: "Sort Descending (\(colTitle))", action: #selector(DataGridView.Coordinator.sortColumnDescending), keyEquivalent: "")
        sortDescItem.target = tableView.target
        menu.addItem(sortDescItem)
        
        let removeSortItem = NSMenuItem(title: "Remove Sorting", action: #selector(DataGridView.Coordinator.removeSortMenuAction), keyEquivalent: "")
        removeSortItem.target = tableView.target
        menu.addItem(removeSortItem)
        
        return menu
    }
}

// MARK: - Editable Data Grid View

final class EditableDataGridView: NSTableView {
    var onBlankAreaClicked: (() -> Void)?
    
    var coordinator: DataGridView.Coordinator? {
        return (delegate as? DataGridView.Coordinator) ?? (target as? DataGridView.Coordinator)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        _ = super.becomeFirstResponder()
        return true
    }
    
    func editCell(row: Int, column: Int) {
        guard let coord = coordinator, coord.parent.isEditable else { return }
        guard row >= 0 && row < numberOfRows else { return }
        guard column >= 0 && column < tableColumns.count else { return }
        let col = tableColumns[column]
        guard col.identifier.rawValue != "_row_num_" else { return }
        guard let dataCol = Int(col.identifier.rawValue) else { return }
        
        // Ensure row and cell selection is updated
        coord.selectionMode = .cell
        coord.selectedCellRange = DataGridView.CellRange(row1: row, col1: dataCol, row2: row, col2: dataCol)
        coord.dragAnchorCell = (row: row, column: dataCol)
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        selectColumnIndexes(IndexSet(), byExtendingSelection: false)
        coord.updateVisibleCellSelections()
        
        // Ensure column and cell textField allow editing
        col.isEditable = true
        if let cellView = view(atColumn: column, row: row, makeIfNecessary: true) as? CustomHighlightCellView,
           let tf = cellView.textField {
            tf.isEditable = true
            tf.isSelectable = true
        }
        
        // Launch standard AppKit cell editing session
        self.editColumn(column, row: row, with: nil, select: true)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCmd = event.modifierFlags.contains(.command)
        let isShift = event.modifierFlags.contains(.shift)
        let isOpt = event.modifierFlags.contains(.option)
        let isCtrl = event.modifierFlags.contains(.control)
        
        if isCmd && !isOpt && !isCtrl {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "c" && !isShift {
                    coordinator?.copySelection()
                    return true
                }
                if chars == "a" && !isShift {
                    let coord = coordinator
                    coord?.selectionMode = .row
                    coord?.selectedCellRange = nil
                    coord?.dragAnchorCell = nil
                    selectColumnIndexes(IndexSet(), byExtendingSelection: false)
                    selectAll(nil)
                    coord?.updateVisibleCellSelections()
                    return true
                }
                if chars == "z" && !isShift {
                    NotificationCenter.default.post(name: .rollbackChanges, object: nil)
                    return true
                }
            }
        }
        
        if isCmd && isOpt {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "c" {
                    coordinator?.copyAllCSV()
                    return true
                } else if chars == "j" {
                    coordinator?.copyAllJSON()
                    return true
                }
            }
        }
        
        return super.performKeyEquivalent(with: event)
    }

    @objc func copy(_ sender: Any?) {
        coordinator?.copySelection()
    }
    
    @objc func undo(_ sender: Any?) {
        NotificationCenter.default.post(name: .rollbackChanges, object: nil)
    }
    
    @objc func redo(_ sender: Any?) {
        // Redo is currently a no-op for grid
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) {
            return coordinator?.parent.stagedChanges.isEmpty == false
        }
        if menuItem.action == #selector(copy(_:)) {
            return true
        }
        return true
    }
    
    private var isDraggingDataCells = false
    private var isDraggingRowNumbers = false
    private var rowDragAnchor: Int? = nil
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        
        let startPoint = convert(event.locationInWindow, from: nil)
        let clickedRowIndex = self.row(at: startPoint)
        let clickedColIndex = self.column(at: startPoint)
        let coord = coordinator
        
        // Double-click handling for inline editing
        if event.clickCount == 2 {
            if clickedRowIndex == -1 && startPoint.y >= 0 {
                onBlankAreaClicked?()
                return
            }
            if clickedRowIndex >= 0 && clickedColIndex >= 0 && clickedColIndex < tableColumns.count {
                let colId = tableColumns[clickedColIndex].identifier.rawValue
                if colId != "_row_num_" {
                    editCell(row: clickedRowIndex, column: clickedColIndex)
                    return
                }
            }
        }
        
        let isShift = event.modifierFlags.contains(.shift)
        let isCmd = event.modifierFlags.contains(.command)
        let colId = (clickedColIndex >= 0 && clickedColIndex < tableColumns.count) ? tableColumns[clickedColIndex].identifier.rawValue : ""
        
        // 1. Clicked on "#" (Row Number) -> SELECT ENTIRE ROW(S)
        if colId == "_row_num_" && clickedRowIndex >= 0 {
            isDraggingRowNumbers = true
            isDraggingDataCells = false
            coord?.selectionMode = .row
            coord?.selectedCellRange = nil
            coord?.dragAnchorCell = nil
            selectColumnIndexes(IndexSet(), byExtendingSelection: false)
            
            let anchorRow: Int
            if isShift {
                anchorRow = selectedRowIndexes.first ?? clickedRowIndex
                let lower = min(anchorRow, clickedRowIndex)
                let upper = max(anchorRow, clickedRowIndex)
                selectRowIndexes(IndexSet(integersIn: lower...upper), byExtendingSelection: false)
            } else if isCmd {
                anchorRow = clickedRowIndex
                var current = selectedRowIndexes
                if current.contains(clickedRowIndex) { current.remove(clickedRowIndex) } else { current.insert(clickedRowIndex) }
                selectRowIndexes(current, byExtendingSelection: false)
            } else {
                anchorRow = clickedRowIndex
                selectRowIndexes(IndexSet(integer: clickedRowIndex), byExtendingSelection: false)
            }
            rowDragAnchor = anchorRow
            coord?.updateVisibleCellSelections()
            return
        }
        
        // 2. Clicked on a Data Cell -> CELL SELECTION
        if clickedRowIndex >= 0, let dataColIndex = Int(colId) {
            if !isShift && !isCmd {
                isDraggingDataCells = true
                isDraggingRowNumbers = false
                coord?.selectionMode = .cell
                coord?.dragAnchorCell = (row: clickedRowIndex, column: dataColIndex)
                coord?.selectedCellRange = DataGridView.CellRange(row1: clickedRowIndex, col1: dataColIndex, row2: clickedRowIndex, col2: dataColIndex)
                
                selectRowIndexes(IndexSet(integer: clickedRowIndex), byExtendingSelection: false)
                selectColumnIndexes(IndexSet(), byExtendingSelection: false)
                coord?.updateVisibleCellSelections()
                return
            } else {
                coord?.selectionMode = .row
                coord?.selectedCellRange = nil
                coord?.dragAnchorCell = nil
                selectColumnIndexes(IndexSet(), byExtendingSelection: false)
            }
        }
        
        super.mouseDown(with: event)
        coord?.updateVisibleCellSelections()
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        let coord = coordinator
        
        if isDraggingRowNumbers, let anchorRow = rowDragAnchor {
            let r = self.row(at: currentPoint)
            let clampedRow = r >= 0 ? r : (currentPoint.y < 0 ? 0 : numberOfRows - 1)
            let lower = min(anchorRow, clampedRow)
            let upper = max(anchorRow, clampedRow)
            selectRowIndexes(IndexSet(integersIn: lower...upper), byExtendingSelection: false)
            coord?.updateVisibleCellSelections()
            autoscroll(with: event)
            return
        }
        
        if isDraggingDataCells, let anchor = coord?.dragAnchorCell {
            let r = self.row(at: currentPoint)
            let c = self.column(at: currentPoint)
            
            let clampedRow = r >= 0 ? r : (currentPoint.y < 0 ? 0 : numberOfRows - 1)
            let clampedCol = c >= 0 ? c : (currentPoint.x < 0 ? 1 : numberOfColumns - 1)
            let dragColId = clampedCol < tableColumns.count ? tableColumns[clampedCol].identifier.rawValue : "0"
            let dragDataCol = Int(dragColId) ?? 0
            
            if clampedRow >= 0 {
                let newRange = DataGridView.CellRange(row1: anchor.row, col1: anchor.column, row2: clampedRow, col2: dragDataCol)
                if coord?.selectedCellRange != newRange {
                    coord?.selectedCellRange = newRange
                    let rowsIndexSet = IndexSet(integersIn: newRange.minRow...newRange.maxRow)
                    selectRowIndexes(rowsIndexSet, byExtendingSelection: false)
                    coord?.updateVisibleCellSelections()
                    autoscroll(with: event)
                }
            }
            return
        }
        
        super.mouseDragged(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDraggingDataCells = false
        isDraggingRowNumbers = false
        rowDragAnchor = nil
        super.mouseUp(with: event)
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let col = self.column(at: point)
        
        guard row >= 0 && col >= 0 && col < tableColumns.count else {
            return super.menu(for: event)
        }
        
        let colId = tableColumns[col].identifier.rawValue
        guard let coord = coordinator else {
            return super.menu(for: event)
        }
        
        // 1. Right-clicked on row number column:
        if colId == "_row_num_" {
            if !selectedRowIndexes.contains(row) {
                coord.selectionMode = .row
                coord.selectedCellRange = nil
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                selectColumnIndexes(IndexSet(), byExtendingSelection: false)
                coord.updateVisibleCellSelections()
            }
            return super.menu(for: event)
        }
        
        guard let dataCol = Int(colId) else { return super.menu(for: event) }
        
        // 2. Preserve active selections when right-clicking inside them
        if coord.selectionMode == .cell, let range = coord.selectedCellRange, range.contains(row: row, col: dataCol) {
            // Keep active cell block selection intact!
            return super.menu(for: event)
        }
        
        if coord.selectionMode == .row && selectedRowIndexes.contains(row) {
            // Keep active row selection intact!
            return super.menu(for: event)
        }
        
        if coord.selectionMode == .column && selectedColumnIndexes.contains(col) {
            // Keep active column selection intact!
            return super.menu(for: event)
        }
        
        // 3. Right-clicked outside current selection -> select this cell
        coord.selectionMode = .cell
        coord.dragAnchorCell = (row: row, column: dataCol)
        coord.selectedCellRange = DataGridView.CellRange(row1: row, col1: dataCol, row2: row, col2: dataCol)
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        selectColumnIndexes(IndexSet(), byExtendingSelection: false)
        coord.updateVisibleCellSelections()
        
        return super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        let coord = coordinator
        let isShift = event.modifierFlags.contains(.shift)
        let isCmd = event.modifierFlags.contains(.command)
        
        // Cmd + C -> Smart Copy
        if isCmd && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "c" {
                coord?.copySelection()
                return
            }
        }
        
        // Cmd + A -> Select All Rows
        if isCmd && !isShift && !event.modifierFlags.contains(.option) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "a" {
                coord?.selectionMode = .row
                coord?.selectedCellRange = nil
                coord?.dragAnchorCell = nil
                selectColumnIndexes(IndexSet(), byExtendingSelection: false)
                selectAll(nil)
                coord?.updateVisibleCellSelections()
                return
            }
        }
        
        // Cmd + Z -> Rollback staged changes
        if isCmd && !isShift && !event.modifierFlags.contains(.option) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "z" {
                NotificationCenter.default.post(name: .rollbackChanges, object: nil)
                return
            }
        }
        
        // Shift + Space -> Select Entire Row of active cell
        if event.keyCode == 49 && isShift {
            let activeRow = coord?.selectedCellRange?.minRow ?? (selectedRow >= 0 ? selectedRow : 0)
            if activeRow >= 0 && activeRow < numberOfRows {
                coord?.selectionMode = .row
                coord?.selectedCellRange = nil
                coord?.dragAnchorCell = nil
                selectColumnIndexes(IndexSet(), byExtendingSelection: false)
                selectRowIndexes(IndexSet(integer: activeRow), byExtendingSelection: false)
                coord?.updateVisibleCellSelections()
                return
            }
        }
        
        // Space -> Open Details Panel for selected row
        if event.keyCode == 49 && !isShift {
            if selectedRow >= 0 {
                coord?.openDetailsPanel()
                return
            }
        }
        
        // Return / Enter -> Edit selected cell if table is editable
        if event.keyCode == 36 { // Return
            if let coord = coord, coord.parent.isEditable, let range = coord.selectedCellRange {
                let cellRow = range.minRow
                let cellDataCol = range.minCol
                let tableCol = column(withIdentifier: NSUserInterfaceItemIdentifier(String(cellDataCol)))
                if tableCol >= 0 {
                    editCell(row: cellRow, column: tableCol)
                    return
                }
            }
        }
        
        let maxDataCols = (coord?.parent.columns.count ?? 1) - 1
        
        // Left Arrow
        if event.keyCode == 123 {
            if let coord = coord, let range = coord.selectedCellRange {
                if isShift {
                    let newMinCol = max(0, range.minCol - 1)
                    coord.selectedCellRange = DataGridView.CellRange(row1: range.minRow, col1: newMinCol, row2: range.maxRow, col2: range.maxCol)
                } else {
                    let nextCol = max(0, range.minCol - 1)
                    coord.selectedCellRange = DataGridView.CellRange(row1: range.minRow, col1: nextCol, row2: range.minRow, col2: nextCol)
                }
                coord.selectionMode = .cell
                coord.updateVisibleCellSelections()
                scrollRowToVisible(coord.selectedCellRange!.minRow)
                return
            }
        }
        
        // Right Arrow
        if event.keyCode == 124 {
            if let coord = coord, let range = coord.selectedCellRange {
                if isShift {
                    let newMaxCol = min(maxDataCols, range.maxCol + 1)
                    coord.selectedCellRange = DataGridView.CellRange(row1: range.minRow, col1: range.minCol, row2: range.maxRow, col2: newMaxCol)
                } else {
                    let nextCol = min(maxDataCols, range.maxCol + 1)
                    coord.selectedCellRange = DataGridView.CellRange(row1: range.minRow, col1: nextCol, row2: range.minRow, col2: nextCol)
                }
                coord.selectionMode = .cell
                coord.updateVisibleCellSelections()
                scrollRowToVisible(coord.selectedCellRange!.minRow)
                return
            }
        }
        
        // Esc -> Deselect all rows, columns, and cell range
        if event.keyCode == 53 { // Esc
            deselectAll(nil)
            selectColumnIndexes(IndexSet(), byExtendingSelection: false)
            coord?.selectedCellRange = nil
            coord?.dragAnchorCell = nil
            coord?.selectionMode = .cell
            coord?.updateVisibleCellSelections()
            return
        }
        
        // Cmd + Option shortcuts
        if isCmd && event.modifierFlags.contains(.option) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "c" {
                    coord?.copyAllCSV()
                    return
                } else if chars == "j" {
                    coord?.copyAllJSON()
                    return
                }
            }
        }
        
        super.keyDown(with: event)
        
        // If Up/Down arrow was pressed in cell mode, update selectedCellRange
        if (event.keyCode == 125 || event.keyCode == 126) && coord?.selectionMode == .cell { // Down or Up
            if let coord = coord, let range = coord.selectedCellRange, selectedRow >= 0 {
                if isShift {
                    let anchor = coord.dragAnchorCell?.row ?? range.minRow
                    coord.selectedCellRange = DataGridView.CellRange(row1: anchor, col1: range.minCol, row2: selectedRow, col2: range.maxCol)
                } else {
                    coord.selectedCellRange = DataGridView.CellRange(row1: selectedRow, col1: range.minCol, row2: selectedRow, col2: range.minCol)
                    coord.dragAnchorCell = (row: selectedRow, column: range.minCol)
                }
                coord.updateVisibleCellSelections()
            }
        }
    }
}
