import SwiftUI

struct EditorToolbarView: View {
    let currentDatabase: String
    let queryText: String
    let isLoading: Bool
    var onClear: (() -> Void)? = nil
    var onExplain: ((String) -> Void)? = nil
    
    init(
        currentDatabase: String,
        queryText: String,
        isLoading: Bool,
        onClear: (() -> Void)? = nil,
        onExplain: ((String) -> Void)? = nil
    ) {
        self.currentDatabase = currentDatabase
        self.queryText = queryText
        self.isLoading = isLoading
        self.onClear = onClear
        self.onExplain = onExplain
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Left: Database Name with Icon
            HStack(spacing: 5) {
                Image(systemName: "cylinder")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                
                Text(currentDatabase.isEmpty ? "No database" : currentDatabase)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
            
            Spacer(minLength: 16)
            
            // Right Side Action Buttons: Trash -> Formatter -> Star -> Divider -> Explain -> Execute
            HStack(spacing: 6) {
                // 1. Trash / Clear Query Editor
                Button {
                    onClear?()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear Editor")
                
                // 2. Format SQL
                Button {
                    NotificationCenter.default.post(name: .formatSQL, object: nil)
                } label: {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Format SQL (⇧⌘I)")
                
                // 3. Save / Star Query
                Button {
                    NotificationCenter.default.post(name: .formatSQL, object: nil)
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Save / Favorite Query")
                
                // Vertical Separator
                Rectangle()
                    .fill(AppTheme.border.opacity(0.35))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)
                
                // 4. Explain Dropdown
                Menu {
                    Button("EXPLAIN (Execution Plan)") {
                        onExplain?("")
                    }
                    Button("EXPLAIN ANALYZE (Actual Runtime)") {
                        onExplain?("ANALYZE")
                    }
                    Button("EXPLAIN FORMAT=JSON (JSON Plan)") {
                        onExplain?("FORMAT=JSON")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                        Text("Explain")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border.opacity(0.4), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Explain SQL Query")
                
                // 5. Execute Action Button (Blue Highlighted)
                HStack(spacing: 0) {
                    Button {
                        NotificationCenter.default.post(name: .runCurrentQuery, object: nil)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Execute")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                        .padding(.trailing, 6)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 13)
                    
                    Menu {
                        Button("Execute Current (⌘↩)") {
                            NotificationCenter.default.post(name: .runCurrentQuery, object: nil)
                        }
                        Button("Execute All (⌃⇧⌘↩)") {
                            NotificationCenter.default.post(name: .runAllQueries, object: nil)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .background(Color(hex: "#2563eb"))
                .cornerRadius(4)
                .shadow(color: Color(hex: "#2563eb").opacity(0.3), radius: 2, x: 0, y: 1)
                .disabled(isLoading)
                .opacity(isLoading ? 0.6 : 1.0)
                .help("Execute Current Query (⌘↩) / Execute All (⌃⇧⌘↩)")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(hex: "#181825"))
        .overlay(
            Rectangle()
                .fill(AppTheme.border.opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
