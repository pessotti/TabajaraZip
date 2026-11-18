import AppKit
import SwiftUI

@main struct WorkspaceTests {
    @MainActor static func wait(_ doc:ArchiveDocument) async throws {
        for _ in 0..<600 { if !doc.busy { break }; try await Task.sleep(nanoseconds:50_000_000) }
        if let error = doc.error { throw ArchiveError(error) }; precondition(!doc.busy)
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let suite = "TabajaraWindows-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let root = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:root) }
        let preferences = AppPreferences(defaults:defaults); preferences.values.temporaryDirectory = root.path
        let workspace = ArchiveWorkspace(preferences:preferences,showsWindows:false)
        let input = root.appendingPathComponent("nota.txt"); try "janela independente".write(to:input,atomically:true,encoding:.utf8)
        let staging = root.appendingPathComponent("staging"); try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        let entries = try ArchiveEngine.scan([input],prefix:"",staging:staging,control:JobControl())
        let firstURL = root.appendingPathComponent("Primeiro.zip"), secondURL = root.appendingPathComponent("Segundo.zip")
        for url in [firstURL,secondURL] { _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:url,options:SaveOptions(),password:nil,originalPassword:nil,expectedStamp:nil,control:JobControl(),progress:{_,_ in}) }
        let first = workspace.openArchive(firstURL)
        precondition(workspace.openArchive(firstURL) === first && workspace.controllers.count == 1)
        try await wait(first.archiveDocument)
        let doc = first.archiveDocument
        doc.renamePath("nota.txt",to:"alterada.txt"); precondition(doc.dirty)
        let second = workspace.openArchive(secondURL); try await wait(second.archiveDocument)
        precondition(workspace.controllers.count == 2 && doc !== second.archiveDocument)
        precondition(doc.dirty && doc.entries[0].path == "alterada.txt" && second.archiveDocument.entries[0].path == "nota.txt")
        precondition(doc.session != second.archiveDocument.session)
        workspace.activate(doc); precondition(workspace.activeDocument === doc)
        doc.requestOpen(secondURL); precondition(workspace.controllers.count == 2 && doc.dirty && workspace.activeDocument === second.archiveDocument)
        let alias = root.appendingPathComponent("atalho.zip"); try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:secondURL)
        precondition(workspace.openArchive(alias) === second && workspace.controllers.count == 2)
        doc.entries = [ArchiveEntry(path:"Pasta",directory:true,size:0),ArchiveEntry(path:"Pasta/Sub",directory:true,size:0),ArchiveEntry(path:"Pasta/nota.txt",directory:false,size:1),ArchiveEntry(path:"Pasta/Sub/fim.txt",directory:false,size:1),ArchiveEntry(path:".oculta",directory:true,size:0),ArchiveEntry(path:".oculta/segredo",directory:false,size:1)]
        doc.setViewMode(.outline); precondition(doc.visibleEntries.count == 2)
        doc.toggleExpanded("Pasta"); precondition(doc.visibleEntries.contains { $0.path == "Pasta/nota.txt" } && !doc.visibleEntries.contains { $0.path == "Pasta/Sub/fim.txt" })
        doc.toggleExpanded("Pasta/Sub"); precondition(doc.visibleEntries.contains { $0.path == "Pasta/Sub/fim.txt" })
        doc.toggleExpanded("Pasta"); precondition(!doc.visibleEntries.contains { $0.parent == "Pasta" })
        doc.search = "fim"; precondition(doc.visibleEntries.map(\.path) == ["Pasta/Sub/fim.txt"])
        doc.search = ""; doc.setViewMode(.columns); doc.selectInColumn(doc.entries[1])
        precondition(doc.folder == "Pasta/Sub" && doc.columnFolders == ["","Pasta","Pasta/Sub"])
        doc.setViewMode(.icons); precondition(doc.visibleEntries.map(\.path) == ["Pasta/Sub/fim.txt"])
        let restored = ArchiveDocument(storage:root,preferences:preferences); precondition(restored.viewMode == .icons); restored.timer?.invalidate()
        let cleanSession = second.archiveDocument.session!
        second.window?.close()
        precondition(!workspace.controllers.contains { $0 === second } && !FileManager.default.fileExists(atPath:cleanSession.path) && doc.dirty)
        for controller in workspace.controllers { controller.archiveDocument.dirty = false; controller.window?.close() }
        precondition(workspace.controllers.isEmpty)
        workspace.fallbackDocument.requestOpen(firstURL)
        precondition(workspace.controllers.count == 1)
        let reopened = workspace.controllers[0]; try await wait(reopened.archiveDocument); reopened.window?.close()
        print("PASS: independent windows and sessions, opening does not replace dirty documents, active-document routing, native close cleanup, outline expansion, column navigation, icons and persisted mode")
    }
}
