import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

@MainActor final class PrayerStore: ObservableObject {
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
        location.onError = { [weak self] message in self?.errorMessage = message }
        Task { await refreshIfNeeded() }
    }

    func refreshIfNeeded() async {
        let now = Date()
        if let snapshot,
           snapshot.day(for: now) != nil,
           snapshot.day(for: IstanbulClock.nextDay(now)) != nil,
           now.timeIntervalSince(snapshot.fetchedAt) < 12 * 60 * 60 { return }
        let previous = snapshot
        await load(district: previous?.district ?? "Fatih", latitude: previous?.latitude ?? 41.0082, longitude: previous?.longitude ?? 28.9784)
    }

    func select(_ district: String) async {
        loading = true
        errorMessage = nil
        do {
            let point = try await resolver.coordinate(for: district)
            await load(district: district, latitude: point.latitude, longitude: point.longitude)
            if errorMessage == nil { showingDistricts = false }
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
            await load(district: district, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            if errorMessage == nil { showingDistricts = false }
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }

    func reload() async {
        await load(district: snapshot?.district ?? "Fatih", latitude: snapshot?.latitude ?? 41.0082, longitude: snapshot?.longitude ?? 28.9784)
    }

    private func load(district: String, latitude: Double, longitude: Double) async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let fresh = try await service.fetch(district: district, latitude: latitude, longitude: longitude)
            snapshot = fresh
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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways: manager.requestLocation()
        default: onError?("Konum izni kapalı. Sistem Ayarları’ndan izin verin veya bir ilçe seçin.")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in onLocation?(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = "Konum alınamadı: \(error.localizedDescription)"
        Task { @MainActor in onError?(message) }
    }
}
