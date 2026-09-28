import WidgetKit
import SwiftUI
import os

private let widgetLog = Logger(subsystem: "com.halilozel.EzanVakti", category: "Widget")

struct PrayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerSnapshot?
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry {
        widgetLog.info("Widget placeholder requested")
        return PrayerEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        widgetLog.info("Widget snapshot requested")
        Task {
            let now = Date()
            let snapshot = context.isPreview ? SharedSnapshot.load() : await resolvedSnapshot(at: now)
            completion(PrayerEntry(date: now, snapshot: snapshot))
        }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        widgetLog.info("Widget timeline requested")
        Task {
            let now = Date()
            let snapshot = await resolvedSnapshot(at: now)
            completion(makeTimeline(snapshot: snapshot, now: now))
        }
    }

    private func resolvedSnapshot(at now: Date) async -> PrayerSnapshot? {
        let cached = SharedSnapshot.load()
        let hasUpcomingDays = cached?.day(for: now) != nil && cached?.day(for: IstanbulClock.nextDay(now)) != nil
        let freshEnough = cached.map { now.timeIntervalSince($0.fetchedAt) < 12 * 60 * 60 } ?? false
        if hasUpcomingDays && freshEnough {
            widgetLog.info("Widget using shared schedule")
            return cached
        }
        do {
            let updated = try await PrayerService().fetch(
                district: cached?.district ?? DefaultLocation.district,
                latitude: cached?.latitude ?? DefaultLocation.latitude,
                longitude: cached?.longitude ?? DefaultLocation.longitude,
                now: now
            )
            SharedSnapshot.save(updated)
            widgetLog.info("Widget downloaded schedule")
            return updated
        } catch {
            widgetLog.error("Widget schedule fetch failed: \(error.localizedDescription, privacy: .public)")
            // Keep a usable cached schedule when a refresh is unavailable.
            return hasUpcomingDays ? cached : nil
        }
    }

    private func makeTimeline(snapshot: PrayerSnapshot?, now: Date) -> Timeline<PrayerEntry> {
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
        let retryInterval: TimeInterval = snapshot == nil ? 10 * 60 : 6 * 60 * 60
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(retryInterval)))
    }
}

struct EzanWidgetView: View {
    let entry: PrayerEntry
    @Environment(\.widgetFamily) private var family

    private let orange = Color(red: 1, green: 0.48, blue: 0.09)
    private let muted = Color(red: 0.73, green: 0.75, blue: 0.79)

    private var snapshot: PrayerSnapshot? { entry.snapshot }
    private var next: PrayerMoment? { snapshot?.next(after: entry.date) }
    private var current: Prayer? { snapshot?.current(at: entry.date)?.prayer }
    private var today: PrayerDay? { snapshot?.day(for: entry.date) }

    var body: some View {
        Group {
            if let snapshot, let next {
                switch family {
                case .systemSmall: small(snapshot: snapshot, next: next)
                case .systemMedium: medium(snapshot: snapshot, next: next)
                default: large(snapshot: snapshot, next: next)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "moon.stars.fill").foregroundStyle(orange)
                    Text("Ezan Vakti").font(.headline)
                    Text("Vakitler yüklenemedi. İnternet bağlantını kontrol et.")
                        .font(.caption).foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.18), Color(red: 0.19, green: 0.21, blue: 0.27)], startPoint: .top, endPoint: .bottom)
        }
        .widgetURL(URL(string: "ezanvakti://location"))
    }

    private func header(_ district: String, date: Date, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(district).font(.system(size: compact ? 17 : 20, weight: .bold, design: .rounded)).lineLimit(1)
            Text(IstanbulClock.display(date, format: compact ? "d MMMM" : "d MMMM yyyy"))
                .font(.system(size: compact ? 11 : 12, weight: .medium)).foregroundStyle(muted).lineLimit(1)
        }
    }

    private func countdown(to next: PrayerMoment) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(next.prayer.title.uppercased()) VAKTİNE")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(muted).lineLimit(1)
            Text(timerInterval: entry.date...next.date, countsDown: true, showsHours: true)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func small(snapshot: PrayerSnapshot, next: PrayerMoment) -> some View {
        let displayDate = next.isTomorrow ? next.date : entry.date
        let rows = [snapshot.current(at: entry.date), next].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 9) {
            header(snapshot.district, date: displayDate, compact: true)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, moment in
                HStack(spacing: 7) {
                    Image(systemName: moment.prayer.symbol).font(.system(size: 12)).frame(width: 15)
                    Text(moment.prayer.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(moment.clock)
                        .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(moment.prayer == next.prayer ? orange : .white)
            }
            Spacer(minLength: 0)
            HStack {
                Text("\(next.prayer.title) vaktine").foregroundStyle(muted)
                Spacer(minLength: 2)
                Text(timerInterval: entry.date...next.date, countsDown: true, showsHours: true)
                    .monospacedDigit().foregroundStyle(orange)
            }
            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
    }

    private func medium(snapshot: PrayerSnapshot, next: PrayerMoment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                header(snapshot.district, date: entry.date)
                Spacer(minLength: 4)
                countdown(to: next)
            }
            Rectangle().fill(.white.opacity(0.13)).frame(height: 1)
            if let today {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 12) {
                    ForEach(Prayer.allCases) { prayer in
                        VStack(spacing: 4) {
                            Text(prayer.title).font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                            Text(today.time(for: prayer)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        .foregroundStyle(prayer == current ? orange : .white)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func large(snapshot: PrayerSnapshot, next: PrayerMoment) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                header(snapshot.district, date: entry.date)
                Spacer(minLength: 4)
                countdown(to: next)
            }
            Rectangle().fill(.white.opacity(0.13)).frame(height: 1)
            if let today {
                ForEach(Prayer.allCases) { prayer in
                    HStack(spacing: 12) {
                        Image(systemName: prayer.symbol)
                            .font(.system(size: 16)).frame(width: 30, height: 30)
                            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                        Text(prayer.title).font(.system(size: 17, weight: prayer == current ? .bold : .medium))
                        Spacer()
                        Text(today.time(for: prayer))
                            .font(.system(size: 17, weight: prayer == current ? .bold : .regular, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(prayer == current ? orange : .white)
                }
            }
            Spacer(minLength: 0)
            Text("İlçe değiştirmek için dokun").font(.system(size: 10)).foregroundStyle(muted)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
