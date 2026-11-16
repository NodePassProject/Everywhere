//
//  DashboardComponents.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import SwiftUI

// MARK: - Formatting

enum DashboardFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    static func bytes(_ count: Int64) -> String {
        var value = Double(max(count, 0))
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) B" }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, units[unit])
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        "\(bytes(Int64(bytesPerSecond.rounded())))/s"
    }

    static func duration(since start: Date, now: Date = Date()) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return String(format: "%dm %02ds", seconds / 60, seconds % 60)
        case ..<86400: return String(format: "%dh %02dm", seconds / 3600, seconds % 3600 / 60)
        default: return String(format: "%dd %02dh", seconds / 86400, seconds % 86400 / 3600)
        }
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum DashboardColor {
    static let upload = Color.orange
    static let download = Color.accentColor

    static func delay(_ delay: Delay) -> Color {
        switch delay {
        case .untested: return .secondary
        case .failed: return .red
        case .milliseconds(let ms) where ms < 400: return .green
        case .milliseconds(let ms) where ms < 800: return .orange
        case .milliseconds: return .red
        }
    }

    static func level(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Delay

struct DelayLabel: View {
    let delay: Delay
    var isTesting = false

    var body: some View {
        Group {
            if isTesting {
                ProgressView()
                    .controlSize(.small)
            } else {
                switch delay {
                case .untested:
                    Image(systemName: "bolt")
                        .accessibilityLabel("Not tested")
                case .failed:
                    Text("Timeout")
                case .milliseconds(let ms):
                    Text(verbatim: "\(ms) ms")
                }
            }
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(DashboardColor.delay(delay))
        .frame(minWidth: 28, alignment: .trailing)
    }
}

// MARK: - Unavailable features

struct FeatureUnavailableView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let core: CoreType

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(core.unavailableLabel)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RouteLabel: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .lineLimit(1)
        }
    }
}

struct FeatureRow<Content: View>: View {
    let feature: DashboardFeature
    let core: CoreType
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        if feature.isAvailable(on: core) {
            content()
        } else {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(core.unavailableLabel)
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

struct DashboardPlaceholder: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

// MARK: - Chart

struct TrafficChart: View {
    let samples: [TrafficSample]

    var body: some View {
        GeometryReader { geometry in
            let peak = max(samples.map { max($0.up, $0.down) }.max() ?? 0, 1024)
            ZStack {
                gridlines(in: geometry.size)
                series(\.down, peak: peak, in: geometry.size, color: DashboardColor.download, filled: true)
                series(\.up, peak: peak, in: geometry.size, color: DashboardColor.upload, filled: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func gridlines(in size: CGSize) -> some View {
        Path { path in
            for fraction in [0.0, 0.5, 1.0] {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
    }

    private func points(_ value: KeyPath<TrafficSample, Double>, peak: Double, in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let step = size.width / CGFloat(samples.count - 1)
        return samples.enumerated().map { index, sample in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height * (1 - CGFloat(min(sample[keyPath: value] / peak, 1)))
            )
        }
    }

    @ViewBuilder
    private func series(
        _ value: KeyPath<TrafficSample, Double>,
        peak: Double,
        in size: CGSize,
        color: Color,
        filled: Bool
    ) -> some View {
        let points = points(value, peak: peak, in: size)
        if let first = points.first, let last = points.last {
            if filled {
                Path { path in
                    path.move(to: CGPoint(x: first.x, y: size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [color.opacity(0.25), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            Path { path in
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
