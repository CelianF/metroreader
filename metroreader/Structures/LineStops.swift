//
//  LineStops.swift
//  metroreader
//

import Foundation
import CoreLocation


/// Les arrêts desservis par chaque ligne, indexés par l'identifiant IDFM de la
/// ligne — celui que NavigoLines appelle public_id.
///
/// Ne dépend pas du code billettique, donc couvre aussi les réseaux qui n'ont
/// pas déclaré le leur. Sert à proposer un nom quand la carte annonce un arrêt
/// que le référentiel ne sait pas résoudre.
struct LineStop: Decodable {
    let name: String
    /// Le nom complété de sa commune, quand celui du référentiel ne nomme rien :
    /// « Mairie » sur le TVM, qui traverse huit communes, est la mairie de
    /// Chevilly-Larue. Absent dès que le nom se suffit.
    let alias: String?
    let lat: Double
    let lon: Double

    /// Les noms que l'exploitant de la ligne donne au même poteau, quand ils
    /// diffèrent de celui du référentiel régional. Les deux jeux se contredisent
    /// sur deux mille cinq cents arrêts : presque toujours parce que
    /// l'exploitant tronque ou abrège, parfois parce qu'il est le seul à avoir
    /// suivi un renommage — le 162 s'arrête à « Grange Ory » là où le
    /// référentiel écrit encore « Carnot - Aristide Briand ». On n'arbitre pas :
    /// c'est le même arrêt, il porte les deux noms.
    let autres: [String]?

    /// Ce qu'on montre et ce qu'on enregistre en premier. `name` reste ce que le
    /// référentiel écrit, et c'est lui seul qui sert à rapprocher deux tables.
    var libelle: String { alias ?? name }

    /// Tous les noms sous lesquels ce poteau se présente, le libellé principal
    /// en tête. Aucun ne prime sur les autres pour reconnaître une saisie.
    var noms: [String] { [libelle] + (autres ?? []) }
}

public class LineStops {
    private static let table: [String: [LineStop]] =
        DonneesLivrees.charger("LineStops", comme: [String: [LineStop]].self) ?? [:]

    static func stops(forLine publicId: String?) -> [LineStop] {
        guard let publicId, !publicId.isEmpty else { return [] }
        return table[publicId] ?? []
    }

    /// La table connaît-elle les arrêts de cette ligne ?
    ///
    /// Distingue « la ligne ne passe nulle part par ici » de « on ne sait rien
    /// de cette ligne ». Dans le premier cas, l'arrêt du voisinage est celui
    /// d'une autre ligne, et le proposer serait une erreur ; dans le second,
    /// c'est tout ce qu'on a.
    static func connait(_ publicId: String?) -> Bool {
        !stops(forLine: publicId).isEmpty
    }

    /// Décode la table et bâtit l'index des noms comparables.
    static func prechauffer() {
        _ = comparables
    }

    /// La ligne dessert-elle un arrêt de ce nom ?
    ///
    /// Le code qu'écrit un valideur de bus ou de tram est un numéro de séquence
    /// le long de sa ligne : l'arrêt qu'il désigne est forcément dans cette
    /// liste. C'est ce qui permet d'écarter un arrêt que la liste d'un
    /// exploitant, toutes lignes confondues, aurait donné pour ce code.
    static func dessert(_ publicId: String, arret nom: String) -> Bool {
        comparables[publicId]?.contains(comparable(nom)) ?? false
    }

    /// Les noms de chaque ligne, réduits à ce qui permet de les reconnaître.
    /// Normaliser à la volée, c'était replier quatre-vingt mille chaînes à
    /// chaque validation affichée.
    /// Le nom du référentiel et, s'il existe, celui complété de sa commune :
    /// un arrêt nommé « Mairie de Chevilly-Larue » depuis une suggestion doit
    /// se reconnaître dans la « Mairie » que la ligne déclare.
    private static let comparables: [String: Set<String>] =
        table.mapValues { Set($0.flatMap { arret in
            ([arret.name] + arret.noms).map(comparable)
        }) }

    /// Le nom d'un arrêt réduit à ce qui permet de le reconnaître d'une table du
    /// référentiel à l'autre : la casse, les accents et la ponctuation y varient
    /// — « Route d'Ève » s'y écrit aussi « Route d'Eve », et « Trésor public »
    /// « Trésor Public ».
    private static func comparable(_ nom: String) -> String {
        nom.folding(options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "fr_FR"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Les arrêts de la ligne dont le nom ressemble à celui qu'on a saisi.
    ///
    /// Sert là où la position ne dit rien : un code relevé sans coordonnées, ou
    /// un arrêt trop loin de la ligne pour que le voisinage tranche. Une faute
    /// de frappe, un complément de nom omis ou un libellé emprunté au réseau
    /// voisin s'y retrouvent. Au-delà du seuil, on ne propose rien plutôt que
    /// de proposer au hasard.
    static func semblables(_ nom: String, forLine publicId: String?,
                           limit: Int = 3) -> [LineStop] {
        let cible = comparable(nom)
        guard !cible.isEmpty else { return [] }
        let motsCible = mots(nom)
        var vus = Set<String>()
        return stops(forLine: publicId)
            .compactMap { arret -> (stop: LineStop, ecart: Double)? in
                // Le poteau se reconnaît sous n'importe lequel de ses noms : on
                // garde le meilleur rapprochement, pas le premier.
                let ecarts = arret.noms.compactMap { ecart(cible, motsCible, versus: $0) }
                return ecarts.min().map { (arret, $0) }
            }
            .sorted { $0.ecart < $1.ecart }
            .filter { vus.insert($0.stop.libelle).inserted }
            .prefix(limit)
            .map(\.stop)
    }

    /// L'écart entre le nom saisi et l'un des noms d'un arrêt, entre 0 et 1.
    /// Nil au-delà du seuil : mieux vaut ne rien proposer que du hasard.
    private static func ecart(_ cible: String, _ motsCible: Set<String>,
                              versus nom: String) -> Double? {
        let candidat = comparable(nom)
        guard !candidat.isEmpty else { return nil }
        // L'un contient l'autre : « Mairie » pour « Mairie de Rungis ».
        if cible.contains(candidat) || candidat.contains(cible) { return 0 }
        // Les mêmes mots pleins sous un autre habillage : « La Croix de Berny
        // RER » et « Gare de la Croix de Berny » ne se contiennent pas et sont
        // trop loin l'un de l'autre pour la distance d'édition, mais partagent
        // « croix » et « berny ». Il y faut un mot qui désigne vraiment un
        // lieu : « collège » ou « avenue », que la moitié des arrêts porte, ne
        // rapproche de rien.
        let motsCandidat = mots(nom)
        let communs = motsCible.intersection(motsCandidat)
        if communs.contains(where: { $0.count >= 5 && !generiques.contains($0) }),
           communs.count * 2 >= min(motsCible.count, motsCandidat.count) {
            // Plus les deux noms se recouvrent, meilleure est la piste :
            // « berny » seul ne vaut pas « croix » et « berny ».
            let couverture = Double(communs.count)
                             / Double(max(motsCible.count, motsCandidat.count))
            return 0.2 + 0.1 * (1 - couverture)
        }
        let brut = Double(distance(cible, candidat))
                   / Double(max(cible.count, candidat.count))
        return brut <= 0.34 ? brut : nil
    }

    /// Ce qui ne distingue pas deux arrêts : les liaisons, et les qualificatifs
    /// de lieu que les référentiels ajoutent ou omettent au gré des tables.
    private static let liaisons: Set<String> = [
        "de", "du", "des", "d", "la", "le", "les", "l", "et", "en", "sur",
        "au", "aux", "a", "gare", "rer", "quai", "station", "arret",
    ]

    /// Les mots que presque tous les noms d'arrêt portent : ils ne rapprochent
    /// pas deux arrêts, ils les rapprochent tous. Un nom qui ne partage que
    /// ceux-là avec un autre n'en est pas une variante.
    private static let generiques: Set<String> = [
        "avenue", "boulevard", "place", "route", "chemin", "allee", "square",
        "centre", "commercial", "college", "lycee", "ecole", "groupe",
        "eglise", "mairie", "hopital", "stade", "parc", "marche", "piscine",
        "carrefour", "pont", "cimetiere", "gymnase", "poste", "monument",
        "universite", "saint", "sainte", "ville", "nord", "sud", "est",
        "ouest", "grande", "petit", "petite", "vieux", "vieille", "haut",
        "haute", "basse", "rond", "point", "square",
    ]

    /// Les mots pleins d'un nom d'arrêt. « Gare de la Croix de Berny » et « La
    /// Croix de Berny RER » n'ont aucune forme entière en commun, mais bien
    /// « croix » et « berny ».
    private static func mots(_ nom: String) -> Set<String> {
        Set(nom.folding(options: [.diacriticInsensitive, .caseInsensitive],
                        locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !liaisons.contains($0) })
    }

    /// Distance d'édition, sur deux lignes seulement : les noms d'arrêt sont
    /// courts, et cette table en compare quelques dizaines à chaque rendu.
    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var precedente = Array(0...b.count)
        var courante = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            courante[0] = i
            for j in 1...b.count {
                let cout = a[i - 1] == b[j - 1] ? 0 : 1
                courante[j] = min(precedente[j] + 1,
                                  courante[j - 1] + 1,
                                  precedente[j - 1] + cout)
            }
            swap(&precedente, &courante)
        }
        return precedente[b.count]
    }

    /// Les arrêts de la ligne autour d'une position, du plus proche au plus
    /// éloigné et dédoublonnés par nom.
    ///
    /// Le code lu vient d'un valideur de cette ligne : son arrêt est forcément
    /// dans cette liste. Les arrêts du voisinage, eux, appartiennent à
    /// n'importe quelle ligne passant là — proposer les deux à égalité, c'est
    /// inviter à nommer la validation d'après une ligne qu'on n'a pas prise.
    static func around(_ position: CLLocationCoordinate2D,
                       forLine publicId: String?,
                       within radius: CLLocationDistance = 400,
                       limit: Int = 8) -> [(stop: LineStop, distance: CLLocationDistance)] {
        var vus = Set<String>()
        return stops(forLine: publicId)
            .map { (stop: $0, distance: position.distance(toLatitude: $0.lat, longitude: $0.lon)) }
            .filter { $0.distance < radius }
            .sorted { $0.distance < $1.distance }
            .filter { vus.insert($0.stop.libelle).inserted }
            .prefix(limit)
            .map { $0 }
    }
}
