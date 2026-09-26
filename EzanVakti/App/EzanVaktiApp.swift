import SwiftUI

@main struct EzanVaktiApp: App {
    @StateObject private var store = PrayerStore()

    var body: some Scene {
        MenuBarExtra {
            PrayerPanel(store: store)
        } label: {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                if let next = store.snapshot?.next(after: timeline.date) {
                    let minutes = max(0, Int(ceil(next.date.timeIntervalSince(timeline.date) / 60)))
                    Label("\(next.prayer.title) \(minutes) dk", systemImage: "moon.stars.fill")
                } else {
                    Label("Ezan Vakti", systemImage: "moon.stars.fill")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
