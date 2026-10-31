//
//  CalculateurPrixView.swift
//  metroreader
//

import SwiftUI


/// Ce que les trajets d'une carte ont coûté, et ce qu'ils auraient coûté
/// autrement : en Liberté+, ou sous un Navigo mois ou annuel.
///
/// Il s'ouvre depuis la fiche de la carte : chaque Navigo a ses trajets. Les
/// prix des forfaits, eux, valent pour toutes les cartes et se règlent dans
/// les Réglages. Les trajets se rangent une fois, hors du fil principal ; les
/// prix se relisent à chaque retour sur la page.
struct CalculateurPrixView: View {
    let events: [[String: Any]]
    let contracts: [[String: Any]]

    @State private var chiffrage: ChiffrageDesTrajets?
    @State private var saisis: [Int: Double] = [:]

    private static let titreDuMois: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = intercodeTimeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        List {
            if let chiffrage {
                let bilans = chiffrage.bilans(saisis: saisis)
                if bilans.isEmpty {
                    Section {
                        Text("Aucun trajet sur cette carte")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(bilans) { bilan in
                    Section {
                        BilanDuMoisView(bilan: bilan)
                    } header: {
                        Text(Self.titreDuMois.string(from: bilan.mois).capitalized)
                    } footer: {
                        if bilan.partiel {
                            Text("La carte ne garde peut-être pas le début de ce mois.")
                        }
                    }
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Calcul des trajets…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Tarifs IDFM au 1er janvier \(String(TarifsIDFM.annee)), plein tarif : Liberté+ \(enEuros(TarifsIDFM.libertePlusRail)) en métro-train-RER et \(enEuros(TarifsIDFM.libertePlusSurface)) en bus-tram, Navigo mois \(enEuros(TarifsIDFM.navigoMois)), Navigo annuel \(enEuros(TarifsIDFM.navigoAnnuel)). L'estimation Liberté+ compte les correspondances : 2 h dans le rail sans sortir, sauf par la voie publique, et 1 h 30 entre bus et tram. Les liaisons aéroport et le tarif réduit n'y sont pas. Le prix de ton forfait se règle dans Réglages › Prix des forfaits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calculateur de prix")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { saisis = PrixDesForfaits.saisis() }
        .task {
            guard chiffrage == nil else { return }
            let events = events, contrats = contracts
            chiffrage = await Task.detached(priority: .userInitiated) {
                ChiffrageDesTrajets(events: events, contrats: contrats)
            }.value
        }
    }
}


/// Les prix des forfaits, saisis une fois pour toutes les cartes.
struct PrixDesForfaitsView: View {
    var body: some View {
        List {
            Section {
                ForEach(PrixDesForfaits.duCatalogue, id: \.self) { tarif in
                    PrixForfaitField(tarif: tarif)
                }
            } footer: {
                Text("Le prix sert à répartir un forfait entre les trajets qu'il a payés. Sans saisie, l'app prend celui que la carte écrit, sinon la grille IDFM \(String(TarifsIDFM.annee)) : Navigo mois, semaine et annuel, Imagine R, Solidarité. Un prix saisi l'emporte sur les deux.")
            }
        }
        .navigationTitle("Prix des forfaits")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


/// Un mois : ce que les trajets ont coûté, et ce qu'ils auraient coûté.
private struct BilanDuMoisView: View {
    let bilan: BilanDuMois

    /// Le moins cher des trois titres, pour ce mois.
    private var moinsCher: String {
        let options = [("Liberté+", bilan.libertePlus),
                       ("Navigo annuel", TarifsIDFM.navigoAnnuelParMois),
                       ("Navigo mois", TarifsIDFM.navigoMois)]
        return options.min { $0.1 < $1.1 }?.0 ?? ""
    }

    var body: some View {
        LabeledContent("Trajets", value: "\(bilan.trajets)")
        LabeledContent("En Liberté+", value: enEuros(bilan.libertePlus))
        LabeledContent("Navigo mois", value: enEuros(TarifsIDFM.navigoMois))
        LabeledContent("Navigo annuel", value: "\(enEuros(TarifsIDFM.navigoAnnuelParMois)) / mois")
        if let forfaits = bilan.forfaits {
            LabeledContent("Ton forfait", value: enEuros(forfaits))
            if bilan.trajets > 0 {
                LabeledContent("Soit par trajet", value: enEuros(forfaits / Double(bilan.trajets)))
            }
        }
        Text(bilan.partiel ? "Sur ce qu'en garde la carte : \(moinsCher) revenait le moins cher."
                           : "\(moinsCher) revenait le moins cher.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}


/// Le prix d'un forfait, à saisir.
private struct PrixForfaitField: View {
    let tarif: Int

    @AppStorage private var saisi: Double

    init(tarif: Int) {
        self.tarif = tarif
        _saisi = AppStorage(wrappedValue: 0, PrixDesForfaits.cle(tarif))
    }

    private var nom: String {
        TariffCatalog.find(tarif)?.name ?? String(format: "Titre 0x%04X", tarif)
    }

    /// Rien tant qu'on n'a rien saisi : le champ montre alors le prix de la
    /// grille, plutôt qu'un zéro.
    private var saisieOptionnelle: Binding<Double?> {
        Binding(get: { saisi > 0 ? saisi : nil }, set: { saisi = max($0 ?? 0, 0) })
    }

    /// Le prix qui s'applique faute de saisie.
    private var parDefaut: PrixForfait? {
        PrixDesForfaits.prix(tarif: tarif, saisis: [:])
    }

    var body: some View {
        let periode = PrixDesForfaits.periode(tarif: tarif)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nom)
                Spacer()
                TextField(parDefaut.map { enEuros($0.montant) } ?? "Prix", value: saisieOptionnelle,
                          format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(maxWidth: 110)
                Text("€")
                    .foregroundStyle(.secondary)
            }
            Text(legende(periode))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func legende(_ periode: PeriodeForfait) -> String {
        if saisi > 0 { return "Saisi, \(periode.parPeriode)" }
        if parDefaut != nil { return "Grille IDFM \(String(TarifsIDFM.annee)), \(periode.parPeriode)" }
        return "Prix inconnu, \(periode.parPeriode) : à saisir"
    }
}
