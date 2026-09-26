import SwiftUI
import AppKit

private enum Palette {
    static let navy = Color(red: 0.035, green: 0.105, blue: 0.17)
    static let deep = Color(red: 0.055, green: 0.17, blue: 0.22)
    static let gold = Color(red: 0.92, green: 0.73, blue: 0.43)
    static let muted = Color(red: 0.65, green: 0.76, blue: 0.77)
}

struct PrayerPanel: View {
    @ObservedObject var store: PrayerStore
    @State private var search = ""

    private var districts: [String] {
        search.isEmpty ? IstanbulDistricts.all : IstanbulDistricts.all.filter {
            $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) != nil
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            VStack(spacing: 0) {
                header(now: now)
                if store.showingDistricts {
                    districtPicker
                } else {
                    mainContent(now: now)
                }
                footer
            }
            .frame(width: 390, height: 570)
            .background {
                LinearGradient(colors: [Palette.navy, Palette.deep, Palette.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .foregroundStyle(.white)
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Palette.gold)
                    Text("EZAN VAKTİ").tracking(2.5).font(.system(size: 11, weight: .bold, design: .rounded))
                }
                Text(IstanbulClock.display(now, format: "EEEE, d MMMM"))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                store.showingDistricts.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill").font(.system(size: 10))
                    Text(store.snapshot?.district ?? "Fatih").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("İlçe seç")
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
    }

    private func mainContent(now: Date) -> some View {
        VStack(spacing: 0) {
            if let snapshot = store.snapshot, let next = snapshot.next(after: now) {
                hero(snapshot: snapshot, next: next, now: now)
                if let day = snapshot.day(for: now) {
                    timesList(day: day, next: next, now: now)
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                ProgressView().tint(Palette.gold)
                Text("Vakitler yükleniyor…").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.top, 12)
                Spacer()
            }
            if let error = store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(Color.orange).multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.bottom, 6)
            }
        }
    }

    private func hero(snapshot: PrayerSnapshot, next: PrayerMoment, now: Date) -> some View {
        let minutes = max(0, Int(ceil(next.date.timeIntervalSince(now) / 60)))
        let hours = minutes / 60
        let remainder = minutes % 60
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Palette.gold).frame(width: 6, height: 6)
                Text("SIRADAKİ VAKİT").tracking(2).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Palette.gold)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: next.prayer.symbol).font(.system(size: 29, weight: .light)).foregroundStyle(Palette.gold)
                Text(next.prayer.title).font(.system(size: 40, weight: .medium, design: .rounded))
            }
            Text(next.isTomorrow ? "Yarın · \(next.clock)" : "Bugün · \(next.clock)")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if hours > 0 {
                    Text("\(hours)").font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("sa").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.trailing, 8)
                }
                Text("\(remainder)").font(.system(size: 36, weight: .semibold, design: .rounded))
                Text("dk kaldı").font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            .monospacedDigit().padding(.top, 2)
            GeometryReader { geometry in
                let previous = snapshot.current(at: now)?.date ?? now
                let total = max(1, next.date.timeIntervalSince(previous))
                let progress = min(1, max(0, now.timeIntervalSince(previous) / total))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [Palette.gold, .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 5).padding(.top, 7)
            HStack {
                Text("Şimdi \(snapshot.current(at: now)?.prayer.title ?? "—")")
                Spacer()
                Text("Sonraki \(next.prayer.title)")
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .padding(21)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
        .padding(.horizontal, 20)
    }

    private func timesList(day: PrayerDay, next: PrayerMoment, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("BUGÜNÜN VAKİTLERİ").tracking(1.5).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted)
                Spacer()
                Text(IstanbulClock.display(now, format: "HH:mm"))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(Prayer.allCases) { prayer in
                let instant = day.instant(for: prayer)
                let isNext = instant == next.date
                HStack(spacing: 12) {
                    Image(systemName: prayer.symbol).frame(width: 20).foregroundStyle(isNext ? Palette.gold : Palette.muted)
                    Text(prayer.title).font(.system(size: 13, weight: isNext ? .semibold : .regular))
                    Spacer()
                    Text(day.time(for: prayer)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    if let instant, instant > now {
                        Text("\(Int(ceil(instant.timeIntervalSince(now) / 60))) dk")
                            .font(.system(size: 10)).foregroundStyle(isNext ? Palette.gold : Palette.muted)
                            .frame(width: 55, alignment: .trailing)
                    } else {
                        Text("GEÇTİ").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted.opacity(0.6))
                            .frame(width: 55, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 10).frame(height: 36)
                .background(isNext ? Palette.gold.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 26).padding(.top, 20)
    }

    private var districtPicker: some View {
        VStack(spacing: 12) {
            Text("İlçeni seç").font(.system(size: 25, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("İstanbul’un 39 ilçesinden birini seç veya konumuna izin ver.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
            Button { store.location.request() } label: {
                Label("Konumumu kullan", systemImage: "location.north.fill")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(11)
                    .background(Palette.gold, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Palette.navy)
            }.buttonStyle(.plain)
            Text("İzin verirsen konumun vakitleri almak için AlAdhan servisine gönderilir.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("İlçe ara", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(districts, id: \.self) { district in
                        Button {
                            Task { await store.select(district) }
                        } label: {
                            HStack {
                                Text(district)
                                Spacer()
                                if district == store.snapshot?.district { Image(systemName: "checkmark").foregroundStyle(Palette.gold) }
                            }
                            .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 31)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if store.loading { ProgressView().tint(Palette.gold) }
            if let error = store.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
        }
        .padding(.horizontal, 24).frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("AlAdhan · Diyanet yöntemi (deneysel)")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            Button { Task { await store.reload() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Vakitleri yenile")
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Çıkış")
        }
        .buttonStyle(.plain).foregroundStyle(Palette.muted)
        .padding(.horizontal, 25).padding(.bottom, 19).padding(.top, 10)
    }
}
