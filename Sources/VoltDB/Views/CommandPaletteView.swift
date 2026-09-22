import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @Environment(SchemaState.self) private var schemaState
    @Environment(TabState.self) private var tabState
    
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    private var filteredTables: [TableInfo] {
        var allTables: [TableInfo] = []
        for db in schemaState.databases {
            if let tables = schemaState.tablesByDatabase[db.name] {
                allTables.append(contentsOf: tables)
            }
        }
        
        if searchText.isEmpty {
            return allTables
        } else {
            let lowercasedSearch = searchText.lowercased()
            return allTables.filter { $0.name.lowercased().contains(lowercasedSearch) }
        }
    }
    
    var body: some View {
        ZStack {
            if isPresented {
                // Semi-transparent overlay
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }
                
                // Centered card
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.textMuted)
                        TextField("Search tables, views...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .focused($isSearchFocused)
                            .font(.system(size: 18))
                            .onChange(of: searchText) { _, _ in
                                selectedIndex = 0
                            }
                    }
                    .padding()
                    
                    Divider()
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                let results = filteredTables
                                ForEach(Array(results.enumerated()), id: \.offset) { index, table in
                                    HStack {
                                        Image(systemName: table.type.icon)
                                            .foregroundColor(AppTheme.textSecondary)
                                        
                                        // Highlight match logic can be expanded, keeping simple bold for now
                                        Text(table.name)
                                            .fontWeight(.bold)
                                            .foregroundColor(AppTheme.textPrimary)
                                        
                                        Spacer()
                                        
                                        Text(table.database)
                                            .foregroundColor(AppTheme.textMuted)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(selectedIndex == index ? AppTheme.accent : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectItem(table)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) { _, newIndex in
                            withAnimation {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: 500)
                .background(AppTheme.backgroundSecondary)
                .cornerRadius(12)
                .shadow(radius: 20)
                .padding()
                .transition(.scale.combined(with: .opacity))
                .onKeyPress(.downArrow) {
                    let maxIndex = filteredTables.count - 1
                    if selectedIndex < maxIndex {
                        selectedIndex += 1
                    }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 {
                        selectedIndex -= 1
                    }
                    return .handled
                }
                .onKeyPress(.return) {
                    let results = filteredTables
                    if !results.isEmpty && selectedIndex < results.count {
                        selectItem(results[selectedIndex])
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
                .onAppear {
                    isSearchFocused = true
                }
            }
        }
        .animation(.spring(), value: isPresented)
    }
    
    private func dismiss() {
        withAnimation {
            isPresented = false
            searchText = ""
        }
    }
    
    private func selectItem(_ table: TableInfo) {
        tabState.addTableViewTab(database: table.database, table: table.name)
        dismiss()
    }
}
