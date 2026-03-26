import Foundation
import AppKit

class DiskMonitor: ObservableObject {
    @Published var volumeName: String = "Macintosh HD"
    @Published var totalBytes: Int64 = 0
    @Published var usedBytes: Int64 = 0
    @Published var freeBytes: Int64 = 0
    @Published var usageRatio: Double = 0.0

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = max(0, total - free)

        DispatchQueue.main.async {
            self.volumeName = values.volumeName ?? "Macintosh HD"
            self.totalBytes = total
            self.usedBytes = used
            self.freeBytes = free
            self.usageRatio = total > 0 ? Double(used) / Double(total) : 0
        }
    }

    func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .decimal
        formatter.isAdaptive = false
        return formatter.string(fromByteCount: bytes)
    }
}
