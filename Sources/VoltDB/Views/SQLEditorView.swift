import SwiftUI
import AppKit

struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    var tableNames: [String] = []
    var columnNames: [String] = []
    var columnsByTable: [String: [String]] = [:]
    var databaseNames: [String] = []
    var isEditable: Bool = true
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        let textView = EditorNSTextView()
        textView.isRichText = false
        textView.isSelectable = true
        textView.isEditable = isEditable
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        
        // Disable smart quotes / curly quotes / smart dashes / spell corrections for code editor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        
        textView.font = AppTheme.editorNSFont
        textView.backgroundColor = SyntaxColors.colors(for: NSAppearance(named: .darkAqua)).background
        textView.textColor = SyntaxColors.colors(for: NSAppearance(named: .darkAqua)).text
        textView.insertionPointColor = SyntaxColors.colors(for: NSAppearance(named: .darkAqua)).text
        
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        
        scrollView.documentView = textView
        
        context.coordinator.textView = textView
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.formatSQL),
            name: .formatSQL,
            object: nil
        )
        
        textView.string = text
        context.coordinator.highlightSyntax(in: textView.textStorage)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let oldTables = context.coordinator.parent.tableNames
        let oldCols = context.coordinator.parent.columnNames
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let schemaChanged = oldTables != tableNames || oldCols != columnNames
        
        if textView.string != text {
            textView.string = text
            context.coordinator.highlightSyntax(in: textView.textStorage)
        } else if schemaChanged {
            context.coordinator.highlightSyntax(in: textView.textStorage)
        }
        
        textView.isEditable = isEditable
    }
    
    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SQLEditorView
        weak var textView: NSTextView?
        
        private let keywords = [
            "SELECT", "FROM", "WHERE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "CROSS JOIN", "NATURAL JOIN", "ON",
            "AND", "OR", "NOT", "IN", "IS NULL", "IS NOT NULL", "IS", "NULL", "AS", "ORDER BY", "GROUP BY", "HAVING",
            "LIMIT", "OFFSET", "INSERT INTO", "INSERT", "VALUES", "UPDATE", "SET", "DELETE FROM", "DELETE",
            "CREATE TABLE", "CREATE", "ALTER TABLE", "ALTER", "DROP TABLE", "DROP", "CREATE INDEX", "DROP INDEX",
            "DATABASE", "TABLE", "INDEX", "VIEW", "IF EXISTS", "IF NOT EXISTS",
            "BETWEEN", "LIKE", "DISTINCT", "UNION ALL", "UNION",
            "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC",
            "PRIMARY KEY", "FOREIGN KEY", "REFERENCES", "CONSTRAINT", "DEFAULT", "AUTO_INCREMENT", "UNIQUE",
            "SHOW TABLES", "SHOW DATABASES", "SHOW PROCESSLIST", "SHOW", "DESCRIBE", "EXPLAIN", "USE",
            "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "ALL", "ANY", "EXISTS", "CROSS", "NATURAL",
            "INNER", "OUTER", "LEFT", "RIGHT", "INTO", "BY"
        ]
        
        private let functions = [
            "COUNT", "SUM", "AVG", "MIN", "MAX", "NOW", "COALESCE", "CONCAT", "CONCAT_WS",
            "LOWER", "UPPER", "LENGTH", "TRIM", "LTRIM", "RTRIM", "SUBSTRING", "SUBSTR",
            "DATE", "DATE_FORMAT", "DATEDIFF", "DATE_ADD", "DATE_SUB", "IFNULL", "NULLIF",
            "ROUND", "CEIL", "CEILING", "FLOOR", "ABS", "CAST", "CONVERT", "GROUP_CONCAT",
            "DATABASE", "VERSION", "UUID", "JSON_EXTRACT", "JSON_UNQUOTE", "JSON_ARRAY", "JSON_OBJECT",
            "REPLACE", "LEFT", "RIGHT", "LOCATE", "INSTR", "FORMAT"
        ]
        
        private let dataTypes = [
            "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "MEDIUMINT",
            "VARCHAR", "CHAR", "TEXT", "MEDIUMTEXT", "LONGTEXT", "TINYTEXT",
            "BLOB", "MEDIUMBLOB", "LONGBLOB", "TINYBLOB",
            "DATETIME", "TIMESTAMP", "DATE", "TIME", "YEAR",
            "BOOLEAN", "BOOL", "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL",
            "JSON", "ENUM", "SET", "BINARY", "VARBINARY"
        ]
        
        private var isHighlighting = false
        
        init(_ parent: SQLEditorView) {
            self.parent = parent
        }
        
        // MARK: - Autocomplete Suggestions
        
        private func columnsForTable(_ table: String) -> [String] {
            let lower = table.lowercased()
            for (tblKey, cols) in parent.columnsByTable {
                if tblKey.lowercased() == lower {
                    return cols
                }
                if tblKey.lowercased().hasSuffix(".\(lower)") {
                    return cols
                }
            }
            return []
        }
        
        private func getTableIdentifier(before location: Int, in string: NSString) -> String? {
            guard location > 0 else { return nil }
            var pos = location - 1
            // Skip whitespace
            while pos >= 0 {
                let c = string.character(at: pos)
                if CharacterSet.whitespaces.contains(UnicodeScalar(c)!) {
                    pos -= 1
                } else {
                    break
                }
            }
            guard pos >= 0, string.character(at: pos) == 46 /* '.' */ else { return nil }
            pos -= 1
            while pos >= 0 {
                let c = string.character(at: pos)
                if CharacterSet.whitespaces.contains(UnicodeScalar(c)!) {
                    pos -= 1
                } else {
                    break
                }
            }
            let endPos = pos
            while pos >= 0 {
                let c = string.character(at: pos)
                let isIdent = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_`")).contains(UnicodeScalar(c)!)
                if isIdent {
                    pos -= 1
                } else {
                    break
                }
            }
            let startPos = pos + 1
            guard startPos <= endPos else { return nil }
            let range = NSRange(location: startPos, length: endPos - startPos + 1)
            let raw = string.substring(with: range)
            return raw.replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
        }
        
        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let string = textView.string as NSString
            guard charRange.location != NSNotFound, charRange.location + charRange.length <= string.length else {
                return []
            }
            
            let partial = string.substring(with: charRange)
            let partialLower = partial.lowercased()
            
            var suggestions: [String] = []
            
            // Check if there is a dot-qualified table prefix before the partial word or inside it
            if let tableBefore = getTableIdentifier(before: charRange.location, in: string) {
                let tableCols = columnsForTable(tableBefore)
                if !tableCols.isEmpty {
                    let filtered = tableCols.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }
                    return filtered.isEmpty ? tableCols : filtered
                }
            }
            
            if partialLower.contains(".") {
                let parts = partialLower.components(separatedBy: ".")
                let tbl = parts[0]
                let colPart = parts.count > 1 ? parts[1] : ""
                let tableCols = columnsForTable(tbl)
                if !tableCols.isEmpty {
                    let matching = tableCols.filter { colPart.isEmpty || $0.lowercased().starts(with: colPart) }
                    return matching.map { "\(parts[0]).\($0)" }
                }
            }
            
            guard !partialLower.isEmpty else { return [] }
            
            // 1. Matching Columns from current database
            let matchingCols = parent.columnNames.filter { $0.lowercased().starts(with: partialLower) }
            for col in matchingCols {
                if !suggestions.contains(col) { suggestions.append(col) }
            }
            
            // 2. Matching Tables
            let matchingTables = parent.tableNames.filter { $0.lowercased().starts(with: partialLower) }
            for tbl in matchingTables {
                if !suggestions.contains(tbl) { suggestions.append(tbl) }
            }
            
            // 3. SQL Keywords & Functions
            let allKeywords = keywords + functions
            let matchingKeywords = allKeywords.filter { $0.lowercased().starts(with: partialLower) }
            for kw in matchingKeywords {
                if !suggestions.contains(kw) { suggestions.append(kw) }
            }
            
            // 4. Database names
            let matchingDBs = parent.databaseNames.filter { $0.lowercased().starts(with: partialLower) }
            for db in matchingDBs {
                if !suggestions.contains(db) { suggestions.append(db) }
            }
            
            // 5. Fallback substring matches if few results
            if suggestions.count < 8 {
                let containCols = parent.columnNames.filter { $0.lowercased().contains(partialLower) && !suggestions.contains($0) }
                suggestions.append(contentsOf: containCols)
                
                let containTables = parent.tableNames.filter { $0.lowercased().contains(partialLower) && !suggestions.contains($0) }
                suggestions.append(contentsOf: containTables)
                
                let containKeywords = allKeywords.filter { $0.lowercased().contains(partialLower) && !suggestions.contains($0) }
                suggestions.append(contentsOf: containKeywords)
            }
            
            return suggestions
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlightSyntax(in: textView.textStorage)
            
            // Only auto-trigger completion on typing '.' (e.g. table. -> shows columns)
            // Regular typing is never interrupted
            let selectedRange = textView.selectedRange()
            if selectedRange.length == 0 && selectedRange.location > 0 {
                let string = textView.string as NSString
                let lastChar = string.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
                if lastChar == "." {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(triggerCompletion), object: nil)
                    self.perform(#selector(triggerCompletion), with: nil, afterDelay: 0.05)
                }
            }
        }
        
        @objc func triggerCompletion() {
            textView?.complete(nil)
        }
        
        // MARK: - Syntax Highlighting
        
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            highlightSyntax(in: textStorage)
        }
        
        func highlightSyntax(in textStorage: NSTextStorage?) {
            guard !isHighlighting, let textStorage = textStorage else { return }
            let string = textStorage.string as NSString
            guard string.length > 0 else { return }
            
            isHighlighting = true
            defer { isHighlighting = false }
            
            let fullRange = NSRange(location: 0, length: string.length)
            let colors = SyntaxColors.colors(for: NSAppearance(named: .darkAqua))
            
            textStorage.beginEditing()
            
            // 1. Reset all to default text color and font
            textStorage.setAttributes([
                .foregroundColor: colors.text,
                .font: AppTheme.editorNSFont
            ], range: fullRange)
            
            let allKeywordSet = Set((keywords + functions + dataTypes).map { $0.uppercased() })
            
            // 2. Columns Highlighting (Soft Cyan / Sky Blue)
            var validCols: [String] = []
            for col in parent.columnNames {
                let trimmed = col.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !allKeywordSet.contains(trimmed.uppercased()) {
                    validCols.append(NSRegularExpression.escapedPattern(for: trimmed))
                }
            }
            if !validCols.isEmpty {
                let colPattern = "\\b(?i)(" + validCols.joined(separator: "|") + ")\\b"
                if let colRegex = try? NSRegularExpression(pattern: colPattern) {
                    let matches = colRegex.matches(in: string as String, range: fullRange)
                    for match in matches {
                        textStorage.addAttribute(.foregroundColor, value: colors.column, range: match.range)
                    }
                }
            }
            
            // 3. Tables Highlighting (Warm Amber / Orange)
            var validTables: [String] = []
            for tbl in parent.tableNames {
                let trimmed = tbl.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !allKeywordSet.contains(trimmed.uppercased()) {
                    validTables.append(NSRegularExpression.escapedPattern(for: trimmed))
                }
            }
            if !validTables.isEmpty {
                let tablePattern = "\\b(?i)(" + validTables.joined(separator: "|") + ")\\b"
                if let tableRegex = try? NSRegularExpression(pattern: tablePattern) {
                    let matches = tableRegex.matches(in: string as String, range: fullRange)
                    for match in matches {
                        textStorage.addAttribute(.foregroundColor, value: colors.table, range: match.range)
                    }
                }
            }
            
            // 4. Data Types (Lavender / Purple)
            let typePattern = "\\b(?i)(" + dataTypes.joined(separator: "|") + ")\\b"
            if let typeRegex = try? NSRegularExpression(pattern: typePattern) {
                let matches = typeRegex.matches(in: string as String, range: fullRange)
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: colors.type, range: match.range)
                }
            }
            
            // 5. Functions (Purple / Violet)
            let funcPattern = "\\b(?i)(" + functions.joined(separator: "|") + ")\\b(?=\\s*\\()"
            if let funcRegex = try? NSRegularExpression(pattern: funcPattern) {
                let matches = funcRegex.matches(in: string as String, range: fullRange)
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: colors.function, range: match.range)
                }
            }
            
            // 6. Keywords (SELECT, FROM, WHERE, etc. - Pink / Magenta)
            let keywordPattern = "\\b(?i)(" + keywords.map { $0.replacingOccurrences(of: " ", with: "\\s+") }.joined(separator: "|") + ")\\b"
            if let keywordRegex = try? NSRegularExpression(pattern: keywordPattern) {
                let matches = keywordRegex.matches(in: string as String, range: fullRange)
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: colors.keyword, range: match.range)
                }
            }
            
            // 7. Numbers (Golden yellow)
            let numberPattern = "\\b\\d+(\\.\\d+)?\\b"
            if let numberRegex = try? NSRegularExpression(pattern: numberPattern) {
                let matches = numberRegex.matches(in: string as String, range: fullRange)
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: colors.number, range: match.range)
                }
            }
            
            // 8. Strings & Backticks
            let stringPattern = "('(?:''|[^'\\\\]|\\\\.)*')|(\"(?:\"\"|[^\"\\\\]|\\\\.)*\")|(`(?:[^`\\\\]|\\\\.)*`)"
            if let stringRegex = try? NSRegularExpression(pattern: stringPattern) {
                let matches = stringRegex.matches(in: string as String, range: fullRange)
                for match in matches {
                    let matchedStr = string.substring(with: match.range)
                    if matchedStr.hasPrefix("`") && matchedStr.hasSuffix("`") {
                        let inner = String(matchedStr.dropFirst().dropLast()).lowercased()
                        if parent.tableNames.contains(where: { $0.lowercased() == inner }) {
                            textStorage.addAttribute(.foregroundColor, value: colors.table, range: match.range)
                        } else if parent.columnNames.contains(where: { $0.lowercased() == inner }) {
                            textStorage.addAttribute(.foregroundColor, value: colors.column, range: match.range)
                        } else {
                            textStorage.addAttribute(.foregroundColor, value: colors.string, range: match.range)
                        }
                    } else {
                        textStorage.addAttribute(.foregroundColor, value: colors.string, range: match.range)
                    }
                }
            }
            
            // 9. Comments (-- and /* */ - Muted slate)
            let commentPattern = "(--.*$)|(/\\*[\\s\\S]*?\\*/)"
            if let commentRegex = try? NSRegularExpression(pattern: commentPattern, options: [.anchorsMatchLines]) {
                let matches = commentRegex.matches(in: string as String, range: fullRange)
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: colors.comment, range: match.range)
                }
            }
            
            textStorage.endEditing()
        }
        
        // MARK: - Keyboard Shortcuts
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let event = NSApp.currentEvent, event.modifierFlags.contains(.command) {
                    let flags = event.modifierFlags
                    if flags.contains(.control) && flags.contains(.shift) {
                        NotificationCenter.default.post(name: .runAllQueries, object: nil)
                    } else {
                        let queryToRun = extractQueryToRun(from: textView)
                        NotificationCenter.default.post(name: .runCurrentQuery, object: queryToRun)
                    }
                    return true
                }
                // Regular Return inserts a newline without triggering completion
                return false
            }
            
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                let selectedRange = textView.selectedRange()
                if selectedRange.length == 0 && selectedRange.location > 0 {
                    let string = textView.string as NSString
                    let charBefore = string.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
                    if charBefore.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._`"))) != nil {
                        textView.complete(nil)
                        return true
                    }
                }
                
                // Default Tab: 2 spaces
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            }
            
            if commandSelector == #selector(NSResponder.complete(_:)) {
                textView.complete(nil)
                return true
            }
            return false
        }
        
        private func extractQueryToRun(from textView: NSTextView) -> String {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                let full = textView.string as NSString
                return full.substring(with: selectedRange).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return SQLStatementExtractor.extractCurrentStatement(from: textView.string, cursorPosition: selectedRange.location)
            }
        }
        
        @objc func formatSQL() {
            guard let textView = textView else { return }
            let formatted = SQLFormatter.format(textView.string)
            if formatted != textView.string {
                textView.string = formatted
                parent.text = formatted
                highlightSyntax(in: textView.textStorage)
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Editor NSTextView Subclass

final class EditorNSTextView: NSTextView {
    override func cut(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0 {
            super.cut(sender)
        } else {
            cutCurrentLine()
        }
    }
    
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0 {
            super.copy(sender)
        } else {
            copyCurrentLine()
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "w" {
                    NotificationCenter.default.post(name: .closeActiveTab, object: nil)
                    return true
                }
                if chars == "x" && selectedRange().length == 0 {
                    cutCurrentLine()
                    return true
                }
                if chars == "c" && selectedRange().length == 0 {
                    copyCurrentLine()
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    func cutCurrentLine() {
        let nsString = string as NSString
        guard nsString.length > 0 else { return }
        
        let cursor = selectedRange().location
        let clampedCursor = min(cursor, nsString.length)
        let lineRange = nsString.lineRange(for: NSRange(location: clampedCursor, length: 0))
        let lineText = nsString.substring(with: lineRange)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lineText, forType: .string)
        
        if shouldChangeText(in: lineRange, replacementString: "") {
            replaceCharacters(in: lineRange, with: "")
            didChangeText()
        }
    }
    
    func copyCurrentLine() {
        let nsString = string as NSString
        guard nsString.length > 0 else { return }
        
        let cursor = selectedRange().location
        let clampedCursor = min(cursor, nsString.length)
        let lineRange = nsString.lineRange(for: NSRange(location: clampedCursor, length: 0))
        let lineText = nsString.substring(with: lineRange)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lineText, forType: .string)
    }
}
