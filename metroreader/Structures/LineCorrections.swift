//
//  LineCorrections.swift
//  metroreader
//

import Foundation


/// Les correspondances course → ligne que le référentiel donne fausses.
///
/// Le numéro de course qu'une carte annonce n'est publié nulle part : IDFM ne
/// diffuse que son `privatecode`, qu'il partage parfois entre plusieurs lignes
/// — cinquante codes pour cent dix-neuf lignes. La table livrée relie donc les
/// deux par observation de vraies cartes, et cette observation se trompe
/// parfois de prétendante.
///
/// Ces corrections vivent à part plutôt que retouchées dans `NavigoLines.json`,
/// pour trois raisons. Un diff y montre ce qu'on surcharge et sur quelle foi,
/// là où une retouche directe serait indiscernable de la donnée d'origine.
/// Elles survivent à une régénération, que le script n'écrit jamais ici. Et
/// leur prémisse se revérifie — `build_data.py corrections` alerte le jour où
/// le référentiel se corrige en amont, pour que la surcharge s'efface au lieu
/// de persister en silence.
///
/// Elles ne passent pas non plus par `ManualEntries` : ce journal est celui de
/// l'utilisateur, effaçable d'un geste depuis les Réglages, et il ne doit pas
/// porter ce que l'app livre — l'utilisateur corrige nos erreurs, il n'en
/// hérite pas comme des siennes.
struct LineCorrection: Decodable {
    /// Ce que la carte annonce
    let provider_id: Int
    let line_id: Int
    let mode: String

    /// La ligne qu'il faut lire, et celle qu'elle déloge
    let public_id: String
    let remplace: String?

    /// Quand la course a été observée, et ce qui fonde la correction
    let constate: String?
    let raison: String?
}


public class LineCorrections {
    static let all: [LineCorrection] = {
        guard let url = Bundle.main.url(forResource: "LineCorrections", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([LineCorrection].self, from: data)
        } catch {
            print("Error loading line corrections: \(error)")
            return []
        }
    }()

    private static let index: [String: LineCorrection] = {
        Dictionary(all.map { (cle($0.provider_id, $0.line_id, $0.mode), $0) },
                   uniquingKeysWith: { first, _ in first })
    }()

    private static func cle(_ provider: Int, _ line_id: Int, _ mode: String) -> String {
        "\(provider)|\(line_id)|\(mode)"
    }

    /// La ligne corrigée pour cette course, quand il y en a une.
    ///
    /// Le nom et les couleurs viennent du référentiel — c'est bien lui qui
    /// décrit la ligne, seul son rattachement à la course était faux. Mais
    /// l'exploitant et la course redeviennent ceux que la carte annonce : la
    /// ligne visée n'est parfois déclarée que sous ses anciens exploitants,
    /// d'avant les délégations, et la laisser sous ceux-là brouillerait tout
    /// rapprochement avec l'arrêt.
    static func corrected(_ provider: Int, _ line_id: Int, _ mode: String,
                          parmi lignes: [NavigoLineInfo]) -> NavigoLineInfo? {
        guard let correction = index[cle(provider, line_id, mode)],
              let ligne = lignes.first(where: { $0.public_id == correction.public_id })
        else { return nil }

        return NavigoLineInfo(name: ligne.name,
                              mode: ligne.mode,
                              direction: ligne.direction,
                              public_id: ligne.public_id,
                              provider_id: provider,
                              line_id: line_id,
                              background_color: ligne.background_color,
                              text_color: ligne.text_color,
                              is_noctilien: ligne.is_noctilien)
    }
}
