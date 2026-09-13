//
//  ContratDesigne.swift
//  metroreader
//

import Foundation


/// La clé sous laquelle une validation garde une copie du titre qu'elle
/// désignait au moment du scan.
let cleContratPaye = "EventContractSnapshot"

/// La clé sous laquelle un contrat garde l'emplacement d'où il a été lu, de 1 à
/// 4, en bits comme le reste de la carte.
let cleEmplacementContrat = "ContractSlot"

/// Le titre qu'une validation désigne.
///
/// La carte ne l'écrit que par un numéro d'emplacement. Lu dans les contrats du
/// scan où la validation figure, il est sûr. Lu dans ceux d'un scan suivant — une
/// fiche d'historique garde les validations d'hier et les contrats d'aujourd'hui —
/// il peut désigner le titre qui a pris la place. D'où, dans l'ordre : la copie
/// faite au scan, l'emplacement noté à la lecture, et à défaut le rang dans la
/// liste, que supposaient les fichiers d'avant et qui se trompait dès qu'un
/// emplacement restait vide.
func contratDesigne(par evenement: [String: Any], parmi contrats: [[String: Any]]) -> [String: Any]? {
    if let copie = evenement[cleContratPaye] as? [String: Any] {
        return copie
    }
    guard let pointeur = getKey(evenement, "EventContractPointer").flatMap({ Int($0, radix: 2) }),
          pointeur > 0 else { return nil }
    if contrats.contains(where: { $0[cleEmplacementContrat] != nil }) {
        return contrats.first { ($0[cleEmplacementContrat] as? String).flatMap { Int($0, radix: 2) } == pointeur }
    }
    return pointeur <= contrats.count ? contrats[pointeur - 1] : nil
}

/// La validation, augmentée d'une copie du titre qu'elle désigne parmi ces
/// contrats — ceux que la carte porte au moment où on la lit.
func figerContratPaye(_ evenement: [String: Any], parmi contrats: [[String: Any]]) -> [String: Any] {
    guard evenement[cleContratPaye] == nil,
          let contrat = contratDesigne(par: evenement, parmi: contrats) else { return evenement }
    var fige = evenement
    fige[cleContratPaye] = contrat
    return fige
}
