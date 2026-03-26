import SwiftUI

struct DiskStatusBar: View {
    @StateObject private var monitor = DiskMonitor()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(monitor.volumes) { volume in
                    VolumeItemView(volume: volume, formatted: monitor.formatted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    if volume.id != monitor.volumes.last?.id {
                        Divider().frame(height: 42)
                    }
                }
            }
        }
        .frame(height: 78)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}

private struct VolumeItemView: View {
    let volume: VolumeInfo
    let formatted: (Int64) -> String

    private var gaugeColor: Color {
        if volume.usageRatio >= 0.90 { return .red }
        if volume.usageRatio >= 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(volume.usageRatio))
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: volume.usageRatio)
                Text("\(Int(volume.usageRatio * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(gaugeColor)
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if volume.isExternal {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Text(volume.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    infoItem("전체", formatted(volume.totalBytes))
                    Divider().frame(height: 28)
                    infoItem("사용", formatted(volume.usedBytes))
                    Divider().frame(height: 28)
                    infoItem("잔여", formatted(volume.freeBytes))
                }
            }
        }
    }

    private func infoItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}
