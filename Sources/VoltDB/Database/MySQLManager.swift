import Foundation
import MySQLNIO
import NIOPosix
import NIOSSL

struct FilterCondition {
    var column: String
    var op: FilterOperator
    var value: String
    
    enum FilterOperator: String, CaseIterable {
        case equals = "="
        case notEquals = "!="
        case like = "LIKE"
        case greaterThan = ">"
        case lessThan = "<"
        case greaterOrEqual = ">="
        case lessOrEqual = "<="
        case isNull = "IS NULL"
        case isNotNull = "IS NOT NULL"
    }
}

/// Securely streams SSH passphrases or passwords into an in-memory POSIX FIFO (named pipe)
/// without ever persisting plaintext secrets to disk blocks or persistent storage.
private final class SSHPassphraseFeeder: @unchecked Sendable {
    private let fifoPath: String
    private var passphraseData: Data
    private var isStopped = false
    private let lock = NSLock()
    private var thread: Thread?
    
    init(fifoPath: String, passphrase: String) {
        self.fifoPath = fifoPath
        var data = passphrase.data(using: .utf8) ?? Data()
        data.append(0x0A) // Append newline for terminal response
        self.passphraseData = data
    }
    
    func start() {
        // Ignore SIGPIPE on current process so any closed pipe write fails with EPIPE rather than terminating process
        Darwin.signal(SIGPIPE, SIG_IGN)
        
        let t = Thread { [weak self] in
            guard let self = self else { return }
            // Feed up to 3 times (OpenSSH default prompt retry limit)
            for _ in 0..<3 {
                self.lock.lock()
                if self.isStopped {
                    self.lock.unlock()
                    break
                }
                let dataToWrite = self.passphraseData
                self.lock.unlock()
                
                // Blocks in kernel until a reader (/bin/cat in SSH_ASKPASS) opens the FIFO
                let fd = Darwin.open(self.fifoPath, O_WRONLY)
                if fd < 0 { break }
                
                self.lock.lock()
                let stopped = self.isStopped
                self.lock.unlock()
                
                if !stopped {
                    dataToWrite.withUnsafeBytes { raw in
                        if let base = raw.baseAddress {
                            _ = Darwin.write(fd, base, raw.count)
                        }
                    }
                }
                Darwin.close(fd)
            }
        }
        self.thread = t
        t.name = "VoltDB.SSHPassphraseFeeder"
        t.start()
    }
    
    func stop() {
        lock.lock()
        isStopped = true
        // Zero out in-memory passphrase copy
        passphraseData.resetBytes(in: 0..<passphraseData.count)
        passphraseData = Data()
        lock.unlock()
        
        // Open read-end non-blocking to wake up any Darwin.open(O_WRONLY) waiting on the FIFO
        let unblockFd = Darwin.open(fifoPath, O_RDONLY | O_NONBLOCK)
        if unblockFd >= 0 {
            Darwin.close(unblockFd)
        }
    }
}

actor MySQLManager {
    static let shared = MySQLManager()
    
    private var connection: MySQLConnection?
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var sshProcess: Process?
    private var sshLocalPort: Int?
    private var activeDatabase: String = ""
    
    init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }
    
    func connect(config: ConnectionConfig, password: String) async throws {
        // Disconnect previous if active
        await disconnect()
        
        let eventLoop = eventLoopGroup.next()
        
        var targetHost = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetHost.isEmpty { targetHost = "127.0.0.1" }
        var targetPort = config.port
        
        // Handle SSH Tunnel if requested
        if config.useSSHTunnel && !config.sshHost.isEmpty {
            let localPort = try startSSHTunnel(config: config)
            targetHost = "127.0.0.1"
            targetPort = localPort
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        var tlsConfig: TLSConfiguration? = nil
        if config.useSSL {
            tlsConfig = TLSConfiguration.makeClientConfiguration()
            // Load custom CA certificate if user specified one (for self-signed or private CA databases)
            let caPath = config.sslCAPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !caPath.isEmpty {
                let expandedPath = (caPath as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expandedPath) {
                    tlsConfig?.trustRoots = .file(expandedPath)
                }
            }
        }
        
        self.connection = try await establishConnection(
            host: targetHost,
            port: targetPort,
            user: config.user,
            database: config.database,
            password: password,
            tlsConfig: tlsConfig,
            isSSH: config.useSSHTunnel,
            sshHost: config.sshHost,
            realTargetHost: config.host,
            realTargetPort: config.port,
            on: eventLoop
        )
        self.activeDatabase = config.database.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func useDatabase(_ database: String) async throws {
        guard let connection = self.connection else { return }
        let cleanDB = database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDB.isEmpty && cleanDB != self.activeDatabase else { return }
        let escapedDB = cleanDB.replacingOccurrences(of: "`", with: "``")
        _ = try await connection.simpleQuery("USE `\(escapedDB)`").get()
        self.activeDatabase = cleanDB
    }
    
    func disconnect() async {
        if let conn = self.connection {
            self.connection = nil
            _ = try? await conn.close().get()
        }
        self.activeDatabase = ""
        
        // Stop SSH tunnel process if running
        if let proc = self.sshProcess, proc.isRunning {
            proc.terminate()
        }
        self.sshProcess = nil
        self.sshLocalPort = nil
    }
    
    deinit {
        if let conn = connection {
            conn.channel.close(mode: .all, promise: nil)
        }
        if let proc = sshProcess, proc.isRunning {
            proc.terminate()
        }
    }
    
    func testConnection(config: ConnectionConfig, password: String) async throws -> String {
        var targetHost = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetHost.isEmpty { targetHost = "127.0.0.1" }
        var targetPort = config.port
        var testSSHProcess: Process? = nil
        
        if config.useSSHTunnel && !config.sshHost.isEmpty {
            let (proc, port) = try createSSHTunnelProcess(config: config)
            testSSHProcess = proc
            targetHost = "127.0.0.1"
            targetPort = port
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        defer {
            if let p = testSSHProcess, p.isRunning {
                p.terminate()
            }
        }
        
        var tlsConfig: TLSConfiguration? = nil
        if config.useSSL {
            tlsConfig = TLSConfiguration.makeClientConfiguration()
            let caPath = config.sslCAPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !caPath.isEmpty {
                let expandedPath = (caPath as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expandedPath) {
                    tlsConfig?.trustRoots = .file(expandedPath)
                }
            }
        }
        
        let conn = try await establishConnection(
            host: targetHost,
            port: targetPort,
            user: config.user,
            database: config.database,
            password: password,
            tlsConfig: tlsConfig,
            isSSH: config.useSSHTunnel,
            sshHost: config.sshHost,
            realTargetHost: config.host,
            realTargetPort: config.port,
            on: self.eventLoopGroup.next()
        )
        
        var versionString = "Connected successfully"
        do {
            let rows = try await conn.simpleQuery("SELECT VERSION() AS ver").get()
            for row in rows {
                if let col = row.column("ver"), let s = col.string {
                    versionString = s
                    break
                }
            }
        } catch {
            _ = try? await conn.close().get()
            throw error
        }
        
        _ = try? await conn.close().get()
        return versionString
    }
    
    private func establishConnection(
        host: String,
        port: Int,
        user: String,
        database: String,
        password: String,
        tlsConfig: TLSConfiguration?,
        isSSH: Bool = false,
        sshHost: String = "",
        realTargetHost: String = "",
        realTargetPort: Int = 3306,
        on eventLoop: EventLoop
    ) async throws -> MySQLConnection {
        let maxAttempts = isSSH ? 5 : 2
        var lastError: Error?
        
        let targetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = try SocketAddress.makeAddressResolvingHost(targetHost, port: port)
        
        let expectedHostname = isSSH && !realTargetHost.isEmpty ? realTargetHost : (!targetHost.isEmpty ? targetHost : nil)
        for attempt in 1...maxAttempts {
            do {
                return try await MySQLConnection.connect(
                    to: addr,
                    username: user.trimmingCharacters(in: .whitespacesAndNewlines),
                    database: database.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    tlsConfiguration: tlsConfig,
                    serverHostname: expectedHostname,
                    on: eventLoop
                ).get()
            } catch {
                lastError = error
                
                // If authentication error (Access denied), do not retry because credentials are invalid
                let msg = "\(error)"
                if msg.contains("Access denied") {
                    let displayHost = isSSH ? (realTargetHost.isEmpty ? host : realTargetHost) : host
                    let displayPort = isSSH ? (realTargetPort > 0 ? realTargetPort : port) : port
                    throw translateError(error, host: displayHost, port: displayPort, isSSH: isSSH, sshHost: sshHost)
                }
                
                // If SSH tunnel process died, stop retrying immediately
                if isSSH {
                    if let proc = self.sshProcess, !proc.isRunning {
                        break
                    }
                    // Incremental backoff to let bastion finish DNS & TCP handshake to remote RDS
                    let delayNanos: UInt64 = attempt == 1 ? 400_000_000 : (attempt == 2 ? 600_000_000 : 800_000_000)
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
            }
        }
        
        // 2. If 127.0.0.1 failed on direct connection (not SSH), try localhost
        if !isSSH && targetHost == "127.0.0.1" {
            if let altAddr = try? SocketAddress.makeAddressResolvingHost("localhost", port: port),
               let altConn = try? await MySQLConnection.connect(
                to: altAddr,
                username: user,
                database: database,
                password: password,
                tlsConfiguration: tlsConfig,
                serverHostname: "localhost",
                on: eventLoop
               ).get() {
                return altConn
            }
        } else if !isSSH && targetHost == "localhost" {
            if let altAddr = try? SocketAddress.makeAddressResolvingHost("127.0.0.1", port: port),
               let altConn = try? await MySQLConnection.connect(
                to: altAddr,
                username: user,
                database: database,
                password: password,
                tlsConfiguration: tlsConfig,
                serverHostname: "127.0.0.1",
                on: eventLoop
               ).get() {
                return altConn
            }
        }
        
        let displayHost = isSSH ? (realTargetHost.isEmpty ? targetHost : realTargetHost) : targetHost
        let displayPort = isSSH ? (realTargetPort > 0 ? realTargetPort : port) : port
        let finalError = lastError ?? NSError(domain: "VoltDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
        throw translateError(finalError, host: displayHost, port: displayPort, isSSH: isSSH, sshHost: sshHost)
    }
    
    private func translateError(_ error: Error, host: String, port: Int, isSSH: Bool = false, sshHost: String = "") -> Error {
        // If it's already a custom VoltDB error with clear message, pass through
        let ns = error as NSError
        if ns.domain == "VoltDB" {
            return error
        }
        
        let msg = "\(error)"
        
        if isSSH {
            return NSError(
                domain: "VoltDB",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "SSH Tunnel to '\(sshHost)' connected, but could not reach MySQL at '\(host):\(port)' through the tunnel.\n\n• If MySQL is running directly on the SSH server, make sure MySQL Host is set to '127.0.0.1' or 'localhost'.\n• If MySQL is on a private RDS / VPC instance, verify the private host name and port."
                ]
            )
        }
        
        if msg.contains("error 1") || msg.contains("error 61") || msg.contains("Connection refused") || msg.contains("Operation not permitted") {
            return NSError(
                domain: "VoltDB",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Cannot reach MySQL server at \(host):\(port).\n\n• Ensure your MySQL server is running.\n• Try using 'localhost' or '127.0.0.1'."
                ]
            )
        }
        if msg.contains("Access denied") {
            return NSError(
                domain: "VoltDB",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Authentication failed: Access denied for MySQL user. Please check your database username and password."
                ]
            )
        }
        return error
    }
    
    // MARK: - SSH Tunnel Helper
    
    private static func findAvailablePort() -> Int {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            return Int.random(in: 34000...45000)
        }
        defer { Darwin.close(sock) }
        
        var opt: Int32 = 1
        Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        
        var bindAddr = addr
        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            return Int.random(in: 34000...45000)
        }
        
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let sockNameResult = withUnsafeMutablePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(sock, $0, &len)
            }
        }
        guard sockNameResult == 0 else {
            return Int.random(in: 34000...45000)
        }
        
        let port = Int(UInt16(bigEndian: bindAddr.sin_port))
        return port > 1024 ? port : Int.random(in: 34000...45000)
    }
    
    private static func canConnectToLocalPort(_ port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }
        
        var bindAddr = addr
        let res = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return res == 0
    }
    
    private func startSSHTunnel(config: ConnectionConfig) throws -> Int {
        if let proc = self.sshProcess, proc.isRunning {
            proc.terminate()
        }
        self.sshProcess = nil
        self.sshLocalPort = nil
        
        let (proc, port) = try createSSHTunnelProcess(config: config)
        self.sshProcess = proc
        self.sshLocalPort = port
        return port
    }
    
    private func createSSHTunnelProcess(config: ConnectionConfig) throws -> (Process, Int) {
        let targetRemoteHost = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSSHHost = config.sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSSHUser = config.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSSHKeyPath = config.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Security check: ensure parameters don't start with '-' to prevent SSH argument injection
        guard !targetSSHHost.starts(with: "-"),
              !targetSSHUser.starts(with: "-"),
              !targetRemoteHost.starts(with: "-"),
              !targetSSHKeyPath.starts(with: "-") else {
            throw NSError(
                domain: "VoltDB",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid SSH configuration parameter: hostnames, usernames, and key paths cannot start with '-'."]
            )
        }
        
        var lastErrorMsg = ""
        let maxAttempts = 5
        
        for _ in 1...maxAttempts {
            let localPort = MySQLManager.findAvailablePort()
            
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            
            var env = ProcessInfo.processInfo.environment
            // Handle Passphrase or Password via temporary SSH_ASKPASS script and in-memory IPC FIFO (Named Pipe)
            var tempScriptURL: URL? = nil
            var tempFIFOURL: URL? = nil
            var passphraseFeeder: SSHPassphraseFeeder? = nil
            if !config.sshPassphrase.isEmpty {
                // Use private Application Support directory with 0700 permissions
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let privateDir = appSupport.appendingPathComponent("VoltDB/tmp", isDirectory: true)
                if !FileManager.default.fileExists(atPath: privateDir.path) {
                    try? FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                }
                
                let uniqueId = UUID().uuidString
                let fifoURL = privateDir.appendingPathComponent("voltdb_pipe_\(uniqueId).fifo")
                let scriptURL = privateDir.appendingPathComponent("voltdb_askpass_\(uniqueId).sh")
                
                // Create in-memory IPC FIFO (Named Pipe) with 0600 POSIX permissions.
                // In UNIX, a FIFO exists exclusively in kernel memory (RAM buffers) and never writes data to physical storage blocks.
                Darwin.unlink(fifoURL.path)
                if Darwin.mkfifo(fifoURL.path, 0o600) == 0 {
                    tempFIFOURL = fifoURL
                    tempScriptURL = scriptURL
                    
                    // Script contains NO credentials — strictly reads from the volatile in-memory IPC FIFO
                    let scriptContent = """
                    #!/bin/sh
                    exec /bin/cat "\(fifoURL.path)"
                    """
                    if (try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)) != nil {
                        chmod(scriptURL.path, 0o700)
                        
                        let feeder = SSHPassphraseFeeder(fifoPath: fifoURL.path, passphrase: config.sshPassphrase)
                        feeder.start()
                        passphraseFeeder = feeder
                        
                        env["SSH_ASKPASS"] = scriptURL.path
                        env["SSH_ASKPASS_REQUIRE"] = "force"
                        env["DISPLAY"] = ":0"
                    }
                }
            }
            proc.environment = env
            
            defer {
                // Ensure passphrase feeder is stopped, memory is zeroed, and ephemeral FIFO/script are unlinked
                passphraseFeeder?.stop()
                if let fURL = tempFIFOURL {
                    Darwin.unlink(fURL.path)
                }
                if let sURL = tempScriptURL {
                    Darwin.unlink(sURL.path)
                }
            }
            
            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            proc.standardError = stderrPipe
            proc.standardOutput = stdoutPipe
            proc.standardInput = FileHandle.nullDevice
            
            let hostKeyPolicy = config.sshStrictHostKeyChecking ? "yes" : "accept-new"
            var args = [
                "-N",
                "-L", "\(localPort):\(targetRemoteHost):\(config.port)",
                "-p", "\(config.sshPort)",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "StrictHostKeyChecking=\(hostKeyPolicy)",
                "-o", "ConnectTimeout=15",
                "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=3",
                "-o", "TCPKeepAlive=yes"
            ]
            
            if config.sshAuthMode == .password {
                args.append(contentsOf: [
                    "-o", "PasswordAuthentication=yes",
                    "-o", "PreferredAuthentications=password,keyboard-interactive"
                ])
            } else {
                if config.sshPassphrase.isEmpty {
                    args.append(contentsOf: ["-o", "BatchMode=yes"])
                }
                
                if !targetSSHKeyPath.isEmpty {
                    let expandedPath = (targetSSHKeyPath as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: expandedPath) {
                        args.append(contentsOf: ["-i", expandedPath])
                    } else if targetSSHKeyPath != "~/.ssh/id_rsa" {
                        // Only error if user explicitly specified a non-default custom key file that doesn't exist
                        throw NSError(
                            domain: "VoltDB",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "SSH Key File Not Found: '\(expandedPath)'\n\nPlease check the file path in your SSH Tunnel settings or use 'Browse...' to select your private key file."]
                        )
                    } else {
                        // Check if default ed25519 exists as alternative
                        let ed25519Path = ("~/.ssh/id_ed25519" as NSString).expandingTildeInPath
                        if FileManager.default.fileExists(atPath: ed25519Path) {
                            args.append(contentsOf: ["-i", ed25519Path])
                        }
                    }
                }
            }
            
            let destination = targetSSHUser.isEmpty ? targetSSHHost : "\(targetSSHUser)@\(targetSSHHost)"
            args.append("--")
            args.append(destination)
            
            proc.arguments = args
            
            do {
                try proc.run()
            } catch {
                throw NSError(
                    domain: "VoltDB",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to launch SSH process: \(error.localizedDescription)"]
                )
            }
            
            // Poll for up to 2.5 seconds until SSH binds the local port or terminates with error
            var isListening = false
            for _ in 0..<25 {
                if !proc.isRunning { break }
                if MySQLManager.canConnectToLocalPort(localPort) {
                    isListening = true
                    break
                }
                usleep(100_000)
            }
            
            if !proc.isRunning || (!isListening && proc.isRunning) {
                // If it died or failed to bind after 2.5s
                if proc.isRunning && !isListening {
                    proc.terminate()
                }
                
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let outString = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                let combined = [errString, outString].filter { !$0.isEmpty }.joined(separator: "\n")
                
                // If port collision occurred, retry with a fresh port
                if combined.contains("Address already in use") || combined.contains("cannot listen to port") {
                    lastErrorMsg = combined
                    continue
                }
                
                var friendlyMsg = "SSH Tunnel to '\(destination)' failed."
                if !combined.isEmpty {
                    friendlyMsg += "\n\nSSH Output: \(combined)"
                }
                if combined.contains("Host key verification failed") {
                    friendlyMsg += "\n\n• SSH Host Key Verification Failed: The host key presented by '\(config.sshHost)' is not recognized or has changed.\n• To prevent Man-in-the-Middle attacks, please verify the server fingerprint or add it to ~/.ssh/known_hosts (e.g., run 'ssh \(config.sshHost)' in Terminal).\n• If this is a trusted host, you can toggle off 'Strict Host Key Checking' in SSH Tunnel settings."
                } else if combined.contains("Permission denied") || combined.contains("passphrase") {
                    friendlyMsg += "\n\n• The SSH server rejected the credentials. Verify your SSH username, password, or private key passphrase."
                } else if combined.contains("Could not resolve hostname") {
                    friendlyMsg += "\n\n• The SSH Host '\(config.sshHost)' could not be found. Check the hostname or IP address."
                } else if combined.contains("Connection refused") {
                    friendlyMsg += "\n\n• SSH port \(config.sshPort) refused connection on \(config.sshHost). Check if the SSH port is correct."
                }
                
                throw NSError(domain: "VoltDB", code: 3, userInfo: [NSLocalizedDescriptionKey: friendlyMsg])
            }
            
            return (proc, localPort)
        }
        
        let destination = config.sshUser.isEmpty ? config.sshHost : "\(config.sshUser)@\(config.sshHost)"
        throw NSError(
            domain: "VoltDB",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "SSH Tunnel to '\(destination)' failed after multiple port attempts.\n\nSSH Output: \(lastErrorMsg)"]
        )
    }
    
    func executeQuery(_ sql: String, database: String? = nil) async throws -> QueryResult {
        guard let connection = self.connection else {
            throw NSError(domain: "MySQLManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected to database. Please connect first."])
        }
        
        let startTime = Date()
        do {
            if let db = database?.trimmingCharacters(in: .whitespacesAndNewlines), !db.isEmpty, !sql.uppercased().starts(with: "USE ") {
                let escapedDB = db.replacingOccurrences(of: "`", with: "``")
                _ = try await connection.simpleQuery("USE `\(escapedDB)`").get()
                self.activeDatabase = db
            }
            
            var rows: [MySQLRow] = []
            var okPacket: MySQLProtocol.OK_Packet? = nil
            
            let command = EnhancedSimpleQueryCommand(
                sql: sql,
                onRow: { row in
                    rows.append(row)
                },
                onOK: { ok in
                    okPacket = ok
                }
            )
            try await connection.send(command, logger: connection.logger).get()
            let executionTime = Date().timeIntervalSince(startTime)
            
            var columns: [QueryResult.ColumnHeader] = []
            var resultRows: [[QueryResult.CellValue]] = []
            
            // Extract column names from command columns or first row
            let colDefs = !command.columns.isEmpty ? command.columns : (rows.first?.columnDefinitions ?? [])
            for (index, col) in colDefs.enumerated() {
                columns.append(QueryResult.ColumnHeader(name: col.name, type: "", index: index))
            }
            
            // Extract cell values
            for row in rows {
                var cellRow: [QueryResult.CellValue] = []
                for col in row.columnDefinitions {
                    if let data = row.column(col.name) {
                        cellRow.append(parseMySQLData(data))
                    } else {
                        cellRow.append(.null)
                    }
                }
                resultRows.append(cellRow)
            }
            
            let affected = okPacket != nil ? Int(okPacket!.affectedRows) : rows.count
            
            return QueryResult(
                columns: columns,
                rows: resultRows,
                affectedRows: affected,
                executionTime: executionTime,
                error: nil,
                queryType: QueryResult.QueryType(from: sql)
            )
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            return QueryResult(
                columns: [],
                rows: [],
                affectedRows: 0,
                executionTime: executionTime,
                error: error.localizedDescription,
                queryType: QueryResult.QueryType(from: sql)
            )
        }
    }
    
    private func parseMySQLData(_ data: MySQLData) -> QueryResult.CellValue {
        if data.buffer == nil { return .null }
        if let s = data.string { return .string(s) }
        if let i = data.int { return .int(Int64(i)) }
        if let d = data.double { return .double(d) }
        
        guard var buf = data.buffer else { return .null }
        let bytes = buf.readBytes(length: buf.readableBytes) ?? []
        guard !bytes.isEmpty else { return .null }
        
        // 1. Decode MySQL Binary DateTime / Timestamp / Date
        if let dateStr = decodeMySQLBinaryDateTime(bytes) {
            return .string(dateStr)
        }
        
        // 2. Decode UTF-8 string if valid printable text (e.g. JSON, Decimal, Varchar)
        if let text = String(bytes: bytes, encoding: .utf8), isPrintableText(text) {
            return .string(text)
        }
        
        // 3. Fallback to raw binary data
        return .data(Data(bytes))
    }
    
    private func decodeMySQLBinaryDateTime(_ bytes: [UInt8]) -> String? {
        // Case A: Payload starts directly with little-endian year (length 4, 7, 8, 11)
        if bytes.count >= 4 {
            let year = Int(bytes[0]) | (Int(bytes[1]) << 8)
            let month = Int(bytes[2])
            let day = Int(bytes[3])
            
            if year >= 1000 && year <= 9999 && month >= 1 && month <= 12 && day >= 1 && day <= 31 {
                if bytes.count == 4 {
                    return String(format: "%04d-%02d-%02d", year, month, day)
                } else if bytes.count == 7 || bytes.count == 8 {
                    let hour = Int(bytes[4])
                    let minute = Int(bytes[5])
                    let second = Int(bytes[6])
                    if hour < 24 && minute < 60 && second < 60 {
                        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
                    }
                } else if bytes.count >= 11 {
                    let hour = Int(bytes[4])
                    let minute = Int(bytes[5])
                    let second = Int(bytes[6])
                    let micro = Int(bytes[7]) | (Int(bytes[8]) << 8) | (Int(bytes[9]) << 16) | (Int(bytes[10]) << 24)
                    if hour < 24 && minute < 60 && second < 60 {
                        return String(format: "%04d-%02d-%02d %02d:%02d:%02d.%06d", year, month, day, hour, minute, second, micro)
                    }
                }
            }
        }
        
        // Case B: Payload starts with length byte prefix (e.g. length 4, 7, 11)
        if bytes.count >= 5 && (bytes[0] == 4 || bytes[0] == 7 || bytes[0] == 11) {
            let year = Int(bytes[1]) | (Int(bytes[2]) << 8)
            let month = Int(bytes[3])
            let day = Int(bytes[4])
            
            if year >= 1000 && year <= 9999 && month >= 1 && month <= 12 && day >= 1 && day <= 31 {
                if bytes[0] == 4 || bytes.count == 5 {
                    return String(format: "%04d-%02d-%02d", year, month, day)
                } else if (bytes[0] == 7 && bytes.count >= 8) || bytes.count == 8 {
                    let hour = Int(bytes[5])
                    let minute = Int(bytes[6])
                    let second = Int(bytes[7])
                    if hour < 24 && minute < 60 && second < 60 {
                        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
                    }
                } else if bytes[0] == 11 && bytes.count >= 12 {
                    let hour = Int(bytes[5])
                    let minute = Int(bytes[6])
                    let second = Int(bytes[7])
                    let micro = Int(bytes[8]) | (Int(bytes[9]) << 8) | (Int(bytes[10]) << 16) | (Int(bytes[11]) << 24)
                    if hour < 24 && minute < 60 && second < 60 {
                        return String(format: "%04d-%02d-%02d %02d:%02d:%02d.%06d", year, month, day, hour, minute, second, micro)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func isPrintableText(_ str: String) -> Bool {
        if str.isEmpty { return true }
        for scalar in str.unicodeScalars {
            if scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D {
                return false
            }
        }
        return true
    }
    
    // MARK: - Helpers
    
    private func str(_ cell: QueryResult.CellValue) -> String? {
        if case .string(let s) = cell { return s }
        if case .int(let i) = cell { return String(i) }
        return nil
    }
    
    private func int64(_ cell: QueryResult.CellValue) -> Int64? {
        if case .int(let i) = cell { return i }
        if case .string(let s) = cell { return Int64(s) }
        return nil
    }
    
    // MARK: - Schema Introspection
    
    func getDatabases() async throws -> [DatabaseInfo] {
        let res = try await executeQuery("SHOW DATABASES")
        return res.rows.compactMap { row in
            guard let name = str(row[0]) else { return nil }
            return DatabaseInfo(name: name)
        }
    }
    
    func getTables(database: String) async throws -> [TableInfo] {
        let escapedDB = database
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let sql = """
        SELECT TABLE_NAME, TABLE_TYPE, TABLE_ROWS 
        FROM information_schema.tables 
        WHERE table_schema = '\(escapedDB)'
        ORDER BY TABLE_NAME
        """
        let res = try await executeQuery(sql)
        if let err = res.error {
            throw NSError(domain: "MySQLManager", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return res.rows.compactMap { row in
            guard row.count >= 2,
                  let name = str(row[0]),
                  let typeStr = str(row[1]) else { return nil }
            let rowCount: Int? = row.count >= 3 ? int64(row[2]).map { Int($0) } : nil
            let type: TableInfo.TableType = typeStr == "VIEW" ? .view : .table
            return TableInfo(name: name, type: type, rowCount: rowCount, database: database)
        }
    }
    
    func getColumns(database: String, table: String) async throws -> [ColumnInfo] {
        let escapedDB = database
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedTable = table
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let sql = """
        SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_KEY, EXTRA, ORDINAL_POSITION
        FROM information_schema.columns 
        WHERE table_schema = '\(escapedDB)' AND table_name = '\(escapedTable)'
        ORDER BY ORDINAL_POSITION
        """
        let res = try await executeQuery(sql)
        if let err = res.error {
            throw NSError(domain: "MySQLManager", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return res.rows.compactMap { row in
            guard row.count >= 7,
                  let name = str(row[0]),
                  let type = str(row[1]),
                  let isNullStr = str(row[2]) else { return nil }
            
            let defValue = str(row[3])
            let keyStr = str(row[4]) ?? ""
            let extra = str(row[5]) ?? ""
            let ord = int64(row[6]).map { Int($0) } ?? 0
            
            let key: ColumnInfo.ColumnKey
            switch keyStr {
            case "PRI": key = .primary
            case "UNI": key = .unique
            case "MUL": key = .multiple
            default: key = .none
            }
            
            return ColumnInfo(name: name, type: type, isNullable: isNullStr == "YES", defaultValue: defValue, key: key, extra: extra, ordinalPosition: ord, characterMaxLength: nil, numericPrecision: nil)
        }
    }
    
    func getIndexes(database: String, table: String) async throws -> [IndexInfo] {
        let escapedDB = database.replacingOccurrences(of: "`", with: "``")
        let escapedTable = table.replacingOccurrences(of: "`", with: "``")
        let sql = "SHOW INDEX FROM `\(escapedDB)`.`\(escapedTable)`"
        let res = try await executeQuery(sql)
        
        var indexMap: [String: (columns: [String], isUnique: Bool, type: String)] = [:]
        for row in res.rows {
            guard row.count >= 11,
                  let indexName = str(row[2]),
                  let colName = str(row[4]) else { continue }
            let nonUnique = int64(row[1]) ?? 1
            let indexType = str(row[10]) ?? "BTREE"
            
            if var existing = indexMap[indexName] {
                existing.columns.append(colName)
                indexMap[indexName] = existing
            } else {
                indexMap[indexName] = (columns: [colName], isUnique: nonUnique == 0, type: indexType)
            }
        }
        
        return indexMap.map { name, info in
            IndexInfo(name: name, columns: info.columns, isUnique: info.isUnique, type: info.type)
        }
    }
    
    func getForeignKeys(database: String, table: String) async throws -> [ForeignKeyInfo] {
        let escapedDB = database
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedTable = table
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let sql = """
        SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = '\(escapedDB)' AND TABLE_NAME = '\(escapedTable)' AND REFERENCED_TABLE_NAME IS NOT NULL
        """
        let res = try await executeQuery(sql)
        if let err = res.error {
            throw NSError(domain: "MySQLManager", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return res.rows.compactMap { row in
            guard row.count >= 4,
                  let name = str(row[0]),
                  let column = str(row[1]),
                  let refTable = str(row[2]),
                  let refColumn = str(row[3]) else { return nil }
            return ForeignKeyInfo(name: name, column: column, referencedTable: refTable, referencedColumn: refColumn, onUpdate: "RESTRICT", onDelete: "RESTRICT")
        }
    }
    
    // MARK: - Table Data
    
    func getTableData(database: String, table: String, page: Int, pageSize: Int, filters: [FilterCondition], sortColumn: String?, sortAscending: Bool) async throws -> QueryResult {
        let escapedDB = database.replacingOccurrences(of: "`", with: "``")
        let escapedTable = table.replacingOccurrences(of: "`", with: "``")
        var sql = "SELECT * FROM `\(escapedDB)`.`\(escapedTable)`"
        
        if !filters.isEmpty {
            let clauses = filters.map { f -> String in
                let escapedCol = f.column.replacingOccurrences(of: "`", with: "``")
                switch f.op {
                case .isNull: return "`\(escapedCol)` IS NULL"
                case .isNotNull: return "`\(escapedCol)` IS NOT NULL"
                default:
                    let escapedVal = f.value
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    return "`\(escapedCol)` \(f.op.rawValue) '\(escapedVal)'"
                }
            }
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }
        if let sort = sortColumn {
            let escapedSort = sort.replacingOccurrences(of: "`", with: "``")
            sql += " ORDER BY `\(escapedSort)` \(sortAscending ? "ASC" : "DESC")"
        }
        // LIMIT and OFFSET are validated integers — safe to interpolate
        sql += " LIMIT \(pageSize) OFFSET \(page * pageSize)"
        
        return try await executeQuery(sql)
    }
    
    func getRowCount(database: String, table: String) async throws -> Int {
        let escapedDB = database.replacingOccurrences(of: "`", with: "``")
        let escapedTable = table.replacingOccurrences(of: "`", with: "``")
        let res = try await executeQuery("SELECT COUNT(*) AS cnt FROM `\(escapedDB)`.`\(escapedTable)`")
        if let first = res.rows.first?.first, let count = int64(first) {
            return Int(count)
        }
        return 0
    }
    
    // MARK: - Apply Changes
    
    func applyChanges(_ changes: [CellChange]) async throws {
        guard self.connection != nil else {
            throw NSError(domain: "MySQLManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected to database."])
        }
        for change in changes {
            _ = try await executeQuery(change.toSQL())
        }
    }
}

// MARK: - Enhanced Simple Query Command (Captures Rows & OK_Packet Affected Rows)

private final class EnhancedSimpleQueryCommand: MySQLCommand, @unchecked Sendable {
    let sql: String
    
    enum State {
        case ready
        case columns(count: UInt64)
        case rows
        case done
    }
    var state: State
    
    var columns: [MySQLProtocol.ColumnDefinition41]
    let onRow: (MySQLRow) -> Void
    let onOK: (MySQLProtocol.OK_Packet) -> Void
    
    init(sql: String, onRow: @escaping (MySQLRow) -> Void, onOK: @escaping (MySQLProtocol.OK_Packet) -> Void) {
        self.state = .ready
        self.sql = sql
        self.columns = []
        self.onRow = onRow
        self.onOK = onOK
    }
    
    func handle(packet: inout MySQLPacket, capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        guard !packet.isError else {
            self.state = .done
            let errorPacket = try packet.decode(MySQLProtocol.ERR_Packet.self, capabilities: capabilities)
            let error: any Error
            switch errorPacket.errorCode {
            case .DUP_ENTRY:
                error = MySQLError.duplicateEntry(errorPacket.errorMessage)
            case .PARSE_ERROR:
                error = MySQLError.invalidSyntax(errorPacket.errorMessage)
            default:
                error = MySQLError.server(errorPacket)
            }
            throw error
        }
        
        switch self.state {
        case .ready:
            if packet.isOK {
                self.state = .done
                if let ok = try? packet.decode(MySQLProtocol.OK_Packet.self, capabilities: capabilities) {
                    self.onOK(ok)
                }
                return MySQLCommandState(done: true)
            } else {
                let res = try packet.decode(MySQLProtocol.COM_QUERY_Response.self, capabilities: capabilities)
                self.state = .columns(count: res.columnCount)
                return MySQLCommandState()
            }
        case .columns(let total):
            let column = try packet.decode(MySQLProtocol.ColumnDefinition41.self, capabilities: capabilities)
            self.columns.append(column)
            if self.columns.count == numericCast(total) {
                self.state = .rows
            }
            return MySQLCommandState()
        case .rows:
            guard !packet.isEOF else {
                self.state = .done
                if packet.isOK, let ok = try? packet.decode(MySQLProtocol.OK_Packet.self, capabilities: capabilities) {
                    self.onOK(ok)
                }
                return MySQLCommandState(done: true)
            }
            
            let data = try MySQLProtocol.TextResultSetRow.decode(from: &packet, columnCount: columns.count)
            let row = MySQLRow(
                format: .text,
                columnDefinitions: self.columns,
                values: data.values
            )
            self.onRow(row)
            return MySQLCommandState()
        case .done:
            throw MySQLError.protocolError
        }
    }
    
    func activate(capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        let packet = try MySQLPacket.encode(MySQLProtocol.COM_QUERY(query: self.sql), capabilities: capabilities)
        return MySQLCommandState(response: [packet])
    }
}
