import XCTest
@testable import EzanVakti

final class PrayerScheduleTests: XCTestCase {
    private func day(_ date: String) -> PrayerDay {
        PrayerDay(date: date, times: [
            .imsak: "05:20", .gunes: "06:45", .ogle: "13:00",
            .ikindi: "16:20", .aksam: "19:00", .yatsi: "20:20"
        ])
    }

    func testNightRolloverUsesTomorrowImsak() {
        let snapshot = PrayerSnapshot(district: "Fatih", latitude: 41, longitude: 29,
                                      days: [day("2026-09-26"), day("2026-09-27")], fetchedAt: .now)
        let now = IstanbulClock.date(from: "2026-09-26", time: "23:58")!
        XCTAssertEqual(snapshot.current(at: now)?.prayer, .yatsi)
        XCTAssertEqual(snapshot.next(after: now)?.prayer, .imsak)
        XCTAssertEqual(snapshot.next(after: now)?.isTomorrow, true)
        XCTAssertEqual(Int(snapshot.next(after: now)!.date.timeIntervalSince(now) / 60), 322)
    }

    func testUpcomingPrayerChangesAtExactMinute() {
        let snapshot = PrayerSnapshot(district: "Fatih", latitude: 41, longitude: 29,
                                      days: [day("2026-09-26")], fetchedAt: .now)
        let before = IstanbulClock.date(from: "2026-09-26", time: "12:59")!
        let at = IstanbulClock.date(from: "2026-09-26", time: "13:00")!
        XCTAssertEqual(snapshot.next(after: before)?.prayer, .ogle)
        XCTAssertEqual(snapshot.current(at: at)?.prayer, .ogle)
        XCTAssertEqual(snapshot.next(after: at)?.prayer, .ikindi)
    }
}
