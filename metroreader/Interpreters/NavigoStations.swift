//
//  NavigoStations.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import Foundation


public struct NavigoStationInfo: Codable {
    let name: String
    let provider_id: Int
    let line_id: Int?
    let location_id: Int
    let mode: String
    let lat: Double
    let lon: Double
    let lines: [NavigoLineInfo]
    let found: Bool

    enum CodingKeys: String, CodingKey {
        case name, provider_id, line_id, location_id, mode, lat, lon, lines
        // omit 'found' if it's not in the JSON file
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.provider_id = try container.decode(Int.self, forKey: .provider_id)
        self.line_id = try container.decodeIfPresent(Int.self, forKey: .line_id)
        self.location_id = try container.decode(Int.self, forKey: .location_id)
        self.mode = try container.decode(String.self, forKey: .mode)
        self.lat = try container.decode(Double.self, forKey: .lat)
        self.lon = try container.decode(Double.self, forKey: .lon)
        self.lines = try container.decode([NavigoLineInfo].self, forKey: .lines)

        // Default to true when decoding from JSON
        self.found = true
    }

    init(name: String, provider_id: Int, line_id: Int?, location_id: Int, mode: String,
         lat: Double, lon: Double, lines: [NavigoLineInfo] = [], found: Bool = true) {
        self.name = name
        self.provider_id = provider_id
        self.line_id = line_id
        self.location_id = location_id
        self.mode = mode
        self.lat = lat
        self.lon = lon
        self.lines = lines
        self.found = found
    }

    /// Un arrêt identifié à la main peut n'avoir aucune coordonnée : on connaît
    /// son nom mais rien à placer sur une carte.
    var isLocatable: Bool { found && (lat != 0 || lon != 0) }
}

public class NavigoStations {
    public static let allStations: [NavigoStationInfo] =
        DonneesLivrees.charger("NavigoStations", comme: FichierArrets.self)?.arrets ?? []

    /// Les arrêts rangés par exploitant, identifiant et mode, dans l'ordre du
    /// fichier. Parcourir les quarante mille arrêts à chaque validation coûtait
    /// plusieurs millisecondes : sur une carte chargée, la carte des validations
    /// mettait des secondes à se remplir.
    private static let parCle: [CleReseau: [NavigoStationInfo]] = {
        var index: [CleReseau: [NavigoStationInfo]] = [:]
        for station in allStations {
            index[cle(station.provider_id, station.location_id, station.mode), default: []].append(station)
        }
        return index
    }()

    private static func cle(_ provider: Int, _ location: Int, _ mode: String) -> CleReseau {
        CleReseau(exploitant: provider, numero: location, mode: mode)
    }

    /// Décode la table et bâtit son index : la première recherche n'a plus rien
    /// à attendre.
    static func prechauffer() {
        _ = parCle
    }

    /// Un réseau : un exploitant, un mode.
    private struct Reseau: Hashable {
        let exploitant: Int
        let mode: String
    }

    /// Les arrêts rangés par réseau, pour la liste où l'on choisit un arrêt : la
    /// filtrer parmi les quarante mille, deux fois par rendu et à chaque frappe
    /// dans la recherche, coûtait une quinzaine de millisecondes.
    private static let parReseau: [Reseau: [NavigoStationInfo]] =
        Dictionary(grouping: allStations, by: { Reseau(exploitant: $0.provider_id, mode: $0.mode) })

    /// Les arrêts d'un exploitant pour un mode, dans l'ordre du fichier.
    static func arrets(exploitant: Int, mode: String) -> [NavigoStationInfo] {
        parReseau[Reseau(exploitant: exploitant, mode: mode)] ?? []
    }

    /// Le premier arrêt du fichier à répondre, comme le rendrait un parcours.
    private static func premier(_ provider: Int, _ location: Int, _ mode: String) -> NavigoStationInfo? {
        parCle[cle(provider, location, mode)]?.first
    }

    /// Le même, sur une ligne donnée — rien comptant pour une ligne absente.
    private static func premier(_ provider: Int, _ line: Int?, _ location: Int, _ mode: String) -> NavigoStationInfo? {
        parCle[cle(provider, location, mode)]?.first { $0.line_id == line }
    }

    /// Les modes dont le référentiel numérote les arrêts ligne par ligne.
    ///
    /// Le code d'un bus ou d'un tram n'identifie pas un arrêt sur le réseau :
    /// c'est un numéro de séquence le long d'une ligne. Le 68 de la RATP est
    /// Bourse sur la 29 et tout autre chose sur la 38 ; le 15 est Hélène Boucher
    /// sur le T7 et Basilique de Saint-Denis sur le T1. Chercher un tel code
    /// dans la liste d'un exploitant, toutes lignes confondues, revient à tirer
    /// au sort.
    ///
    /// Le rail n'en est pas : un code de station ou de gare vaut pour le réseau
    /// entier, et c'est bien la liste de l'exploitant qui le porte.
    private static let modesNumerotesParLigne: Set<String> = [
        ModeTransport.busUrbain.rawValue,
        ModeTransport.busInterurbain.rawValue,
        ModeTransport.tramway.rawValue,
    ]

    /// Ce mode numérote-t-il ses arrêts ligne par ligne ?
    ///
    /// Le journal des saisies s'y range de la même façon : un nom relevé sur
    /// une ligne ne vaut pas pour la ligne d'à côté qui réemploie le code.
    static func numeroteParLigne(_ mode: String) -> Bool {
        modesNumerotesParLigne.contains(mode == "RER" ? "Train" : mode)
    }

    /// Tous les arrêts d'une liste portant ce code, dans l'ordre du fichier.
    private static func tous(_ provider: Int, _ location: Int, _ mode: String) -> [NavigoStationInfo] {
        parCle[cle(provider, location, mode)] ?? []
    }

    /// L'arrêt que la liste d'un exploitant donne pour ce code, toutes lignes
    /// confondues — et, pour un mode numéroté ligne par ligne, seulement si la
    /// course annoncée le dessert.
    ///
    /// Pas de repli sans l'exploitant, en revanche. Les identifiants d'arrêt
    /// sont locaux à chaque réseau et massivement recyclés — le 161 est déclaré
    /// par vingt exploitants — donc chercher sans lui renvoie le premier venu
    /// dans l'ordre du fichier, soit un arrêt à l'autre bout de la région
    /// annoncé comme une certitude. Mieux vaut rendre l'identifiant brut.
    ///
    /// `table` est la liste où chercher, `provider` l'exploitant qu'annonce la
    /// carte : les deux diffèrent, mais c'est bien la course de la carte qui
    /// désigne la ligne.
    private static func sansLaLigne(_ table: Int, annonce provider: Int, course: Int?,
                                   _ location: Int, _ mode: String) -> NavigoStationInfo? {
        guard let course, modesNumerotesParLigne.contains(mode) else {
            return premier(table, location, mode)
        }
        let lignes = NavigoLines.candidates(provider, course, mode)
        return tous(table, location, mode).first { arret in
            lignes.contains { dessert($0, arret, annonce: provider) }
        }
    }

    /// La ligne annoncée dessert-elle cet arrêt ?
    ///
    /// Quand le référentiel range l'arrêt sous une ligne — les trams de la RATP,
    /// et eux seuls —, c'est lui qui tranche, et il n'y a rien à deviner. Une
    /// même ligne y figurant sous plusieurs numéros de course, le T1 sous 11,
    /// 921 et 1389, la comparaison porte sur l'identifiant IDFM. C'est ce qui
    /// permet de nommer un arrêt du T1 rangé sous 1389 quand la carte annonce
    /// la course 11, sans pour autant rendre un arrêt du T5 qui se trouverait
    /// porter le même code et figurer aussi sur le T1.
    ///
    /// Partout ailleurs, deux témoignages, l'un ou l'autre suffit : la liste de
    /// lignes que le référentiel attache à l'arrêt, et la liste d'arrêts qu'il
    /// attache à la ligne. Aucun ne couvre les deux modes à lui seul — il
    /// n'attache aucune ligne aux arrêts de tram hors RATP, et un dixième des
    /// arrêts de bus manquent à la liste de leur propre ligne, « Bois
    /// Fleuri-Passerelle N3 » y figurant « RN3 ». Ensemble, ils y suffisent.
    private static func dessert(_ ligne: NavigoLineInfo, _ arret: NavigoStationInfo,
                                annonce provider: Int) -> Bool {
        if let sienne = arret.line_id {
            return NavigoLines.candidates(provider, sienne, arret.mode)
                .contains { $0.public_id == ligne.public_id }
        }
        return arret.lines.contains { $0.public_id == ligne.public_id }
            || LineStops.dessert(ligne.public_id, arret: arret.name)
    }

    /// Les listes du référentiel où chercher les arrêts d'un exploitant.
    ///
    /// Les valideurs n'annoncent pas toujours le numéro sous lequel le
    /// référentiel range leur réseau : la SNCF s'annonce 2 et y figure sous 1,
    /// la RATP s'annonce 3 et y figure sous 59 pour le métro, le tram et le
    /// train, sous 3 pour ses lignes de bus. La recherche ne consultait que la
    /// première, si bien que les neuf mille arrêts de bus n'étaient jamais
    /// atteints — une validation sur un bus RATP n'affichait qu'un nombre.
    ///
    /// Le renvoi vers la RATP s'arrête là. `NavigoLines` en fait un pour les
    /// lignes des délégations « RATP Cap », qui ont gardé leurs numéros sans
    /// être redéclarées ; six d'entre elles ne déclarent aucun arrêt, et il
    /// serait tentant de leur ouvrir la liste de la RATP de la même façon. Ce
    /// serait faux : un code de bus est un numéro de séquence le long d'une
    /// ligne, et le 12 de la 299 à Massy n'a rien à voir avec le 12 de la
    /// liste RATP. Leurs arrêts restent des nombres jusqu'à ce qu'on les
    /// nomme.
    private static func listes(_ provider: Int) -> [Int] {
        switch provider {
        case 2:  return [1]
        case 3:  return [59, 3]
        default: return [provider]
        }
    }

    /// L'exploitant déclare-t-il ce code quelque part dans ses listes ?
    ///
    /// Vrai même quand `find` a refusé de nommer l'arrêt : le code est bien
    /// connu, c'est son rattachement à la ligne annoncée qui ne l'est pas.
    public class func declare(_ provider: Int, _ location: Int, _ mode: String) -> Bool {
        let modeToUse = (mode == "RER") ? "Train" : mode
        return listes(provider).contains { !tous($0, location, modeToUse).isEmpty }
    }

    public class func find(_ provider_id: Int, _ line_id: Int?, _ location_id: Int, _ mode: String) -> NavigoStationInfo? {
        let modeToUse = (mode == "RER") ? "Train" : mode
        let listes = listes(provider_id)

        // Sur la ligne annoncée d'abord, quand le référentiel la donne.
        for table in listes {
            if let station = premier(table, line_id, location_id, modeToUse) { return station }
        }
        // Le bit 15 du code d'un T7 dit le sens, et la carte l'écrit à l'envers
        // de ce que note le référentiel. Les deux sens partageant le nom de
        // l'arrêt, le miroir ramène le bon nom, rien de plus.
        if provider_id == 3, line_id == 17,
           let station = premier(59, 17, location_id ^ 0x8000, modeToUse) {
            return station
        }
        for table in listes {
            if let station = sansLaLigne(table, annonce: provider_id, course: line_id,
                                         location_id, modeToUse) {
                return station
            }
        }
        return nil
    }
}


/// NavigoStations.json, dans l'un ou l'autre de ses formats.
///
/// L'ancien recopiait chaque ligne dans chaque arrêt qu'elle dessert : 4 079
/// lignes distinctes y figuraient 93 132 fois, seize des vingt-cinq
/// mégaoctets. Le format compact, qu'écrit `build_data.py compact`, les range
/// une fois dans une table et ne laisse aux arrêts que leurs rangs. Un fichier
/// produit autrement se lit encore, seulement plus lentement.
private struct FichierArrets: Decodable {
    let arrets: [NavigoStationInfo]

    private enum CodingKeys: String, CodingKey {
        case lines, stations
    }

    init(from decoder: Decoder) throws {
        if let conteneur = try? decoder.container(keyedBy: CodingKeys.self) {
            let lignes = try conteneur.decode([NavigoLineInfo].self, forKey: .lines)
            arrets = try conteneur.decode([ArretCompact].self, forKey: .stations).map { $0.arret(lignes) }
        } else {
            arrets = try [NavigoStationInfo](from: decoder)
        }
    }
}

/// Un arrêt du format compact : ses lignes par leur rang dans la table.
private struct ArretCompact: Decodable {
    let name: String
    let provider_id: Int
    let line_id: Int?
    let location_id: Int
    let mode: String
    let lat: Double
    let lon: Double
    let lines: [Int]

    func arret(_ table: [NavigoLineInfo]) -> NavigoStationInfo {
        NavigoStationInfo(name: name, provider_id: provider_id, line_id: line_id,
                          location_id: location_id, mode: mode, lat: lat, lon: lon,
                          lines: lines.compactMap { table.indices.contains($0) ? table[$0] : nil },
                          found: true)
    }
}
