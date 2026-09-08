//
//  IdentifyStopSheet.swift
//  metroreader
//

import SwiftUI
import CoreLocation


/// Sélection de l'arrêt correspondant à un identifiant que l'app n'a pas su
/// résoudre. Les arrêts du réseau sont connus — seule la clé manque — donc on
/// propose d'abord ceux de la ligne empruntée.
struct IdentifyStopSheet: View {
    let providerId: Int
    let locationId: Int
    let mode: String
    let routeNumber: Int?
    let lineName: String?
    /// Identifiant IDFM de la ligne, qui donne accès à ses arrêts
    var linePublicId: String?
    /// Instant de la validation, pour juger si la position actuelle veut dire
    /// quelque chose. Une carte scannée le lendemain ne dit rien du trajet.
    var eventDate: Date?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var journal = ManualEntries.shared

    @ObservedObject private var gps = LocationProvider.shared
    @State private var recherche = ""
    @State private var toutLeReseau = false
    @State private var saisieLibre = ""

    /// Arrêts déjà nommés à la main sur ce réseau. Un même arrêt physique porte
    /// plusieurs codes — un par quai, par sens, par exploitant qui le dessert —
    /// et c'est le cas courant : le deuxième code se rattache en un geste.
    private var dejaNommes: [StopReport] {
        var vus = Set<String>()
        return journal.stops
            .filter { $0.mode == mode && $0.locationId != locationId }
            .filter { recherche.isEmpty || $0.stationName.localizedCaseInsensitiveContains(recherche) }
            .filter { vus.insert($0.stationName).inserted }
            .prefix(6)
            .map { $0 }
    }

    /// Arrêts du réseau, dédoublonnés par nom : les quais d'un même arrêt
    /// portent des identifiants différents mais le même libellé.
    private var candidats: [NavigoStationInfo] {
        var vus = Set<String>()
        return NavigoStations.allStations
            .filter { $0.provider_id == providerId && $0.mode == mode }
            .filter { station in
                if toutLeReseau { return true }
                guard let lineName else { return true }
                return station.lines.contains { $0.name == lineName }
            }
            .filter { station in
                recherche.isEmpty
                || station.name.localizedCaseInsensitiveContains(recherche)
            }
            .filter { vus.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var surLaLigne: Bool { lineName != nil && !toutLeReseau }

    /// Arrêts de la ligne empruntée, connus même quand le réseau n'a aucun
    /// arrêt indexé sur un code billettique.
    private var arretsDeLaLigne: [LineStop] {
        LineStops.stops(forLine: linePublicId).filter {
            recherche.isEmpty || $0.name.localizedCaseInsensitiveContains(recherche)
        }
    }

    private var ecoule: TimeInterval? {
        eventDate.map { Date().timeIntervalSince($0) }
    }

    /// Le relevé du scan, s'il éclaire encore cette validation.
    private var releve: (position: CLLocationCoordinate2D, accuracy: CLLocationDistance)? {
        gps.fix(for: eventDate)
    }

    private func precisionOuZero(_ m: CLLocationDistance) -> CLLocationDistance { max(0, m) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Identifiant", value: "\(locationId)")
                    if let lineName {
                        LabeledContent("Ligne", value: lineName)
                    }
                    LabeledContent("Exploitant", value: interpretServiceProviderName(providerId))
                } header: {
                    Text("Ce que la carte annonce")
                } footer: {
                    Text("Cet arrêt n'est pas dans le jeu de données. En l'identifiant, tu l'ajoutes au journal, consultable depuis Réglages › Données.")
                }

                if let releve {
                    Section {
                        // Les arrêts les plus proches, tous exploitants
                        // confondus. Dix des treize réseaux concernés n'ont
                        // aucun arrêt en base, mais leurs arrêts physiques sont
                        // souvent desservis aussi par un réseau qu'on connaît :
                        // c'est de là que vient la suggestion.
                        let voisins = NearbyStops.around(releve.position, mode: mode)
                        if voisins.isEmpty {
                            Text("Aucun arrêt connu à moins de 400 m")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(voisins, id: \.stop.name) { station, distance in
                                Button {
                                    enregistrer(nom: station.name, lat: station.lat, lon: station.lon)
                                } label: {
                                    HStack {
                                        Text(station.name).foregroundStyle(.primary)
                                        Spacer()
                                        Text(distance.courte)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Là où tu étais au scan")
                    } footer: {
                        Text("Position relevée au moment du scan, à \(Int(gps.gap(from: eventDate) ?? 0)) s de la validation, précise à \(precisionOuZero(releve.accuracy).courte) près. Les arrêts proposés viennent de tous les réseaux — c'est souvent le même arrêt physique.")
                    }
                } else if let ecoule, ecoule < LocationProvider.freshnessWindow {
                    Section {
                        switch gps.state {
                        case .denied:
                            Text("Accès à la position refusé. Il se réactive dans les réglages de l'iPhone.")
                                .foregroundStyle(.secondary)
                        default:
                            Text("Aucune position relevée pendant ce scan. Le relevé s'active dans les Réglages, et n'a lieu qu'au moment où tu scannes.")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Là où tu étais au scan")
                    }
                }

                if !dejaNommes.isEmpty {
                    Section {
                        ForEach(dejaNommes) { report in
                            Button {
                                enregistrer(nom: report.stationName, reference: report.referenceId,
                                            lat: report.lat, lon: report.lon)
                            } label: {
                                HStack {
                                    Text(report.stationName).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(report.locationId)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Arrêts que tu as déjà nommés")
                    } footer: {
                        Text("Un même arrêt porte plusieurs codes : un par quai, par sens, ou par exploitant qui le dessert. Le rattacher ici réunit ses codes sous un seul nom.")
                    }
                }

                if !arretsDeLaLigne.isEmpty {
                    Section {
                        ForEach(arretsDeLaLigne, id: \.name) { arret in
                            Button {
                                enregistrer(nom: arret.name, lat: arret.lat, lon: arret.lon)
                            } label: {
                                HStack {
                                    Text(arret.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Desservi par la ligne \(lineName ?? "")")
                    } footer: {
                        Text("Liste établie depuis le référentiel régional des lignes, indépendante du code billettique — elle vaut donc aussi pour les réseaux dont les arrêts manquent.")
                    }
                }

                if !candidats.isEmpty {
                    Section(surLaLigne ? "Arrêts de la ligne \(lineName ?? "")" : "Tous les arrêts du réseau") {
                        ForEach(candidats, id: \.location_id) { station in
                            Button {
                                enregistrer(nom: station.name, reference: station.location_id,
                                            lat: station.lat, lon: station.lon)
                            } label: {
                                HStack {
                                    Text(station.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if lineName != nil {
                    Section {
                        Toggle("Chercher dans tout le réseau", isOn: $toutLeReseau)
                    }
                }

                Section {
                    TextField("Nom de l'arrêt", text: $saisieLibre)
                    Button("Enregistrer ce nom") {
                        enregistrer(nom: saisieLibre.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(saisieLibre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Sinon, à la main")
                } footer: {
                    Text("Dix des treize réseaux concernés n'ont aucun arrêt en base : le nom ne peut alors qu'être saisi. Il remplacera l'identifiant à l'écran, mais l'arrêt ne sera pas placé sur la carte, faute de coordonnées.")
                }
            }
            .searchable(text: $recherche, prompt: "Rechercher un arrêt")
            .navigationTitle("Identifier l'arrêt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func enregistrer(nom: String, reference: Int? = nil,
                             lat: Double? = nil, lon: Double? = nil) {
        guard !nom.isEmpty else { return }
        journal.save(StopReport(
            id: UUID(),
            date: Date(),
            providerId: providerId,
            locationId: locationId,
            mode: mode,
            routeNumber: routeNumber,
            lineName: lineName,
            stationName: nom,
            referenceId: reference,
            lat: lat,
            lon: lon
        ))
        dismiss()
    }
}
