import Foundation

struct SQLFormatter {
    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "NATURAL",
        "ON", "AND", "OR", "NOT", "IN", "IS", "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING",
        "LIMIT", "OFFSET", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA",
        "BETWEEN", "LIKE", "DISTINCT", "UNION", "ALL", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END",
        "ASC", "DESC", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "AUTO_INCREMENT",
        "UNIQUE", "SHOW", "DESCRIBE", "EXPLAIN", "USE", "BEGIN", "COMMIT", "ROLLBACK"
    ]
    
    private static let newlineKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY", "LIMIT", "OFFSET",
        "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "CROSS JOIN", "NATURAL JOIN",
        "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM", "UNION", "UNION ALL"
    ]
    
    private static let functions: Set<String> = [
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "IFNULL", "NULLIF",
        "CONCAT", "CONCAT_WS", "SUBSTRING", "SUBSTR", "TRIM", "LTRIM", "RTRIM",
        "LOWER", "UPPER", "LENGTH", "CHAR_LENGTH", "REPLACE", "ROUND", "FLOOR", "CEIL",
        "DATE", "NOW", "CURDATE", "CURTIME", "DATEDIFF", "DATE_ADD", "DATE_SUB",
        "JSON_EXTRACT", "JSON_UNQUOTE", "ROW_NUMBER", "RANK", "DENSE_RANK"
    ]
    
    static func format(_ sql: String) -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        
        let tokens = tokenize(trimmed)
        if tokens.isEmpty { return trimmed }
        
        var formattedLines: [String] = []
        var currentLine = ""
        var indentLevel = 0
        var i = 0
        
        func pushLine() {
            let line = currentLine.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                let indent = String(repeating: "  ", count: max(0, indentLevel))
                formattedLines.append(indent + line)
            }
            currentLine = ""
        }
        
        while i < tokens.count {
            let token = tokens[i]
            
            // Preserve blank lines between logical sections
            if token.type == .blankLine {
                pushLine()
                if formattedLines.last?.isEmpty == false {
                    formattedLines.append("")
                }
                i += 1
                continue
            }
            
            // Place comments cleanly on their own lines
            if token.type == .comment {
                pushLine()
                formattedLines.append(token.text)
                i += 1
                continue
            }
            
            // Check for two-word clauses (e.g. ORDER BY, GROUP BY, LEFT JOIN)
            var clauseCandidate = token.text.uppercased()
            var step = 1
            if i + 1 < tokens.count && tokens[i + 1].type == .word {
                let twoWords = "\(token.text.uppercased()) \(tokens[i + 1].text.uppercased())"
                if newlineKeywords.contains(twoWords) {
                    clauseCandidate = twoWords
                    step = 2
                }
            }
            
            if newlineKeywords.contains(clauseCandidate) {
                pushLine()
                if clauseCandidate == "SELECT" || clauseCandidate == "INSERT INTO" || clauseCandidate == "UPDATE" || clauseCandidate == "DELETE FROM" {
                    indentLevel = 0
                }
                currentLine += (clauseCandidate == token.text.uppercased() ? token.text.uppercased() : clauseCandidate) + " "
                i += step
                continue
            }
            
            switch token.type {
            case .word:
                let upper = token.text.uppercased()
                if keywords.contains(upper) {
                    currentLine += upper + " "
                } else {
                    currentLine += token.text + " "
                }
            case .symbol:
                if token.text == ";" {
                    currentLine = currentLine.trimmingCharacters(in: .whitespaces) + ";"
                    pushLine()
                    indentLevel = 0
                } else if token.text == "," {
                    currentLine = currentLine.trimmingCharacters(in: .whitespaces) + ", "
                } else if token.text == "(" {
                    let trimmedCur = currentLine.trimmingCharacters(in: .whitespaces)
                    if let lastWord = trimmedCur.split(separator: " ").last?.uppercased(),
                       functions.contains(lastWord) {
                        currentLine = trimmedCur + "("
                    } else if !trimmedCur.isEmpty && !trimmedCur.hasSuffix("(") {
                        currentLine = trimmedCur + " ("
                    } else {
                        currentLine += "("
                    }
                } else if token.text == ")" {
                    currentLine = currentLine.trimmingCharacters(in: .whitespaces) + ") "
                } else {
                    currentLine += token.text + " "
                }
            case .literal:
                currentLine += token.text + " "
            case .comment, .blankLine:
                break
            }
            
            i += 1
        }
        
        pushLine()
        return formattedLines.joined(separator: "\n")
    }
    
    // MARK: - Tokenizer
    
    private enum TokenType {
        case word
        case literal
        case symbol
        case comment
        case blankLine
    }
    
    private struct Token {
        let text: String
        let type: TokenType
    }
    
    private static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        let ns = sql as NSString
        let len = ns.length
        var i = 0
        
        while i < len {
            let c = ns.character(at: i)
            
            // Whitespace & blank lines detection
            if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(c)!) {
                var newlineCount = 0
                while i < len, let scalar = UnicodeScalar(ns.character(at: i)),
                      CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    if ns.character(at: i) == 10 /* '\n' */ {
                        newlineCount += 1
                    }
                    i += 1
                }
                if newlineCount >= 2 {
                    tokens.append(Token(text: "", type: .blankLine))
                }
                continue
            }
            
            // Line comment --
            if c == 45 && i + 1 < len && ns.character(at: i + 1) == 45 {
                let start = i
                while i < len && ns.character(at: i) != 10 && ns.character(at: i) != 13 {
                    i += 1
                }
                tokens.append(Token(text: ns.substring(with: NSRange(location: start, length: i - start)), type: .comment))
                continue
            }
            
            // Line comment #
            if c == 35 {
                let start = i
                while i < len && ns.character(at: i) != 10 && ns.character(at: i) != 13 {
                    i += 1
                }
                tokens.append(Token(text: ns.substring(with: NSRange(location: start, length: i - start)), type: .comment))
                continue
            }
            
            // Block comment /* */
            if c == 47 && i + 1 < len && ns.character(at: i + 1) == 42 {
                let start = i
                i += 2
                while i + 1 < len && !(ns.character(at: i) == 42 && ns.character(at: i + 1) == 47) {
                    i += 1
                }
                i = min(len, i + 2)
                tokens.append(Token(text: ns.substring(with: NSRange(location: start, length: i - start)), type: .comment))
                continue
            }
            
            // Strings '...' or "..." or `...`
            if c == 39 || c == 34 || c == 96 {
                let quote = c
                let start = i
                i += 1
                while i < len {
                    let qc = ns.character(at: i)
                    if qc == 92 /* \ */ && i + 1 < len {
                        i += 2
                        continue
                    }
                    if qc == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(Token(text: ns.substring(with: NSRange(location: start, length: i - start)), type: .literal))
                continue
            }
            
            // Words / Identifiers / Numbers
            let isWordChar = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.")).contains(UnicodeScalar(c)!)
            if isWordChar {
                let start = i
                while i < len {
                    let wc = ns.character(at: i)
                    if CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.")).contains(UnicodeScalar(wc)!) {
                        i += 1
                    } else {
                        break
                    }
                }
                tokens.append(Token(text: ns.substring(with: NSRange(location: start, length: i - start)), type: .word))
                continue
            }
            
            // Symbols / Operators
            tokens.append(Token(text: ns.substring(with: NSRange(location: i, length: 1)), type: .symbol))
            i += 1
        }
        
        return tokens
    }
}
