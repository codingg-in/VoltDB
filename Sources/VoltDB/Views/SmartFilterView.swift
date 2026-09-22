import SwiftUI

struct SmartFilterView: View {
    @Binding var filters: [FilterCondition]
    var columns: [String]
    var onApply: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                        .foregroundColor(filters.isEmpty ? AppTheme.textMuted : AppTheme.accent)
                    
                    Text("Filter:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                if filters.isEmpty {
                    Button {
                        addFilter()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("Add Filter Condition")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(0..<filters.count, id: \.self) { index in
                        HStack(spacing: 4) {
                            // Column Picker
                            Picker("", selection: $filters[index].column) {
                                ForEach(columns, id: \.self) { col in
                                    Text(col).tag(col)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 90)
                            
                            // Operator Picker
                            Picker("", selection: $filters[index].op) {
                                ForEach(FilterCondition.FilterOperator.allCases, id: \.self) { op in
                                    Text(op.rawValue).tag(op)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                            
                            // Value TextField (hidden for IS NULL / IS NOT NULL)
                            if filters[index].op != .isNull && filters[index].op != .isNotNull {
                                TextField("value...", text: $filters[index].value)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.backgroundPrimary)
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border.opacity(0.8), lineWidth: 1))
                                    .frame(width: 120)
                                    .onSubmit {
                                        onApply()
                                    }
                            }
                            
                            // Remove filter condition button
                            Button {
                                filters.remove(at: index)
                                if filters.isEmpty {
                                    onApply()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
                    }
                    
                    // Add more condition button
                    Button {
                        addFilter()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Add another condition")
                    
                    // Apply button
                    Button {
                        onApply()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("Apply")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    // Clear button
                    Button {
                        filters.removeAll()
                        onApply()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(AppTheme.backgroundSecondary)
    }
    
    private func addFilter() {
        let defaultCol = columns.first ?? "id"
        filters.append(FilterCondition(column: defaultCol, op: .equals, value: ""))
    }
}
