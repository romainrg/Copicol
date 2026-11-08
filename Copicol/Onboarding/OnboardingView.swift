import Combine
import SwiftUI

/// Premier lancement : présentation et autorisation Accessibilité (vérifiée en continu).
struct OnboardingView: View {
    let accessibility: AccessibilityPermission
    @Bindable var settings: SettingsStore
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bienvenue dans Copicol")
                        .font(.title.bold())
                    Text("Tout ce que vous copiez, retrouvable en un raccourci.")
                        .foregroundStyle(.secondary)
                }
            }

            step(
                number: 1,
                title: "Copiez comme d'habitude",
                detail: "Textes, images, fichiers, liens et couleurs sont enregistrés automatiquement. Les contenus marqués confidentiels (mots de passe) et les applications exclues sont ignorés."
            )
            step(
                number: 2,
                title: "Ouvrez l'étagère avec \(settings.shelfHotKey.displayString)",
                detail: "Flèches pour naviguer, ↩ pour coller, ⇧↩ pour coller en texte brut, ⌘1…⌘9 pour coller directement, Espace pour l'aperçu, saisie directe pour rechercher."
            )
            accessibilityBox

            HStack {
                Spacer()
                Button("Commencer", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 580)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibility.refresh()
        }
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: accessibility.isGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accessibility.isGranted ? .green : .orange)
                Text(accessibility.isGranted ? "Accès Accessibilité accordé" : "Autorisation Accessibilité requise pour coller")
                    .font(.headline)
            }
            Text("Pour coller directement dans l'application active, Copicol simule la frappe ⌘V. macOS réserve cette capacité aux applications autorisées dans Réglages Système › Confidentialité et sécurité › Accessibilité. Copicol ne lit ni n'enregistre vos frappes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !accessibility.isGranted {
                HStack {
                    Button("Demander l'autorisation") { accessibility.request() }
                    Button("Ouvrir Réglages Système") { accessibility.openSystemSettings() }
                }
            }
            Picker("Après sélection d'un élément :", selection: $settings.pasteMode) {
                ForEach(PasteMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            Text("En mode « copier seulement », aucune autorisation n'est nécessaire : l'élément est placé dans le presse-papiers et vous collez vous-même avec ⌘V.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
