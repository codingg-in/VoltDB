import Foundation
import Observation

enum TabType {
    case query
    case tableView
}

struct EditorTab: Identifiable {
    let id: UUID
    var title: String
    var type: TabType
    var queryText: String
    var database: String
    var tableName: String?
    var result: QueryResult?
    var isLoading: Bool
    var stagedChanges: StagedChanges
    
    init(id: UUID = UUID(), title: String, type: TabType, queryText: String = "", database: String = "", tableName: String? = nil, result: QueryResult? = nil, isLoading: Bool = false, stagedChanges: StagedChanges = StagedChanges()) {
        self.id = id
        self.title = title
        self.type = type
        self.queryText = queryText
        self.database = database
        self.tableName = tableName
        self.result = result
        self.isLoading = isLoading
        self.stagedChanges = stagedChanges
    }
}

@Observable
class TabState {
    var tabs: [EditorTab] = []
    var activeTabId: UUID? = nil
    private var queryCounter: Int = 1
    var currentConnectionId: UUID? = nil
    
    init() {}
    
    var activeTab: EditorTab? {
        get {
            guard let id = activeTabId else { return nil }
            return tabs.first(where: { $0.id == id })
        }
        set {
            if let newValue = newValue, let index = tabs.firstIndex(where: { $0.id == newValue.id }) {
                tabs[index] = newValue
                saveSession()
            }
        }
    }
    
    func restoreSession(for connectionId: UUID?, defaultDatabase: String = "") {
        self.currentConnectionId = connectionId
        if let saved = TabSessionStore.shared.loadSession(connectionId: connectionId), !saved.tabs.isEmpty {
            self.tabs = saved.tabs.map { pt in
                EditorTab(
                    id: pt.id,
                    title: pt.title,
                    type: pt.type == "tableView" ? .tableView : .query,
                    queryText: pt.queryText,
                    database: pt.database,
                    tableName: pt.tableName,
                    stagedChanges: StagedChanges()
                )
            }
            self.queryCounter = max(saved.queryCounter, tabs.count + 1)
            self.activeTabId = saved.activeTabId ?? tabs.first?.id
        } else {
            // First time: initialize with Query 1
            if tabs.isEmpty {
                addNewQueryTab(database: defaultDatabase)
            }
        }
    }
    
    private func saveSession() {
        TabSessionStore.shared.saveSession(
            tabs: tabs,
            activeTabId: activeTabId,
            queryCounter: queryCounter,
            connectionId: currentConnectionId
        )
    }
    
    func addNewQueryTab(database: String = "") {
        let title = "Query \(queryCounter)"
        queryCounter += 1
        
        let newTab = EditorTab(title: title, type: .query, database: database, stagedChanges: StagedChanges())
        tabs.append(newTab)
        activeTabId = newTab.id
        saveSession()
    }
    
    func addTableViewTab(database: String, table: String) {
        if let existingTab = tabs.first(where: { $0.type == .tableView && $0.database == database && $0.tableName == table }) {
            activeTabId = existingTab.id
            saveSession()
            return
        }
        
        let newTab = EditorTab(title: table, type: .tableView, database: database, tableName: table, stagedChanges: StagedChanges())
        tabs.append(newTab)
        activeTabId = newTab.id
        saveSession()
    }
    
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        tabs.remove(at: index)
        
        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }
        }
        saveSession()
    }
    
    func setActiveTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            activeTabId = id
            saveSession()
        }
    }
    
    func updateQueryText(for tabId: UUID, text: String) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].queryText = text
            saveSession()
        }
    }
    
    func setResult(for tabId: UUID, result: QueryResult) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].result = result
        }
    }
    
    func setLoading(for tabId: UUID, loading: Bool) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].isLoading = loading
        }
    }
}
