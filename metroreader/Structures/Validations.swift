//
//  Validations.swift
//  metroreader
//

import Foundation


/// Ce que la carte écrit d'une validation, lu une fois : l'instant, le mode et
/// la transition de la borne, le titre qu'elle désigne.
struct LectureValidation {
    let instant: Date?
    /// Le mode tel que la carte l'encode.
    let mode: String
    /// La transition telle que la borne l'a écrite.
    let brute: String
    /// La même, lue comme aux portes relevées qui mènent au métro.
    let transition: String
    let refus: Bool
    /// L'exploitant et la course, pour reconnaître une ligne reprise. Rien quand
    /// la carte ne les écrit pas, comme aux portes SNCF.
    let ligne: LigneEmpruntee?
    /// Le titre que la validation désigne.
    let contrat: [String: Any]?
    /// Payé par un titre sans compteur — un forfait, ou Liberté+. Faute de titre
    /// désigné, on ne se prononce pas.
    let forfait: Bool

    init(_ evenement: [String: Any], contrats: [[String: Any]]) {
        let course = getKey(evenement, "EventRouteNumber").flatMap { Int($0, radix: 2) }
        let exploitant = getKey(evenement, "EventServiceProvider").flatMap { Int($0, radix: 2) }
        let (mode, brute) = interpretEventCode(getKey(evenement, "EventCode") ?? "",
                                               isRouteNumberPresent: course != nil,
                                               routeNumber: course,
                                               serviceProvider: exploitant)
        self.instant = ResolvedEvent.instant(evenement)
        self.mode = mode
        self.brute = brute
        self.transition = transitionAuxPortes(brute, evenement)
        self.refus = isRefus(evenement)
        if let course, let exploitant {
            self.ligne = LigneEmpruntee(exploitant: exploitant, course: course)
        } else {
            self.ligne = nil
        }
        let contrat = contratDesigne(par: evenement, parmi: contrats)
        self.contrat = contrat
        self.forfait = contrat.map { getKey($0, "CounterContractCount") == nil } ?? false
    }
}


/// Une ligne, telle qu'un trajet la reconnaît : l'exploitant et la course.
struct LigneEmpruntee: Hashable {
    let exploitant: Int
    let course: Int
}


/// Les validations d'une carte, lues chacune une seule fois.
///
/// Raconter une validation demande ses voisines : la sortie « voie publique »
/// que suit une entrée ferrée, l'entrée qui prolonge un trajet sous forfait.
/// Chaque ligne affichée recopiait donc les validations d'avant et d'après, et
/// relisait de chacune code, porte, instant et titre : une liste de n
/// validations en faisait n². Elles ne se lisent plus qu'à la demande, une
/// fois chacune, et leurs transitions de même.
///
/// Une classe, pour que les lignes d'un même rendu partagent ce qui est lu ;
/// à ne pas partager d'un fil à l'autre.
final class Validations {
    let evenements: [[String: Any]]
    let contrats: [[String: Any]]
    private var lectures: [LectureValidation?]
    private var transitions: [String?]

    init(_ evenements: [[String: Any]], contrats: [[String: Any]]) {
        self.evenements = evenements
        self.contrats = contrats
        lectures = Array(repeating: nil, count: evenements.count)
        transitions = Array(repeating: nil, count: evenements.count)
    }

    subscript(i: Int) -> LectureValidation {
        if let lue = lectures[i] { return lue }
        let lue = LectureValidation(evenements[i], contrats: contrats)
        lectures[i] = lue
        return lue
    }

    /// Les validations écrites après la i-ième — la carte range la plus récente
    /// en tête —, de la plus proche à la plus lointaine.
    func suivants(de i: Int) -> LazyMapCollection<ReversedCollection<Range<Int>>, LectureValidation> {
        (0..<i).reversed().lazy.map { self[$0] }
    }

    /// Les validations écrites avant la i-ième, de la plus proche à la plus
    /// lointaine.
    func precedents(de i: Int) -> LazyMapCollection<Range<Int>, LectureValidation> {
        ((i + 1)..<evenements.count).lazy.map { self[$0] }
    }

    /// La transition que le trajet raconte pour la i-ième validation.
    func transition(de i: Int) -> String {
        if let racontee = transitions[i] { return racontee }
        let racontee = transitionRacontee(self[i], suivants: suivants(de: i), precedents: precedents(de: i))
        transitions[i] = racontee
        return racontee
    }
}
