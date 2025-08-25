import Foundation

class LogManager {
    static let shared = LogManager()
    
    private var logs: [LogEntry] = []
    private let maxLogEntries = 100
    
    private init() {}
    
    struct LogEntry {
        let timestamp: Date
        let message: String
        
        var formattedString: String {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            formatter.dateStyle = .medium
            return "[\(formatter.string(from: timestamp))] \(message)"
        }
    }
    
    func log(_ message: String) {
        let entry = LogEntry(timestamp: Date(), message: message)
        logs.append(entry)
        
        // Keep only the most recent entries
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
        
        // Also print to console (existing behavior)
        print(message)
    }
    
    func getAllLogs() -> [LogEntry] {
        return logs.reversed()
    }
}
