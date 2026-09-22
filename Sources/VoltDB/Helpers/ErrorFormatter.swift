import Foundation
import AppKit

struct ErrorFormatter {
    static func format(_ error: Error, host: String = "", port: Int = 3306) -> String {
        let ns = error as NSError
        if ns.domain == "VoltDB", let customMsg = ns.userInfo[NSLocalizedDescriptionKey] as? String {
            return customMsg
        }
        
        let raw = "\(error)"
        let loc = error.localizedDescription
        
        var message = ""
        
        if raw.localizedCaseInsensitiveContains("Access denied") {
            message = "Authentication Failed: Access denied for this username/password.\n\n• Verify your username and password are correct."
        } else if raw.localizedCaseInsensitiveContains("Unknown database") {
            message = "Database Not Found: The default database does not exist on this server.\n\n• Leave 'Default Database' empty to connect without selecting one."
        } else if raw.contains("error 61") || raw.localizedCaseInsensitiveContains("Connection refused") {
            let target = host.isEmpty ? "specified server" : "\(host):\(port)"
            message = "Connection Refused by \(target).\n\n• Ensure MySQL is running on port \(port).\n• If using Docker on macOS, make sure port 3306 is mapped (-p 3306:3306).\n• If MySQL is on a remote server, enable 'Connect via SSH Tunnel'."
        } else if raw.contains("error 1") || raw.localizedCaseInsensitiveContains("Operation not permitted") {
            let target = host.isEmpty ? "host" : "\(host):\(port)"
            message = "Cannot reach \(target).\n\n• If connecting locally, try changing Host to 'localhost' instead of '127.0.0.1' (or vice-versa).\n• If connecting to a remote server, check your network / VPN or enable 'Connect via SSH Tunnel'."
        } else if raw.localizedCaseInsensitiveContains("timed out") || raw.localizedCaseInsensitiveContains("timeout") {
            message = "Connection Timed Out: The server did not respond.\n\n• Verify the host IP and port are reachable from your machine.\n• Check if your server firewall or AWS security group allows inbound traffic on port \(port)."
        } else if raw.localizedCaseInsensitiveContains("SSL") || raw.localizedCaseInsensitiveContains("TLS") {
            message = "SSL/TLS Handshake Failed: Server requires different encryption settings.\n\n• Try toggling 'Use SSL / TLS Encryption' on/off."
        } else if !loc.starts(with: "The operation couldn’t be completed") && !loc.starts(with: "The operation couldn't be completed") {
            message = loc
        } else {
            message = raw
        }
        
        return message
    }
}
