import Foundation
import AppKit

struct VolumeInfo: Identifiable {
    let id: String          // volume mount path (stable across refreshes)
    let name: String
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let isExternal: Bool
    var usageRatio: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

class DiskMonitor: ObservableObject {
    @Published var volumes: [VolumeInfo] = []

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
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: .skipHiddenVolumes
        ) else { return }

        var result: [VolumeInfo] = []
        for url in urls {
            guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard vals.volumeIsBrowsable == true else { continue }
            let total = Int64(vals.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            // volumeAvailableCapacityForImportantUsage returns 0 on ExFAT/non-APFS volumes
            // fall back to the basic volumeAvailableCapacity in that case
            let freeImportant = Int64(vals.volumeAvailableCapacityForImportantUsage ?? 0)
            let freeBasic     = Int64(vals.volumeAvailableCapacity ?? 0)
            let free = max(freeImportant, freeBasic)
            let used = max(0, total - free)
            result.append(VolumeInfo(
                id: url.path,
                name: vals.volumeName ?? url.lastPathComponent,
                totalBytes: total,
                usedBytes: used,
                freeBytes: free,
                isExternal: !(vals.volumeIsInternal ?? true)
            ))
        }

        DispatchQueue.main.async {
            self.volumes = result
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
