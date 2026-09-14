//
//  ChampsBruts.swift
//  metroreader
//

import SwiftUI

/// Un champ tel que la carte l'écrit : son nom EN1545 et ses bits.
struct ChampBrut {
    let nom: String
    let bits: String
}

/// Tous les champs d'une structure lue sur la carte : d'abord ceux que sa
/// définition EN1545 décrit, dans l'ordre où elle les range, puis ce que la
/// lecture y a ajouté — les compteurs d'un contrat, son emplacement, l'entrée de
/// la liste qui le désigne. Les clés `exclues` ne s'y lisent pas : la copie du
/// titre payé qu'une validation garde est un contrat, pas un de ses champs.
func champsBruts(_ info: [String: Any], structure: EN1545Element, exclues: Set<String> = []) -> [ChampBrut] {
    var champs: [ChampBrut] = []
    var decrits = Set<String>()

    func parcourir(_ niveau: [String: Any], _ element: EN1545Element, _ chemin: String) {
        for sous in element.subfields ?? [] {
            if sous.field_type == FieldType.Final {
                guard let bits = niveau[sous.name] as? String else { continue }
                champs.append(ChampBrut(nom: sous.name, bits: bits))
                decrits.insert(chemin + sous.name)
            } else if let imbrique = niveau[sous.name] as? [String: Any] {
                parcourir(imbrique, sous, chemin + sous.name + "/")
            }
        }
    }

    func reste(_ niveau: [String: Any], _ chemin: String) {
        for cle in niveau.keys.sorted() where !exclues.contains(cle) {
            if let bits = niveau[cle] as? String {
                if !decrits.contains(chemin + cle) { champs.append(ChampBrut(nom: cle, bits: bits)) }
            } else if let imbrique = niveau[cle] as? [String: Any] {
                reste(imbrique, chemin + cle + "/")
            }
        }
    }

    parcourir(info, structure, "")
    reste(info, "")
    return champs
}

/// « Tous les champs », en bas d'une fiche quand les données brutes sont
/// affichées : chaque champ, sa valeur dans la base choisie et sa longueur. La
/// fiche n'en traduit qu'une partie ; les autres sont ceux qu'on cherche à
/// comprendre.
struct SectionChampsBruts: View {
    let champs: [ChampBrut]
    let base: BaseBrute

    var body: some View {
        Section {
            ForEach(Array(champs.enumerated()), id: \.offset) { _, champ in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(champ.nom)
                        .font(.caption.monospaced())
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(valeur(champ))
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                        Text("\(champ.bits.count) bits")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Tous les champs")
        }
    }

    private func valeur(_ champ: ChampBrut) -> String {
        (base == .hexadecimal ? hexadecimal(champ.bits) : decimal(champ.bits)) ?? "—"
    }
}
