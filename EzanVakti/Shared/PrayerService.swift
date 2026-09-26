import Foundation
import CoreLocation

enum PrayerServiceError: LocalizedError {
    case invalidResponse, noDistrict, outsideIstanbul
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Vakit bilgileri alınamadı. İnternet bağlantınızı kontrol edin."
        case .noDistrict: "İlçe bulunamadı. Başka bir ilçe seçin."
        case .outsideIstanbul: "Konumunuz İstanbul dışında görünüyor. Lütfen bir İstanbul ilçesi seçin."
        }
    }
}

struct PrayerService {
    private struct APIResponse: Decodable {
        let code: Int
        let data: [APIDay]
    }
    private struct APIDay: Decodable {
        let timings: [String: String]
        let date: APIDate
    }
    private struct APIDate: Decodable {
        let gregorian: GregorianDate
    }
    private struct GregorianDate: Decodable {
        let date: String
    }

    func fetch(district: String, latitude: Double, longitude: Double, now: Date = Date()) async throws -> PrayerSnapshot {
        let current = IstanbulClock.calendar.dateComponents([.year, .month], from: now)
        let nextMonth = IstanbulClock.calendar.date(byAdding: .month, value: 1, to: now)!
        let upcoming = IstanbulClock.calendar.dateComponents([.year, .month], from: nextMonth)
        var days = try await month(year: current.year!, month: current.month!, latitude: latitude, longitude: longitude)
        days += try await month(year: upcoming.year!, month: upcoming.month!, latitude: latitude, longitude: longitude)
        return PrayerSnapshot(district: district, latitude: latitude, longitude: longitude, days: days, fetchedAt: now)
    }

    private func month(year: Int, month: Int, latitude: Double, longitude: Double) async throws -> [PrayerDay] {
        var url = URLComponents(string: "https://api.aladhan.com/v1/calendar/\(year)/\(month)")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "method", value: "13")
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(APIResponse.self, from: data),
              decoded.code == 200 else { throw PrayerServiceError.invalidResponse }
        return decoded.data.compactMap { item in
            let dateParts = item.date.gregorian.date.split(separator: "-")
            guard dateParts.count == 3 else { return nil }
            let key = "\(dateParts[2])-\(dateParts[1])-\(dateParts[0])"
            var times: [Prayer: String] = [:]
            for prayer in Prayer.allCases {
                guard let raw = item.timings[prayer.apiKey] else { return nil }
                let time = String(raw.prefix(5))
                guard IstanbulClock.date(from: key, time: time) != nil else { return nil }
                times[prayer] = time
            }
            return PrayerDay(date: key, times: times)
        }
    }
}

@MainActor final class DistrictResolver {
    private let geocoder = CLGeocoder()

    func coordinate(for district: String) async throws -> CLLocationCoordinate2D {
        let placemarks = try await geocoder.geocodeAddressString("\(district), İstanbul, Türkiye", in: nil, preferredLocale: Locale(identifier: "tr_TR"))
        guard let point = placemarks.first?.location?.coordinate else { throw PrayerServiceError.noDistrict }
        return point
    }

    func district(for location: CLLocation) async throws -> String {
        let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "tr_TR"))
        guard let place = placemarks.first, place.administrativeArea?.localizedStandardContains("İstanbul") == true else { throw PrayerServiceError.outsideIstanbul }
        let candidate = place.subAdministrativeArea ?? place.locality ?? ""
        return IstanbulDistricts.all.first { $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) == .orderedSame } ?? candidate
    }
}
