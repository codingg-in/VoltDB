import Foundation

public struct SQLStatementExtractor {
    
    /// Cleans an individual SQL statement by removing trailing semicolons and normalizing smart quotes/dashes
    public static func cleanSQLStatement(_ sql: String) -> String {
        let normalized = normalizeSQLQuotes(sql)
        var trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
    
    /// Normalizes Unicode smart/curly quotes and dashes into standard ASCII SQL characters
    public static func normalizeSQLQuotes(_ sql: String) -> String {
        return sql
            .replacingOccurrences(of: "\u{201C}", with: "\"") // “ left double curly quote
            .replacingOccurrences(of: "\u{201D}", with: "\"") // ” right double curly quote
            .replacingOccurrences(of: "\u{2018}", with: "'")  // ‘ left single curly quote
            .replacingOccurrences(of: "\u{2019}", with: "'")  // ’ right single curly quote
            .replacingOccurrences(of: "\u{2014}", with: "--") // em-dash —
            .replacingOccurrences(of: "\u{2013}", with: "-")  // en-dash –
    }
    
    /// Splits a full SQL script into individual executable statements
    public static func splitStatements(from fullText: String) -> [String] {
        let normalizedText = normalizeSQLQuotes(fullText)
        let clean = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return [] }
        
        var statements: [String] = []
        var currentStart = 0
        let nsString = normalizedText as NSString
        let len = nsString.length
        
        var inSingleQuote = false
        var inDoubleQuote = false
        var inBacktick = false
        var inLineComment = false
        var inBlockComment = false
        
        var i = 0
        while i < len {
            let char = nsString.character(at: i)
            
            // Check comment boundaries
            if !inSingleQuote && !inDoubleQuote && !inBacktick {
                if !inLineComment && !inBlockComment {
                    if char == 45 && i + 1 < len && nsString.character(at: i + 1) == 45 { // --
                        inLineComment = true
                        i += 2
                        continue
                    } else if char == 47 && i + 1 < len && nsString.character(at: i + 1) == 42 { // /*
                        inBlockComment = true
                        i += 2
                        continue
                    }
                } else if inLineComment {
                    if char == 10 || char == 13 { // newline
                        inLineComment = false
                    }
                    i += 1
                    continue
                } else if inBlockComment {
                    if char == 42 && i + 1 < len && nsString.character(at: i + 1) == 47 { // */
                        inBlockComment = false
                        i += 2
                        continue
                    }
                    i += 1
                    continue
                }
            }
            
            if !inLineComment && !inBlockComment {
                if char == 39 { // '
                    if !inDoubleQuote && !inBacktick { inSingleQuote.toggle() }
                } else if char == 34 { // "
                    if !inSingleQuote && !inBacktick { inDoubleQuote.toggle() }
                } else if char == 96 { // `
                    if !inSingleQuote && !inDoubleQuote { inBacktick.toggle() }
                } else if char == 59 { // ;
                    if !inSingleQuote && !inDoubleQuote && !inBacktick {
                        let stmtRange = NSRange(location: currentStart, length: i - currentStart + 1)
                        let raw = nsString.substring(with: stmtRange)
                        let cleaned = cleanSQLStatement(raw)
                        if !cleaned.isEmpty {
                            statements.append(cleaned)
                        }
                        currentStart = i + 1
                    }
                }
            }
            i += 1
        }
        
        if currentStart < len {
            let stmtRange = NSRange(location: currentStart, length: len - currentStart)
            let raw = nsString.substring(with: stmtRange)
            let cleaned = cleanSQLStatement(raw)
            if !cleaned.isEmpty {
                statements.append(cleaned)
            }
        }
        
        return statements
    }
    
    /// Extracts the single SQL statement at the current cursor position
    public static func extractCurrentStatement(from fullText: String, cursorPosition: Int) -> String {
        let clean = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "" }
        
        var statements: [(range: NSRange, text: String)] = []
        var currentStart = 0
        let nsString = fullText as NSString
        let len = nsString.length
        
        var inSingleQuote = false
        var inDoubleQuote = false
        var inBacktick = false
        var inLineComment = false
        var inBlockComment = false
        
        var i = 0
        while i < len {
            let char = nsString.character(at: i)
            
            if !inSingleQuote && !inDoubleQuote && !inBacktick {
                if !inLineComment && !inBlockComment {
                    if char == 45 && i + 1 < len && nsString.character(at: i + 1) == 45 { // --
                        inLineComment = true
                        i += 2
                        continue
                    } else if char == 47 && i + 1 < len && nsString.character(at: i + 1) == 42 { // /*
                        inBlockComment = true
                        i += 2
                        continue
                    }
                } else if inLineComment {
                    if char == 10 || char == 13 {
                        inLineComment = false
                    }
                    i += 1
                    continue
                } else if inBlockComment {
                    if char == 42 && i + 1 < len && nsString.character(at: i + 1) == 47 {
                        inBlockComment = false
                        i += 2
                        continue
                    }
                    i += 1
                    continue
                }
            }
            
            if !inLineComment && !inBlockComment {
                if char == 39 { // '
                    if !inDoubleQuote && !inBacktick { inSingleQuote.toggle() }
                } else if char == 34 { // "
                    if !inSingleQuote && !inBacktick { inDoubleQuote.toggle() }
                } else if char == 96 { // `
                    if !inSingleQuote && !inDoubleQuote { inBacktick.toggle() }
                } else if char == 59 { // ;
                    if !inSingleQuote && !inDoubleQuote && !inBacktick {
                        let stmtRange = NSRange(location: currentStart, length: i - currentStart + 1)
                        let raw = nsString.substring(with: stmtRange)
                        let cleaned = cleanSQLStatement(raw)
                        if !cleaned.isEmpty {
                            statements.append((range: stmtRange, text: cleaned))
                        }
                        currentStart = i + 1
                    }
                }
            }
            i += 1
        }
        
        if currentStart < len {
            let stmtRange = NSRange(location: currentStart, length: len - currentStart)
            let raw = nsString.substring(with: stmtRange)
            let cleaned = cleanSQLStatement(raw)
            if !cleaned.isEmpty {
                statements.append((range: stmtRange, text: cleaned))
            }
        }
        
        if statements.isEmpty { return cleanSQLStatement(fullText) }
        
        // Find statement containing cursorPosition
        for stmt in statements {
            if cursorPosition >= stmt.range.location && cursorPosition <= (stmt.range.location + stmt.range.length) {
                return stmt.text
            }
        }
        
        // If cursor is beyond the last statement
        if let last = statements.last, cursorPosition >= last.range.location {
            return last.text
        }
        
        return statements.first?.text ?? cleanSQLStatement(fullText)
    }
}
