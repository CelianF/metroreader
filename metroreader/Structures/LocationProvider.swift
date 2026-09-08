//
//  LocationProvider.swift
//  metroreader
//

import Foundation
import CoreLocation


/// La position au moment du scan.
///
/// Sert à proposer les arrêts proches quand la carte annonce un identifiant que
/// le référentiel ne connaît pas. Le relevé est déclenché au début de la lecture
/// NFC, et non à l'ouverture du sélecteur : entre les deux il s'écoule le temps
/// de consulter la carte, pendant lequel un bus a déjà quitté l'arrêt. C'est
/// l'instant du scan qui approche celui de la validation, pas celui du regard.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum State: Equatable {
        case idle
        case requesting
        case located(CLLocationCoordinate2D, accuracy: CLLocationDistance)
        case denied
        case failed

        static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.idle, .idle), (.requesting, .requesting), (.denied, .denied), (.failed, .failed):
                return true
            case let (.located(c1, a1), .located(c2, a2)):
                return c1.latitude == c2.latitude && c1.longitude == c2.longitude && a1 == a2
            default:
                return false
            }
        }
    }

    static let shared = LocationProvider()

    /// Clé du réglage qui autorise le relevé au scan
    static let settingKey = "locateOnScan"

    @Published private(set) var state: State = .idle

    /// Instant du relevé, à comparer à celui de la validation
    @Published private(set) var capturedAt: Date?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Appelé au début d'un scan, si le réglage l'autorise.
    func captureForScan() {
        guard UserDefaults.standard.bool(forKey: Self.settingKey) else { return }
        request()
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .requesting
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            state = .denied
        default:
            state = .requesting
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if state == .requesting { manager.requestLocation() }
        case .denied, .restricted:
            state = .denied
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let position = locations.last else { return }
        capturedAt = Date()
        state = .located(position.coordinate, accuracy: position.horizontalAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        state = .failed
    }
}


extension CLLocationCoordinate2D {
    /// Distance à vol d'oiseau, en mètres.
    func distance(toLatitude lat: Double, longitude lon: Double) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lon))
    }
}
