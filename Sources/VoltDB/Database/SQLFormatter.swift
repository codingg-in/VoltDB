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
                    currentLine += "( "
                } else if token.text == ")" {
                    currentLine = currentLine.trimmingCharacters(in: .whitespaces) + " ) "
                } else {
                    currentLine += token.text + " "
                }
            case .literal, .comment:
                currentLine += token.text + " "
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
            
            // Skip whitespace
            if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(c)!) {
                i += 1
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
