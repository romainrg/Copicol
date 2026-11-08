import AppKit
import CopicolCore
import Observation
import ServiceManagement
import UniformTypeIdentifiers

/// Lancement à l'ouverture de session via SMAppService (aucun helper à embarquer).
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct ExcludedApp: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage
    var id: String { bundleID }
}

/// Actions et informations de la fenêtre de réglages (les préférences elles-mêmes vivent dans SettingsStore).
@MainActor
@Observable
final class SettingsViewModel {
    let settings: SettingsStore
    let accessibility: AccessibilityPermission
    let launchAtLogin = LaunchAtLogin()
    private(set) var itemCount = 0
    private(set) var pinnedCount = 0
    private(set) var diskUsage: Int64 = 0
    /// Synchronisation effectivement active dans cette session (un changement s'applique au relancement).
    let isCloudSyncActive: Bool
    let cloudContainerID = CloudSyncAvailability.containerIdentifier
    private(set) var isICloudAccountAvailable = CloudSyncAvailability.isAccountAvailable

    @ObservationIgnored var onShowOnboarding: (() -> Void)?
    @ObservationIgnored var onShortcutRecording: ((Bool) -> Void)?
    @ObservationIgnored private let store: ClipStore
    @ObservationIgnored private let images: ImageCache

    init(settings: SettingsStore, accessibility: AccessibilityPermission, store: ClipStore, images: ImageCache, isCloudSyncActive: Bool) {
        self.settings = settings
        self.accessibility = accessibility
        self.store = store
        self.images = images
        self.isCloudSyncActive = isCloudSyncActive
    }

    /// Ouvre une nouvelle instance puis quitte celle-ci (prise en compte du réglage iCloud).
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func refresh() {
        launchAtLogin.refresh()
        accessibility.refresh()
        itemCount = store.count()
        pinnedCount = store.pinnedCount()
        diskUsage = store.files.diskUsage()
        isICloudAccountAvailable = CloudSyncAvailability.isAccountAvailable
    }

    func clearHistory() {
        store.clearHistory()
        refresh()
    }

    // MARK: - Exclusions

    var excludedApps: [ExcludedApp] {
        settings.excludedBundleIDs.map { bundleID in
            ExcludedApp(
                bundleID: bundleID,
                name: PasteboardReader.applicationName(for: bundleID) ?? bundleID,
                icon: images.appIcon(bundleID: bundleID)
            )
        }
    }

    /// Applications ouvertes, proposées pour une exclusion rapide.
    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else { return false }
                return bundleID != Bundle.main.bundleIdentifier && !settings.excludedBundleIDs.contains(bundleID)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    func exclude(bundleID: String) {
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }
        settings.excludedBundleIDs.append(bundleID)
    }

    func removeExclusion(_ bundleID: String) {
        settings.excludedBundleIDs.removeAll { $0 == bundleID }
    }

    func restoreDefaultExclusions() {
        settings.excludedBundleIDs = SettingsStore.defaultExcludedBundleIDs
    }

    func chooseApplicationToExclude() {
        let panel = NSOpenPanel()
        panel.title = "Exclure des applications"
        panel.prompt = "Exclure"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                exclude(bundleID: bundleID)
            }
        }
    }
}
