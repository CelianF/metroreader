//
//  LineIcons.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//


import SwiftUI

struct LineIcons: View {
    let lines: [NavigoLineInfo]
    let size: CGFloat

    init(lines: [NavigoLineInfo], size: CGFloat = 25) {
        self.lines = lines
        self.size = size
    }

    /// L'ordre des groupes : le ferré d'abord, puis le métro, le tramway et le
    /// câble, la surface en dernier. Un mode que la liste ignore passe après les
    /// autres au lieu de disparaître : c'est ainsi qu'une validation en câble
    /// n'affichait aucune ligne.
    private static let modeOrder = [
        "RER", "Train / RER", "Transilien", "Train", "TER",
        "Métro", "Tramway", "Câble",
        "Bus urbain", "Bus interurbain", "Noctilien", "Navette fluviale",
    ]

    /// Les modes présents, dans cet ordre, les inconnus dans l'ordre où ils
    /// viennent.
    private var presentModes: [String] {
        var vus = Set<String>()
        return lines.map(\.mode)
            .filter { vus.insert($0).inserted }
            .enumerated()
            .sorted { a, b in
                let rangA = Self.modeOrder.firstIndex(of: a.element) ?? Self.modeOrder.count
                let rangB = Self.modeOrder.firstIndex(of: b.element) ?? Self.modeOrder.count
                return (rangA, a.offset) < (rangB, b.offset)
            }
            .map(\.element)
    }

    func lines(for mode: String) -> [NavigoLineInfo] {
        var seenIDs = Set<String>()
        return lines
            // Les TER ne se distinguent que par leur région, que la pastille
            // tait : un seul suffit.
            .filter { $0.mode == mode && seenIDs.insert(mode == "TER" ? "TER" : $0.public_id).inserted }
            // « 2 » avant « 10 », comme sur un plan
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presentModes, id: \.self) { mode in
                HStack(spacing: 4) {
                    Image(Self.modeIconName(for: mode))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundStyle(.primary)

                    ForEach(lines(for: mode), id: \.public_id) { line in
                        PastilleLigne(line, taille: size)
                    }
                }
                // Add extra spacing between different mode groups
                .padding(.trailing, 4)
            }
        }
    }

    /// Le symbole du mode, celui des plans IDFM.
    private static func modeIconName(for mode: String) -> String {
        switch mode {
        case "RER": return "mode_rer"
        case "Train / RER": return "mode_train_rer"
        case "Transilien", "Train", "TER": return "mode_train"
        case "Métro": return "mode_metro"
        case "Tramway": return "mode_tram"
        case "Câble": return "mode_cable"
        case "Noctilien": return "mode_noctilien"
        case "Navette fluviale": return "mode_fluvial"
        default: return "mode_bus"
        }
    }
}

#Preview {
    LineIcons(lines: [NavigoLineInfo(name: "D", mode: "RER", direction: nil, public_id: "D", provider_id: nil, line_id: nil, background_color: "008b5b", text_color: "ffffff", is_noctilien: false), NavigoLineInfo(name: "A", mode: "RER", direction: nil, public_id: "A", provider_id: nil, line_id: nil, background_color: "eb2132", text_color: "ffffff", is_noctilien: false)])
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
