import SwiftUI

struct ResultsPanelView: View {
    var result: QueryResult?
    var isLoading: Bool
    var isEditable: Bool = true
    var onCellEdit: ((Int, Int, QueryResult.CellValue) -> Void)? = nil
    var tableName: String? = nil
    
    var body: some View {
        ZStack {
            AppTheme.backgroundPrimary.edgesIgnoringSafeArea(.all)
            
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Executing query...")
                        .foregroundColor(AppTheme.textSecondary)
                }
            } else if let result = result {
                if result.isError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.error)
                            .font(.system(size: 28))
                        Text("Query Execution Failed")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                        Text(result.error ?? "Unknown Error")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .textSelection(.enabled)
                        
                        Button {
                            NotificationCenter.default.post(name: .runQuery, object: nil)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry Query (⌘↩)")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(AppTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                } else if result.hasRows {
                    DataGridView(
                        columns: result.columns,
                        rows: result.rows,
                        isEditable: isEditable,
                        onCellEdit: onCellEdit,
                        tableName: tableName
                    )
                } else if result.queryType == .select {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .foregroundColor(AppTheme.textMuted)
                            .font(.system(size: 48))
                        Text("No rows returned")
                            .foregroundColor(AppTheme.textPrimary)
                            .font(.system(size: 24, weight: .bold))
                        Text(String(format: "Execution time: %.3fs", result.executionTime))
                            .foregroundColor(AppTheme.textSecondary)
                            .font(.system(size: 13))
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 24))
                        Text("Query executed successfully. \(result.affectedRows) row(s) affected.")
                            .foregroundColor(AppTheme.textPrimary)
                        Text(String(format: "Execution time: %.3fs", result.executionTime))
                            .foregroundColor(AppTheme.textSecondary)
                            .font(.caption)
                    }
                }
            } else {
                Text("Run a query to see results")
                    .foregroundColor(AppTheme.textMuted)
            }
        }
    }
}
