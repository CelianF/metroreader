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
        return NavigoStations.arrets(exploitant: providerId, mode: mode)
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

    /// « la ligne 5443 », ou « la ligne empruntée » quand la carte annonce une
    /// course que le référentiel ne nomme pas.
    private var laLigne: String {
        lineName.map { "la ligne \($0)" } ?? "la ligne empruntée"
    }

    /// Arrêts de la ligne empruntée, connus même quand le réseau n'a aucun
    /// arrêt indexé sur un code billettique.
    private var arretsDeLaLigne: [LineStop] {
        LineStops.stops(forLine: linePublicId).filter { arret in
            recherche.isEmpty
            || arret.noms.contains { $0.localizedCaseInsensitiveContains(recherche) }
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

    /// Ce que vaut le relevé : son âge par rapport à la validation, et sa
    /// précision. Sans quoi une suggestion à 300 m passe pour une certitude.
    private func qualiteDuReleve(_ releve: (position: CLLocationCoordinate2D,
                                            accuracy: CLLocationDistance)) -> String {
        "Position relevée au moment du scan, à \(Int(gps.gap(from: eventDate) ?? 0)) s de la validation, précise à \(precisionOuZero(releve.accuracy).courte) près."
    }

    /// Une proposition d'arrêt, avec la distance qui dit ce qu'elle vaut.
    ///
    /// Un poteau porte parfois deux noms — celui du référentiel régional et
    /// celui que son exploitant lui donne. Aucun des deux n'a raison contre
    /// l'autre, alors les deux se proposent : c'est le nom lu sur le poteau
    /// qu'on veut au journal, pas celui qu'une table a gardé le plus longtemps.
    @ViewBuilder
    private func suggestion(noms: [String], lat: Double, lon: Double,
                            distance: CLLocationDistance) -> some View {
        ForEach(Array(noms.enumerated()), id: \.offset) { rang, nom in
            Button {
                enregistrer(nom: nom, lat: lat, lon: lon)
            } label: {
                HStack {
                    Text(nom).foregroundStyle(.primary)
                    Spacer()
                    Text(rang == 0 ? distance.courte : "même poteau")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        // Une fois par rendu : le corps la lisait deux fois.
        let arretsDuReseau = candidats
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
                    // Le code lu vient d'un valideur de la ligne empruntée :
                    // son arrêt est dans la liste de cette ligne, forcément.
                    // Les arrêts du voisinage, eux, appartiennent à n'importe
                    // quelle ligne passant là. Tant que la ligne a des arrêts
                    // connus, les proposer — même à part — c'est inviter à
                    // nommer la validation d'après une ligne qu'on n'a pas
                    // prise ; le voisinage ne sert donc qu'à défaut de ligne.
                    let ligneConnue = LineStops.connait(linePublicId)
                    let prochesDeLaLigne = LineStops.around(releve.position, forLine: linePublicId)
                    let voisins = ligneConnue
                        ? []
                        : NearbyStops.around(releve.position, mode: mode)

                    Section {
                        if !prochesDeLaLigne.isEmpty {
                            ForEach(prochesDeLaLigne, id: \.stop.libelle) { arret, distance in
                                suggestion(noms: arret.noms, lat: arret.lat,
                                           lon: arret.lon, distance: distance)
                            }
                        } else if !voisins.isEmpty {
                            // Aucune ligne connue : le voisinage est tout ce
                            // qu'on a, et la note dit ce qu'il vaut.
                            ForEach(voisins, id: \.stop.libelle) { station, distance in
                                suggestion(noms: [station.libelle], lat: station.lat,
                                           lon: station.lon, distance: distance)
                            }
                        } else if ligneConnue {
                            Text("Aucun arrêt de \(laLigne) à moins de 400 m")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Aucun arrêt connu à moins de 400 m")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Là où tu étais au scan")
                    } footer: {
                        Text(ligneConnue
                             ? "\(qualiteDuReleve(releve)) Le code lu vient d'un valideur de \(laLigne) : seuls ses arrêts sont proposés ici."
                             : "\(qualiteDuReleve(releve)) Les arrêts proposés viennent de tous les réseaux — c'est souvent le même arrêt physique.")
                    }
                } else if let ecoule, ecoule < LocationProvider.freshnessWindow {
                    Section {
                        switch gps.state {
                        case .denied:
                            Text("Accès à la position refusé. Il se réactive dans les réglages de l'iPhone.")
                                .foregroundStyle(.secondary)
                        case .requesting:
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Relevé de la position en cours…")
                                    .foregroundStyle(.secondary)
                            }
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
                        ForEach(arretsDeLaLigne, id: \.libelle) { arret in
                            ForEach(Array(arret.noms.enumerated()), id: \.offset) { rang, nom in
                                Button {
                                    enregistrer(nom: nom, lat: arret.lat, lon: arret.lon)
                                } label: {
                                    HStack {
                                        Text(nom)
                                            .foregroundStyle(rang == 0 ? .primary : .secondary)
                                        Spacer()
                                        if rang == 0 {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("même poteau")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Desservi par la ligne \(lineName ?? "")")
                    } footer: {
                        Text("Liste établie depuis le référentiel régional des lignes, indépendante du code billettique — elle vaut donc aussi pour les réseaux dont les arrêts manquent. Quand un poteau y porte un nom et un autre chez son exploitant, les deux sont proposés.")
                    }
                }

                if !arretsDuReseau.isEmpty {
                    Section(surLaLigne ? "Arrêts de la ligne \(lineName ?? "")" : "Tous les arrêts du réseau") {
                        ForEach(arretsDuReseau, id: \.location_id) { station in
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
