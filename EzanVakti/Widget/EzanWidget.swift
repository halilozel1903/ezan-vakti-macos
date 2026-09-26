import WidgetKit
import SwiftUI

struct PrayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerSnapshot?
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { PrayerEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(PrayerEntry(date: .now, snapshot: SharedSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedSnapshot.load()
        var dates = [now]
        if let snapshot {
            for day in snapshot.days {
                for prayer in Prayer.allCases {
                    if let instant = day.instant(for: prayer), instant > now, instant < now.addingTimeInterval(48 * 3600) {
                        dates.append(instant)
                    }
                }
            }
        }
        let entries = dates.sorted().map { PrayerEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

struct EzanWidgetView: View {
    let entry: PrayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let next = snapshot.next(after: entry.date) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "moon.stars.fill").foregroundStyle(.yellow)
                    Text("EZAN VAKTİ").tracking(1.4).font(.system(size: 10, weight: .bold))
                    Spacer()
                    Text(snapshot.district).font(.system(size: 10)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(next.prayer.title).font(.system(size: 27, weight: .semibold, design: .rounded))
                HStack(alignment: .firstTextBaseline) {
                    Text(timerInterval: entry.date...next.date, countsDown: true, showsHours: true)
                        .font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("kaldı").font(.system(size: 11))
                    Spacer()
                    Text(next.clock).font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                if family != .systemSmall, let day = snapshot.day(for: entry.date) {
                    Divider().overlay(.white.opacity(0.4))
                    HStack {
                        ForEach(Prayer.allCases) { prayer in
                            VStack(spacing: 3) {
                                Text(prayer.title).font(.system(size: 9)).lineLimit(1)
                                Text(day.time(for: prayer)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.04, green: 0.12, blue: 0.19), Color(red: 0.08, green: 0.25, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Ezan Vakti", systemImage: "moon.stars.fill").font(.headline)
                Text("Vakitleri görmek için uygulamayı açın.").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color(red: 0.04, green: 0.12, blue: 0.19) }
        }
    }
}

@main struct EzanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EzanVaktiWidget", provider: PrayerProvider()) { entry in
            EzanWidgetView(entry: entry)
        }
        .configurationDisplayName("Ezan Vakti")
        .description("Sıradaki namaz vaktini ve kalan süreyi gösterir.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
