import AppKit
import SwiftUI
import Combine
import QuickLookUI

@MainActor final class ArchiveWorkspace: ObservableObject {
    static let shared = ArchiveWorkspace()
    @Published var controllers: [ArchiveWindowController] = []
    @Published var activeDocument: ArchiveDocument?
    let preferences: AppPreferences
    let showsWindows: Bool
    lazy var fallbackDocument: ArchiveDocument = {
        let doc = ArchiveDocument(storage:nil,preferences:preferences)
        doc.openRequest = { [weak self] url,password in self?.openArchive(url,password:password) }
        doc.newRequest = { [weak self] files in self?.newArchive(files) }
        return doc
    }()
    private var subscriptions: [ObjectIdentifier:AnyCancellable] = [:]
    init(preferences: AppPreferences? = nil, showsWindows: Bool = true) {
        self.preferences = preferences ?? .shared; self.showsWindows = showsWindows
    }
    @discardableResult func makeWindow() -> ArchiveWindowController {
        let doc = ArchiveDocument(storage:nil,preferences:preferences)
        doc.openRequest = { [weak self] url,password in self?.openArchive(url,password:password) }
        doc.newRequest = { [weak self] files in self?.newArchive(files) }
        let controller = ArchiveWindowController(document:doc,workspace:self)
        controllers.append(controller); activeDocument = doc
        subscriptions[ObjectIdentifier(doc)] = doc.objectWillChange.sink { [weak self, weak controller] _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); controller?.updateTitle() }
        }
        if showsWindows { controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
        return controller
    }
    @discardableResult func openArchive(_ url: URL, password: String? = nil) -> ArchiveWindowController {
        if let existing = controllers.first(where:{ controller in
            guard let current = controller.pendingOpenURL ?? controller.archiveDocument.archiveURL else { return false }
            return Self.sameFile(current,url)
        }) {
            activeDocument = existing.archiveDocument
            if showsWindows { existing.showWindow(nil); existing.window?.deminiaturize(nil); existing.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
            return existing
        }
        // Reuse an untouched welcome window, never another archive or a pending edit.
        let controller = controllers.first { !$0.archiveDocument.opened && !$0.archiveDocument.busy && !$0.archiveDocument.dirty && $0.archiveDocument.archiveURL == nil } ?? makeWindow()
        activeDocument = controller.archiveDocument
        if showsWindows { controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil) }
        controller.pendingOpenURL = url
        controller.archiveDocument.open(url,password:password)
        return controller
    }
    static func sameFile(_ first: URL, _ second: URL) -> Bool {
        let a = first.standardizedFileURL.resolvingSymlinksInPath(), b = second.standardizedFileURL.resolvingSymlinksInPath()
        if a == b { return true }
        if let idA = try? a.resourceValues(forKeys:[.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject,
           let idB = try? b.resourceValues(forKeys:[.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject { return idA.isEqual(idB) }
        return false
    }
    @discardableResult func newArchive(_ files: [URL] = []) -> ArchiveWindowController {
        let controller = makeWindow(); controller.archiveDocument.create(files); return controller
    }
    func welcomeIfNeeded() {
        guard controllers.isEmpty else { return }
        if preferences.values.startup == "last", let path = preferences.defaults.string(forKey:"lastOpenedArchive"), FileManager.default.fileExists(atPath:path) { openArchive(URL(fileURLWithPath:path)) }
        else { makeWindow() }
    }
    func activate(_ document: ArchiveDocument) { activeDocument = document }
    func remove(_ controller: ArchiveWindowController) {
        subscriptions.removeValue(forKey:ObjectIdentifier(controller.archiveDocument))
        controllers.removeAll { $0 === controller }
        if activeDocument === controller.archiveDocument { activeDocument = controllers.last?.archiveDocument }
    }
    func closeActiveWindow() {
        if let key = NSApp.keyWindow { key.performClose(nil); return }
        controllers.first(where:{ $0.archiveDocument === activeDocument })?.window?.performClose(nil)
    }
    func prepareToTerminate(_ completion: @escaping (Bool) -> Void) {
        let documents = controllers.map(\.archiveDocument)
        guard documents.allSatisfy({ !$0.busy && $0.saveReview == nil && !$0.editorVisible }) else {
            if let doc = documents.first(where:{ $0.busy || $0.saveReview != nil || $0.editorVisible }) { activeDocument = doc; doc.error = "Conclua ou cancele a operação aberta antes de sair." }
            completion(false); return
        }
        func sync(_ index: Int) {
            if index < documents.count { documents[index].checkExternalEdits { sync(index+1) }; return }
            guard documents.allSatisfy({ !$0.busy && $0.saveReview == nil && !$0.editorVisible }) else { completion(false); return }
            // Ask about every document before discarding anything; Cancel preserves every window.
            for doc in documents where doc.dirty {
                controllers.first(where:{ $0.archiveDocument === doc })?.window?.makeKeyAndOrderFront(nil)
                let alert = NSAlert(); alert.messageText = "Há alterações não salvas."
                alert.informativeText = (doc.archiveURL?.lastPathComponent ?? "Novo arquivo") + "\nVocê pode voltar e salvar, ou sair e perder as mudanças."
                alert.addButton(withTitle:"Voltar"); alert.addButton(withTitle:"Sair e perder mudanças")
                guard alert.runModal() == .alertSecondButtonReturn else { completion(false); return }
            }
            do { for doc in documents { try doc.discardSessionForExit() }; completion(true) }
            catch { activeDocument?.fail(error); completion(false) }
        }
        sync(0)
    }
}

struct ArchiveWindowRoot: View {
    @ObservedObject var document: ArchiveDocument
    @AppStorage("appAppearance") private var appearance = "system"
    var theme: AppTheme { AppTheme(rawValue:appearance) ?? .system }
    var body: some View {
        ContentView(doc:document).preferredColorScheme(theme.colorScheme)
            .onAppear { theme.apply() }.onChange(of:appearance) { _,_ in theme.apply() }
    }
}

@MainActor final class ArchiveWindowController: NSWindowController, NSWindowDelegate {
    let archiveDocument: ArchiveDocument
    weak var workspace: ArchiveWorkspace?
    var pendingOpenURL: URL?
    init(document: ArchiveDocument, workspace: ArchiveWorkspace) {
        self.archiveDocument = document; self.workspace = workspace
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:650),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.contentMinSize = NSSize(width:640,height:400); window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false; window.identifier = .init("archive-" + UUID().uuidString)
        super.init(window:window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView:ArchiveWindowRoot(document:document))
        window.setContentSize(NSSize(width:1000,height:650))
        window.center(); window.setFrameTopLeftPoint(NSPoint(x:window.frame.minX+CGFloat(workspace.controllers.count%8)*24,y:window.frame.maxY-CGFloat(workspace.controllers.count%8)*24))
        updateTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateTitle() {
        if !archiveDocument.busy { pendingOpenURL = nil }
        window?.title = archiveDocument.archiveURL?.lastPathComponent ?? (archiveDocument.opened ? "Novo arquivo — TabajaraZip" : "TabajaraZip")
        window?.representedURL = archiveDocument.archiveURL
        window?.isDocumentEdited = archiveDocument.dirty
    }
    func windowDidBecomeKey(_ notification: Notification) { workspace?.activate(archiveDocument) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { archiveDocument.confirmDiscard() }
    func windowWillClose(_ notification: Notification) {
        archiveDocument.timer?.invalidate(); archiveDocument.previewTask?.cancel()
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.dataSource === archiveDocument {
            panel.orderOut(nil); panel.dataSource = nil; panel.delegate = nil
        }
        do { try archiveDocument.discardSessionForExit() } catch { archiveDocument.fail(error) }
        workspace?.remove(self)
    }
}
