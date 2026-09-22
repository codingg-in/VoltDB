import SwiftUI
import AppKit

struct ConnectionManagerView: View {
    @State private var appState = AppState()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    
    @State private var searchText: String = ""
    @State private var selectedConnectionId: UUID? = nil
    @State private var isCreatingNew: Bool = false
    @State private var editingConfig = ConnectionConfig(
        id: UUID(),
        name: "MySQL Connection",
        host: "127.0.0.1",
        port: 3306,
        user: "root",
        database: "",
        colorHex: "#3b82f6",
        useSSL: false,
        isProduction: false
    )
    @State private var password = ""
    @State private var isConnecting = false
    @State private var connectionErrorMessage: String? = nil
    
    // Master Password Vault State
    @State private var vaultStore = VaultStore.shared
    @State private var isShowingUnlockVaultSheet = false
    @State private var isShowingVaultSettingsSheet = false
    @State private var isShowingResetConfirmation = false
    @State private var masterPasswordInput = ""
    @State private var masterPasswordConfirmInput = ""
    @State private var oldMasterPasswordInput = ""
    @State private var vaultErrorMessage: String? = nil
    
    init() {}
    
    private var appVersionString: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return "v\(version)"
        }
        return "v0.1.0"
    }
    
    private var filteredConnections: [ConnectionConfig] {
        if searchText.isEmpty {
            return appState.savedConnections
        }
        let query = searchText.lowercased()
        return appState.savedConnections.filter { conn in
            conn.name.lowercased().contains(query) ||
            conn.host.lowercased().contains(query) ||
            conn.user.lowercased().contains(query) ||
            conn.database.lowercased().contains(query)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Header (Spacious & Vertically Centered with Traffic Lights)
            HStack(spacing: 9) {
                // Traffic light clearance
                Spacer()
                    .frame(width: 70)
                
                AppLogoView(size: 21)
                
                Text("VoltDB Connection Manager")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(appVersionString)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AppTheme.border.opacity(0.35), lineWidth: 1)
                    )
                
                if isConnecting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(AppTheme.accent)
                    }
                    .padding(.leading, 8)
                }
                
                Spacer()
                
                // Vault Status Button
                if vaultStore.hasVault && !vaultStore.isUnlocked {
                    Button {
                        vaultErrorMessage = nil
                        masterPasswordInput = ""
                        isShowingUnlockVaultSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#F59E0B"))
                            Text("Unlock Vault")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#FBBF24"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#F59E0B").opacity(0.18))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(hex: "#F59E0B").opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Unlock Vault to access saved passwords")
                } else if vaultStore.hasVault && vaultStore.isUnlocked {
                    VaultUnlockedMenuButton(
                        onLock: {
                            vaultStore.lock()
                            password = ""
                        },
                        onChangePassword: {
                            vaultErrorMessage = nil
                            oldMasterPasswordInput = ""
                            masterPasswordInput = ""
                            masterPasswordConfirmInput = ""
                            isShowingVaultSettingsSheet = true
                        },
                        onReset: {
                            isShowingResetConfirmation = true
                        }
                    )
                } else {
                    Button {
                        vaultErrorMessage = nil
                        masterPasswordInput = ""
                        masterPasswordConfirmInput = ""
                        isShowingVaultSettingsSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                            Text("Setup Vault")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.border.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Set a master password to encrypt connection passwords")
                }
                
                if appState.connectionStatus == .connected {
                    Button {
                        appState.isShowingConnectionManager = false
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left")
                            Text("Back to Workspace")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(AppTheme.backgroundSecondary)
            
            Divider()
            
            // Error banner if connection failed
            if let errorMsg = connectionErrorMessage {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.error)
                        .font(.subheadline)
                    
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    Button {
                        connectTo(editingConfig, customPassword: password)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        connectionErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(AppTheme.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(AppTheme.error.opacity(0.4), lineWidth: 1)
                )
            }
            
            // Main Body: Left List (250px) + Right Form
            HStack(spacing: 0) {
                // Left Connections Sidebar
                VStack(spacing: 0) {
                    // Search box for saved connections
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        
                        TextField("Search connections...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
                    .padding(8)
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            let conns = filteredConnections
                            if conns.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "server.rack")
                                        .font(.title2)
                                        .foregroundColor(AppTheme.textMuted)
                                    Text(appState.savedConnections.isEmpty ? "No Saved Connections" : "No Matching Connections")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                            } else {
                                ForEach(conns) { conn in
                                    connectionRow(conn)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    
                    Divider()
                    
                    HStack {
                        Button {
                            createNewConnection()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AppTheme.accent)
                                    .font(.system(size: 13))
                                Text("New Connection")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                }
                .frame(width: 250)
                .background(AppTheme.backgroundSecondary)
                
                Divider()
                
                // Right Pane: Form (if connection selected or creating new) or Empty State Placeholder
                if selectedConnectionId != nil || isCreatingNew || appState.savedConnections.isEmpty {
                    ConnectionFormView(
                        config: $editingConfig,
                        password: $password,
                        onSave: {
                            selectedConnectionId = editingConfig.id
                            isCreatingNew = false
                        },
                        onDelete: {
                            appState.deleteConnection(id: editingConfig.id)
                            selectedConnectionId = nil
                            isCreatingNew = false
                        },
                        onConnect: { cfg, pass in
                            connectTo(cfg, customPassword: pass)
                        }
                    )
                    .environment(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.textMuted.opacity(0.6))
                        
                        Text("No Connection Selected")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Select a saved connection from the left list to view or edit details, or create a new connection.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button {
                            createNewConnection()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("New Connection")
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.backgroundPrimary)
                }
            }
        }
        .ignoresSafeArea()
        .frame(width: 820, height: 575)
        .background(AppTheme.backgroundPrimary)
        .sheet(isPresented: $isShowingUnlockVaultSheet) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Credentials Vault")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Enter your Master Password to access saved connection secrets.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
                
                if let error = vaultErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                SecureField("Master Password", text: $masterPasswordInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        unlockVaultAction()
                    }
                
                HStack {
                    Button("Cancel") {
                        isShowingUnlockVaultSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Reset Vault...", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                    
                    Spacer()
                    
                    Button("Unlock") {
                        unlockVaultAction()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(masterPasswordInput.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(AppTheme.backgroundPrimary)
            .alert("Reset Credentials Vault?", isPresented: $isShowingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset & Delete Passwords", role: .destructive) {
                    vaultStore.resetVault()
                    isShowingUnlockVaultSheet = false
                    vaultErrorMessage = nil
                    password = ""
                }
            } message: {
                Text("Are you sure you want to reset the vault? All saved encrypted database passwords and SSH passphrases will be permanently deleted from disk. You can configure a new Master Password afterwards.")
            }
        }
        .sheet(isPresented: $isShowingVaultSettingsSheet) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vaultStore.hasVault ? "Change Master Password" : "Set Master Password")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                        Text("All saved database credentials will be encrypted with AES-256-GCM.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
                
                if let error = vaultErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                VStack(spacing: 10) {
                    if vaultStore.hasVault {
                        SecureField("Current Master Password", text: $oldMasterPasswordInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    SecureField("New Master Password", text: $masterPasswordInput)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Confirm New Master Password", text: $masterPasswordConfirmInput)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Button("Cancel") {
                        isShowingVaultSettingsSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button(vaultStore.hasVault ? "Update Password" : "Create Vault") {
                        saveMasterPasswordAction()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(masterPasswordInput.isEmpty || masterPasswordInput != masterPasswordConfirmInput)
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(AppTheme.backgroundPrimary)
        }
        .alert("Reset Credentials Vault?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Delete Passwords", role: .destructive) {
                vaultStore.resetVault()
                isShowingUnlockVaultSheet = false
                vaultErrorMessage = nil
                password = ""
            }
        } message: {
            Text("Are you sure you want to reset the vault? All saved encrypted database passwords and SSH passphrases will be permanently deleted from disk. You can configure a new Master Password afterwards.")
        }
        .onAppear {
            (NSApp.delegate as? AppDelegate)?.openLauncherWindow = {
                openWindow(id: "launcher")
            }
            setupConnectionManagerWindow()
            selectedConnectionId = nil
            isCreatingNew = false
            if appState.savedConnections.isEmpty {
                createNewConnection()
            }
            if vaultStore.hasVault && !vaultStore.isUnlocked {
                vaultErrorMessage = nil
                masterPasswordInput = ""
                isShowingUnlockVaultSheet = true
            }
        }
    }
    
    private func unlockVaultAction() {
        if vaultStore.unlock(masterPassword: masterPasswordInput) {
            isShowingUnlockVaultSheet = false
            vaultErrorMessage = nil
            if let selected = selectedConnectionId,
               let conn = appState.savedConnections.first(where: { $0.id == selected }) {
                selectConnection(conn)
            }
        } else {
            vaultErrorMessage = "Incorrect Master Password. Please try again."
        }
    }
    
    private func saveMasterPasswordAction() {
        guard masterPasswordInput == masterPasswordConfirmInput else {
            vaultErrorMessage = "Passwords do not match."
            return
        }
        do {
            if vaultStore.hasVault {
                try vaultStore.changeMasterPassword(oldPassword: oldMasterPasswordInput, newPassword: masterPasswordInput)
            } else {
                try vaultStore.createVault(masterPassword: masterPasswordInput)
            }
            isShowingVaultSettingsSheet = false
            vaultErrorMessage = nil
        } catch {
            vaultErrorMessage = error.localizedDescription
        }
    }
    
    private func setupConnectionManagerWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && ($0.title == "VoltDB Connection Manager" || $0.title == "VoltDB")
            }) else { return }
            
            let targetSize = NSSize(width: 820, height: 575)
            window.setContentSize(targetSize)
            window.minSize = targetSize
            window.maxSize = targetSize
            window.center()
            
            window.styleMask.remove([.resizable, .miniaturizable])
            window.showsResizeIndicator = false
            
            // Hide & disable zoom (green) and miniaturize (yellow)
            if let zoom = window.standardWindowButton(.zoomButton) {
                zoom.isHidden = true
                zoom.isEnabled = false
            }
            if let mini = window.standardWindowButton(.miniaturizeButton) {
                mini.isHidden = true
                mini.isEnabled = false
            }
            
            window.title = "VoltDB Connection Manager"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
    }
    
    @ViewBuilder
    private func connectionRow(_ conn: ConnectionConfig) -> some View {
        let isSelected = selectedConnectionId == conn.id
        let isThisConnecting = isConnecting && selectedConnectionId == conn.id
        
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                if isThisConnecting {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else {
                    Circle()
                        .fill(conn.color)
                        .frame(width: 10, height: 10)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(conn.name)
                            .font(.subheadline.bold())
                            .foregroundColor(isSelected ? .white : AppTheme.textPrimary)
                            .lineLimit(1)
                        if conn.isProduction {
                            Text("PROD")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.cornerRadius(3))
                        }
                    }
                    Text(conn.displaySubtitle)
                        .font(.caption2)
                        .foregroundColor(isSelected ? Color.white.opacity(0.8) : AppTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                connectTo(conn)
            }
            .onTapGesture(count: 1) {
                selectConnection(conn)
            }
            
            // Delete trash button
            Button {
                appState.deleteConnection(id: conn.id)
                if selectedConnectionId == conn.id {
                    if let first = appState.savedConnections.first {
                        selectConnection(first)
                    } else {
                        createNewConnection()
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : AppTheme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Delete connection")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? AppTheme.accent : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Connect") {
                connectTo(conn)
            }
            Button("Duplicate") {
                duplicateConnection(conn)
            }
            Divider()
            Button("Delete", role: .destructive) {
                appState.deleteConnection(id: conn.id)
                if selectedConnectionId == conn.id {
                    createNewConnection()
                }
            }
        }
    }
    
    private func selectConnection(_ conn: ConnectionConfig) {
        selectedConnectionId = conn.id
        isCreatingNew = false
        var loaded = conn
        loaded.sshPassphrase = VaultStore.shared.retrieveSSHPassphrase(for: conn.id) ?? conn.sshPassphrase
        editingConfig = loaded
        password = VaultStore.shared.retrieve(for: conn.id) ?? ""
        connectionErrorMessage = nil
    }
    
    private func connectTo(_ conn: ConnectionConfig, customPassword: String? = nil) {
        selectConnection(conn)
        let pass = customPassword ?? (VaultStore.shared.retrieve(for: conn.id) ?? password)
        password = pass
        appState.saveConnection(conn, password: pass)
        
        isConnecting = true
        connectionErrorMessage = nil
        
        Task {
            let res = await appState.testConnection(config: conn, password: pass)
            
            await MainActor.run {
                isConnecting = false
                switch res {
                case .success:
                    // Successfully tested connection, open the workspace window
                    openWindow(value: conn.id)
                    
                    // Post notification to ensure workspace connects even if window was previously opened & closed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .connectToWorkspace, object: conn.id)
                    }
                    
                    // Close the manager window
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        for window in NSApp.windows {
                            if window.title == "VoltDB Connection Manager" || window.title == "VoltDB" {
                                if window.frame.width <= 850 {
                                    window.close()
                                }
                            }
                        }
                    }
                case .failure(let err):
                    let formatted = ErrorFormatter.format(err, host: conn.host, port: conn.port)
                    connectionErrorMessage = formatted
                }
            }
        }
    }
    
    private func createNewConnection() {
        selectedConnectionId = nil
        isCreatingNew = true
        connectionErrorMessage = nil
        let uniqueName = ConnectionStore.shared.generateUniqueName(base: "MySQL Connection")
        let randomPreset = ConnectionConfig.presetColors.randomElement()?.hex ?? "#3b82f6"
        editingConfig = ConnectionConfig(
            id: UUID(),
            name: uniqueName,
            host: "127.0.0.1",
            port: 3306,
            user: "root",
            database: "",
            colorHex: randomPreset,
            useSSL: false,
            isProduction: false
        )
        password = ""
    }
    
    private func duplicateConnection(_ conn: ConnectionConfig) {
        var copy = conn
        copy.id = UUID()
        copy.name = ConnectionStore.shared.generateUniqueName(base: "\(conn.name) Copy")
        let pass = VaultStore.shared.retrieve(for: conn.id) ?? ""
        copy.sshPassphrase = VaultStore.shared.retrieveSSHPassphrase(for: conn.id) ?? conn.sshPassphrase
        appState.saveConnection(copy, password: pass)
        selectConnection(copy)
    }
}

struct VaultUnlockedMenuButton: View {
    var onLock: () -> Void
    var onChangePassword: () -> Void
    var onReset: () -> Void
    
    @State private var isShowingMenu = false
    @State private var isHovered = false
    @State private var hoveredItem: String? = nil
    
    var body: some View {
        Button {
            isShowingMenu.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.success)
                Text("Vault Unlocked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovered ? AppTheme.success.opacity(0.20) : AppTheme.success.opacity(0.12))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.success.opacity(0.40), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Vault is unlocked. Click to manage or lock vault.")
        .onHover { hover in
            isHovered = hover
        }
        .popover(isPresented: $isShowingMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    isShowingMenu = false
                    onLock()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.warning)
                            .frame(width: 14)
                        Text("Lock Vault")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(hoveredItem == "lock" ? AppTheme.backgroundHover : Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in hoveredItem = h ? "lock" : nil }
                
                Button {
                    isShowingMenu = false
                    onChangePassword()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 14)
                        Text("Change Password...")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(hoveredItem == "key" ? AppTheme.backgroundHover : Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in hoveredItem = h ? "key" : nil }
                
                Divider()
                    .padding(.vertical, 2)
                
                Button {
                    isShowingMenu = false
                    onReset()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.error)
                            .frame(width: 14)
                        Text("Reset Vault...")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.error)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(hoveredItem == "reset" ? AppTheme.error.opacity(0.12) : Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in hoveredItem = h ? "reset" : nil }
            }
            .padding(5)
            .frame(width: 175)
            .background(AppTheme.backgroundSecondary)
        }
    }
}


