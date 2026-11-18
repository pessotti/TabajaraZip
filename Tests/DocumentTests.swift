import SwiftUI
import AppKit
import Foundation

@main struct DocumentTests {
    @MainActor static func wait(_ doc:ArchiveDocument) async throws {
        for _ in 0..<600 { if !doc.busy { break }; try await Task.sleep(nanoseconds:50_000_000) }
        if doc.busy { throw ArchiveError("Test timeout") }
        if let error = doc.error { throw ArchiveError(error) }
    }
    @MainActor static func check(_ value:Bool,_ message:String) throws { if !value { throw ArchiveError("TEST FAILED: " + message) } }
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, root = try ArchiveEngine.workspace()
        defer { try? fm.removeItem(at:root) }
        let input = root.appendingPathComponent("input.txt"); try "original".write(to:input,atomically:true,encoding:.utf8)
        let doc = ArchiveDocument(storage:root.appendingPathComponent("support"))
        try check(!doc.canEditFileOptions,"options disabled without archive")
        doc.showFileOptions(); try check(!doc.optionsVisible,"empty document cannot open options")
        doc.create(); try check(doc.canEditFileOptions,"options enabled for new archive")
        doc.add([input]); try await wait(doc)
        try check(doc.entries.count == 1 && doc.dirty,"add staged")
        doc.renamePath("input.txt",to:"renamed.txt"); try check(doc.entries[0].path == "renamed.txt","rename")
        doc.undo(); try check(doc.entries[0].path == "input.txt","undo")
        doc.redo(); try check(doc.entries[0].path == "renamed.txt","redo")
        let document = doc
        precondition(!fm.fileExists(atPath:doc.session!.appendingPathComponent("recovery.json").path))
        document.archiveURL = root.appendingPathComponent("saved.zip")
        document.save()
        try check(document.saveReview != nil && !fm.fileExists(atPath:document.archiveURL!.path),"review precedes disk write")
        document.cancelSaveReview()
        try check(document.dirty && !fm.fileExists(atPath:document.archiveURL!.path),"cancel review preserves session and disk")
        document.save(); try await wait(document); document.confirmSaveReview(); try await wait(document)
        try check(!document.dirty && document.entries[0].original == "renamed.txt","save and index reload")
        document.editorPath = "renamed.txt"; document.editorText = "edited"; document.saveText()
        try check(document.dirty,"edit staged")
        document.undo(); try check(!document.dirty,"undo back to saved state")
        document.redo(); document.save(); try await wait(document); document.confirmSaveReview(); try await wait(document)
        let file = root.appendingPathComponent("editor.txt"); try "external".write(to:file,atomically:true,encoding:.utf8)
        document.external["renamed.txt"] = ExternalEdit(path:"renamed.txt",url:file,hash:"old")
        document.checkExternalEdits(); try await wait(document)
        try check(document.dirty,"external editor change")
        document.save(); try await wait(document); document.confirmSaveReview(); try await wait(document)
        try check(!document.dirty,"external change saved")
        let content = root.appendingPathComponent("checked.txt")
        try ArchiveEngine.materialize(document.entries[0],archive:document.contentArchive,password:nil,to:content,control:JobControl())
        let text = try String(contentsOf:content,encoding:.utf8)
        try check(text == "external","external bytes persisted")
        document.directMode = true
        document.renamePath("renamed.txt",to:"direct.txt"); try await wait(document)
        try check(document.directMode && !document.dirty && document.entries[0].path == "direct.txt","direct mode persists after saving")
        document.directMode = false
        document.renamePath("direct.txt",to:"discarded.txt")
        let discardedSession = document.session!
        precondition(!fm.fileExists(atPath:discardedSession.appendingPathComponent("recovery.json").path))
        try document.discardSessionForExit()
        precondition(!fm.fileExists(atPath:discardedSession.path) && document.session == nil && !document.dirty)
        let savedIndex = try ArchiveEngine.list(document.archiveURL!)
        precondition(savedIndex.entries.contains { $0.path == "direct.txt" })
        print("PASS: edits create no recovery journal; exit removes working copy and preserves saved archive")
        print("PASS: staged add, rename, undo/redo, save/reload, text edit, external edit, direct mode")
        let nav = ArchiveDocument(storage:root.appendingPathComponent("navigation")); nav.create()
        nav.entries = [ArchiveEntry(path:"Pasta",directory:true,size:0,original:"Pasta"),ArchiveEntry(path:"Pasta/Sub",directory:true,size:0,original:"Pasta/Sub"),ArchiveEntry(path:"Pasta/Sub/item.txt",directory:false,size:7,modified:Date(timeIntervalSince1970:1000),original:"Pasta/Sub/item.txt")]
        nav.originalEntries = nav.entries; nav.dirty = false
        nav.navigate(to:"Pasta"); nav.navigate(to:"Pasta/Sub")
        try check(nav.breadcrumbs == ["","Pasta","Pasta/Sub"],"breadcrumb hierarchy")
        nav.search = "item"; nav.navigateUp(); nav.navigateBack()
        try check(nav.folder == "Pasta/Sub" && nav.search == "item","history restores location and query")
        nav.navigateForward(); try check(nav.folder == "Pasta","forward")
        nav.navigate(to:""); try check(nav.forwardHistory.isEmpty,"new navigation clears forward history")
        nav.renamePath("Pasta/Sub/item.txt",to:"Pasta/Sub/novo.txt")
        try check(nav.pendingChanges.contains { $0.kind == .renamed && $0.path == "Pasta/Sub/novo.txt" },"rename badge")
        nav.undo(); nav.change(nav.entries.filter { $0.path != "Pasta/Sub/item.txt" })
        try check(nav.removedEntries.map(\.path) == ["Pasta/Sub/item.txt"],"removed entries remain visible")
        nav.restoreRemoved("Pasta/Sub/item.txt"); try check(nav.removedEntries.isEmpty,"restore removed item")
        let details = ConflictDetails.entry(nav.entries[0],in:nav.entries)
        try check(details.bytes == 7 && details.directory,"folder conflict uses total member size")
        nav.recent = ["/missing/a.zip","/missing/b.zip"]; nav.removeRecent("/missing/a.zip")
        try check(nav.recent == ["/missing/b.zip"],"remove recent only affects history")
        nav.clearRecent(); try check(nav.recent.isEmpty,"clear recent")
        nav.timer?.invalidate(); try nav.discardSessionForExit()
        print("PASS: navigation history, breadcrumb hierarchy, pending changes, restore, conflict metadata and recent actions")
        doc.timer?.invalidate(); document.timer?.invalidate(); doc.dirty = false
    }
}
