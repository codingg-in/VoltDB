import SwiftUI
import AppKit

enum ConnectionTestResult {
    case success(String)
    case failure(String)
}

struct ConnectionFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    
    @Binding var config: ConnectionConfig
    @Binding var password: String
    var onSave: () -> Void
    var onDelete: () -> Void
    var onConnect: ((ConnectionConfig, String) -> Void)? = nil
    
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var isConnecting = false
    @State private var showPassword = false
    @State private var showDeleteConfirmation = false
    @State private var isRecentlySaved = false
        
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    Divider()
                    generalSection
                    serverSection
                    sshTunnelSection
                }
                .padding(20)
            }
            
            Divider()
            
            actionsSection
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(AppTheme.backgroundSecondary)
        }
        .background(AppTheme.backgroundPrimary)
        .overlay {
            if let result = testResult {
                testResultPopupModal(result)
            }
        }
        .alert("Delete Connection", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(config.name)'?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveConnection)) { _ in
            saveConnection()
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name.isEmpty ? "New Connection" : config.name)
                    .font(.title2.bold())
                    .foregroundColor(AppTheme.textPrimary)
                Text(config.useSSHTunnel ? "MySQL over SSH Tunnel" : "Direct MySQL Connection")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
            
            if let grp = config.displayGroup {
                ConnectionGroupBadge(group: grp, size: .regular)
            }
        }
    }
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GENERAL")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary)
            
            formField(label: "Connection Name") {
                TextField("e.g. Production DB, Staging, Local", text: $config.name)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
            }
            
            // Group Selection Dropdown
            formField(label: "Group") {
                Menu {
                    Button("None (Ungrouped)") {
                        config.setGroup(nil)
                    }
                    if !availableGroups.isEmpty {
                        Divider()
                        ForEach(availableGroups, id: \.self) { grp in
                            Button {
                                config.setGroup(grp)
                            } label: {
                                HStack {
                                    Text(grp)
                                    if config.displayGroup?.caseInsensitiveCompare(grp) == .orderedSame {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        Text(config.displayGroup ?? "None (Ungrouped)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .padding(8)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(16)
        .background(AppTheme.backgroundSecondary)
        .cornerRadius(8)
    }
    
    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DATABASE SERVER")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary)
            
            HStack(spacing: 12) {
                formField(label: "Host") {
                    TextField("127.0.0.1 or db.example.com", text: $config.host)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                }
                
                formField(label: "Port") {
                    TextField("3306", value: $config.port, formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                        .frame(width: 90)
                }
            }
            
            HStack(spacing: 12) {
                formField(label: "User") {
                    TextField("root", text: $config.user)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                }
                
                formField(label: "Password") {
                    HStack {
                        if showPassword {
                            TextField("Password", text: $password)
                                .textFieldStyle(.plain)
                        } else {
                            SecureField("Password", text: $password)
                                .textFieldStyle(.plain)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                }
            }
            
            formField(label: "Default Database") {
                TextField("Optional database name", text: $config.database)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
            }
            
            Toggle("Use SSL / TLS Encryption", isOn: $config.useSSL)
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
            
            if !config.useSSL && config.isRemoteHost && !config.useSSHTunnel {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Unencrypted Connection: Connecting to a remote database without SSL/TLS or an SSH tunnel transmits credentials, queries, and data in cleartext over the network.")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            if config.useSSL {
                formField(label: "CA Certificate Path (optional — for self-signed or private CA)") {
                    HStack {
                        TextField("Leave empty to use system trust store", text: $config.sslCAPath)
                            .textFieldStyle(.plain)
                        
                        Button("Browse...") {
                            selectCACertFile()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.backgroundSecondary)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
                    }
                    .padding(8)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(AppTheme.backgroundSecondary)
        .cornerRadius(8)
    }
    
    // MARK: - SSH Tunnel Section
    
    private var sshTunnelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $config.useSSHTunnel) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(config.useSSHTunnel ? AppTheme.accent : AppTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect via SSH Tunnel")
                            .font(.body.bold())
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Tunnel through a bastion/jump host to reach private database")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(AppTheme.accent)
            
            if config.useSSHTunnel {
                Divider()
                
                HStack(spacing: 12) {
                    formField(label: "SSH Host") {
                        TextField("bastion.example.com", text: $config.sshHost)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                    }
                    
                    formField(label: "SSH Port") {
                        TextField("22", value: $config.sshPort, formatter: NumberFormatter())
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                            .frame(width: 80)
                    }
                }
                
                HStack(spacing: 12) {
                    formField(label: "SSH User") {
                        TextField("ubuntu / ec2-user", text: $config.sshUser)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                    }
                    
                    formField(label: "Auth Method") {
                        Picker("", selection: $config.sshAuthMode) {
                            ForEach(SSHAuthMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .padding(.top, 2)
                    }
                }
                
                if config.sshAuthMode == .keyFile {
                    formField(label: "Private Key Path") {
                        HStack {
                            TextField("~/.ssh/id_rsa", text: $config.sshKeyPath)
                                .textFieldStyle(.plain)
                            
                            Button("Browse...") {
                                selectSSHKeyFile()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppTheme.backgroundSecondary)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
                        }
                        .padding(8)
                        .background(AppTheme.backgroundTertiary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                    }
                    
                    formField(label: "Key Passphrase (Optional if key is encrypted)") {
                        SecureField("Leave empty if no passphrase", text: $config.sshPassphrase)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                    }
                } else if config.sshAuthMode == .password {
                    formField(label: "SSH Password") {
                        SecureField("SSH User Password", text: $config.sshPassphrase)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border, lineWidth: 1))
                    }
                }
                
                Divider()
                
                Toggle("Strict Host Key Checking", isOn: $config.sshStrictHostKeyChecking)
                    .toggleStyle(.switch)
                    .tint(AppTheme.accent)
                
                if !config.sshStrictHostKeyChecking {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Warning: Disabling strict host key checking permits SSH connections to automatically accept new host keys, which increases vulnerability to Man-in-the-Middle (MitM) attacks.")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .background(AppTheme.backgroundSecondary)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func testResultPopupModal(_ result: ConnectionTestResult) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    testResult = nil
                }
            
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(AppTheme.success)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(AppTheme.error)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(resultIsSuccess(result) ? "Connection Succeeded" : "Connection Failed")
                            .font(.headline.bold())
                            .foregroundColor(AppTheme.textPrimary)
                        
                        switch result {
                        case .success(let msg):
                            Text(msg)
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        case .failure(let msg):
                            ScrollView {
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(maxHeight: 180)
                            .background(AppTheme.backgroundPrimary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(AppTheme.border.opacity(0.6), lineWidth: 1)
                            )
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                
                HStack {
                    if case .failure(let msg) = result {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg, forType: .string)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Error")
                            }
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.backgroundTertiary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button("OK") {
                        testResult = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(20)
            .frame(width: 440)
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeInOut(duration: 0.15), value: testResult != nil)
    }
    
    private func resultIsSuccess(_ result: ConnectionTestResult) -> Bool {
        if case .success = result { return true }
        return false
    }
    
    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button {
                testConnection()
            } label: {
                HStack(spacing: 5) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(AppTheme.backgroundTertiary)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isTesting)
            
            // Disconnect button - shown when connected
            if appState.connectionStatus == .connected || appState.activeConnection?.id == config.id {
                Button {
                    Task {
                        await appState.disconnect()
                        await MainActor.run {
                            openWindow(id: "launcher")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if let window = NSApp.windows.first(where: { ($0.isKeyWindow || $0.isMainWindow) && $0.title != "VoltDB Connection Manager" }) {
                                    window.close()
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .bold))
                        Text("Disconnect")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppTheme.error)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(AppTheme.error.opacity(0.12))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.error.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Disconnect from this database")
            }
            
            Spacer()
            
            if appState.savedConnections.contains(where: { $0.id == config.id }) {
                Button("Delete") {
                    showDeleteConfirmation = true
                }
                .font(.system(size: 11))
                .foregroundColor(AppTheme.error)
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            
            Button {
                saveConnection()
            } label: {
                HStack(spacing: 4) {
                    if isRecentlySaved {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.success)
                        Text("Saved")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.success)
                    } else {
                        Text("Save")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(AppTheme.backgroundTertiary)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(isRecentlySaved ? AppTheme.success.opacity(0.8) : AppTheme.border.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            
            if appState.connectionStatus == .connected {
                Button {
                    connectNow()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.system(size: 10))
                        Text("Connect in New Window")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(AppTheme.backgroundTertiary)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            
            Button {
                connectNow()
            } label: {
                HStack(spacing: 5) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.8)
                    }
                    Text(isConnecting ? "Connecting..." : "Connect")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(AppTheme.accent)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
            content()
        }
    }
    
    private func selectSSHKeyFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            config.sshKeyPath = url.path
        }
    }
    
    private func selectCACertFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "pem") ?? .item, .init(filenameExtension: "crt") ?? .item, .init(filenameExtension: "cer") ?? .item]
        if panel.runModal() == .OK, let url = panel.url {
            config.sslCAPath = url.path
        }
    }
    
    private func ensureConnectionName() {
        if config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.name = ConnectionStore.shared.generateUniqueName(base: "\(config.user)@\(config.host)")
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            ensureConnectionName()
            let res = await appState.testConnection(config: config, password: password)
            await MainActor.run {
                switch res {
                case .success(let ver):
                    testResult = .success("Connected to MySQL: \(ver)")
                case .failure(let err):
                    let formatted = ErrorFormatter.format(err, host: config.host, port: config.port)
                    testResult = .failure(formatted)
                }
                isTesting = false
            }
        }
    }
    
    private func saveConnection() {
        // Resign active text field focus so uncommitted edits flush into config
        NSApp.keyWindow?.makeFirstResponder(nil)
        ensureConnectionName()
        appState.saveConnection(config, password: password)
        onSave()
        withAnimation(.easeInOut(duration: 0.15)) {
            isRecentlySaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecentlySaved = false
            }
        }
    }
    
    private func connectNow() {
        saveConnection()
        if let onConnect = onConnect {
            onConnect(config, password)
            return
        }
        
        isConnecting = true
        testResult = nil
        
        Task {
            let res = await appState.testConnection(config: config, password: password)
            await MainActor.run {
                isConnecting = false
                switch res {
                case .success:
                    openWindow(value: config.id)
                    appState.isShowingConnectionManager = false
                    dismiss()
                case .failure(let err):
                    let formatted = ErrorFormatter.format(err, host: config.host, port: config.port)
                    testResult = .failure(formatted)
                }
            }
        }
    }
    
    private var availableGroups: [String] {
        var set = Set<String>()
        for g in appState.customGroups {
            set.insert(g)
        }
        for conn in appState.savedConnections {
            if let g = conn.displayGroup {
                set.insert(g)
            }
        }
        return set.sorted { a, b in
            let prio = ["PRODUCTION": 1, "PROD": 1, "STAGING": 2, "DEVELOPMENT": 3, "DEV": 3, "TESTING": 4, "QA": 4, "LOCAL": 5]
            let pA = prio[a.uppercased()] ?? 99
            let pB = prio[b.uppercased()] ?? 99
            if pA != pB { return pA < pB }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}
