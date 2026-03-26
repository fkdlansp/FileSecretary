import SwiftUI

struct DiskStatusBar: View {
    @StateObject private var monitor = DiskMonitor()

    private var gaugeColor: Color {
        if monitor.usageRatio >= 0.90 { return .red }
        if monitor.usageRatio >= 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 16) {

            // Donut gauge — percentage at 16pt
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(monitor.usageRatio))
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: monitor.usageRatio)
                Text("\(Int(monitor.usageRatio * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(gaugeColor)
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)

            // Volume name
            Text(monitor.volumeName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Stats — label 14pt bold / value 10pt
            infoItem("전체", monitor.formatted(monitor.totalBytes))
            Divider().frame(height: 28)
            infoItem("사용", monitor.formatted(monitor.usedBytes))
            Divider().frame(height: 28)
            infoItem("잔여", monitor.formatted(monitor.freeBytes))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
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
