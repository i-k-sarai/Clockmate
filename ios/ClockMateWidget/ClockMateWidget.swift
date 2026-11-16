import SwiftUI
import WidgetKit

/// Shared with the app and written by home_widget (see
/// lib/features/native_sync/native_state_sync.dart).
private let appGroupId = "group.com.karasingh.clockmate"

struct TodayEntry: TimelineEntry {
    let date: Date
    let clockedIn: Bool
    let since: Date?
    let statusLabel: String
    let nextAlarmLabel: String
    let nextAlarmAt: Date?

    static let placeholder = TodayEntry(
        date: Date(),
        clockedIn: true,
        since: Date().addingTimeInterval(-3 * 3600),
        statusLabel: "In since 9:04 AM",
        nextAlarmLabel: "Clock out Today, 6:30 PM",
        nextAlarmAt: nil
    )

    static func load() -> TodayEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return .placeholder }
        let sinceMillis = defaults.double(forKey: "sinceMillis")
        let nextMillis = defaults.double(forKey: "nextAlarmMillis")
        return TodayEntry(
            date: Date(),
            clockedIn: defaults.bool(forKey: "clockedIn"),
            since: sinceMillis > 0 ? Date(timeIntervalSince1970: sinceMillis / 1000) : nil,
            statusLabel: defaults.string(forKey: "statusLabel") ?? "Open ClockMate to sync",
            nextAlarmLabel: defaults.string(forKey: "nextAlarmLabel") ?? "",
            nextAlarmAt: nextMillis > 0 ? Date(timeIntervalSince1970: nextMillis / 1000) : nil
        )
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry.load()
        // The worked-time ticker runs on its own (Text .timer style); ask for
        // a reload only when the next-alarm line goes stale: at the alarm
        // itself, or at midnight when "Today"/"Tomorrow" change meaning.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: entry.date).addingTimeInterval(24 * 3600)
        var reloadAt = midnight
        if let next = entry.nextAlarmAt, next > entry.date, next < reloadAt {
            reloadAt = next.addingTimeInterval(60)
        }
        completion(Timeline(entries: [entry], policy: .after(reloadAt)))
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.49, green: 0.23, blue: 0.93)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(entry.statusLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if entry.clockedIn, let since = entry.since {
                Text(since, style: .timer)
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if !entry.nextAlarmLabel.isEmpty {
                Text(entry.nextAlarmLabel)
                    .font(.caption)
                    .opacity(0.85)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { gradient }
        } else {
            ZStack { gradient; content.padding(16) }
        }
    }
}

struct ClockMateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClockMateWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("ClockMate")
        .description("Clock status, time worked today and your next alarm.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
