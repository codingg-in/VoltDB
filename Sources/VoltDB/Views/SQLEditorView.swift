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
        
        let editorFont = AppTheme.editorNSFont
        let textColor = SyntaxColors.colors(for: NSAppearance(named: .darkAqua)).text
        textView.font = editorFont
        textView.backgroundColor = SyntaxColors.colors(for: NSAppearance(named: .darkAqua)).background
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.typingAttributes = [
            .font: editorFont,
            .foregroundColor: textColor
        ]
        
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        
        context.coordinator.textView = textView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.formatSQL),
            name: .formatSQL,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        
        textView.string = text
        if !text.isEmpty {
            context.coordinator.highlightSyntax(in: textView.textStorage)
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let oldTables = context.coordinator.parent.tableNames
        let oldCols = context.coordinator.parent.columnNames
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let schemaChanged = oldTables != tableNames || oldCols != columnNames
        
        if textView.string != text {
            let savedRange = textView.selectedRange()
            textView.string = text
            let maxLoc = (text as NSString).length
            if savedRange.location <= maxLoc {
                textView.setSelectedRange(savedRange)
            }
            let colors = SyntaxColors.colors(for: NSAppearance(named: .darkAqua))
            textView.typingAttributes = [
                .font: AppTheme.editorNSFont,
                .foregroundColor: colors.text
            ]
            if !text.isEmpty {
                context.coordinator.highlightSyntax(in: textView.textStorage)
            }
        } else if schemaChanged && !textView.string.isEmpty {
            context.coordinator.highlightSyntax(in: textView.textStorage)
        }
        
        textView.isEditable = isEditable
    }
    
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.suggestionController.hide()
    }
    
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SQLEditorView
        weak var textView: NSTextView?
        let suggestionController = SuggestionController()
        
        private let keywords = [
            // DQL & Clauses
            "SELECT", "FROM", "WHERE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "CROSS JOIN",
            "FULL JOIN", "NATURAL JOIN", "ON", "AND", "OR", "NOT", "IN", "IS NULL", "IS NOT NULL",
            "IS", "NULL", "AS", "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET", "DISTINCT",
            "BETWEEN", "LIKE", "NOT LIKE", "ILIKE", "REGEXP", "RLIKE", "EXISTS", "NOT EXISTS",
            "UNION", "UNION ALL", "INTERSECT", "EXCEPT", "WITH", "RECURSIVE",
            "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC",
            // DML
            "INSERT INTO", "INSERT", "VALUES", "UPDATE", "SET", "DELETE FROM", "DELETE",
            "REPLACE INTO", "REPLACE", "ON DUPLICATE KEY UPDATE",
            // DDL
            "CREATE TABLE", "CREATE DATABASE", "CREATE INDEX", "CREATE VIEW", "CREATE",
            "ALTER TABLE", "ALTER", "DROP TABLE", "DROP DATABASE", "DROP INDEX", "DROP VIEW", "DROP",
            "TRUNCATE TABLE", "TRUNCATE", "RENAME TABLE", "RENAME",
            "TABLE", "DATABASE", "INDEX", "VIEW", "SCHEMA", "IF EXISTS", "IF NOT EXISTS",
            // Constraints & Columns
            "PRIMARY KEY", "FOREIGN KEY", "REFERENCES", "CONSTRAINT", "DEFAULT", "AUTO_INCREMENT",
            "UNIQUE", "CHECK", "CASCADE", "RESTRICT", "ADD COLUMN", "ADD", "DROP COLUMN", "MODIFY COLUMN", "MODIFY",
            // Administration & Inspection
            "SHOW TABLES", "SHOW DATABASES", "SHOW COLUMNS", "SHOW CREATE TABLE", "SHOW PROCESSLIST", "SHOW STATUS", "SHOW",
            "DESCRIBE", "DESC", "EXPLAIN", "USE",
            // Transactions & Control
            "START TRANSACTION", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "SAVEPOINT",
            "LOCK TABLES", "UNLOCK TABLES",
            // Window functions clauses
            "OVER", "PARTITION BY", "ROWS BETWEEN",
            // Literals
            "TRUE", "FALSE"
        ]
        
        private let functions = [
            // Aggregate
            "COUNT", "SUM", "AVG", "MIN", "MAX", "GROUP_CONCAT",
            // String
            "CONCAT", "CONCAT_WS", "LOWER", "UPPER", "LENGTH", "CHAR_LENGTH", "TRIM", "LTRIM", "RTRIM",
            "SUBSTRING", "SUBSTR", "REPLACE", "LEFT", "RIGHT", "REVERSE", "LOCATE", "INSTR", "FORMAT",
            "LPAD", "RPAD", "REPEAT",
            // Date & Time
            "NOW", "CURDATE", "CURTIME", "DATE", "DATE_FORMAT", "DATEDIFF", "TIMEDIFF", "DATE_ADD", "DATE_SUB",
            "TIMESTAMP", "STR_TO_DATE", "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND",
            // Control Flow & Null
            "IF", "IFNULL", "NULLIF", "COALESCE", "ISNULL",
            // Numeric & Math
            "ROUND", "CEIL", "CEILING", "FLOOR", "ABS", "MOD", "POW", "POWER", "SQRT", "RAND",
            // Cast & Conversion
            "CAST", "CONVERT",
            // System & Info
            "DATABASE", "VERSION", "USER", "CURRENT_USER", "LAST_INSERT_ID", "UUID", "CONNECTION_ID",
            // JSON
            "JSON_EXTRACT", "JSON_UNQUOTE", "JSON_ARRAY", "JSON_OBJECT", "JSON_SET", "JSON_INSERT", "JSON_CONTAINS",
            // Window functions
            "ROW_NUMBER", "RANK", "DENSE_RANK", "LEAD", "LAG", "FIRST_VALUE", "LAST_VALUE", "NTILE"
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
        
        private func columnsForTable(_ table: String, aliases: [String: String] = [:]) -> [String] {
            let clean = table.replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            let lower = clean.lowercased()
            let resolved = aliases[lower] ?? lower
            
            for (tblKey, cols) in parent.columnsByTable {
                let cleanKey = tblKey.replacingOccurrences(of: "`", with: "").lowercased()
                if cleanKey == resolved || cleanKey == lower {
                    return cols
                }
                if cleanKey.hasSuffix(".\(resolved)") || cleanKey.hasSuffix(".\(lower)") {
                    return cols
                }
            }
            return []
        }
        
        private func extractTableAliases(from sql: String) -> [String: String] {
            var aliases: [String: String] = [:]
            let pattern = "(?i)\\b(?:FROM|JOIN|UPDATE|INTO)\\s+([`\\w]+(?:\\.[`\\w]+)?)(?:\\s+(?:AS\\s+)?([`\\w]+))?"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return aliases }
            
            let ns = sql as NSString
            let matches = regex.matches(in: sql, range: NSRange(location: 0, length: ns.length))
            let nonAliases: Set<String> = [
                "WHERE", "ON", "JOIN", "INNER", "LEFT", "RIGHT", "CROSS", "FULL", "OUTER",
                "NATURAL", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "SET",
                "VALUES", "SELECT", "AND", "OR", "USING"
            ]
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    let tableRaw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
                    let tableName = tableRaw.contains(".") ? String(tableRaw.split(separator: ".").last!) : tableRaw
                    
                    if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                        let aliasRaw = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
                        let aliasUpper = aliasRaw.uppercased()
                        if !nonAliases.contains(aliasUpper) && !aliasRaw.isEmpty {
                            aliases[aliasRaw.lowercased()] = tableName
                        }
                    }
                    aliases[tableName.lowercased()] = tableName
                }
            }
            return aliases
        }
        
        private enum SQLContext {
            case tableExpected
            case columnExpected
            case keywordExpected   // At a clause boundary – next token is likely a SQL keyword
            case statementStart
            case general
        }
        
        private func tokenize(sql sub: String) -> [String] {
            sub.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "(),;`'\"")).uppercased() }
                .filter { !$0.isEmpty }
        }
        
        private func detectSQLContext(before location: Int, in sql: String) -> SQLContext {
            guard location > 0 else { return .statementStart }
            let ns = sql as NSString
            let sub = ns.substring(to: min(location, ns.length))
            let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasSuffix(";") {
                return .statementStart
            }
            
            let rawTokens = tokenize(sql: sub)
            guard !rawTokens.isEmpty else { return .statementStart }
            
            let lastToken = rawTokens.last!
            
            // After a trailing comma → stay in the current clause
            if trimmed.hasSuffix(",") {
                for token in rawTokens.reversed() {
                    if token == "SELECT" || token == "BY" || token == "SET" { return .columnExpected }
                    if token == "FROM" || token == "JOIN" { return .tableExpected }
                    if ["WHERE", "ON", "HAVING", "AND", "OR"].contains(token) { return .columnExpected }
                }
                return .general
            }
            
            // Immediate preceding keyword → deterministic context
            if ["FROM", "JOIN", "INTO", "UPDATE", "TABLE", "TRUNCATE", "DESCRIBE", "EXPLAIN"].contains(lastToken) {
                return .tableExpected
            }
            if ["SELECT", "WHERE", "ON", "HAVING", "SET", "BY", "AND", "OR", "DISTINCT", "BETWEEN", "CASE", "WHEN", "THEN", "ELSE"].contains(lastToken) {
                return .columnExpected
            }
            
            // After join modifiers → expect JOIN keyword
            if ["LEFT", "RIGHT", "INNER", "CROSS", "FULL", "NATURAL", "OUTER"].contains(lastToken) {
                return .keywordExpected
            }
            
            // After DELETE → expect FROM keyword
            if lastToken == "DELETE" { return .keywordExpected }
            
            // After comparison / logical operators → expect value/column
            if ["=", ">", "<", ">=", "<=", "!=", "<>", "LIKE", "ILIKE", "RLIKE", "REGEXP", "IN", "NOT"].contains(lastToken) {
                return .columnExpected
            }
            
            // If last token is a known SQL keyword that doesn't fit above → general
            let miscKeywords: Set<String> = ["ASC", "DESC", "LIMIT", "OFFSET", "AS",
                "UNION", "ALL", "INTERSECT", "EXCEPT", "EXISTS", "VALUES",
                "END", "OVER", "PARTITION", "TRUE", "FALSE", "NULL", "IS"]
            if miscKeywords.contains(lastToken) {
                return .keywordExpected
            }
            
            // Last token is an identifier (table name, column, alias, *, number, etc.)
            // → we're at a clause boundary → suggest next clause keyword
            return .keywordExpected
        }
        
        /// Returns an ordered list of keywords most likely to come next based on
        /// the SQL statement structure before `location`.
        private func clauseBoostKeywords(before location: Int, in sql: String) -> [String] {
            guard location > 0 else { return [] }
            let ns = sql as NSString
            let sub = ns.substring(to: min(location, ns.length))
            let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty && !trimmed.hasSuffix(";") else { return [] }
            
            let tk = tokenize(sql: sub)
            guard !tk.isEmpty else { return [] }
            
            let stmtType = tk.first!
            let has: (String) -> Bool = { kw in tk.contains(kw) }
            let hasPair: (String, String) -> Bool = { a, b in
                for i in 0..<tk.count - 1 { if tk[i] == a && tk[i+1] == b { return true } }
                return false
            }
            
            // Find the last clause keyword to understand where we are
            let clauseKW: Set<String> = ["SELECT", "FROM", "WHERE", "JOIN", "ON",
                "GROUP", "ORDER", "HAVING", "LIMIT", "SET", "VALUES",
                "INSERT", "UPDATE", "DELETE", "INTO", "OFFSET"]
            var lastClause = ""
            for token in tk.reversed() {
                if clauseKW.contains(token) { lastClause = token; break }
            }
            
            let lastToken = tk.last!
            
            // --- SELECT statement ---
            if stmtType == "SELECT" {
                if !has("FROM") {
                    // Still in the column list → most likely next keyword is FROM
                    if lastClause == "SELECT" && lastToken != "SELECT" && lastToken != "DISTINCT" && !trimmed.hasSuffix(",") {
                        return ["FROM", "AS"]
                    }
                    return []
                }
                // After FROM / JOIN table
                if !has("WHERE") && !hasPair("GROUP", "BY") && !hasPair("ORDER", "BY") {
                    if lastClause == "FROM" && lastToken != "FROM" {
                        return ["WHERE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
                                "CROSS JOIN", "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "AS"]
                    }
                    if lastClause == "JOIN" && lastToken != "JOIN" {
                        return ["ON", "AS"]
                    }
                    if lastClause == "ON" && lastToken != "ON" {
                        return ["WHERE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
                                "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "AND", "OR"]
                    }
                }
                // After WHERE condition
                if has("WHERE") && !hasPair("GROUP", "BY") && !hasPair("ORDER", "BY") {
                    if lastClause == "WHERE" && lastToken != "WHERE" {
                        return ["AND", "OR", "IN", "IS", "IS NULL", "IS NOT NULL", "BETWEEN",
                                "LIKE", "NOT", "GROUP BY", "ORDER BY", "HAVING", "LIMIT"]
                    }
                }
                // After GROUP BY columns
                if hasPair("GROUP", "BY") && !hasPair("ORDER", "BY") && !has("HAVING") {
                    if lastClause == "GROUP" || (lastClause == "ORDER" && !hasPair("ORDER", "BY")) {
                        return []
                    }
                    return ["HAVING", "ORDER BY", "LIMIT"]
                }
                // After HAVING
                if has("HAVING") && !hasPair("ORDER", "BY") {
                    return ["ORDER BY", "LIMIT", "AND", "OR"]
                }
                // After ORDER BY
                if hasPair("ORDER", "BY") && !has("LIMIT") {
                    return ["ASC", "DESC", "LIMIT", "OFFSET"]
                }
                if has("LIMIT") && !has("OFFSET") {
                    return ["OFFSET"]
                }
                return []
            }
            
            // --- INSERT statement ---
            if stmtType == "INSERT" {
                if has("INTO") && !has("VALUES") && lastClause != "INTO" && lastToken != "INTO" {
                    return ["VALUES", "SELECT"]
                }
                return []
            }
            
            // --- UPDATE statement ---
            if stmtType == "UPDATE" {
                if !has("SET") && lastToken != "UPDATE" {
                    return ["SET"]
                }
                if has("SET") && !has("WHERE") && lastClause == "SET" && lastToken != "SET" && !trimmed.hasSuffix(",") {
                    return ["WHERE"]
                }
                return []
            }
            
            // --- DELETE statement ---
            if stmtType == "DELETE" {
                if !has("FROM") {
                    return ["FROM"]
                }
                if has("FROM") && !has("WHERE") && lastClause != "FROM" && lastToken != "FROM" {
                    return ["WHERE"]
                }
                return []
            }
            
            // Join modifier keywords
            if ["LEFT", "RIGHT", "INNER", "CROSS", "FULL", "NATURAL", "OUTER"].contains(lastToken) {
                return ["JOIN"]
            }
            
            return []
        }
        
        private func isInsideStringOrComment(at location: Int, in sql: String) -> Bool {
            guard location > 0 else { return false }
            let chars = Array(sql.utf16)
            let limit = min(location, chars.count)
            
            var inSingleQuote = false
            var inDoubleQuote = false
            var inLineComment = false
            var inBlockComment = false
            
            var i = 0
            while i < limit {
                let c = chars[i]
                let next: UInt16? = (i + 1 < limit) ? chars[i + 1] : nil
                
                if inLineComment {
                    if c == 10 /* \n */ || c == 13 /* \r */ {
                        inLineComment = false
                    }
                    i += 1
                    continue
                }
                
                if inBlockComment {
                    if c == 42 /* * */ && next == 47 /* / */ {
                        inBlockComment = false
                        i += 2
                        continue
                    }
                    i += 1
                    continue
                }
                
                if inSingleQuote {
                    if c == 92 /* \ */ {
                        i += 2
                        continue
                    }
                    if c == 39 /* ' */ {
                        if next == 39 {
                            i += 2
                            continue
                        }
                        inSingleQuote = false
                    }
                    i += 1
                    continue
                }
                
                if inDoubleQuote {
                    if c == 92 /* \ */ {
                        i += 2
                        continue
                    }
                    if c == 34 /* " */ {
                        inDoubleQuote = false
                    }
                    i += 1
                    continue
                }
                
                if c == 45 /* - */ && next == 45 /* - */ {
                    inLineComment = true
                    i += 2
                    continue
                }
                if c == 35 /* # */ {
                    inLineComment = true
                    i += 1
                    continue
                }
                if c == 47 /* / */ && next == 42 /* * */ {
                    inBlockComment = true
                    i += 2
                    continue
                }
                
                if c == 39 /* ' */ {
                    inSingleQuote = true
                    i += 1
                    continue
                }
                if c == 34 /* " */ {
                    inDoubleQuote = true
                    i += 1
                    continue
                }
                
                i += 1
            }
            
            return inSingleQuote || inDoubleQuote || inLineComment || inBlockComment
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if suggestionController.isVisible && !suggestionController.isApplying {
                let selectedRange = textView.selectedRange()
                let wr = suggestionController.wordRange
                if selectedRange.length > 0 || selectedRange.location < wr.location || selectedRange.location > wr.location + wr.length {
                    suggestionController.hide()
                }
            }
        }
        
        @objc func scrollViewDidScroll() {
            suggestionController.hide()
        }
        
        @objc func windowDidResignKey() {
            suggestionController.hide()
        }
        
        private func getCompletionContext(before cursor: Int, in string: NSString) -> (prefix: String?, partial: String, wordRange: NSRange)? {
            guard cursor > 0, cursor <= string.length else { return nil }
            
            let wordCharSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            var wordStart = cursor
            while wordStart > 0 {
                let char = string.character(at: wordStart - 1)
                guard let scalar = UnicodeScalar(char), wordCharSet.contains(scalar) else {
                    break
                }
                wordStart -= 1
            }
            
            let partial = string.substring(with: NSRange(location: wordStart, length: cursor - wordStart))
            let wordRange = NSRange(location: wordStart, length: cursor - wordStart)
            
            // Check if preceded by a dot '.'
            if wordStart > 0 && string.character(at: wordStart - 1) == 46 /* '.' */ {
                var qualEnd = wordStart - 1
                var qualStart = qualEnd
                
                if qualEnd > 0 && string.character(at: qualEnd - 1) == 96 /* '`' */ {
                    qualEnd -= 1
                    qualStart = qualEnd
                    while qualStart > 0 && string.character(at: qualStart - 1) != 96 {
                        qualStart -= 1
                    }
                } else {
                    let qualCharSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
                    while qualStart > 0 {
                        let char = string.character(at: qualStart - 1)
                        guard let scalar = UnicodeScalar(char), qualCharSet.contains(scalar) else {
                            break
                        }
                        qualStart -= 1
                    }
                }
                
                let qualifier = string.substring(with: NSRange(location: qualStart, length: qualEnd - qualStart))
                    .replacingOccurrences(of: "`", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                if !qualifier.isEmpty {
                    return (prefix: qualifier, partial: partial, wordRange: wordRange)
                }
            }
            
            // If no dot prefix, ignore empty partial or pure numeric literals
            if partial.isEmpty {
                return nil
            }
            
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: partial)) {
                return nil
            }
            
            return (prefix: nil, partial: partial, wordRange: wordRange)
        }
        
        private func fetchSuggestions(prefix: String?, partial: String, wordStart: Int, fullText: String) -> [SuggestionItem] {
            let partialLower = partial.lowercased()
            let aliases = extractTableAliases(from: fullText)
            
            let effectiveTables = !parent.tableNames.isEmpty ? parent.tableNames : Array(Set(parent.columnsByTable.keys.map { key in
                let clean = key.replacingOccurrences(of: "`", with: "")
                return clean.contains(".") ? String(clean.split(separator: ".").last!) : clean
            })).sorted()
            
            let effectiveColumns = !parent.columnNames.isEmpty ? parent.columnNames : Array(Set(parent.columnsByTable.values.flatMap { $0 })).sorted()
            
            // 1. Dot-qualified prefix (e.g. `users.` or `u.` or `db.`)
            if let prefix = prefix {
                let cleanPrefix = prefix.replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
                
                if parent.databaseNames.contains(where: { $0.lowercased() == cleanPrefix.lowercased() }) {
                    let matches = effectiveTables.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }
                    var results = matches.map { SuggestionItem(text: $0, insertText: $0, kind: .table) }
                    if results.count < 10 && !partialLower.isEmpty {
                        let contains = effectiveTables.filter { $0.lowercased().contains(partialLower) && !matches.contains($0) }
                        results.append(contentsOf: contains.map { SuggestionItem(text: $0, insertText: $0, kind: .table) })
                    }
                    return Array(results.prefix(25))
                }
                
                let tableCols = columnsForTable(cleanPrefix, aliases: aliases)
                let colsToSearch = !tableCols.isEmpty ? tableCols : effectiveColumns
                let prefixMatches = colsToSearch.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }
                var results = prefixMatches.map { SuggestionItem(text: $0, insertText: $0, kind: .column) }
                if results.count < 10 && !partialLower.isEmpty {
                    let contains = colsToSearch.filter { $0.lowercased().contains(partialLower) && !prefixMatches.contains($0) }
                    results.append(contentsOf: contains.map { SuggestionItem(text: $0, insertText: $0, kind: .column) })
                }
                return Array(results.prefix(25))
            }
            
            // 2. Unqualified word completion
            var suggestions: [SuggestionItem] = []
            var seen = Set<String>()
            
            func addSuggestions(_ items: [SuggestionItem]) {
                for item in items {
                    let key = item.text.lowercased()
                    if !seen.contains(key) {
                        seen.insert(key)
                        suggestions.append(item)
                    }
                }
            }
            
            // Use word START position for context detection so the partial word
            // itself doesn't contaminate the clause analysis.
            let context = detectSQLContext(before: wordStart, in: fullText)
            let boostKW = clauseBoostKeywords(before: wordStart, in: fullText)
            
            let activeTableNames = Set(aliases.values.map { $0.lowercased() })
            var activeTableColumns: [String] = []
            for (tblKey, cols) in parent.columnsByTable {
                let clean = tblKey.replacingOccurrences(of: "`", with: "").lowercased()
                let leaf = clean.contains(".") ? String(clean.split(separator: ".").last!) : clean
                if activeTableNames.contains(leaf) {
                    activeTableColumns.append(contentsOf: cols)
                }
            }
            
            let matchActiveCols = activeTableColumns.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .column) }
            let matchCols = effectiveColumns.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .column) }
            let matchTables = effectiveTables.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .table) }
            let matchKeywords = keywords.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .keyword) }
            let matchFuncs = functions.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .function) }
            let matchTypes = dataTypes.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .dataType) }
            let matchDBs = parent.databaseNames.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .database) }
            
            // Insert boost keywords at the very top (clause-progression hints)
            if !boostKW.isEmpty {
                let allKW = keywords + functions + dataTypes
                let boostItems = boostKW.filter { kw in
                    partialLower.isEmpty || kw.lowercased().starts(with: partialLower)
                }.map { kw -> SuggestionItem in
                    let kind: SuggestionKind = allKW.contains(where: { $0.uppercased() == kw.uppercased() }) ? .keyword : .keyword
                    return SuggestionItem(text: kw, insertText: kw, kind: kind)
                }
                addSuggestions(boostItems)
            }
            
            switch context {
            case .tableExpected:
                addSuggestions(matchTables)
                addSuggestions(matchDBs)
                addSuggestions(matchKeywords)
                addSuggestions(matchCols)
                
            case .columnExpected:
                addSuggestions(matchActiveCols)
                addSuggestions(matchCols)
                addSuggestions(matchFuncs)
                addSuggestions(matchKeywords)
                addSuggestions(matchTables)
                
            case .keywordExpected:
                // At a clause boundary – keywords first, then schema items
                addSuggestions(matchKeywords)
                addSuggestions(matchFuncs)
                addSuggestions(matchActiveCols)
                addSuggestions(matchCols)
                addSuggestions(matchTables)
                addSuggestions(matchTypes)
                addSuggestions(matchDBs)
                
            case .statementStart:
                let statementStarters = ["SELECT", "INSERT INTO", "INSERT", "UPDATE", "DELETE FROM", "DELETE",
                                        "CREATE TABLE", "CREATE", "ALTER TABLE", "ALTER", "DROP TABLE", "DROP",
                                        "TRUNCATE TABLE", "TRUNCATE", "SHOW TABLES", "SHOW DATABASES", "SHOW",
                                        "DESCRIBE", "EXPLAIN", "USE", "WITH", "SET", "BEGIN", "START TRANSACTION"]
                let matchStarters = statementStarters.filter { partialLower.isEmpty || $0.lowercased().starts(with: partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .keyword) }
                addSuggestions(matchStarters)
                addSuggestions(matchKeywords)
                addSuggestions(matchTables)
                addSuggestions(matchCols)
                
            case .general:
                addSuggestions(matchKeywords)
                addSuggestions(matchActiveCols)
                addSuggestions(matchCols)
                addSuggestions(matchTables)
                addSuggestions(matchFuncs)
                addSuggestions(matchTypes)
                addSuggestions(matchDBs)
            }
            
            if suggestions.count < 10 && !partialLower.isEmpty {
                if context == .tableExpected {
                    let subTables = effectiveTables.filter { $0.lowercased().contains(partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .table) }
                    addSuggestions(subTables)
                } else {
                    let subCols = effectiveColumns.filter { $0.lowercased().contains(partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .column) }
                    addSuggestions(subCols)
                    let subTables = effectiveTables.filter { $0.lowercased().contains(partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .table) }
                    addSuggestions(subTables)
                }
                let subKw = keywords.filter { $0.lowercased().contains(partialLower) }.map { SuggestionItem(text: $0, insertText: $0, kind: .keyword) }
                addSuggestions(subKw)
            }
            
            return Array(suggestions.prefix(25))
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            let colors = SyntaxColors.colors(for: NSAppearance(named: .darkAqua))
            textView.typingAttributes = [
                .font: AppTheme.editorNSFont,
                .foregroundColor: colors.text
            ]
            
            if !textView.string.isEmpty {
                highlightSyntax(in: textView.textStorage)
            }
            
            if suggestionController.isApplying {
                return
            }
            
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 && selectedRange.location > 0 else {
                suggestionController.hide()
                return
            }
            
            let cursor = selectedRange.location
            let string = textView.string as NSString
            guard cursor <= string.length else {
                suggestionController.hide()
                return
            }
            
            // Suppress autocomplete inside strings and comments
            if isInsideStringOrComment(at: cursor, in: textView.string) {
                suggestionController.hide()
                return
            }
            
            guard let context = getCompletionContext(before: cursor, in: string) else {
                suggestionController.hide()
                return
            }
            
            let items = fetchSuggestions(prefix: context.prefix, partial: context.partial, wordStart: context.wordRange.location, fullText: textView.string)
            if items.isEmpty {
                suggestionController.hide()
            } else {
                suggestionController.show(items: items, wordRange: context.wordRange, in: textView)
            }
        }
        
        private func triggerSuggestionsManually(in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else { return }
            let cursor = selectedRange.location
            let string = textView.string as NSString
            guard cursor <= string.length else { return }
            
            if let context = getCompletionContext(before: cursor, in: string) {
                let items = fetchSuggestions(prefix: context.prefix, partial: context.partial, wordStart: context.wordRange.location, fullText: textView.string)
                if !items.isEmpty {
                    suggestionController.show(items: items, wordRange: context.wordRange, in: textView)
                    return
                }
            }
            
            let items = fetchSuggestions(prefix: nil, partial: "", wordStart: cursor, fullText: textView.string)
            if !items.isEmpty {
                suggestionController.show(items: items, wordRange: NSRange(location: cursor, length: 0), in: textView)
            }
        }
        
        // MARK: - Syntax Highlighting
        
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
            if suggestionController.isVisible {
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    suggestionController.selectPrevious()
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    suggestionController.selectNext()
                    return true
                }
                if commandSelector == #selector(NSResponder.pageUp(_:)) {
                    for _ in 0..<5 { suggestionController.selectPrevious() }
                    return true
                }
                if commandSelector == #selector(NSResponder.pageDown(_:)) {
                    for _ in 0..<5 { suggestionController.selectNext() }
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    suggestionController.hide()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    if let event = NSApp.currentEvent, event.modifierFlags.contains(.command) {
                        suggestionController.hide()
                        let flags = event.modifierFlags
                        if flags.contains(.control) && flags.contains(.shift) {
                            NotificationCenter.default.post(name: .runAllQueries, object: nil)
                        } else {
                            let queryToRun = extractQueryToRun(from: textView)
                            NotificationCenter.default.post(name: .runCurrentQuery, object: queryToRun)
                        }
                        return true
                    }
                    suggestionController.applySelected()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertTab(_:)) {
                    suggestionController.applySelected()
                    return true
                }
            }
            
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
                return false
            }
            
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            }
            
            if commandSelector == #selector(NSResponder.complete(_:)) {
                triggerSuggestionsManually(in: textView)
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
