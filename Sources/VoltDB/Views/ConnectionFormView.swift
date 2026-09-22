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
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    Divider()
                    generalSection
                    serverSection
                    sshTunnelSection
                    
                    if let result = testResult {
                        feedbackBanner(result)
                    }
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
        .alert("Delete Connection", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(config.name)'?")
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
            if config.isProduction {
                Text("PRODUCTION")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.cornerRadius(4))
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Color Tag")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                HStack(spacing: 10) {
                    ForEach(ConnectionConfig.presetColors, id: \.hex) { preset in
                        Button {
                            config.colorHex = preset.hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 22, height: 22)
                                if config.colorHex == preset.hex {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 26, height: 26)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Toggle(isOn: $config.isProduction) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Production Environment")
                        .font(.body)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Displays safety warnings and red alert banners")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(.red)
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
    private func feedbackBanner(_ result: ConnectionTestResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch result {
            case .success(let msg):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.success)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection Succeeded")
                            .font(.subheadline.bold())
                            .foregroundColor(AppTheme.success)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Spacer()
                }
            case .failure(let msg):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.error)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Connection Failed")
                                .font(.subheadline.bold())
                                .foregroundColor(AppTheme.error)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(msg, forType: .string)
                            } label: {
                                Label("Copy Error", systemImage: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(AppTheme.textSecondary)
                        }
                        
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(AppTheme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.backgroundTertiary)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(resultIsSuccess(result) ? AppTheme.success.opacity(0.4) : AppTheme.error.opacity(0.4), lineWidth: 1)
        )
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
            
            Button("Save") {
                saveConnection()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(AppTheme.backgroundTertiary)
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.border.opacity(0.6), lineWidth: 1))
            
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
        ensureConnectionName()
        appState.saveConnection(config, password: password)
        onSave()
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
}
