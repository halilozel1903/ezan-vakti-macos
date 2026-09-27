import AppKit
import SwiftUI

@MainActor final class EzanVaktiDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if PrayerStore.shared.needsLocationChoice {
            LocationChoiceWindow.shared.show()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "ezanvakti" }) {
            LocationChoiceWindow.shared.show()
        }
    }
}

@MainActor final class LocationChoiceWindow {
    static let shared = LocationChoiceWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 410, height: 530),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Konum ve ilçe seçimi"
            window.contentView = NSHostingView(rootView: LocationChoiceView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}

struct LocationChoiceView: View {
    @ObservedObject private var store = PrayerStore.shared
    @State private var search = ""
    @State private var waitingForChoice = false

    private var districts: [String] {
        search.isEmpty ? IstanbulDistricts.all : IstanbulDistricts.all.filter {
            $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill").foregroundStyle(.orange)
                Text("Ezan Vakti").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
            }
            Text("Vakitler hangi ilçe için gösterilsin?")
                .font(.system(size: 18, weight: .semibold))
            Text("Konumuna izin ver veya İstanbul’un 39 ilçesinden birini seç. Konum bulunamazsa Avcılar gösterilir.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            Button {
                waitingForChoice = true
                store.location.request()
            } label: {
                Label("Konumumu kullan", systemImage: "location.fill")
                    .frame(maxWidth: .infinity).padding(10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            HStack {
                TextField("İlçe ara", text: $search)
                Button("Avcılar’ı kullan") {
                    waitingForChoice = true
                    Task {
                        await store.select(DefaultLocation.district)
                        if store.errorMessage == nil {
                            LocationChoiceWindow.shared.close()
                        }
                    }
                }
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(districts, id: \.self) { district in
                        Button {
                            waitingForChoice = true
                            Task {
                                await store.select(district)
                                if store.errorMessage == nil {
                                    LocationChoiceWindow.shared.close()
                                }
                            }
                        } label: {
                            HStack {
                                Text(district)
                                Spacer()
                                if district == store.snapshot?.district {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 10).frame(height: 31)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if store.loading { ProgressView("Vakitler alınıyor…") }
            if let error = store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Text("Konum seçilirse koordinatlar yalnızca vakitleri almak için AlAdhan’a gönderilir.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 410, height: 530)
        .background(Color(red: 0.10, green: 0.13, blue: 0.18))
        .foregroundStyle(.white)
        .onChange(of: store.snapshot?.district) { _, _ in
            if waitingForChoice && !store.loading && store.errorMessage == nil {
                LocationChoiceWindow.shared.close()
            }
        }
    }
}
