//
//  DonneesLivrees.swift
//  metroreader
//

import Foundation


/// Les tables livrées avec l'app, sous Data/.
enum DonneesLivrees {

    /// Lit une table livrée ; nil, et un mot dans la console, quand elle manque
    /// ou ne se décode pas. Ce chargement était recopié dans dix catalogues.
    static func charger<T: Decodable>(_ nom: String, comme type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: nom, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Table \(nom).json absente")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Lecture de \(nom).json impossible : \(error)")
            return nil
        }
    }

    /// Décode d'avance, hors du fil principal, les tables qu'interroge chaque
    /// validation affichée.
    ///
    /// NavigoStations se décodait au premier rendu d'un événement : plusieurs
    /// centaines de millisecondes sur le fil principal, en pleine animation
    /// d'arrivée de la carte. Chaque table ne se décode qu'une fois ; si l'écran
    /// en réclame une avant la fin, il n'attend que celle-là.
    static func prechauffer() {
        NavigoStations.prechauffer()
        NavigoLines.prechauffer()
        StopCorrections.prechauffer()
        LineCorrections.prechauffer()
        GateCorrections.prechauffer()
        _ = ProviderCatalog.findProvider(0)
        _ = TariffCatalog.find(0)
    }
}


/// Ce qui désigne un arrêt ou une ligne dans les index : l'exploitant, le
/// numéro que la carte annonce et le mode. Une structure plutôt qu'une chaîne
/// composée à la volée, allouée à chaque recherche et écrite différemment d'un
/// index à l'autre.
struct CleReseau: Hashable {
    let exploitant: Int
    let numero: Int
    let mode: String
}
