import AppKit
import Carbon.HIToolbox
import CopicolCore
import SwiftUI

/// Fenêtre de réglages.
struct SettingsView: View {
    let model: SettingsViewModel

    var body: some View {
        TabView {
            GeneralPane(model: model)
                .tabItem { Label("Général", systemImage: "gearshape") }
            ShelfPane(model: model)
                .tabItem { Label("Étagère", systemImage: "rectangle.bottomthird.inset.filled") }
            HistoryPane(model: model)
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
            ExclusionsPane(model: model)
                .tabItem { Label("Exclusions", systemImage: "hand.raised") }
            SyncPane(model: model)
                .tabItem { Label("iCloud", systemImage: "icloud") }
        }
        .frame(width: 580, height: 470)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refresh()
        }
    }
}

// MARK: - Général

private struct GeneralPane: View {
    let model: SettingsViewModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle("Lancer Copicol à l'ouverture de session", isOn: Binding(
                    get: { model.launchAtLogin.isEnabled },
                    set: { model.launchAtLogin.setEnabled($0) }
                ))
                if model.launchAtLogin.requiresApproval {
                    HStack {
                        Text("À approuver dans Réglages Système › Général › Ouverture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Ouvrir") { model.launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = model.launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Sons à la copie et au collage", isOn: $settings.playsSounds)
            }

            Section("Collage") {
                Picker("Après sélection d'un élément", selection: $settings.pasteMode) {
                    ForEach(PasteMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Toggle("Toujours coller en texte brut", isOn: $settings.alwaysPastePlainText)
                LabeledContent("Accessibilité") {
                    if model.accessibility.isGranted {
                        Label("Autorisée", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("Non autorisée", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Button("Autoriser…") {
                                model.accessibility.request()
                                model.accessibility.openSystemSettings()
                            }
                        }
                    }
                }
                Button("Revoir l'introduction…") { model.onShowOnboarding?() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Étagère

private struct ShelfPane: View {
    let model: SettingsViewModel

    private let shortcuts: [(keys: String, action: String)] = [
        ("↩", "Coller l'élément sélectionné"),
        ("⇧↩", "Coller en texte brut"),
        ("⌘1 … ⌘9", "Coller l'élément n"),
        ("Espace", "Aperçu en grand"),
        ("⌦ (Fn-⌫) ou ⌘⌫", "Supprimer l'élément"),
        ("⌘C", "Copier sans coller"),
        ("⌘F ou saisie", "Rechercher"),
        ("⇥ / ⇧⇥", "Onglet suivant / précédent"),
        ("⎋", "Effacer la recherche, puis fermer")
    ]

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Raccourci global") {
                LabeledContent("Ouvrir l'étagère") {
                    HStack {
                        ShortcutRecorder(combo: $settings.shelfHotKey) { recording in
                            model.onShortcutRecording?(recording)
                        }
                        Button("Par défaut") { settings.shelfHotKey = .defaultShelf }
                            .disabled(settings.shelfHotKey == .defaultShelf)
                    }
                }
                if !settings.isHotKeyRegistered {
                    Text("Ce raccourci est déjà utilisé par une autre application : choisissez-en un autre.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Apparence") {
                Picker("Position", selection: $settings.shelfPosition) {
                    ForEach(ShelfPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Taille des cartes", selection: $settings.cardSize) {
                    ForEach(CardSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Dans l'étagère") {
                ForEach(shortcuts, id: \.keys) { shortcut in
                    LabeledContent(shortcut.action) {
                        Text(shortcut.keys)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Historique

private struct HistoryPane: View {
    let model: SettingsViewModel
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Conservation") {
                Picker("Conserver l'historique", selection: $settings.retention) {
                    ForEach(RetentionPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("La durée court depuis la dernière copie ou le dernier collage. Les éléments épinglés dans un pinboard ne sont jamais supprimés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Mettre en pause la capture", isOn: $settings.isCapturePaused)
            }

            Section("Stockage") {
                LabeledContent("Éléments", value: model.itemCount.formatted())
                LabeledContent("Dont épinglés", value: model.pinnedCount.formatted())
                LabeledContent("Espace disque", value: ByteCountFormatter.string(fromByteCount: model.diskUsage, countStyle: .file))
            }

            Section {
                Button("Vider l'historique…", role: .destructive) { isConfirmingClear = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Vider l'historique ?", isPresented: $isConfirmingClear) {
            Button("Vider l'historique", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Tous les éléments non épinglés seront supprimés définitivement. Les pinboards sont conservés.")
        }
    }
}

// MARK: - Exclusions

private struct ExclusionsPane: View {
    let model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rien n'est capturé quand ces applications sont au premier plan ou sont la source déclarée de la copie. Les contenus marqués confidentiels (mots de passe) sont ignorés dans tous les cas.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(model.excludedApps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.removeExclusion(app.bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Ne plus exclure \(app.name)")
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Button("Ajouter une application…") { model.chooseApplicationToExclude() }
                Menu("Application ouverte") {
                    ForEach(model.runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let bundleID = app.bundleIdentifier {
                                model.exclude(bundleID: bundleID)
                            }
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Liste par défaut") { model.restoreDefaultExclusions() }
            }
        }
        .padding(20)
    }
}

// MARK: - iCloud

private struct SyncPane: View {
    let model: SettingsViewModel

    var body: some View {
        @Bindable var settings = model.settings
        let isAvailable = model.cloudContainerID != nil
        Form {
            Section {
                Toggle("Synchroniser avec iCloud", isOn: $settings.iCloudSyncEnabled)
                    .disabled(!isAvailable)
                Text("Synchronise les pinboards et les éléments texte de moins de 1 Mo (textes, liens, couleurs) entre vos Mac, via votre base iCloud privée. Images, fichiers et textes enrichis restent sur ce Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("État") {
                LabeledContent("Capacité iCloud de cette build", value: model.cloudContainerID ?? "absente")
                LabeledContent("Compte iCloud", value: model.isICloudAccountAvailable ? "connecté" : "indisponible")
                LabeledContent("Synchronisation", value: model.isCloudSyncActive ? "active" : "inactive")
                if isAvailable, settings.iCloudSyncEnabled != model.isCloudSyncActive {
                    HStack {
                        Text("Relancez Copicol pour appliquer ce changement.")
                            .font(.caption)
                        Spacer()
                        Button("Relancer") { model.relaunch() }
                    }
                }
            }

            if !isAvailable {
                Section {
                    Text("Cette build n'embarque pas l'entitlement CloudKit. Compilez avec la configuration « iCloud » et votre équipe de développement Apple (voir le README) pour activer la synchronisation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Saisie de raccourci

/// Bouton qui enregistre la prochaine combinaison de touches (Échap annule).
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    var onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Tapez le raccourci…" : combo.displayString)
                .frame(minWidth: 130)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        // Le raccourci actuel est suspendu, sinon il serait intercepté avant d'arriver ici.
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
            } else if let recorded = KeyCombo(event: event) {
                combo = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }
}
