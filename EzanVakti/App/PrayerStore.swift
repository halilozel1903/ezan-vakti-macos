import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

@MainActor final class PrayerStore: ObservableObject {
    static let shared = PrayerStore()
    @Published private(set) var snapshot: PrayerSnapshot?
    @Published private(set) var loading = false
    @Published var errorMessage: String?
    @Published var showingDistricts = false

    let location = LocationProvider()
    private let service = PrayerService()
    private let resolver = DistrictResolver()

    init() {
        snapshot = SharedSnapshot.load()
        location.onLocation = { [weak self] place in
            Task { await self?.useCurrentLocation(place) }
        }
        location.onError = { [weak self] message in
            Task { await self?.fallbackToAvcilar(message: message) }
        }
        Task { await refreshIfNeeded() }
    }

    var needsLocationChoice: Bool { !SharedSnapshot.defaults.bool(forKey: SharedSnapshot.selectedKey) }

    func refreshIfNeeded() async {
        let now = Date()
        if let snapshot,
           snapshot.day(for: now) != nil,
           snapshot.day(for: IstanbulClock.nextDay(now)) != nil,
           now.timeIntervalSince(snapshot.fetchedAt) < 12 * 60 * 60 {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let previous = snapshot
        await load(district: previous?.district ?? DefaultLocation.district,
                   latitude: previous?.latitude ?? DefaultLocation.latitude,
                   longitude: previous?.longitude ?? DefaultLocation.longitude)
    }

    func select(_ district: String) async {
        loading = true
        errorMessage = nil
        do {
            if district == DefaultLocation.district {
                await load(district: district, latitude: DefaultLocation.latitude, longitude: DefaultLocation.longitude, explicitSelection: true)
            } else {
                let point = try await resolver.coordinate(for: district)
                await load(district: district, latitude: point.latitude, longitude: point.longitude, explicitSelection: true)
            }
            if errorMessage == nil {
                showingDistricts = false
            }
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }

    func useCurrentLocation(_ location: CLLocation) async {
        loading = true
        errorMessage = nil
        do {
            let district = try await resolver.district(for: location)
            await load(district: district, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, explicitSelection: true)
            if errorMessage == nil {
                showingDistricts = false
            }
        } catch {
            await fallbackToAvcilar(message: error.localizedDescription)
        }
    }

    func reload() async {
        await load(district: snapshot?.district ?? DefaultLocation.district,
                   latitude: snapshot?.latitude ?? DefaultLocation.latitude,
                   longitude: snapshot?.longitude ?? DefaultLocation.longitude)
    }

    func fallbackToAvcilar(message: String) async {
        await load(district: DefaultLocation.district,
                   latitude: DefaultLocation.latitude,
                   longitude: DefaultLocation.longitude)
        if errorMessage == nil { errorMessage = "Konum bulunamadı; Avcılar gösteriliyor. \(message)" }
    }

    private func load(district: String, latitude: Double, longitude: Double, explicitSelection: Bool = false) async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let fresh = try await service.fetch(district: district, latitude: latitude, longitude: longitude)
            snapshot = fresh
            if explicitSelection { SharedSnapshot.defaults.set(true, forKey: SharedSnapshot.selectedKey) }
            SharedSnapshot.save(fresh)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onError: ((String) -> Void)?
    private let manager = CLLocationManager()
    private var requestPending = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        requestPending = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways: manager.requestLocation()
        default:
            requestPending = false
            onError?("Konum izni kapalı. Sistem Ayarları’ndan izin verin veya bir ilçe seçin.")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if requestPending && (manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways) {
                manager.requestLocation()
            } else if requestPending && manager.authorizationStatus == .denied {
                requestPending = false
                onError?("Konum izni kapalı. Sistem Ayarları’ndan izin verin veya bir ilçe seçin.")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            requestPending = false
            onLocation?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = "Konum alınamadı: \(error.localizedDescription)"
        Task { @MainActor in
            requestPending = false
            onError?(message)
        }
    }
}
