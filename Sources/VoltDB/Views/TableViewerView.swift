import SwiftUI

enum SubTab: String, CaseIterable {
    case data = "Data"
    case structure = "Structure"
}

struct TableViewerView: View {
    var database: String
    var tableName: String
    
    @State private var selectedSubTab: SubTab = .data
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.accent)
                    Text("\(database).\(tableName)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                Picker("", selection: $selectedSubTab) {
                    ForEach(SubTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 180)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.backgroundSecondary)
            
            Divider()
            
            switch selectedSubTab {
            case .data:
                TableDataView(database: database, tableName: tableName)
            case .structure:
                TableStructureView(database: database, tableName: tableName)
            }
        }
        .background(AppTheme.backgroundPrimary)
    }
}
