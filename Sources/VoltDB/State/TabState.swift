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
    @MainActor static let activeInstances = NSHashTable<TabState>.weakObjects()
    
    var tabs: [EditorTab] = []
    var activeTabId: UUID? = nil {
        didSet {
            if activeTabId != oldValue {
                saveSession()
            }
        }
    }
    var selectedRowIndex: Int? = nil
    private var queryCounter: Int = 1
    var currentConnectionId: UUID? = nil
    
    init() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                TabState.activeInstances.add(self)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    TabState.activeInstances.add(self)
                }
            }
        }
    }
    
    @MainActor
    static func uncommittedChangesSummary() -> (totalCount: Int, tabsWithChanges: [String]) {
        var total = 0
        var tabNames: [String] = []
        for state in activeInstances.allObjects {
            for tab in state.tabs {
                if tab.stagedChanges.count > 0 {
                    total += tab.stagedChanges.count
                    tabNames.append("\(tab.title) (\(tab.stagedChanges.count))")
                }
            }
        }
        return (total, tabNames)
    }
    
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
        // If already restored for this exact connection and we have tabs, avoid resetting active state
        if self.currentConnectionId == connectionId && !self.tabs.isEmpty {
            return
        }
        
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
            if let savedActive = saved.activeTabId, tabs.contains(where: { $0.id == savedActive }) {
                self.activeTabId = savedActive
            } else {
                self.activeTabId = tabs.first?.id
            }
        } else {
            // First time: initialize with Query 1
            if tabs.isEmpty {
                addNewQueryTab(database: defaultDatabase)
            }
        }
    }
    
    func saveSession() {
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
    
    func selectPreviousTab() {
        guard !tabs.isEmpty, let currentId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        activeTabId = tabs[prevIndex].id
        saveSession()
    }
    
    func selectNextTab() {
        guard !tabs.isEmpty, let currentId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        activeTabId = tabs[nextIndex].id
        saveSession()
    }
    
    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeTabId = tabs[index].id
        saveSession()
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
    
    // MARK: - Running Task Management (for query cancellation)
    
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    
    func setRunningTask(for tabId: UUID, task: Task<Void, Never>) {
        runningTasks[tabId] = task
    }
    
    func cancelRunningTask(for tabId: UUID) {
        runningTasks[tabId]?.cancel()
        runningTasks.removeValue(forKey: tabId)
    }
    
    func clearRunningTask(for tabId: UUID) {
        runningTasks.removeValue(forKey: tabId)
    }
}
