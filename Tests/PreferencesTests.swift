import AppKit
import SwiftUI

@main struct PreferencesTests {
    @MainActor static func settle() async { for _ in 0..<5 { await Task.yield() }; try? await Task.sleep(nanoseconds:30_000_000) }
    @MainActor static func wait(_ doc: ArchiveDocument) async throws {
        for _ in 0..<600 { if !doc.busy { break }; try await Task.sleep(nanoseconds:50_000_000) }
        if let error = doc.error { throw ArchiveError(error) }
        precondition(!doc.busy)
    }
    @MainActor static func main() async throws {
        let suite = "TabajaraPreferencesTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let store = AppPreferences(defaults:defaults)
        precondition(store.values == PreferenceValues())
        store.values.format = "7z"; store.values.compression = 9
        store.values.showHidden = false; store.values.foldersFirst = true; store.values.showExtensions = false
        store.values.previewByDefault = false; store.values.conflict = .keepBoth
        let loaded = AppPreferences(defaults:defaults)
        precondition(loaded.values == store.values)
        let root = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:root) }
        store.values.temporaryDirectory = root.path
        let doc = ArchiveDocument(storage:nil,preferences:store); defer { doc.timer?.invalidate() }
        doc.create()
        precondition(doc.options.format == "7z" && doc.options.level == 9 && !doc.previewVisible && doc.conflict == .keepBoth)
        precondition(doc.session!.path.hasPrefix(root.path))
        doc.entries = [ArchiveEntry(path:"zeta",directory:true,size:0),ArchiveEntry(path:"a.txt",directory:false,size:1),ArchiveEntry(path:".oculto",directory:true,size:0),ArchiveEntry(path:".oculto/item.txt",directory:false,size:1),ArchiveEntry(path:".segredo",directory:false,size:1)]
        precondition(doc.visibleEntries.map(\.path) == ["zeta","a.txt"])
        precondition(doc.entries.count == 5 && doc.displayName(doc.entries[1]) == "a")
        doc.search = "item"; precondition(doc.visibleEntries.isEmpty)
        store.values.showHidden = true; await settle(); precondition(doc.visibleEntries.count == 1)
        doc.search = ""
        doc.sortOrder = [KeyPathComparator(\ArchiveEntry.size,order:.reverse)]
        let another = ArchiveDocument(storage:root,preferences:store); defer { another.timer?.invalidate() }
        precondition(another.sortOrder[0].keyPath == \ArchiveEntry.size && another.sortOrder[0].order == .reverse)
        store.values.rememberSort = false; await settle(); precondition(doc.sortOrder[0].keyPath == \ArchiveEntry.name)
        store.values.extractionDestination = "custom"; store.values.extractionDirectory = root.path; await settle()
        precondition(doc.defaultExtractionDestination()?.path == root.path)
        store.values.extractionDestination = "same"; await settle()
        doc.archiveURL = root.appendingPathComponent("origem.zip"); precondition(doc.defaultExtractionDestination()?.path == root.path)
        store.values.confirmRemoval = false; await settle(); doc.remove([".oculto"])
        precondition(!doc.entries.contains { $0.path.hasPrefix(".oculto") })
        doc.undo(); precondition(doc.entries.count == 5)
        doc.recent = (0..<15).map { "/arquivo\($0).zip" }
        store.values.recentLimit = 5; await settle(); precondition(doc.recent.count == 5)
        doc.clearRecent(); precondition(defaults.stringArray(forKey:"recent") == [])
        doc.entries = []; doc.dirty = false
        let input = root.appendingPathComponent("nota.txt"); try "preferências".write(to:input,atomically:true,encoding:.utf8)
        doc.add([input]); try await wait(doc)
        doc.archiveURL = root.appendingPathComponent("salvo.7z")
        store.values.reviewSave = false; await settle(); doc.save(); try await wait(doc)
        precondition(doc.saveReview == nil && !doc.dirty && FileManager.default.fileExists(atPath:doc.archiveURL!.path))
        let extractionRoot = root.appendingPathComponent("extraídos")
        store.values.extractionDestination = "custom"; store.values.extractionDirectory = extractionRoot.path
        store.values.revealExtraction = false; await settle()
        doc.extract([]); try await wait(doc)
        precondition(FileManager.default.fileExists(atPath:extractionRoot.appendingPathComponent("nota.txt").path))
        doc.previewVisible = true
        var preview = doc.entries[0]; preview.size = 6_000_000; preview.staged = input.path
        doc.entries = [preview]; doc.selection = [preview.path]
        store.values.previewLimitMB = 5; await settle(); doc.updatePreview()
        precondition(doc.previewURL == nil)
        store.values.previewLimitMB = 10; await settle(); await doc.previewTask?.value
        precondition(doc.previewURL != nil)
        let oldTemp = UserDefaults.standard.object(forKey:"customTemporaryDirectory")
        UserDefaults.standard.set(root.path,forKey:"customTemporaryDirectory")
        let scratch = try ArchiveEngine.workspace(); precondition(scratch.path.hasPrefix(root.path))
        UserDefaults.standard.set(oldTemp,forKey:"customTemporaryDirectory")
        defaults.set(doc.archiveURL!.path,forKey:"lastOpenedArchive")
        store.values.startup = "last"; await settle()
        let startup = ArchiveDocument(storage:root,preferences:store); defer { startup.timer?.invalidate() }
        startup.startIfNeeded(); try await wait(startup); precondition(startup.archiveURL == doc.archiveURL && startup.opened)
        store.values.nameSize = 17; store.values.comfortableRows = true; store.values.previewLimitMB = 5; await settle()
        precondition(doc.preferences.nameSize == 17 && doc.preferences.comfortableRows && doc.preferences.previewLimitMB == 5)
        defaults.set(["preservado.zip"],forKey:"recent"); store.reset(); await settle()
        precondition(store.values == PreferenceValues() && defaults.stringArray(forKey:"recent") == ["preservado.zip"])
        precondition(defaults.string(forKey:"appAppearance") == "system" && defaults.bool(forKey:ArchivePreferences.metadataKey))
        try doc.discardSessionForExit(); try startup.discardSessionForExit()
        print("PASS: preference persistence, defaults for new archives, live hidden/folder/name settings, sort persistence, extraction destinations, removal confirmation off with undo, recent limit, save review off, startup reopen, temporary root and reset preserving recents")
    }
}
