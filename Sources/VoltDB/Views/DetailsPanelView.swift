import SwiftUI
import AppKit

@MainActor
struct DetailsPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabState.self) private var tabState
    @Environment(SchemaState.self) private var schemaState
    
    var onClose: () -> Void
    
    @State private var searchText: String = ""
    @State private var copiedFieldName: String? = nil
    
    private var activeResult: QueryResult? {
        tabState.activeTab?.result
    }
    
    private var selectedRow: [QueryResult.CellValue]? {
        guard let res = activeResult, !res.rows.isEmpty else { return nil }
        let index = tabState.selectedRowIndex ?? 0
        if index >= 0 && index < res.rows.count {
            return res.rows[index]
        }
        return res.rows.first
    }
    
    private var columns: [QueryResult.ColumnHeader] {
        activeResult?.columns ?? []
    }
    
    private var fieldItems: [FieldItem] {
        guard let row = selectedRow else { return [] }
        var items: [FieldItem] = []
        for (i, col) in columns.enumerated() {
            let val = i < row.count ? row[i] : .null
            let isPk = isPrimaryKey(col.name)
            let typeLabel = inferTypeLabel(name: col.name, val: val)
            items.append(FieldItem(
                id: i,
                name: col.name,
                value: val,
                typeLabel: typeLabel,
                isPrimaryKey: isPk
            ))
        }
        return items
    }
    
    private var filteredItems: [FieldItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return fieldItems }
        return fieldItems.filter {
            $0.name.lowercased().contains(query) ||
            $0.value.description.lowercased().contains(query) ||
            $0.typeLabel.lowercased().contains(query)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Header: Blue "Details" Pill tab + Close button
            HStack {
                HStack(spacing: 0) {
                    Text("Details")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#007AFF"))
                        .cornerRadius(6)
                }
                
                Spacer()
                
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Details")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "#1e1e24"))
            
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8e8e93"))
                
                TextField("Search fields...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: "#2c2c34"))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(Color(hex: "#1e1e24"))
            
            // Sub-header: Fields count
            HStack {
                Text("Fields")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#a1a1aa"))
                
                Spacer()
                
                Text("\(filteredItems.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#a1a1aa"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color(hex: "#18181e"))
            
            Divider()
                .background(Color(hex: "#2c2c36"))
            
            // Content List
            if let _ = selectedRow, !fieldItems.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            fieldRow(for: item)
                        }
                    }
                    .padding(12)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#18181e"))
    }
    
    // MARK: - Field Row View
    
    @ViewBuilder
    private func fieldRow(for item: FieldItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Label & Type badge
            HStack(spacing: 6) {
                if item.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#facc15")) // yellow key
                }
                
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#e4e4e7"))
                
                Spacer()
                
                // Type pill badge (e.g. number, date, string)
                Text(item.typeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#a1a1aa"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#272730"))
                    .cornerRadius(8)
            }
            
            // Value Box
            valueBox(for: item)
        }
    }
    
    // MARK: - Value Box
    
    @ViewBuilder
    private func valueBox(for item: FieldItem) -> some View {
        let isJson = isJSONString(item.value.description)
        let isNull = item.value.isNull
        
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: isJson ? .bottomTrailing : .trailing) {
                HStack(alignment: isJson ? .top : .center, spacing: 6) {
                    if isNull {
                        Text("NULL")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .italic()
                            .foregroundColor(Color(hex: "#71717a"))
                    } else if isJson, let pretty = prettifyJSON(item.value.description) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(pretty)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(hex: "#f9a8d4"))
                                .textSelection(.enabled)
                                .lineSpacing(2)
                                .padding(.bottom, 16)
                        }
                    } else {
                        Text(item.value.description)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(Color(hex: "#f4f4f5"))
                            .lineLimit(isJson ? nil : 4)
                            .textSelection(.enabled)
                    }
                    
                    if !isJson {
                        Spacer(minLength: 4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, isJson ? 8 : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Copy & expand buttons
                HStack(spacing: 6) {
                    Button {
                        copyValue(item.value.description, field: item.name)
                    } label: {
                        Image(systemName: copiedFieldName == item.name ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(copiedFieldName == item.name ? Color(hex: "#22c55e") : Color(hex: "#71717a"))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy Value")
                }
                .padding(.trailing, 8)
                .padding(.bottom, isJson ? 6 : 0)
            }
            .background(Color(hex: "#22222a"))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(hex: "#2e2e38"), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundColor(Color(hex: "#52525b"))
            Text("No Row Selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#a1a1aa"))
            Text("Select a row in the results table to view all its field details.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#71717a"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }
    
    // MARK: - Helpers
    
    private func copyValue(_ val: String, field: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(val, forType: .string)
        copiedFieldName = field
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedFieldName == field {
                copiedFieldName = nil
            }
        }
    }
    
    private func isPrimaryKey(_ colName: String) -> Bool {
        let lower = colName.lowercased()
        if lower == "id" || lower.hasSuffix("_id") && lower == "id" { return true }
        
        if let tab = tabState.activeTab, let table = tab.tableName {
            let db = tab.database
            if let cols = schemaState.columnsByTable[table] ?? schemaState.columnsByTable["\(db).\(table)"] {
                if let matched = cols.first(where: { $0.lowercased() == lower }) {
                    // Check if PK
                    return matched.lowercased() == "id"
                }
            }
        }
        return false
    }
    
    private func inferTypeLabel(name: String, val: QueryResult.CellValue) -> String {
        let lowerName = name.lowercased()
        
        switch val {
        case .int:
            return "number"
        case .double:
            return "number"
        case .null:
            if lowerName.contains("date") || lowerName.hasSuffix("_at") || lowerName.hasSuffix("_on") {
                return "date"
            }
            if lowerName.hasSuffix("_id") || lowerName == "id" {
                return "number"
            }
            return "string"
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
                if isJSONString(trimmed) { return "string" }
            }
            if isDateString(trimmed) || lowerName.hasSuffix("_at") || lowerName.hasSuffix("_on") || lowerName.contains("date") {
                return "date"
            }
            if Int64(trimmed) != nil || Double(trimmed) != nil {
                if lowerName.hasSuffix("_id") || lowerName == "id" || lowerName.contains("count") || lowerName.contains("amount") {
                    return "number"
                }
            }
            return "string"
        case .data:
            return "binary"
        }
    }
    
    private func isDateString(_ s: String) -> Bool {
        // e.g. 2021-08-03 or 2021-08-03 19:50:54
        if s.count >= 10 && s[s.index(s.startIndex, offsetBy: 4)] == "-" {
            return true
        }
        return false
    }
    
    private func isJSONString(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return false
        }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }
    
    private func prettifyJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyStr = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyStr
    }
}

// MARK: - Models

struct FieldItem: Identifiable {
    let id: Int
    let name: String
    let value: QueryResult.CellValue
    let typeLabel: String
    let isPrimaryKey: Bool
}
