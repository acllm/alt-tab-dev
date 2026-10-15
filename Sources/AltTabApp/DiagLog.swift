import Foundation

/// Minimal append-only diagnostic log for runtime verification.
/// Written to /tmp/alttab-dev.log so behavior can be checked without
/// attaching a debugger (the app runs from launchd with no stdout).
enum DiagLog {
    private static let path = "/tmp/alttab-dev.log"
    private static let queue = DispatchQueue(label: "alttab.diaglog")

    static func log(_ message: String) {
        queue.async {
            let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let line = "\(stamp) \(message)\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
