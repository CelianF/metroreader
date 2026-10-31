//
//  CalculateurPrixView.swift
//  metroreader
//

import SwiftUI


/// Ce que les trajets d'une carte ont coûté, et ce qu'ils auraient coûté
/// autrement : en Liberté+, ou sous un Navigo mois ou annuel.
///
/// Les trajets se rangent une fois, hors du fil principal. Le prix d'un forfait
/// qu'on saisit s'y applique aussitôt, sans relire la carte.
struct CalculateurPrixView: View {
    let events: [[String: Any]]
    let contracts: [[String: Any]]

    @AppStorage(PrixSettings.afficher) private var afficherPrix = false

    @State private var chiffrage: ChiffrageDesTrajets?
    /// Relu à chaque saisie de prix.
    @State private var saisis: [Int: Double] = [:]

    /// Les forfaits de la carte, qu'ils aient payé un trajet ou non.
    private var forfaits: [Int] {
        var tarifs = chiffrage?.tarifsDesForfaits ?? []
        for contrat in contracts where PrixDesForfaits.estForfait(contrat) {
            if let tarif = PrixDesForfaits.tarif(contrat), !tarifs.contains(tarif) { tarifs.append(tarif) }
        }
        return tarifs
    }

    private func contrat(_ tarif: Int) -> [String: Any]? {
        contracts.first { PrixDesForfaits.tarif($0) == tarif }
    }

    private static let titreDuMois: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = intercodeTimeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        List {
            Section {
                Toggle(isOn: $afficherPrix) {
                    Label("Prix sous chaque trajet", systemImage: "eurosign.circle")
                }
            } footer: {
                Text("Dans l'historique, un trajet payé par un forfait affiche sa part du forfait ; un trajet en Liberté+, son estimation.")
            }

            if !forfaits.isEmpty {
                Section {
                    ForEach(forfaits, id: \.self) { tarif in
                        PrixForfaitField(tarif: tarif, contrat: contrat(tarif)) {
                            saisis = PrixDesForfaits.saisis(forfaits)
                        }
                    }
                } header: {
                    Text("Tes forfaits")
                } footer: {
                    Text("Le prix sert à répartir le forfait entre les trajets qu'il a payés. Sans saisie, l'app prend celui que la carte écrit, ou la grille IDFM pour les Navigo mois, semaine et annuel.")
                }
            }

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
                Text("Tarifs IDFM au 1er janvier \(String(TarifsIDFM.annee)), plein tarif : Liberté+ \(enEuros(TarifsIDFM.libertePlusRail)) en métro-train-RER et \(enEuros(TarifsIDFM.libertePlusSurface)) en bus-tram, Navigo mois \(enEuros(TarifsIDFM.navigoMois)), Navigo annuel \(enEuros(TarifsIDFM.navigoAnnuel)). L'estimation Liberté+ compte les correspondances : 2 h dans le rail sans sortir, sauf par la voie publique, et 1 h 30 entre bus et tram. Les liaisons aéroport et le tarif réduit n'y sont pas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calculateur de prix")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            saisis = PrixDesForfaits.saisis(forfaits)
            guard chiffrage == nil else { return }
            let events = events, contrats = contracts
            chiffrage = await Task.detached(priority: .userInitiated) {
                ChiffrageDesTrajets(events: events, contrats: contrats)
            }.value
            saisis = PrixDesForfaits.saisis(forfaits)
        }
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
    let contrat: [String: Any]?
    let onChange: () -> Void

    @AppStorage private var saisi: Double

    init(tarif: Int, contrat: [String: Any]?, onChange: @escaping () -> Void) {
        self.tarif = tarif
        self.contrat = contrat
        self.onChange = onChange
        _saisi = AppStorage(wrappedValue: 0, PrixDesForfaits.cle(tarif))
    }

    private var nom: String {
        TariffCatalog.find(tarif)?.name ?? String(format: "Titre 0x%04X", tarif)
    }

    /// Rien tant qu'on n'a rien saisi : le champ montre alors le prix qui
    /// s'applique, plutôt qu'un zéro.
    private var saisieOptionnelle: Binding<Double?> {
        Binding(get: { saisi > 0 ? saisi : nil }, set: { saisi = max($0 ?? 0, 0) })
    }

    /// Le prix qui s'applique faute de saisie.
    private var parDefaut: PrixForfait? {
        contrat.flatMap { PrixDesForfaits.prix($0, saisis: [:]) }
    }

    var body: some View {
        let periode = contrat.map(PrixDesForfaits.periode) ?? .mois
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
        .onChange(of: saisi) { _, _ in onChange() }
    }

    private func legende(_ periode: PeriodeForfait) -> String {
        if saisi > 0 { return "Saisi, \(periode.parPeriode)" }
        switch parDefaut?.source {
        case .carte:  return "Écrit sur la carte, \(periode.parPeriode)"
        case .grille: return "Grille IDFM \(String(TarifsIDFM.annee)), \(periode.parPeriode)"
        default:      return "Prix inconnu, \(periode.parPeriode) : à saisir"
        }
    }
}
