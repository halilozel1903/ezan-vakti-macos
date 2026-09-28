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

    private let orange = Color(red: 1, green: 0.52, blue: 0.17)
    private let muted = Color(red: 0.64, green: 0.68, blue: 0.75)
    private let hairline = Color(red: 0.31, green: 0.35, blue: 0.42)
    private let card = Color(red: 0.18, green: 0.22, blue: 0.29)
    private let activeCard = Color(red: 0.34, green: 0.25, blue: 0.18)

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
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 20)).foregroundStyle(orange)
                    Text("Ezan Vakti").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Vakitler yüklenemedi. İnternet bağlantını kontrol et.")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.12, blue: 0.17), Color(red: 0.15, green: 0.19, blue: 0.26)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(colors: [orange.opacity(0.14), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
        }
        .widgetURL(URL(string: "ezanvakti://location"))
    }

    private func locationHeader(_ district: String, date: Date, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(orange)
                Text(district)
                    .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(IstanbulClock.display(date, format: compact ? "d MMMM" : "d MMMM yyyy"))
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .foregroundStyle(muted).lineLimit(1)
        }
    }

    private func countdown(to next: PrayerMoment, size: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(next.prayer.title.uppercased()) VAKTİNE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5).foregroundStyle(orange).lineLimit(1)
            Text(timerInterval: entry.date...next.date, countsDown: true, showsHours: true)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func prayerCell(_ prayer: Prayer, day: PrayerDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(prayer.title)
                .font(.system(size: 9, weight: .medium)).foregroundStyle(prayer == current ? orange : muted)
                .lineLimit(1)
            Text(day.time(for: prayer))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(prayer == current ? activeCard : card, in: RoundedRectangle(cornerRadius: 9))
    }

    private func small(snapshot: PrayerSnapshot, next: PrayerMoment) -> some View {
        let displayDate = next.isTomorrow ? next.date : entry.date
        let rows = [snapshot.current(at: entry.date), next].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 5) {
            locationHeader(snapshot.district, date: displayDate, compact: true)
            Spacer(minLength: 2)
            Text("\(next.prayer.title.uppercased()) VAKTİNE")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5).foregroundStyle(orange).lineLimit(1)
            Text(timerInterval: entry.date...next.date, countsDown: true, showsHours: true)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Rectangle().fill(hairline).frame(height: 1)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, moment in
                HStack(spacing: 5) {
                    Image(systemName: moment.prayer.symbol).font(.system(size: 9)).frame(width: 11)
                    Text(moment.prayer.title).font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 0)
                    Text(moment.clock)
                        .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(moment.prayer == next.prayer ? orange : .white)
            }
        }
    }

    private func medium(snapshot: PrayerSnapshot, next: PrayerMoment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                locationHeader(snapshot.district, date: entry.date)
                    .frame(maxWidth: .infinity, alignment: .leading)
                countdown(to: next, size: 23)
            }
            Rectangle().fill(hairline).frame(height: 1)
            if let today {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Prayer.allCases) { prayer in
                        prayerCell(prayer, day: today)
                    }
                }
            }
        }
    }

    private func large(snapshot: PrayerSnapshot, next: PrayerMoment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            locationHeader(snapshot.district, date: entry.date)
            HStack(spacing: 10) {
                Image(systemName: next.prayer.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(orange)
                    .frame(width: 36, height: 36)
                    .background(activeCard, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SIRADAKİ VAKİT")
                        .font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(muted)
                    Text("\(next.prayer.title) · \(next.clock)")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(timerInterval: entry.date...next.date, countsDown: true, showsHours: true)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(10)
            .background(card, in: RoundedRectangle(cornerRadius: 13))
            if let today {
                VStack(spacing: 2) {
                    ForEach(Prayer.allCases) { prayer in
                        HStack(spacing: 10) {
                            Image(systemName: prayer.symbol)
                                .font(.system(size: 12)).frame(width: 19)
                                .foregroundStyle(prayer == current ? orange : muted)
                            Text(prayer.title)
                                .font(.system(size: 13, weight: prayer == current ? .bold : .medium))
                            Spacer()
                            Text(today.time(for: prayer))
                                .font(.system(size: 14, weight: prayer == current ? .bold : .medium, design: .rounded))
                                .monospacedDigit()
                        }
                        .font(.system(size: 13, weight: prayer == current ? .semibold : .medium))
                        .padding(.horizontal, 9).frame(height: 27)
                        .background(prayer == current ? activeCard : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Spacer(minLength: 0)
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
