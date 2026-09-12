//
//  ValidationHistoryView.swift
//  metroreader
//

import SwiftUI


/// Toutes les validations d'une carte, par jour puis par trajet.
///
/// La carte les donne en vrac, de la plus récente à la plus ancienne ; c'est
/// au trajet qu'on les relit. Chaque trajet forme un bloc, et le jour coiffe le
/// premier de sa journée.
///
/// Sur une carte chargée, tout résoudre d'un coup figeait l'écran : la page
/// s'ouvre sur la dernière semaine, cinquante validations au plus, et calcule
/// ses trajets hors du fil principal. Le reste se demande.
struct ValidationHistoryView: View {
    let events: [[String: Any]]
    let contracts: [[String: Any]]

    // Un arrêt identifié depuis une fiche se renomme ici sans quitter l'écran.
    @ObservedObject private var entries = ManualEntries.shared

    /// Faux tant qu'on s'en tient à la dernière semaine.
    @State private var toutVoir = false
    /// Les trajets montrés, rien tant qu'ils se calculent.
    @State private var journees: [JourneeDeTrajets]?

    /// La carte s'ouvre en grand d'un toucher, sur l'étendue de la liste.
    @State private var carteEnGrand = false
    @State private var joursALOuverture = 7

    /// Ce que la page montre d'emblée.
    private static let joursAffiches = 7
    private static let validationsAffichees = 50

    /// La moitié de l'écart ordinaire entre deux sections.
    private static let ecartEntreTrajets: CGFloat = 17.5

    private static let titreDuJour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = intercodeTimeZone
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    /// Combien de validations, en tête de la carte, la page montre.
    private var montrees: Int {
        guard !toutVoir else { return events.count }
        let semaine = debutDesDerniersJours(events, jours: Self.joursAffiches)
            .map { nombreDeValidations(events, depuis: $0) } ?? events.count
        return min(semaine, Self.validationsAffichees)
    }

    /// Au moins une des `n` premières validations se place sur une carte :
    /// sinon, pas de carte vide.
    private func carteUtile(_ n: Int) -> Bool {
        events.prefix(n).contains { event in
            interpretLocationId(getKey(event, "EventLocationId") ?? "",
                                getKey(event, "EventCode") ?? "",
                                getKey(event, "EventServiceProvider") ?? "",
                                getKey(event, "EventRouteNumber")).isLocatable
        }
    }

    private func compte(_ n: Int) -> String {
        n == 1 ? "1 validation" : "\(n) validations"
    }

    var body: some View {
        let montrees = self.montrees
        List {
            if carteUtile(montrees) {
                Section {
                    // Dans la liste, la carte ne se manipule pas : la toucher
                    // l'ouvre en grand, où elle se déplace et se zoome.
                    Button {
                        joursALOuverture = toutVoir ? max(joursCouverts(events), 1) : Self.joursAffiches
                        carteEnGrand = true
                    } label: {
                        EventsMapView(events: events, affiches: montrees, contrats: contracts)
                            .allowsHitTesting(false)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(8)
                                    .background(.regularMaterial, in: Circle())
                                    .padding(10)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            if let journees {
                ForEach(journees) { journee in
                    ForEach(Array(journee.trajets.enumerated()), id: \.element.id) { rang, trajet in
                        Section {
                            ForEach(trajet.indices, id: \.self) { i in
                                NavigationLink {
                                    EventView(eventInfo: events[i],
                                              suivants: Array(events[..<i]),
                                              precedents: Array(events[(i + 1)...]),
                                              contractsInfos: contracts)
                                } label: {
                                    EventPreview(eventInfo: events[i],
                                                 suivants: Array(events[..<i]),
                                                 precedents: Array(events[(i + 1)...]),
                                                 contrats: contracts,
                                                 afficheDate: false)
                                }
                            }
                        } header: {
                            if rang == 0 {
                                Text(Self.titreDuJour.string(from: journee.jour))
                            }
                        }
                    }
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Chargement des trajets…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !toutVoir && montrees < events.count {
                Section {
                    Button {
                        toutVoir = true
                    } label: {
                        HStack {
                            Text("Voir tout l'historique")
                            Spacer()
                            Text("+ \(compte(events.count - montrees))")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        // Deux trajets d'un même jour se tiennent à mi-distance de l'ordinaire.
        // Entre deux jours, le titre garde son écart : 57 pt avant comme après.
        .listSectionSpacing(Self.ecartEntreTrajets)
        .navigationTitle("Validations")
        .task(id: toutVoir) {
            journees = nil
            let calculees = await Self.calculerJournees(events, contrats: contracts, n: montrees)
            if !Task.isCancelled { journees = calculees }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $carteEnGrand) {
            CarteEnGrand(events: events, contrats: contracts, joursInitiaux: joursALOuverture)
        }
        #endif
    }

    /// Les trajets des `n` premières validations, hors du fil principal.
    nonisolated private static func calculerJournees(_ events: [[String: Any]], contrats: [[String: Any]],
                                                     n: Int) async -> [JourneeDeTrajets] {
        guard n < events.count else { return trajetsParJour(events, contrats: contrats) }
        // Ce qui précède la plus ancienne retenue, sur 3 h, entre dans le
        // calcul sans s'afficher : elle en a besoin pour savoir si elle
        // prolonge un trajet.
        var marge = n
        if n > 0, let ancienne = ResolvedEvent.instant(events[n - 1]) {
            marge = max(n, nombreDeValidations(events, depuis: ancienne.addingTimeInterval(-3 * 3600)))
        }
        return trajetsParJour(Array(events.prefix(marge)), contrats: contrats).compactMap { journee in
            let trajets = journee.trajets.compactMap { trajet -> Trajet? in
                let retenues = trajet.indices.filter { $0 < n }
                return retenues.isEmpty ? nil : Trajet(indices: retenues)
            }
            return trajets.isEmpty ? nil : JourneeDeTrajets(jour: journee.jour, trajets: trajets)
        }
    }
}


#if os(iOS)
/// Combien de validations, en tête de la carte, tiennent dans les `jours`
/// derniers jours — sur des dates déjà lues.
private func validationsSurLesDerniersJours(_ jours: Int, dates: [Date?], recente: Date?) -> Int {
    guard let recente else { return dates.count }
    let limite = debutDesDerniersJours(depuis: recente, jours: jours)
    return dates.firstIndex { ($0 ?? .distantPast) < limite } ?? dates.count
}

/// La carte des validations en plein écran, et le curseur qui l'étend.
///
/// Le curseur vit dans sa propre vue : le glisser ne redessine que lui, ni la
/// carte ni l'historique derrière. La carte reste affichée pendant le geste et
/// ne se recharge qu'au lâcher.
private struct CarteEnGrand: View {
    let events: [[String: Any]]
    let contrats: [[String: Any]]

    @Environment(\.dismiss) private var dismiss

    /// Les dates des validations, lues une fois pour toutes.
    private let dates: [Date?]
    private let recente: Date?
    private let couverts: Int

    @State private var joursRetenus: Int

    init(events: [[String: Any]], contrats: [[String: Any]], joursInitiaux: Int) {
        self.events = events
        self.contrats = contrats
        let dates = events.map { ResolvedEvent.instant($0) }
        self.dates = dates
        recente = dates.compactMap { $0 }.max()
        couverts = max(joursCouverts(dates.compactMap { $0 }), 1)
        let depart = min(max(joursInitiaux, 1), couverts)
        _joursRetenus = State(initialValue: depart)
    }

    var body: some View {
        NavigationStack {
            EventsMapView(events: events,
                          affiches: validationsSurLesDerniersJours(joursRetenus, dates: dates, recente: recente),
                          contrats: contrats, hauteur: nil)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) {
                    if couverts > 1 {
                        CurseurDesJours(dates: dates, recente: recente, couverts: couverts,
                                        joursRetenus: $joursRetenus)
                    }
                }
                .navigationTitle("Carte des validations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
    }
}

/// Le curseur, du dernier jour à toute la carte.
///
/// Il glisse d'un geste continu, sans crans : un cran par jour, sur des mois
/// de validations, faisait vibrer le téléphone en rafale. Il garde sa valeur
/// pour lui pendant le geste, et ne rend l'étendue, arrondie au jour, qu'au
/// lâcher.
private struct CurseurDesJours: View {
    let dates: [Date?]
    let recente: Date?
    let couverts: Int
    @Binding var joursRetenus: Int

    @State private var jours: Double

    init(dates: [Date?], recente: Date?, couverts: Int, joursRetenus: Binding<Int>) {
        self.dates = dates
        self.recente = recente
        self.couverts = couverts
        _joursRetenus = joursRetenus
        _jours = State(initialValue: Double(joursRetenus.wrappedValue))
    }

    var body: some View {
        let valeur = Int(jours.rounded())
        let etendue = valeur >= couverts ? "Toute la carte"
            : valeur == 1 ? "Le dernier jour"
            : "Les \(valeur) derniers jours"
        let n = validationsSurLesDerniersJours(valeur, dates: dates, recente: recente)
        VStack(spacing: 6) {
            HStack {
                Text(etendue)
                Spacer()
                Text(n == 1 ? "1 validation" : "\(n) validations")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: $jours, in: 1...Double(couverts)) { geste in
                if !geste { joursRetenus = Int(jours.rounded()) }
            }
        }
        .padding()
        .modifier(VerreDuCurseur())
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// Le fond du curseur : du verre liquide, qui laisse voir la carte dessous.
/// Avant iOS 26, le matériau translucide d'avant.
private struct VerreDuCurseur: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
#endif
