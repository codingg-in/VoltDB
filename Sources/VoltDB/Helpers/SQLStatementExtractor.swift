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
    
    /// Extracts the raw SQL statement at current cursor position (preserving trailing semicolon and syntax)
    public static func extractRawStatement(from fullText: String, cursorPosition: Int) -> String {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        
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
                if char == 39 {
                    if !inDoubleQuote && !inBacktick { inSingleQuote.toggle() }
                } else if char == 34 {
                    if !inSingleQuote && !inBacktick { inDoubleQuote.toggle() }
                } else if char == 96 {
                    if !inSingleQuote && !inDoubleQuote { inBacktick.toggle() }
                } else if char == 59 { // ;
                    if !inSingleQuote && !inDoubleQuote && !inBacktick {
                        let stmtRange = NSRange(location: currentStart, length: i - currentStart + 1)
                        let raw = nsString.substring(with: stmtRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !raw.isEmpty {
                            statements.append((range: stmtRange, text: raw))
                        }
                        currentStart = i + 1
                    }
                }
            }
            i += 1
        }
        
        if currentStart < len {
            let stmtRange = NSRange(location: currentStart, length: len - currentStart)
            let raw = nsString.substring(with: stmtRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                statements.append((range: stmtRange, text: raw))
            }
        }
        
        for stmt in statements {
            if cursorPosition >= stmt.range.location && cursorPosition <= (stmt.range.location + stmt.range.length) {
                return stmt.text
            }
        }
        
        if let last = statements.last, cursorPosition >= last.range.location {
            return last.text
        }
        
        return statements.first?.text ?? trimmed
    }
    
    /// Extracts the current SQL statement at cursor position along with its exact NSRange in fullText
    public static func extractCurrentStatementWithRange(from fullText: String, cursorPosition: Int) -> (range: NSRange, text: String)? {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
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
                    } else if char == 35 { // #
                        inLineComment = true
                        i += 1
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
                        let slice = NSRange(location: currentStart, length: i - currentStart + 1)
                        if let trimmedRange = trimmedRangeOfSlice(slice, in: nsString) {
                            statements.append((range: trimmedRange, text: nsString.substring(with: trimmedRange)))
                        }
                        currentStart = i + 1
                    }
                }
            }
            i += 1
        }
        
        if currentStart < len {
            let slice = NSRange(location: currentStart, length: len - currentStart)
            if let trimmedRange = trimmedRangeOfSlice(slice, in: nsString) {
                statements.append((range: trimmedRange, text: nsString.substring(with: trimmedRange)))
            }
        }
        
        if statements.isEmpty { return nil }
        
        for stmt in statements {
            if cursorPosition >= stmt.range.location && cursorPosition <= (stmt.range.location + stmt.range.length) {
                return stmt
            }
        }
        
        var best = statements[0]
        var minDiff = Int.max
        for stmt in statements {
            let mid = stmt.range.location + stmt.range.length / 2
            let diff = abs(cursorPosition - mid)
            if diff < minDiff {
                minDiff = diff
                best = stmt
            }
        }
        return best
    }
    
    private static func trimmedRangeOfSlice(_ slice: NSRange, in nsString: NSString) -> NSRange? {
        var start = slice.location
        var end = slice.location + slice.length
        let len = nsString.length
        
        while start < end && start < len {
            let c = nsString.character(at: start)
            if let scalar = UnicodeScalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                start += 1
            } else {
                break
            }
        }
        
        while end > start && end <= len {
            let c = nsString.character(at: end - 1)
            if let scalar = UnicodeScalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                end -= 1
            } else {
                break
            }
        }
        
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
    
    /// Extracts the principal table name from a SQL statement (e.g. SELECT * FROM vehicle -> vehicle)
    public static func extractTableName(from sql: String) -> String? {
        let clean = cleanSQLStatement(sql)
        let pattern = #"(?i)\b(?:FROM|INTO|UPDATE)\s+[`"]?(?:[a-zA-Z0-9_]+[`"]?\.)?[`"]?([a-zA-Z0-9_]+)[`"]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = clean as NSString
        let matches = regex.matches(in: clean, options: [], range: NSRange(location: 0, length: nsString.length))
        
        let excluded: Set<String> = ["dual", "information_schema", "performance_schema", "sys", "mysql"]
        for match in matches.reversed() {
            if match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                let name = nsString.substring(with: range)
                if !excluded.contains(name.lowercased()) {
                    return name
                }
            }
        }
        return nil
    }
}

