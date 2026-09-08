//
//  EventView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI
import MapKit

struct EventView: View {
    var eventInfo: [String: Any] = [:]
    var contractsInfos: [[String: Any]] = []

    // La résolution est refaite à chaque rendu et le journal est observé : ce
    // qu'on vient d'identifier s'affiche sans quitter l'écran.
    @ObservedObject private var entries = ManualEntries.shared
    @ObservedObject private var gps = LocationProvider.shared

    @State private var cityName: String = "Loading..."
    @State private var identifying: Identification?

    private enum Identification: Int, Identifiable {
        case stop, line, provider
        var id: Int { rawValue }
    }

    init(eventInfo: [String: Any] = [:], contractsInfos: [[String: Any]] = []) {
        self.eventInfo = eventInfo
        self.contractsInfos = contractsInfos
    }

    private var event: ResolvedEvent { ResolvedEvent(eventInfo) }

    private var eventInstant: Date? { ResolvedEvent.instant(eventInfo) }

    var body: some View {
        let event = self.event
        List {
            Section {
                VStack(alignment: .center, spacing: 8) {
                    if event.location.found {
                        Text("\(event.location.name)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)

                        LineIcons(lines: event.location.lines)

                        HStack(spacing: 0) {
                            if let route = event.route {
                                LineIcons(lines: [route])
                            } else {
                                Text("\(event.mode)")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            Text(" - \(interpretTransitionLabel(event.transition))")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    } else {
                        HStack(spacing: 0) {
                            if let route = event.route {
                                LineIcons(lines: [route], size: 50.0)
                            } else {
                                Text("\(event.mode)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                            }
                        }

                        Text(interpretTransitionLabel(event.transition))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                    }

                    // Ce que la carte annonce sans que le référentiel sache le
                    // nommer : chaque manque se comble ici, et la saisie se
                    // relit dans Réglages › Données.
                    if event.hasSomethingToIdentify {
                        VStack(spacing: 6) {
                            if event.isStopUnidentified, let locationId = event.locationId {
                                // Quand la position a été relevée au bon moment,
                                // l'arrêt le plus proche est presque toujours le
                                // bon : on le propose d'un bouton, et la liste
                                // reste à côté pour les cas où il ne l'est pas.
                                if let voisin = suggestion(pour: event) {
                                    VStack(spacing: 6) {
                                        Text("Arrêt \(locationId) inconnu · « \(voisin.stop.name) » à \(voisin.distance.courte)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                        HStack(spacing: 8) {
                                            Button {
                                                ajouter(voisin.stop, pour: event)
                                            } label: {
                                                Label("Ajouter", systemImage: "plus")
                                                    .font(.system(size: 15, weight: .medium))
                                            }
                                            .buttonStyle(.borderedProminent)

                                            Button {
                                                identifying = .stop
                                            } label: {
                                                Label("Autre arrêt", systemImage: "list.bullet")
                                                    .font(.system(size: 15, weight: .medium))
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                } else {
                                    identifyButton("Arrêt inconnu (\(locationId))", icon: "mappin.slash") {
                                        identifying = .stop
                                    }
                                }
                            }
                            if event.isLineUnidentified, let routeNumber = event.routeNumber {
                                identifyButton("Ligne inconnue (\(routeNumber))", icon: "arrow.triangle.swap") {
                                    identifying = .line
                                }
                            }
                            if event.isProviderUnidentified {
                                identifyButton("Réseau inconnu (\(event.providerId))", icon: "building.2") {
                                    identifying = .provider
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    if let eventResult = getKey(eventInfo, "EventResult") {
                        Text("\(interpretEventResult(eventResult))")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    
                    Text("\(interpretDate(getKey(eventInfo, "EventDateStamp") ?? "")) \(interpretTime(getKey(eventInfo, "EventTimeStamp") ?? ""))")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.white.opacity(0.0))
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if interpretInt(getKey(eventInfo, "EventContractPointer") ?? "") <= contractsInfos.count && interpretInt(getKey(eventInfo, "EventContractPointer") ?? "") > 0 {
                        Text("Payé avec \(interpretTariff(getKey(contractsInfos[interpretInt(getKey(eventInfo, "EventContractPointer") ?? "") - 1], "ContractTariff") ?? "", getKey(contractsInfos[interpretInt(getKey(eventInfo, "EventContractPointer") ?? "") - 1], "ContractValidityEndDate") ?? ""))")
                            .fontWeight(.semibold)
                    }
                    else {
                        Text("Payé avec Navigo")
                            .fontWeight(.semibold)
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Transporteur")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(interpretServiceProviderName(event.providerId))
                            .fontWeight(.semibold)
                    }
                    
                    if let eventLocationGate = getKey(eventInfo, "EventLocationGate") {
                        Divider()
                        
                        HStack {
                            Text("Porte")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(interpretInt(eventLocationGate))")
                                .fontWeight(.semibold)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Valideur")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(interpretInt(getKey(eventInfo, "EventDevice") ?? ""))")
                            .fontWeight(.semibold)
                    }
                    
                    if let eventVehicleId = getKey(eventInfo, "EventVehicleId") {
                        Divider()
                        
                        HStack {
                            Text("Véhicule")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(interpretInt(eventVehicleId))")
                                .fontWeight(.semibold)
                        }
                    }
                    
                    if let route = event.route, let routeFromLocation = event.location.lines.first(where: { $0.line_id == route.line_id && $0.provider_id == route.provider_id }), let direction = routeFromLocation.direction {
                        Divider()
                        
                        HStack {
                            Text("Direction")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(direction)")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            
            if event.location.isLocatable {
                let center = CLLocationCoordinate2D(latitude: event.location.lat, longitude: event.location.lon)
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Marker(event.location.name, systemImage: getTransitIcon(event.mode, event.transition), coordinate: center)
                            .tint(TransitionKind(event.transition).color)
                    }
                    .frame(height: 200)
                    // La carte ne relit sa position initiale qu'à sa création :
                    // un arrêt identifié en cours de route la fait renaître.
                    .id("\(center.latitude),\(center.longitude)")
                    Text(cityName)
                        .padding()
                        .task(id: "\(center.latitude),\(center.longitude)") {
                            await fetchCityName(for: center)
                        }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            else {
                Section {
                    HStack {
                        Text("Emplacement")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(event.location.name)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(item: $identifying) { quoi in
            switch quoi {
            case .stop:
                IdentifyStopSheet(providerId: event.providerId,
                                  locationId: event.locationId ?? 0,
                                  mode: event.lookupMode,
                                  routeNumber: event.routeNumber,
                                  lineName: event.routeName,
                                  linePublicId: event.lineData?.public_id,
                                  eventDate: eventInstant)
            case .line:
                IdentifyLineSheet(providerId: event.providerId,
                                  routeNumber: event.routeNumber ?? 0,
                                  mode: event.lookupMode)
            case .provider:
                IdentifyProviderSheet(providerId: event.providerId)
            }
        }
    }

    /// L'arrêt connu le plus proche du relevé fait pendant le scan, quand ce
    /// relevé est assez proche de la validation pour vouloir dire quelque chose.
    private func suggestion(pour event: ResolvedEvent) -> (stop: NearbyStop, distance: CLLocationDistance)? {
        guard let releve = gps.fix(for: eventInstant) else { return nil }
        return NearbyStops.nearest(releve.position, mode: event.lookupMode)
    }

    private func ajouter(_ stop: NearbyStop, pour event: ResolvedEvent) {
        guard let locationId = event.locationId else { return }
        entries.save(StopReport(
            id: UUID(),
            date: Date(),
            providerId: event.providerId,
            locationId: locationId,
            mode: event.lookupMode,
            routeNumber: event.routeNumber,
            lineName: event.routeName,
            stationName: stop.name,
            referenceId: nil,
            lat: stop.lat,
            lon: stop.lon
        ))
    }

    private func identifyButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .medium))
        }
        .buttonStyle(.bordered)
    }
    
    // Reverse Geocoding to get City Name
    func fetchCityName(for coordinate: CLLocationCoordinate2D) async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
              let city = placemark.locality else {
            cityName = "Unknown Location"
            return
        }
        cityName = placemark.administrativeArea.map { "\(city), \($0)" } ?? city
    }
}

#Preview {
    EventView()
}
