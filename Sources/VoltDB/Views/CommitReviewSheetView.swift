import SwiftUI

/// Modal sheet for reviewing and editing SQL generated from staged changes before executing.
struct CommitReviewSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(SchemaState.self) private var schemaState
    
    let initialSQL: String
    let database: String
    let tableName: String?
    let changeCount: Int
    
    let onApply: (String) async throws -> Void
    let onCancel: () -> Void
    
    @State private var editableSQL: String
    @State private var isExecuting: Bool = false
    @State private var errorMessage: String? = nil
    
    init(
        initialSQL: String,
        database: String,
        tableName: String? = nil,
        changeCount: Int,
        onApply: @escaping (String) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSQL = initialSQL
        self.database = database
        self.tableName = tableName
        self.changeCount = changeCount
        self.onApply = onApply
        self.onCancel = onCancel
        self._editableSQL = State(initialValue: initialSQL)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Changes to Commit")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    HStack(spacing: 6) {
                        Text("\(changeCount) staged \(changeCount == 1 ? "change" : "changes")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        if !database.isEmpty {
                            Text("•")
                                .foregroundColor(AppTheme.textMuted)
                            Text("DB: \(database)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppTheme.accentLight)
                        }
                        
                        if let tbl = tableName, !tbl.isEmpty {
                            Text("•")
                                .foregroundColor(AppTheme.textMuted)
                            Text("Table: \(tbl)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                if editableSQL != initialSQL {
                    Button {
                        editableSQL = initialSQL
                        errorMessage = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset SQL")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accentLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Revert SQL edits back to generated statements")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.backgroundSecondary)
            
            Divider()
            
            // Instruction bar
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textMuted)
                Text("Review the SQL statements below. You can modify the query before executing; only the final edited SQL will be applied.")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.backgroundTertiary.opacity(0.5))
            
            // Error banner if execution failed
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.error)
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.error.opacity(0.18))
                .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.error.opacity(0.4)), alignment: .bottom)
            }
            
            Divider()
            
            // SQL Editor Area
            VStack(alignment: .leading, spacing: 0) {
                SQLEditorView(
                    text: $editableSQL,
                    databaseNames: schemaState.databases.map(\.name)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer Action Buttons
            HStack(spacing: 12) {
                Text(editableSQL != initialSQL ? "• Edited" : "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#eab308"))
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.backgroundTertiary)
                .foregroundColor(AppTheme.textPrimary)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
                .disabled(isExecuting)
                
                Button {
                    executeChanges()
                } label: {
                    HStack(spacing: 6) {
                        if isExecuting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                        }
                        Text(isExecuting ? "Executing..." : "Apply Changes (⌘↩)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(AppTheme.success)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(isExecuting || editableSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.backgroundSecondary)
        }
        .frame(width: 660, height: 460)
        .background(AppTheme.backgroundPrimary)
        .onAppear {
            if editableSQL.isEmpty || editableSQL != initialSQL {
                editableSQL = initialSQL
            }
        }
        .onChange(of: initialSQL) { _, newSQL in
            editableSQL = newSQL
        }
    }
    
    private func executeChanges() {
        let trimmedSQL = editableSQL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSQL.isEmpty else { return }
        
        isExecuting = true
        errorMessage = nil
        
        Task {
            do {
                try await onApply(trimmedSQL)
                await MainActor.run {
                    self.isExecuting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = ErrorFormatter.format(error)
                    self.isExecuting = false
                }
            }
        }
    }
}
