import SwiftUI
import AppKit

struct PreferenceValues: Codable, Equatable {
    var startup = "welcome"
    var recentLimit = 15
    var confirmRemoval = true
    var nameSize = 13
    var comfortableRows = false
    var showExtensions = true
    var previewByDefault = true
    var foldersFirst = false
    var showHidden = true
    var rememberSort = true
    var rememberColumns = true
    var extractionDestination = "ask"
    var extractionDirectory = ""
    var revealExtraction = true
    var conflict = ArchiveEngine.Conflict.ask
    var format = "zip"
    var compression = 5
    var reviewSave = true
    var editorApplication = ""
    var confirmExternalEdits = false
    var temporaryDirectory = ""
    var previewLimitMB = 50
}

@MainActor final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    static let key = "appPreferences.v1"
    let defaults: UserDefaults
    @Published var values: PreferenceValues { didSet { persist() } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey:Self.key) {
            do { values = try JSONDecoder().decode(PreferenceValues.self,from:data) }
            catch { values = PreferenceValues(); DiagnosticLog.record("preferences-decode",error:error) }
        } else { values = PreferenceValues() }
    }
    private func persist() {
        do { defaults.set(try JSONEncoder().encode(values),forKey:Self.key) }
        catch { DiagnosticLog.record("preferences-encode",error:error) }
        defaults.set(values.temporaryDirectory,forKey:"customTemporaryDirectory")
    }
    func reset() {
        defaults.removeObject(forKey:"rememberedArchiveSort")
        defaults.removeObject(forKey:"archiveColumnWidths")
        defaults.set("system",forKey:"appAppearance")
        defaults.set(true,forKey:ArchivePreferences.metadataKey)
        defaults.removeObject(forKey:"lastExtractionDirectory")
        values = PreferenceValues()
        NotificationCenter.default.post(name:.archivePreferencesReset,object:nil)
    }
    func chooseDirectory(_ title: String, current: String) -> String? {
        let panel = NSOpenPanel(); panel.message = title; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath:current) }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
    func chooseEditor() -> String? {
        let panel = NSOpenPanel(); panel.message = "Escolha o aplicativo para abrir e editar os arquivos."; panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath:"/Applications")
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}


extension Notification.Name {
    static let clearArchiveRecents = Notification.Name("TabajaraZip.clearRecents")
    static let archivePreferencesReset = Notification.Name("TabajaraZip.preferencesReset")
}
