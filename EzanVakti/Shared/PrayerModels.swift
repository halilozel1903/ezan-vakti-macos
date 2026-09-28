import Foundation

enum Prayer: String, CaseIterable, Codable, Identifiable {
    case imsak, gunes, ogle, ikindi, aksam, yatsi

    var id: String { rawValue }
    var title: String {
        switch self {
        case .imsak: "İmsak"
        case .gunes: "Güneş"
        case .ogle: "Öğle"
        case .ikindi: "İkindi"
        case .aksam: "Akşam"
        case .yatsi: "Yatsı"
        }
    }
    var symbol: String {
        switch self {
        case .imsak: "moon.stars.fill"
        case .gunes: "sunrise.fill"
        case .ogle: "sun.max.fill"
        case .ikindi: "sun.haze.fill"
        case .aksam: "sunset.fill"
        case .yatsi: "moon.fill"
        }
    }
    var apiKey: String {
        switch self {
        case .imsak: "Fajr"
        case .gunes: "Sunrise"
        case .ogle: "Dhuhr"
        case .ikindi: "Asr"
        case .aksam: "Maghrib"
        case .yatsi: "Isha"
        }
    }
}

struct PrayerDay: Codable, Equatable {
    let date: String
    let times: [Prayer: String]

    func time(for prayer: Prayer) -> String { times[prayer] ?? "--:--" }

    func instant(for prayer: Prayer) -> Date? {
        guard let time = times[prayer] else { return nil }
        return IstanbulClock.date(from: date, time: time)
    }
}

struct PrayerMoment {
    let prayer: Prayer
    let date: Date
    let clock: String
    let isTomorrow: Bool
}

enum IstanbulClock {
    static let zone = TimeZone(identifier: "Europe/Istanbul")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(from day: String, time: String) -> Date? {
        let dayParts = day.split(separator: "-").compactMap { Int($0) }
        let timeParts = time.prefix(5).split(separator: ":").compactMap { Int($0) }
        guard dayParts.count == 3, timeParts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(timeZone: zone, year: dayParts[0], month: dayParts[1], day: dayParts[2], hour: timeParts[0], minute: timeParts[1]))
    }

    static func nextDay(_ date: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: date)! }

    static func display(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct PrayerSnapshot: Codable {
    var district: String
    var latitude: Double
    var longitude: Double
    var days: [PrayerDay]
    var fetchedAt: Date

    func day(for date: Date) -> PrayerDay? { days.first { $0.date == IstanbulClock.dayKey(date) } }

    func next(after now: Date) -> PrayerMoment? {
        for offset in 0...2 {
            guard let date = IstanbulClock.calendar.date(byAdding: .day, value: offset, to: now), let day = day(for: date) else { continue }
            for prayer in Prayer.allCases {
                if let instant = day.instant(for: prayer), instant > now {
                    return PrayerMoment(prayer: prayer, date: instant, clock: day.time(for: prayer), isTomorrow: offset > 0)
                }
            }
        }
        return nil
    }

    func current(at now: Date) -> PrayerMoment? {
        let today = day(for: now)
        let yesterday = IstanbulClock.calendar.date(byAdding: .day, value: -1, to: now).flatMap { day(for: $0) }
        for day in [today, yesterday].compactMap({ $0 }) {
            for prayer in Prayer.allCases.reversed() {
                if let instant = day.instant(for: prayer), instant <= now {
                    return PrayerMoment(prayer: prayer, date: instant, clock: day.time(for: prayer), isTomorrow: false)
                }
            }
        }
        return nil
    }
}

enum SharedSnapshot {
    static let group = "group.com.halilozel.EzanVakti"
    static let key = "prayerSnapshotV1"
    static let selectedKey = "didChooseLocationV1"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static func load() -> PrayerSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(PrayerSnapshot.self, from: data) else { return nil }
        if snapshot.district == "Fatih" && !defaults.bool(forKey: selectedKey) {
            clear()
            return nil
        }
        return snapshot
    }
    static func save(_ snapshot: PrayerSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
    static func clear() { defaults.removeObject(forKey: key) }
}

enum DefaultLocation {
    static let district = "Avcılar"
    static let latitude = 40.981196
    static let longitude = 28.723092
}

enum IstanbulDistricts {
    static let all = [
        "Adalar", "Arnavutköy", "Ataşehir", "Avcılar", "Bağcılar", "Bahçelievler", "Bakırköy", "Başakşehir", "Bayrampaşa", "Beşiktaş", "Beykoz", "Beylikdüzü", "Beyoğlu", "Büyükçekmece", "Çatalca", "Çekmeköy", "Esenler", "Esenyurt", "Eyüpsultan", "Fatih", "Gaziosmanpaşa", "Güngören", "Kadıköy", "Kağıthane", "Kartal", "Küçükçekmece", "Maltepe", "Pendik", "Sancaktepe", "Sarıyer", "Silivri", "Sultanbeyli", "Sultangazi", "Şile", "Şişli", "Tuzla", "Ümraniye", "Üsküdar", "Zeytinburnu"
    ]
}
