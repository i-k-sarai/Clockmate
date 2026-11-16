import SwiftUI
import WidgetKit

/// Shared with the app and written by home_widget (see
/// lib/features/native_sync/widget_data.dart for every key).
private let appGroupId = "group.com.karasingh.clockmate"

/// One work day of the current week, labels already formatted by Dart.
struct WeekRow: Decodable, Hashable {
    let date: String
    let dayLabel: String
    let inLabel: String
    let outLabel: String
    let workedLabel: String
    let state: String
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let clockedIn: Bool
    let since: Date?
    let statusLabel: String
    let nextAlarmLabel: String
    let nextAlarmAt: Date?
    let todayIn: String
    let todayOut: String
    let weekStart: String?
    let rows: [WeekRow]

    static let placeholder = TodayEntry(
        date: Date(),
        clockedIn: true,
        since: Date().addingTimeInterval(-3 * 3600),
        statusLabel: "In since 9:04 AM",
        nextAlarmLabel: "Clock out Today, 6:30 PM",
        nextAlarmAt: nil,
        todayIn: "9:04 AM",
        todayOut: "—",
        weekStart: nil,
        rows: [
            WeekRow(date: "", dayLabel: "Mon", inLabel: "9:02 AM", outLabel: "6:41 PM", workedLabel: "9h 39m", state: "done"),
            WeekRow(date: "", dayLabel: "Tue", inLabel: "9:10 AM", outLabel: "6:35 PM", workedLabel: "9h 25m", state: "done"),
            WeekRow(date: "", dayLabel: "Wed", inLabel: "9:04 AM", outLabel: "—", workedLabel: "Working", state: "today"),
            WeekRow(date: "", dayLabel: "Thu", inLabel: "—", outLabel: "—", workedLabel: "", state: "future"),
            WeekRow(date: "", dayLabel: "Fri", inLabel: "—", outLabel: "—", workedLabel: "", state: "future"),
        ]
    )

    static func load() -> TodayEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return .placeholder }
        let sinceMillis = defaults.double(forKey: "sinceMillis")
        let nextMillis = defaults.double(forKey: "nextAlarmMillis")
        let weekJson = defaults.string(forKey: "weekJson") ?? ""
        let rows = (try? JSONDecoder().decode([WeekRow].self, from: Data(weekJson.utf8))) ?? []
        return TodayEntry(
            date: Date(),
            clockedIn: defaults.bool(forKey: "clockedIn"),
            since: sinceMillis > 0 ? Date(timeIntervalSince1970: sinceMillis / 1000) : nil,
            statusLabel: defaults.string(forKey: "statusLabel") ?? "Open ClockMate to sync",
            nextAlarmLabel: defaults.string(forKey: "nextAlarmLabel") ?? "",
            nextAlarmAt: nextMillis > 0 ? Date(timeIntervalSince1970: nextMillis / 1000) : nil,
            todayIn: defaults.string(forKey: "todayInLabel") ?? "—",
            todayOut: defaults.string(forKey: "todayOutLabel") ?? "—",
            weekStart: defaults.string(forKey: "weekStart"),
            rows: rows
        )
    }

    /// This week's rows, or empty when the data is from an earlier week.
    /// States are re-derived from each row's date, so "today" moves at
    /// midnight even if the app hasn't run.
    var currentWeekRows: [WeekRow] {
        let today = Self.isoDate(date)
        guard weekStart == nil || weekStart == Self.isoDate(Self.monday(of: date)) else { return [] }
        return rows.map { row in
            guard !row.date.isEmpty else { return row }
            let state: String
            if row.date == today {
                state = "today"
            } else if row.state == "today" || (row.state == "future" && row.date < today) {
                state = "done"
            } else {
                state = row.state
            }
            return WeekRow(date: row.date, dayLabel: row.dayLabel, inLabel: row.inLabel,
                           outLabel: row.outLabel, workedLabel: row.workedLabel, state: state)
        }
    }

    private static func monday(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
        // itself, or at midnight when "Today"/"Tomorrow" and the week's
        // current day change meaning.
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
    @Environment(\.widgetFamily) private var family
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
            header
            if family == .systemLarge {
                week
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: family == .systemLarge ? .topLeading : .leading)

        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { gradient }
        } else {
            ZStack { gradient; content.padding(16) }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.statusLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if family == .systemLarge, entry.clockedIn, let since = entry.since {
                Spacer()
                Text(since, style: .timer)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
        if family != .systemLarge, entry.clockedIn, let since = entry.since {
            Text(since, style: .timer)
                .font(.system(size: 32, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        if family != .systemSmall, entry.todayIn != "—" {
            Text("In \(entry.todayIn)  ·  Out \(entry.todayOut)")
                .font(.footnote)
                .lineLimit(1)
        }
        if !entry.nextAlarmLabel.isEmpty {
            Text(entry.nextAlarmLabel)
                .font(.caption)
                .opacity(0.85)
                .lineLimit(1)
                .padding(.top, 2)
        }
    }

    @ViewBuilder private var week: some View {
        Divider().overlay(Color.white.opacity(0.3)).padding(.vertical, 8)
        let rows = entry.currentWeekRows
        if rows.isEmpty {
            Text("Open ClockMate to load this week")
                .font(.caption)
                .opacity(0.85)
        } else {
            VStack(spacing: 4) {
                ForEach(rows, id: \.self) { row in
                    weekRow(row)
                }
            }
        }
    }

    private func weekRow(_ row: WeekRow) -> some View {
        let dimmed = ["future", "leave", "missed"].contains(row.state)
        return HStack {
            Text(row.dayLabel)
                .fontWeight(.semibold)
                .frame(width: 40, alignment: .leading)
            Text(dimmed ? "" : "\(row.inLabel) → \(row.outLabel)")
                .lineLimit(1)
            Spacer()
            Text(row.workedLabel)
        }
        .font(.footnote.monospacedDigit())
        .opacity(dimmed ? 0.6 : 1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(row.state == "today" ? 0.15 : 0))
        )
    }
}

struct ClockMateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClockMateWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("ClockMate")
        .description("Clock status, today's punches, your next alarm and, in the large size, this week.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
