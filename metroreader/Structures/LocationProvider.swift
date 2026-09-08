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

    /// Au-delà de ce délai, la position ne renseigne plus sur l'endroit de la
    /// validation : un bus a déjà quitté l'arrêt.
    static let freshnessWindow: TimeInterval = 90

    @Published private(set) var state: State = .idle

    /// Instant du relevé, à comparer à celui de la validation
    @Published private(set) var capturedAt: Date?

    /// Ce qu'iOS a accordé, pour que le réglage puisse le dire.
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorization = manager.authorizationStatus
    }

    /// Appelé quand l'utilisateur allume le réglage.
    ///
    /// Le réglage de l'app et l'autorisation d'iOS sont deux choses : cocher
    /// l'un sans demander l'autre laissait le relevé armé côté app et muet côté
    /// système, et le scan suivant ne rapportait rien. La demande se fait donc
    /// au moment où on coche, pas au premier scan — l'invite d'iOS a besoin
    /// d'un écran, et le scan NFC en occupe un.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            break
        }
    }

    /// Vrai quand iOS refuse, et que l'app n'y peut plus rien : il faut passer
    /// par ses réglages.
    var isDeniedBySystem: Bool {
        authorization == .denied || authorization == .restricted
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

    /// L'écart entre le relevé et la validation. On compare l'instant du scan à
    /// celui de l'événement, et non à maintenant : l'écran peut être ouvert
    /// longtemps après.
    func gap(from eventDate: Date?) -> TimeInterval? {
        guard let eventDate, let capturedAt else { return nil }
        return abs(capturedAt.timeIntervalSince(eventDate))
    }

    /// La position relevée pendant le scan, quand elle éclaire encore cette
    /// validation. Nil dès que le relevé est trop loin de l'événement.
    func fix(for eventDate: Date?) -> (position: CLLocationCoordinate2D, accuracy: CLLocationDistance)? {
        guard case .located(let position, let accuracy) = state,
              let gap = gap(from: eventDate), gap < Self.freshnessWindow else { return nil }
        return (position, accuracy)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
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


extension CLLocationDistance {
    /// Dite en mètres tant que ça reste marchable.
    var courte: String {
        self < 1000 ? "\(Int(rounded())) m" : String(format: "%.1f km", self / 1000)
    }
}
