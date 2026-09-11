//
//  ControlSettingsView.swift
//  metroreader
//

import SwiftUI


/// Les options du timer « Contrôle ».
///
/// Le contrôle ne se juge pas qu'au temps écoulé : il se juge dans un mode.
/// La carte ne sait que ce qu'on a validé, pas où l'on se trouve maintenant —
/// c'est ici qu'on le lui dit.
struct ControlSettingsView: View {
    @AppStorage(TimerSettings.controlOutline) private var outlineEnabled = true
    @AppStorage(TimerSettings.controlMode) private var controlMode = ControlMode.automatique.rawValue
    @AppStorage(TimerSettings.controlTolerance) private var toleranceEnabled = true
    @AppStorage(TimerSettings.controlToleranceMinutes) private var toleranceMinutes = TimerSettings.defaultToleranceMinutes

    private var minutes: Binding<Double> {
        Binding(get: { Double(toleranceMinutes) },
                set: { toleranceMinutes = Int($0.rounded()) })
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $outlineEnabled) {
                    Label("Entourer le visuel", systemImage: "square.dashed")
                }
            } header: {
                Text("Contour")
            }

            Section {
                Picker(selection: $controlMode) {
                    ForEach(ControlMode.allCases) { mode in
                        Label {
                            Text(mode.label)
                        } icon: {
                            Image(mode.icon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                        .tag(mode.rawValue)
                    }
                } label: {
                    Label("Mode contrôlé", systemImage: "figure.stand")
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                Toggle(isOn: $toleranceEnabled) {
                    Label("Tolérer un titre à peine expiré", systemImage: "hourglass")
                }

                if toleranceEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Délai")
                            Spacer()
                            Text(Self.duree(toleranceMinutes))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: minutes,
                               in: TimerSettings.toleranceRange,
                               step: 5) {
                            Text("Délai de tolérance")
                        } minimumValueLabel: {
                            Text("10 min").font(.caption2)
                        } maximumValueLabel: {
                            Text("2 h").font(.caption2)
                        }
                    }
                }
            } header: {
                Text("Tolérance")
            }
        }
        .navigationTitle("Contrôle")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    static func duree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let heures = minutes / 60
        let reste = minutes % 60
        return reste == 0 ? "\(heures) h" : "\(heures) h \(reste)"
    }
}

#Preview {
    NavigationStack { ControlSettingsView() }
}
