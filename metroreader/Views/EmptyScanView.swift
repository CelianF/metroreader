//
//  EmptyScanView.swift
//  metroreader
//

import SwiftUI

struct EmptyScanView: View {
    var isScanning: Bool = false
    let onScan: () -> Void
    let onImport: () -> Void

    @State private var pulse = false

    /// Hauteur du bouton de scan, mesurée pour que l'import soit un cercle
    /// exactement aussi haut. Le style système décide de sa propre marge, on ne
    /// peut donc pas la deviner.
    @State private var hauteurBouton: CGFloat = 0

    private static let hauteurContenu: CGFloat = 30

    var body: some View {
        VStack(spacing: 24) {
            Image("Cible")
                .resizable()
                .scaledToFit()
                // Pleine largeur, bornée pour ne pas devenir démesurée sur iPad
                .frame(maxWidth: 420)
                // Pendant la lecture, la cible bat entre demi-opacité et pleine
                .opacity(pulse ? 0.5 : 1.0)
                // L'animation est choisie ici plutôt qu'au moment de la
                // mutation : à l'arrêt, c'est le fondu court qui reprend la
                // main, là où un withAnimation laissait la boucle courir.
                .animation(isScanning
                           ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                           : .easeInOut(duration: 0.35),
                           value: pulse)
                .onChange(of: isScanning) { _, enCours in pulse = enCours }
                .onAppear { pulse = isScanning }

            Text(isScanning ? "Collez la carte sur la cible" : "Aucun Navigo scanné")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            actions
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Boutons

    private var actions: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            styled(scanButton)
                .disabled(isScanning)
                .background(mesure)
            importButton
            #else
            // Pas de NFC sur macOS : l'import reste la seule entrée
            styled(importButton)
            #endif
        }
        .onPreferenceChange(HauteurBouton.self) { hauteurBouton = $0 }
    }

    private var scanButton: some View {
        Button(action: onScan) {
            Text(isScanning ? "Scan en cours…" : "Scanner une carte")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: Self.hauteurContenu)
        }
    }

    #if os(iOS)
    /// Le même matériau que la barre du bas, translucide, sur un cercle aussi
    /// haut que le bouton de scan.
    private var importButton: some View {
        let cote = max(hauteurBouton, Self.hauteurContenu)
        return Button(action: onImport) {
            Image(systemName: "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: cote, height: cote)
                .background(.bar, in: Circle())
        }
        .buttonStyle(.plain)
    }
    #else
    private var importButton: some View {
        Button(action: onImport) {
            Label("Importer un fichier", systemImage: "square.and.arrow.down")
                .font(.headline)
                .frame(minHeight: Self.hauteurContenu)
        }
    }
    #endif

    /// Liquid Glass à partir d'iOS 26, style plein en dessous
    @ViewBuilder
    private func styled<V: View>(_ button: V, tint: Color = .blue) -> some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .tint(tint)
    }

    private var mesure: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HauteurBouton.self, value: proxy.size.height)
        }
    }
}

private struct HauteurBouton: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    EmptyScanView(onScan: {}, onImport: {})
}

#Preview("Scan en cours") {
    EmptyScanView(isScanning: true, onScan: {}, onImport: {})
}
