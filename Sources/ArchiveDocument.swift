import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import QuickLookUI

struct SavedPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var options: SaveOptions
    var conflict: ArchiveEngine.Conflict = .ask
}
struct ExternalEdit {
    var path: String
    var url: URL
    var hash: String
}

struct PendingSave: Identifiable, Sendable {
    let id = UUID()
    var destination: URL
    var entries: [ArchiveEntry]
    var original: [ArchiveEntry]
    var source: URL?
    var sourceStamp: DiskStamp?
    var options: SaveOptions
    var password: String?
    var originalPassword: String?
    var userURL: URL?
    var userStamp: DiskStamp?
    var session: URL
    var excludeMetadata: Bool
    var currentProtection: ArchiveProtection
    var summary: SaveSummary { SaveSummary(entries:entries,original:original,options:options,excludeMetadata:excludeMetadata) }
}

enum ArchiveViewMode: String, CaseIterable, Identifiable {
    case list, outline, columns, icons
    var id: String { rawValue }
    var title: String { switch self { case .list: return "Lista"; case .outline: return "Pastas expansíveis"; case .columns: return "Colunas"; case .icons: return "Ícones" } }
    var symbol: String { switch self { case .list: return "list.bullet"; case .outline: return "list.bullet.indent"; case .columns: return "rectangle.split.3x1"; case .icons: return "square.grid.2x2" } }
}

@MainActor final class ArchiveDocument: NSObject, ObservableObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var openRequest: ((URL,String?) -> Void)?
    var newRequest: (([URL]) -> Void)?
    func requestOpen(_ url: URL, password: String? = nil) { if let openRequest { openRequest(url,password) } else { open(url,password:password) } }
    func newArchive(_ files: [URL] = []) { if let newRequest { newRequest(files) } else { create(files) } }
    @Published var viewMode: ArchiveViewMode = .list
    @Published var expandedFolders = Set<String>()
    func setViewMode(_ mode: ArchiveViewMode) {
        guard !busy, saveReview == nil else { return }
        viewMode = mode; preferencesStore.defaults.set(mode.rawValue,forKey:"archiveViewMode")
    }
    func toggleExpanded(_ path: String) {
        if expandedFolders.contains(path) { expandedFolders.remove(path) } else { expandedFolders.insert(path) }
    }
    func indentation(_ entry: ArchiveEntry) -> Int { max(0,entry.path.split(separator:"/").count - folder.split(separator:"/").count - 1) }
    func sortedEntries(_ items: [ArchiveEntry]) -> [ArchiveEntry] {
        let sorted = items.sorted(using:sortOrder + [KeyPathComparator(\ArchiveEntry.path,comparator:.localizedStandard)])
        return preferences.foldersFirst ? sorted.filter(\.directory) + sorted.filter { !$0.directory } : sorted
    }
    var unhiddenEntries: [ArchiveEntry] { entries.filter { entry in preferences.showHidden || !entry.path.split(separator:"/").contains { $0.hasPrefix(".") } } }
    func children(in path: String) -> [ArchiveEntry] { sortedEntries(unhiddenEntries.filter { $0.parent == path }) }
    var columnFolders: [String] { breadcrumbs }
    func selectInColumn(_ entry: ArchiveEntry) {
        navigate(to:entry.directory ? entry.path : entry.parent)
        selection = [entry.path]
    }
    let preferencesStore: AppPreferences
    private var preferenceSubscriptions = Set<AnyCancellable>()
    @Published var preferences = PreferenceValues()
    private var startupChecked = false
    func displayName(_ entry: ArchiveEntry) -> String {
        guard !preferences.showExtensions, !entry.directory, !entry.name.hasPrefix("."), !(entry.name as NSString).pathExtension.isEmpty else { return entry.name }
        return (entry.name as NSString).deletingPathExtension
    }
    func startIfNeeded() {
        guard !startupChecked else { return }; startupChecked = true
        guard !opened, !busy, preferences.startup == "last", let path = preferencesStore.defaults.string(forKey:"lastOpenedArchive") ?? recent.first, fm.fileExists(atPath:path) else { return }
        open(URL(fileURLWithPath:path))
    }
    private func applyPreferences(_ value: PreferenceValues) {
        let old = preferences; preferences = value
        let limit = max(5,min(50,value.recentLimit))
        if recent.count > limit { recent = Array(recent.prefix(limit)); persistRecent() }
        if old.previewLimitMB != value.previewLimitMB { updatePreview() }
        if preferencesStore.defaults.data(forKey:"rememberedArchiveSort") == nil { sortOrder = Self.defaultSort }
        if !value.rememberSort && old.rememberSort { sortOrder = Self.defaultSort }
    }
    static var defaultSort: [KeyPathComparator<ArchiveEntry>] { [KeyPathComparator(\ArchiveEntry.name,comparator:.localizedStandard)] }
    struct RememberedSort: Codable { var key: String; var ascending: Bool }
    static var sortableKeys: [(String,PartialKeyPath<ArchiveEntry>)] { [("name",\ArchiveEntry.name),("size",\ArchiveEntry.size),("packed",\ArchiveEntry.packedSort),("ratio",\ArchiveEntry.ratioSort),("date",\ArchiveEntry.modifiedSort),("kind",\ArchiveEntry.kind)] }
    private func saveSort() {
        guard preferences.rememberSort else { return }
        let saved = sortOrder.compactMap { comparator -> RememberedSort? in
            guard let key = Self.sortableKeys.first(where:{ $0.1 == comparator.keyPath })?.0 else { return nil }
            return RememberedSort(key:key,ascending:comparator.order == .forward)
        }
        if let data = try? JSONEncoder().encode(saved) { preferencesStore.defaults.set(data,forKey:"rememberedArchiveSort") }
    }
    func restoreSort() {
        guard preferences.rememberSort, let data = preferencesStore.defaults.data(forKey:"rememberedArchiveSort"), let saved = try? JSONDecoder().decode([RememberedSort].self,from:data), !saved.isEmpty else { return }
        sortOrder = saved.map { item in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.key {
            case "size": return KeyPathComparator(\ArchiveEntry.size,order:order)
            case "packed": return KeyPathComparator(\ArchiveEntry.packedSort,order:order)
            case "ratio": return KeyPathComparator(\ArchiveEntry.ratioSort,order:order)
            case "date": return KeyPathComparator(\ArchiveEntry.modifiedSort,order:order)
            case "kind": return KeyPathComparator(\ArchiveEntry.kind,order:order)
            default: return KeyPathComparator(\ArchiveEntry.name,comparator:.localizedStandard,order:order)
            }
        }
    }
    @Published var archiveURL: URL?
    @Published var entries: [ArchiveEntry] = [] { didSet { invalidateChangeCache() } }
    @Published var folder = ""
    @Published var selection = Set<String>()
    @Published var search = ""
    @Published var dirty = false
    @Published var busy = false
    @Published var dragPreparing = false
    @Published var progress = 0.0
    @Published var status = "Tá no ZIP, tá no papo."
    private var errorAlreadyLogged = false
    @Published var error: String? {
        didSet { if let error, !errorAlreadyLogged { DiagnosticLog.shared.write("document-error",message:error,context:["archive":archiveURL?.path ?? "novo arquivo","operation":status],secrets:[password,savePassword].compactMap { $0 }) } }
    }
    @Published var message: String?
    @Published var options = SaveOptions()
    @Published var optionsVisible = false
    @Published var saveReview: PendingSave?
    @Published var editorVisible = false
    @Published var editorText = ""
    var optionsBaseline = SaveOptions()
    @Published var previewVisible = true
    @Published var previewURL: URL?
    @Published var previewText: String?
    @Published var sortOrder = ArchiveDocument.defaultSort { didSet { saveSort() } }
    @Published var recent: [String] = []
    @Published var backHistory: [ArchiveLocation] = []
    @Published var forwardHistory: [ArchiveLocation] = []
    @Published var cancelling = false
    var progressIndeterminate: Bool { progress < 0 }
    private var cachedChanges: [SaveChange]?
    private var cachedRemoved: [ArchiveEntry]?
    private func invalidateChangeCache() { cachedChanges = nil; cachedRemoved = nil }
    var pendingChanges: [SaveChange] {
        if let cachedChanges { return cachedChanges }
        let result = SaveSummary(entries:entries,original:originalEntries,options:SaveOptions(),excludeMetadata:false).changes
        cachedChanges = result; return result
    }
    var removedEntries: [ArchiveEntry] {
        if let cachedRemoved { return cachedRemoved }
        let removed = Set(pendingChanges.filter { $0.kind == .removed }.map(\.path))
        let result = originalEntries.filter { removed.contains($0.path) }; cachedRemoved = result; return result
    }
    var breadcrumbs: [String] {
        var result = [""]; var path = ""
        for part in folder.split(separator:"/") { path = path.isEmpty ? String(part) : path + "/" + part; result.append(path) }
        return result
    }
    var canNavigateBack: Bool { !busy && !backHistory.isEmpty }
    var canNavigateForward: Bool { !busy && !forwardHistory.isEmpty }
    func navigate(to path: String, query: String = "") {
        guard opened, !busy, saveReview == nil, path.isEmpty || entries.contains(where:{ $0.path == path && $0.directory }) else { return }
        let current = ArchiveLocation(folder:folder,search:search)
        let next = ArchiveLocation(folder:path,search:query)
        guard current != next else { return }
        backHistory.append(current); forwardHistory = []; applyLocation(next)
    }
    private func applyLocation(_ location: ArchiveLocation) {
        folder = location.folder.isEmpty || entries.contains(where:{ $0.path == location.folder && $0.directory }) ? location.folder : ""
        search = location.search; selection = []
    }
    func navigateBack() {
        guard canNavigateBack, saveReview == nil, let location = backHistory.popLast() else { return }
        forwardHistory.append(ArchiveLocation(folder:folder,search:search)); applyLocation(location)
    }
    func navigateForward() {
        guard canNavigateForward, saveReview == nil, let location = forwardHistory.popLast() else { return }
        backHistory.append(ArchiveLocation(folder:folder,search:search)); applyLocation(location)
    }
    func navigateUp() { navigate(to:(folder as NSString).deletingLastPathComponent) }
    func cancelOperation() { guard busy else { return }; cancelling = true; status = "Cancelando…"; control.cancel() }
    func persistRecent() {
        preferencesStore.defaults.set(recent,forKey:"recent")
        NotificationCenter.default.post(name:.archiveRecentsChanged,object:self)
    }
    func removeRecent(_ path: String) { recent.removeAll { $0 == path }; persistRecent() }
    func clearRecent() { recent = []; persistRecent(); NSDocumentController.shared.clearRecentDocuments(nil) }
    func revealRecent(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)]) }
    func locateRecent(_ path: String) {
        let panel = NSOpenPanel(); panel.message = "Localize \(URL(fileURLWithPath:path).lastPathComponent)."
        if panel.runModal() == .OK, let url = panel.url { open(url,replacingRecent:path) }
    }
    func restoreRemoved(_ path: String) {
        let missing = removedEntries
        let restored = missing.filter { $0.path == path || $0.path.hasPrefix(path + "/") || path.hasPrefix($0.path + "/") }
        change(entries + restored)
    }
    @Published var presets: [SavedPreset] = []
    @Published var undoCount = 0
    @Published var redoCount = 0
    @Published var conflict = ArchiveEngine.Conflict.ask
    @Published var batchLog: [String] = []
    @Published var directMode = false
    var originalEntries: [ArchiveEntry] = [] { didSet { invalidateChangeCache() } }
    var stamp: DiskStamp?
    var contentStamp: DiskStamp?
    var contentArchive: URL?
    var session: URL?
    var password: String?
    var savePassword: String?
    var editorPath: String?
    var undoStack: [[ArchiveEntry]] = []
    var redoStack: [[ArchiveEntry]] = []
    var external: [String: ExternalEdit] = [:]
    var previewItems: [URL] = []
    var control = JobControl()
    var timer: Timer?
    var previewTask: Task<Void,Never>?
    var previewGeneration = UUID()
    let fm = FileManager.default
    let storageOverride: URL?
    var opened: Bool { session != nil }
    var canSave: Bool { opened && !busy && saveReview == nil }
    var canEditFileOptions: Bool { opened && !busy && saveReview == nil }
    func showFileOptions() { guard canEditFileOptions else { return }; optionsVisible = true }
    var savedProtection: ArchiveProtection { ArchiveProtection.detect(originalEntries) }
    var protectionLabel: String { archiveURL == nil ? "Ainda não salvo" : savedProtection.label }
    var editableFormat: Bool { ["zip","7z","rar","tar","tgz","tbz2","txz"].contains(options.format) }
    var visibleEntries: [ArchiveEntry] {
        if !search.isEmpty { return sortedEntries(unhiddenEntries.filter { $0.path.localizedCaseInsensitiveContains(search) }) }
        guard viewMode == .outline else { return children(in:folder) }
        let groups = Dictionary(grouping:unhiddenEntries,by: \.parent)
        var result: [ArchiveEntry] = []
        var stack = Array(sortedEntries(groups[folder] ?? []).reversed())
        while let entry = stack.popLast() {
            result.append(entry)
            if entry.directory && expandedFolders.contains(entry.path) { stack.append(contentsOf:sortedEntries(groups[entry.path] ?? []).reversed()) }
        }
        return result
    }
    var selectedEntry: ArchiveEntry? { selection.count == 1 ? entries.first(where: { selection.contains($0.path) }) : nil }
    var workingDirectory: URL {
        let root = preferences.temporaryDirectory.isEmpty ? fm.temporaryDirectory : URL(fileURLWithPath:preferences.temporaryDirectory)
        let u = storageOverride ?? root.appendingPathComponent("TabajaraZIP-WorkingCopies")
        do { try fm.createDirectory(at:u,withIntermediateDirectories:true) } catch { DiagnosticLog.record("working-directory",error:error,context:["path":u.path]) }; return u
    }
    override convenience init() { self.init(storage: nil) }
    init(storage: URL?, preferences store: AppPreferences? = nil) {
        preferencesStore = store ?? .shared
        preferences = preferencesStore.values
        storageOverride = storage
        super.init()
        viewMode = ArchiveViewMode(rawValue:preferencesStore.defaults.string(forKey:"archiveViewMode") ?? "") ?? .list
        recent = preferencesStore.defaults.stringArray(forKey:"recent") ?? []
        options = preferredSaveOptions(); conflict = preferences.conflict; previewVisible = preferences.previewByDefault
        restoreSort()
        preferencesStore.$values.dropFirst().sink { [weak self] value in Task { @MainActor in self?.applyPreferences(value) } }.store(in:&preferenceSubscriptions)
        NotificationCenter.default.publisher(for:.clearArchiveRecents).sink { [weak self] _ in Task { @MainActor in self?.clearRecent() } }.store(in:&preferenceSubscriptions)
        NotificationCenter.default.publisher(for:.archiveRecentsChanged).sink { [weak self] note in
            guard let self, let source = note.object as? ArchiveDocument, source !== self, source.preferencesStore.defaults === self.preferencesStore.defaults else { return }
            self.recent = self.preferencesStore.defaults.stringArray(forKey:"recent") ?? []
        }.store(in:&preferenceSubscriptions)
        if let data = preferencesStore.defaults.data(forKey:"presets"), let saved = try? JSONDecoder().decode([SavedPreset].self,from:data) { presets = saved }
        timer = Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in Task { @MainActor in self?.checkExternalEdits() } }
    }
    func fail(_ error: Error, operation: String? = nil) {
        errorAlreadyLogged = true; defer { errorAlreadyLogged = false }
        DiagnosticLog.record("document-operation",error:error,context:["archive":archiveURL?.path ?? "novo arquivo","operation":operation ?? status],secrets:[password,savePassword].compactMap { $0 })
        if error is CancellationError { status = "Operação cancelada. Alterações desta operação foram desfeitas." }
        else { self.error = error.localizedDescription; status = "Operação interrompida" }
    }
    func job<T: Sendable>(_ title: String, work: @escaping @Sendable (JobControl, @escaping JobProgress) throws -> T, done: @escaping (T) -> Void) {
        guard !busy, saveReview == nil else { return }
        busy = true; cancelling = false; progress = -1; status = title; control = JobControl()
        let token = control
        let update: JobProgress = { [weak self] value, text in Task { @MainActor in
            guard let self, self.busy, !self.cancelling, self.control === token else { return }; self.progress = value; self.status = text
        } }
        Task {
            do {
                let result = try await Task.detached(priority:.userInitiated) { try work(token,update) }.value
                busy = false; cancelling = false; progress = 1; status = "Pronto. Serviço Tabajara concluído."; done(result)
            } catch { busy = false; cancelling = false; fail(error,operation:title) }
        }
    }
    func preferredSaveOptions() -> SaveOptions {
        var options = SaveOptions()
        options.format = ["zip","7z","rar","tar","tgz","tbz2","txz"].contains(preferences.format) ? preferences.format : "zip"
        options.level = [0,1,5,9].contains(preferences.compression) ? preferences.compression : 5
        return options
    }
    func newSession() throws -> URL {
        let dir = workingDirectory.appendingPathComponent("Workspaces").appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:dir.appendingPathComponent("staging"),withIntermediateDirectories:true); return dir
    }
    func confirmDiscard() -> Bool {
        guard !busy, saveReview == nil else { return false }
        if opened && (dirty || editorVisible) {
            let a = NSAlert(); a.messageText = "Descartar alterações não salvas?"; a.informativeText = "O arquivo compactado original não será alterado."; a.addButton(withTitle:"Cancelar"); a.addButton(withTitle:"Descartar")
            return a.runModal() == .alertSecondButtonReturn
        }
        return true
    }
    func clearOldSession() {
        if let session { ArchiveEngine.removeTemporary(session) }; session = nil
        external = [:]; previewURL = nil; previewText = nil; previewGeneration = UUID(); previewTask?.cancel()
        previewVisible = preferences.previewByDefault; conflict = preferences.conflict
        expandedFolders = []
        optionsVisible = false; backHistory = []; forwardHistory = []
        undoStack = []; redoStack = []; undoCount = 0; redoCount = 0; dirty = false; directMode = false; selection = []; folder = ""; search = ""
    }
    func discardSessionForExit() throws {
        guard !busy else { throw ArchiveError("Aguarde a operação antes de sair.") }
        if let session, fm.fileExists(atPath:session.path) { try fm.removeItem(at:session) }
        session = nil; dirty = false; external = [:]; password = nil; savePassword = nil
    }
    func openPanel() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.allowedContentTypes = ["zip","7z","rar","tar","gz","tgz","bz2","xz","001","cbz","cbr","iso","cab"].compactMap { UTType(filenameExtension:$0) }
        if p.runModal() == .OK { for url in p.urls { requestOpen(url) } }
    }
    func askPassword(title: String = "Senha do arquivo", confirm: Bool = false) -> String? {
        let a = NSAlert(); a.messageText = title
        let first = NSTextField(frame:NSRect(x:0,y:confirm ? 36 : 0,width:300,height:24))
        first.placeholderString = "Senha"
        let view = NSView(frame:NSRect(x:0,y:0,width:300,height:confirm ? 64 : 28)); view.addSubview(first)
        var second: NSTextField?
        if confirm { let field = NSTextField(frame:NSRect(x:0,y:0,width:300,height:24)); field.placeholderString = "Repita a senha"; view.addSubview(field); second = field }
        a.accessoryView = view; a.addButton(withTitle:"Continuar"); a.addButton(withTitle:"Cancelar"); a.window.initialFirstResponder = first
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let pass = first.stringValue
        guard !pass.isEmpty, !pass.contains("\n"), !pass.contains("\r"), second == nil || second?.stringValue == pass else { error = "As senhas devem ser iguais, não vazias e sem quebras de linha."; return nil }
        return pass
    }
    func open(_ url: URL, password supplied: String? = nil, preserveDirect: Bool = false, replacingRecent: String? = nil) {
        guard confirmDiscard() else { return }
        let new: URL
        do { new = try newSession() } catch { fail(error); return }
        job("Lendo índice do arquivo…", work: { control,update in
            do {
                let (index,source) = try ArchiveEngine.resolve(url,in:new,password:supplied,control:control)
                return (index,source,try DiskStamp(url),try DiskStamp(source))
            } catch { ArchiveEngine.removeTemporary(new); throw error }
        }, done: { [weak self] index,source,stamp,contentStamp in
            guard let self else { return }; self.clearOldSession(); self.session = new
            self.archiveURL = url; self.contentArchive = source; self.entries = index.entries; self.originalEntries = index.entries
            self.stamp = stamp; self.contentStamp = contentStamp; self.directMode = preserveDirect; self.password = supplied; self.savePassword = supplied
            self.options = self.preferredSaveOptions(); self.options.format = ["zip","7z","rar","tar","tgz","tbz2","txz"].contains(index.format) ? index.format : "zip"; self.options.encrypt = index.encrypted
            if let replacingRecent { self.recent.removeAll { $0 == replacingRecent } }
            self.recent.removeAll { $0 == url.path }; self.recent.insert(url.path,at:0); self.recent = Array(self.recent.prefix(max(5,min(50,self.preferences.recentLimit)))); self.persistRecent()
            self.preferencesStore.defaults.set(url.path,forKey:"lastOpenedArchive")
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            self.status = "\(index.entries.count) itens • Conteúdo carregado sob demanda"
        })
    }
    func openWithPassword() {
        let p = NSOpenPanel(); p.message = "Escolha o arquivo protegido por senha."
        if p.runModal() == .OK, let url = p.url, let password = askPassword() { requestOpen(url,password:password) }
    }
    func create(_ files: [URL] = []) {
        guard confirmDiscard() else { return }
        do {
            let dir = try newSession(); clearOldSession(); session = dir; archiveURL = nil; contentArchive = nil; stamp = nil; contentStamp = nil
            entries = []; originalEntries = []; password = nil; savePassword = nil; options = preferredSaveOptions(); dirty = true
            if !files.isEmpty { add(files) }
        } catch { fail(error) }
    }
    func change(_ next: [ArchiveEntry]) {
        guard saveReview == nil else { return }
        do { try ArchiveEngine.validateEntries(next) } catch { fail(error); return }
        undoStack.append(entries); redoStack = []; entries = next; dirty = true; selection = []
        undoCount = undoStack.count; redoCount = 0
        if directMode { save() }
    }
    func undo() {
        guard !busy, saveReview == nil, !directMode, let old = undoStack.popLast() else { return }
        redoStack.append(entries); entries = old; dirty = entries != originalEntries
        undoCount = undoStack.count; redoCount = redoStack.count; selection = []
    }
    func redo() {
        guard !busy, saveReview == nil, !directMode, let next = redoStack.popLast() else { return }
        undoStack.append(entries); entries = next; dirty = true
        undoCount = undoStack.count; redoCount = redoStack.count; selection = []
    }
    func addPanel() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true
        if p.runModal() == .OK { add(p.urls) }
    }
    func add(_ urls: [URL]) {
        guard let session, !busy else { if !opened { create(urls) }; return }
        let prefix = folder, current = entries
        let resolver = ConflictPrompter(policy:conflict)
        job("Adicionando arquivos…", work: { control,update in
            let staged = try ArchiveEngine.scan(urls,prefix:prefix,staging:session.appendingPathComponent("staging"),control:control,progress:update)
            var next = current
            let rootNames = Set(urls.map { prefix.isEmpty ? $0.lastPathComponent : prefix + "/" + $0.lastPathComponent })
            for root in rootNames.sorted() {
                try control.check()
                var group = staged.filter { $0.path == root || $0.path.hasPrefix(root + "/") }
                if let existing = next.first(where: { ArchiveEngine.collisionKey($0.path) == ArchiveEngine.collisionKey(root) }) {
                    let chosenPolicy = try resolver.choose(incoming:ConflictDetails.entry(group.first(where:{ $0.path == root })!,in:group),existing:ConflictDetails.entry(existing,in:next))
                    try control.check()
                    if chosenPolicy == .skip { continue }
                    if chosenPolicy == .keepBoth {
                        let path = root as NSString; let ext = path.pathExtension; let base = path.deletingPathExtension; var n = 2; var renamed: String
                        repeat { renamed = base + " (\(n))" + (ext.isEmpty ? "" : "." + ext); n += 1 } while next.contains(where: { ArchiveEngine.collisionKey($0.path) == ArchiveEngine.collisionKey(renamed) })
                        group = group.map { var e = $0; e.path = renamed + String(e.path.dropFirst(root.count)); return e }
                    } else { next.removeAll { ArchiveEngine.collisionKey($0.path) == ArchiveEngine.collisionKey(root) || ArchiveEngine.collisionKey($0.path).hasPrefix(ArchiveEngine.collisionKey(root) + "/") } }
                }
                next += group
            }
            try ArchiveEngine.validateEntries(next); return next
        },done:{ [weak self] in self?.change($0) })
    }
    func prompt(_ title: String, value: String = "") -> String? {
        let a = NSAlert(); a.messageText = title; let field = NSTextField(frame:NSRect(x:0,y:0,width:340,height:24)); field.stringValue = value
        a.accessoryView = field; a.addButton(withTitle:"Confirmar"); a.addButton(withTitle:"Cancelar"); a.window.initialFirstResponder = field
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    func newFolder() {
        guard let name = prompt("Nome da nova pasta") else { return }
        do {
            guard !name.contains("/") else { throw ArchiveError("Use apenas o nome da pasta.") }
            let path = try ArchiveEngine.validatePath(folder.isEmpty ? name : folder + "/" + name)
            change(entries + [ArchiveEntry(path:path,directory:true,size:0,modified:Date())])
        } catch { fail(error) }
    }
    func rename(_ paths: Set<String>) {
        guard paths.count == 1, let old = paths.first, let e = entries.first(where:{ $0.path == old }), let name = prompt("Renomear item",value:e.name) else { return }
        guard !name.contains("/") else { error = "Use apenas o nome do item."; return }
        let target = e.parent.isEmpty ? name : e.parent + "/" + name
        renamePath(old,to:target)
    }
    func renamePath(_ old: String, to target: String) {
        do {
            _ = try ArchiveEngine.validatePath(target)
            guard !target.hasPrefix(old + "/") else { throw ArchiveError("Não é possível mover uma pasta para dentro dela mesma.") }
            let next = entries.map { e -> ArchiveEntry in var e = e; if e.path == old || e.path.hasPrefix(old + "/") { e.path = target + String(e.path.dropFirst(old.count)) }; return e }
            try ArchiveEngine.validateEntries(next); change(next)
        } catch { fail(error) }
    }
    func move(_ paths: Set<String>) {
        guard let dest = prompt("Mover para pasta (caminho dentro do arquivo; vazio = raiz)",value:folder) else { return }
        let target = dest.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        if !target.isEmpty && !entries.contains(where:{ $0.path == target && $0.directory }) { error = "A pasta de destino não existe."; return }
        var next = entries
        let roots = paths.filter { p in !paths.contains(where:{ p.hasPrefix($0 + "/") }) }
        for path in roots {
            let name = (path as NSString).lastPathComponent; let destination = target.isEmpty ? name : target + "/" + name
            if destination == path { continue }
            if destination.hasPrefix(path + "/") { error = "Uma pasta não pode ser movida para dentro dela mesma."; return }
            next = next.map { var e = $0; if e.path == path || e.path.hasPrefix(path + "/") { e.path = destination + String(e.path.dropFirst(path.count)) }; return e }
        }
        change(next)
    }
    func remove(_ paths: Set<String>) {
        guard !paths.isEmpty, !busy else { return }
        if !preferences.confirmRemoval { removeWithoutConfirmation(paths); return }
        let a = NSAlert(); a.messageText = "Remover \(paths.count) item(ns)?"; a.informativeText = directMode ? "A remoção será salva imediatamente." : "Você pode desfazer antes de salvar o arquivo."
        a.addButton(withTitle:"Remover"); a.addButton(withTitle:"Cancelar")
        if a.runModal() == .alertFirstButtonReturn { removeWithoutConfirmation(paths) }
    }
    func removeWithoutConfirmation(_ paths: Set<String>) {
        guard !busy, saveReview == nil else { return }
        guard !paths.isEmpty else { return }
        change(entries.filter { !ArchiveEngine.isSelectedPath($0.path,paths:paths) })
    }
    func setSourcePassword() {
        if let pass = askPassword() { password = pass; updatePreview() }
    }
    func sourcePassword() -> Bool {
        if entries.contains(where:{ $0.encrypted && $0.staged == nil }), password == nil {
            guard let p = askPassword() else { return false }; password = p
            if options.encrypt && savePassword == nil { savePassword = p }
        }
        return true
    }
    func save(as saveAs: Bool = false, synced: Bool = false) {
        guard !busy, opened, saveReview == nil else { return }
        if !synced, !external.isEmpty { checkExternalEdits { [weak self] in self?.save(as:saveAs,synced:true) }; return }
        guard sourcePassword() else { return }
        var dest = archiveURL
        if saveAs || (dest != nil && dest!.pathExtension.lowercased() != options.format) || options.volumeMB != nil || archiveURL?.lastPathComponent.range(of:"\\.part[0-9]+\\.rar$",options:.regularExpression) != nil || dest == nil || !editableFormat || (dest != nil && !["zip","7z","rar","tar","tgz","tbz2","txz"].contains(dest!.pathExtension.lowercased())) {
            let p = NSSavePanel()
            let originalName = archiveURL?.lastPathComponent ?? "Arquivo Tabajara"
            let stem = originalName.replacingOccurrences(of:"\\.part[0-9]+\\.rar$|\\.7z\\.[0-9]+$",with:"",options:.regularExpression)
            p.nameFieldStringValue = (stem != originalName ? stem : archiveURL?.deletingPathExtension().lastPathComponent ?? "Arquivo Tabajara") + "." + options.format
            if options.volumeMB != nil { p.message = "Todas as partes serão criadas nesta pasta. Escolha um novo nome se já existir um conjunto de volumes." }
            p.allowedContentTypes = [UTType(filenameExtension:options.format) ?? .data]
            guard p.runModal() == .OK, let u = p.url else { return }; dest = u
        }
        guard let destination = dest else { return }
        if options.encrypt && savePassword == nil { guard let p = askPassword(title:"Senha para o novo arquivo",confirm:true) else { return }; savePassword = p }
        guard let session else { return }
        let request = PendingSave(destination:destination,entries:entries,original:originalEntries,source:contentArchive,sourceStamp:contentStamp,options:options,password:savePassword,originalPassword:password,userURL:archiveURL,userStamp:stamp,session:session,excludeMetadata:ArchivePreferences.excludeMetadata,currentProtection:savedProtection)
        if directMode || !preferences.reviewSave { commitSave(request) } else { saveReview = request }
    }
    func cancelSaveReview() { saveReview = nil }
    func confirmSaveReview() {
        guard let request = saveReview, !busy else { return }
        saveReview = nil; commitSave(request)
    }
    private func commitSave(_ request: PendingSave) {
        let current = request.entries, old = request.original, source = request.source, sourceStamp = request.sourceStamp
        let opts = request.options, pass = request.password, oldPass = request.originalPassword, userURL = request.userURL, userStamp = request.userStamp
        let session = request.session
        job("Salvando…",work:{ control,update in
            if let userURL, let userStamp, try DiskStamp(userURL) != userStamp { throw ArchiveError("O original foi alterado por outro aplicativo. Reabra-o antes de salvar.") }
            _ = try ArchiveEngine.write(entries:current,originalEntries:old,archive:source,destination:request.destination,options:opts,password:pass,originalPassword:oldPass,expectedStamp:sourceStamp,excludeMetadata:request.excludeMetadata,control:control,progress:update)
            let destination = ArchiveEngine.savedURL(request.destination,options:opts)
            let (index,source) = try ArchiveEngine.resolve(destination,in:session,password:opts.encrypt ? pass : nil,control:JobControl())
            return (index,source,try DiskStamp(destination),try DiskStamp(source),destination)
        },done:{ [weak self] index,source,stamp,sourceStamp,destination in
            guard let self else { return }
            self.archiveURL = destination; self.stamp = stamp; self.password = opts.encrypt ? pass : nil; self.savePassword = self.password
            self.dirty = false; self.undoStack = []; self.redoStack = []; self.undoCount = 0; self.redoCount = 0
            self.contentArchive = source; self.contentStamp = sourceStamp; self.entries = index.entries; self.originalEntries = index.entries
            self.external = self.external.filter { path,_ in index.entries.contains(where:{ $0.path == path }) }
            self.recent.removeAll { $0 == destination.path }; self.recent.insert(destination.path,at:0); self.recent = Array(self.recent.prefix(max(5,min(50,self.preferences.recentLimit)))); self.persistRecent()
            self.preferencesStore.defaults.set(destination.path,forKey:"lastOpenedArchive")
            self.updatePreview(); self.status = "Salvo e verificado. Tá no ZIP, tá no papo."
        })
    }
    func toggleDirect() {
        guard !busy, saveReview == nil else { return }
        if !directMode {
            guard archiveURL != nil, !dirty, options.volumeMB == nil, archiveURL?.pathExtension != "001", !(archiveURL.map { FileManager.default.fileExists(atPath:$0.deletingPathExtension().appendingPathExtension("z01").path) } ?? false), ["zip","7z"].contains(options.format) else { error = "Salve primeiro um ZIP ou 7z sem alterações pendentes para ativar o modo direto."; return }
            let a = NSAlert(); a.messageText = "Ativar modo direto?"; a.informativeText = "Cada alteração será salva imediatamente, com verificação e troca segura do arquivo. O resumo antes de salvar e o comando Desfazer ficam indisponíveis neste modo."; a.addButton(withTitle:"Ativar"); a.addButton(withTitle:"Cancelar")
            if a.runModal() == .alertFirstButtonReturn { directMode = true; undoStack = []; redoStack = []; undoCount = 0; redoCount = 0 }
        } else { directMode = false }
    }
    func defaultExtractionDestination() -> URL? {
        if preferences.extractionDestination == "same" { return archiveURL?.deletingLastPathComponent() }
        if preferences.extractionDestination == "custom", !preferences.extractionDirectory.isEmpty { return URL(fileURLWithPath:preferences.extractionDirectory) }
        return nil
    }
    func extract(_ paths: Set<String>) {
        guard opened, !busy, saveReview == nil else { return }
        var destination = defaultExtractionDestination()
        if destination == nil {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Extrair aqui"
            if let path = preferencesStore.defaults.string(forKey:"lastExtractionDirectory") { panel.directoryURL = URL(fileURLWithPath:path) }
            guard panel.runModal() == .OK, let selected = panel.url else { return }; destination = selected
            preferencesStore.defaults.set(selected.path,forKey:"lastExtractionDirectory")
        }
        guard let destination else { return }
        extract(paths,to:destination)
    }
    func quickExtract(inFolder: Bool) {
        guard let archiveURL else { return }
        var destination = archiveURL.deletingLastPathComponent()
        if inFolder { destination.appendPathComponent(archiveURL.deletingPathExtension().lastPathComponent) }
        extract(selection,to:destination)
    }
    func extract(_ paths: Set<String>, to destination: URL, reveal: Bool? = nil) {
        guard opened, !busy, saveReview == nil, sourcePassword() else { return }
        let chosen = ArchiveEngine.selectedEntries(entries,paths:paths)
        guard !chosen.isEmpty else { status = "Nenhum item para extrair."; return }
        let shouldReveal = reveal ?? preferences.revealExtraction
        let resolver = ConflictPrompter(policy:conflict), source = contentArchive, pass = password
        job("Extraindo…",work:{ control,update in
            let exists = FileManager.default.fileExists(atPath:destination.path)
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            do {
                try ArchiveEngine.extract(entries:chosen,archive:source,password:pass,destination:destination,conflict:.ask,control:control,progress:update,resolveConflict:{ entry,url in
                    try resolver.choose(incoming:ConflictDetails.entry(entry,in:chosen),existing:ConflictDetails.disk(url,control:control))
                })
            } catch {
                if !exists { try? FileManager.default.removeItem(at:destination) }
                throw error
            }
            return destination
        },done:{ [weak self] url in self?.status = "Extração concluída: " + url.path; if shouldReveal { NSWorkspace.shared.open(url) } })
    }
    func prepare(_ entry: ArchiveEntry, done: @escaping (URL) -> Void) {
        guard let session, !entry.directory, !busy, sourcePassword() else { return }
        let source = contentArchive, pass = password
        let destination = session.appendingPathComponent("preview-" + UUID().uuidString).appendingPathComponent(entry.name)
        job("Abrindo \(entry.name)…",work:{ control,_ in try ArchiveEngine.materialize(entry,archive:source,password:pass,to:destination,control:control); return destination },done:done)
    }
    func enter(_ entry: ArchiveEntry) { if entry.directory { navigate(to:entry.path) } else { openExternal(entry) } }
    func editText(_ entry: ArchiveEntry) {
        guard entry.size <= 5_000_000 else { error = "O editor interno aceita textos de até 5 MB. Use um editor externo."; return }
        prepare(entry) { [weak self] url in
            do { let data = try Data(contentsOf:url); guard !data.contains(0), let text = String(data:data,encoding:.utf8) else { throw ArchiveError("Use um aplicativo externo para editar este formato.") }
                self?.editorText = text; self?.editorPath = entry.path; self?.editorVisible = true
            } catch { self?.fail(error) }
        }
    }
    func saveText() {
        guard let session, let path = editorPath, let index = entries.firstIndex(where:{ $0.path == path }) else { return }
        do {
            let file = session.appendingPathComponent("staging").appendingPathComponent(UUID().uuidString)
            try editorText.write(to:file,atomically:true,encoding:.utf8)
            var next = entries; next[index].staged = file.path; next[index].size = Int64(editorText.utf8.count); next[index].modified = Date(); next[index].packed = nil
            editorVisible = false; change(next)
        } catch { fail(error) }
    }
    func openExternal(_ entry: ArchiveEntry) {
        prepare(entry) { [weak self] url in
            guard let self else { return }
            do {
                let hash = try ArchiveEngine.sha256(url,control:JobControl())
                self.external[entry.path] = ExternalEdit(path:entry.path,url:url,hash:hash)
                if self.preferences.editorApplication.isEmpty { if !NSWorkspace.shared.open(url) { throw ArchiveError("Não foi possível abrir o arquivo no aplicativo padrão.") } }
                else {
                    let app = URL(fileURLWithPath:self.preferences.editorApplication)
                    NSWorkspace.shared.open([url],withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration()) { _,error in
                        if let error { Task { @MainActor in self.fail(error) } }
                    }
                }
                self.status = "Edite e salve no outro aplicativo. As mudanças serão incorporadas à sessão."
            } catch { self.fail(error) }
        }
    }
    func checkExternalEdits(completion: (() -> Void)? = nil) {
        guard !busy, saveReview == nil, !editorVisible, !external.isEmpty, let session else { completion?(); return }
        let watched = Array(external.values)
        // Hashing runs off the main thread; each imported revision remains immutable for undo.
        busy = true; cancelling = false; progress = -1; status = "Verificando alterações do editor…"; control = JobControl()
        let token = control
        Task {
            let updates: [(String,String,Int64,URL)]
            do {
                updates = try await Task.detached { () throws -> [(String,String,Int64,URL)] in
                    var changes: [(String,String,Int64,URL)] = []
                    for e in watched {
                        try token.check()
                        guard FileManager.default.fileExists(atPath:e.url.path) else { continue }
                        let hash = try ArchiveEngine.sha256(e.url,control:token)
                        guard hash != e.hash else { continue }
                        let dest = session.appendingPathComponent("staging").appendingPathComponent(UUID().uuidString)
                        try ArchiveEngine.copy(e.url,to:dest,control:token)
                        changes.append((e.path,hash,try DiskStamp(dest).size,dest))
                    }
                    try token.check(); return changes
                }.value
            } catch { busy = false; cancelling = false; fail(error); completion?(); return }
            busy = false; cancelling = false
            guard !updates.isEmpty else { completion?(); return }
            var next = entries
            for (path,hash,size,url) in updates {
                if preferences.confirmExternalEdits {
                    let alert = NSAlert(); alert.messageText = "Incorporar alteração externa?"; alert.informativeText = path + "\nO conteúdo editado substituirá a versão desta sessão. Você pode desfazer antes de salvar."
                    alert.addButton(withTitle:"Incorporar"); alert.addButton(withTitle:"Manter versão atual")
                    if alert.runModal() != .alertFirstButtonReturn {
                        external[path]?.hash = hash; try? fm.removeItem(at:url); continue
                    }
                }
                if let i = next.firstIndex(where:{ $0.path == path }) {
                    next[i].staged = url.path; next[i].size = size; next[i].modified = Date(); next[i].packed = nil
                    external[path]?.hash = hash
                }
            }
            if next != entries { change(next); status = "Alterações do editor externo incorporadas." }
            completion?()
        }
    }
    func updatePreview() {
        previewTask?.cancel(); let generation = UUID(); previewGeneration = generation; previewURL = nil; previewText = nil
        guard previewVisible, let entry = selectedEntry, !entry.directory, entry.size <= Int64(max(1,min(250,preferences.previewLimitMB))) * 1_000_000, let session, !busy else { return }
        if entry.encrypted && password == nil { return }
        let source = contentArchive, pass = password, destination = session.appendingPathComponent("preview-" + UUID().uuidString).appendingPathComponent(entry.name)
        let token = JobControl()
        previewTask = Task {
            do {
                let url = try await withTaskCancellationHandler(operation:{
                    try await Task.detached { try ArchiveEngine.materialize(entry,archive:source,password:pass,to:destination,control:token); return destination }.value
                },onCancel:{ token.cancel() })
                guard !Task.isCancelled, previewGeneration == generation else { return }
                previewURL = url
                if entry.size <= 500_000, let data = try? Data(contentsOf:url), !data.contains(0) { previewText = String(data:data,encoding:.utf8) }
            } catch { DiagnosticLog.record("preview",error:error,context:["archive":self.archiveURL?.path ?? "","entry":entry.path],secrets:pass.map { [$0] } ?? []) }
        }
    }
    func quickLook(_ clicked:ArchiveEntry? = nil) {
        guard let entry = clicked ?? selectedEntry else { return }
        prepare(entry) { [weak self] url in
            guard let self, let panel = QLPreviewPanel.shared() else { return }
            self.previewItems = [url]; panel.dataSource = self; panel.delegate = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil)
        }
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewItems.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewItems[index] as NSURL }
    func testArchive() {
        guard let source = contentArchive, sourcePassword() else { return }; let pass = password
        job("Testando integridade…",work:{ control,_ in try ArchiveEngine.test(source,password:pass,control:control); return "Integridade verificada. Nenhum erro encontrado no arquivo salvo." },done:{ [weak self] in self?.message = $0 })
    }
    func repairZIP() {
        guard !busy else { return }
        let p = NSOpenPanel(); p.allowedContentTypes = [.zip]; p.message = "Escolha um ZIP danificado. O original será preservado."
        guard p.runModal() == .OK, let source = p.url else { return }
        let out = NSSavePanel(); out.allowedContentTypes = [.zip]; out.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "-recuperado.zip"
        guard out.runModal() == .OK, let destination = out.url else { return }
        job("Tentando recuperar ZIP…",work:{ control,_ in try ArchiveEngine.repairZIP(source,destination:destination,control:control) },done:{ [weak self] count in self?.message = "Recuperados \(count) arquivos com integridade válida em uma nova cópia. Confira se todos os itens esperados estão presentes; conteúdos perdidos não podem ser reconstruídos." })
    }
    func hashArchive() {
        guard let source = archiveURL else { return }
        job("Calculando SHA-256…",work:{ control,_ in try ArchiveEngine.sha256(source,control:control) },done:{ [weak self] in self?.message = "SHA-256\n" + $0 })
    }
    func splitArchive() {
        guard let source = archiveURL, !dirty else { error = "Salve o arquivo antes de dividi-lo."; return }
        guard let value = prompt("Tamanho de cada volume em MB",value:"100"), let size = Int(value), size > 0 else { return }
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        if p.runModal() == .OK, let dest = p.url {
            job("Dividindo em volumes…",work:{ control,update in try ArchiveEngine.split(source,destination:dest,megabytes:size,control:control,progress:update); return dest },done:{ NSWorkspace.shared.open($0) })
        }
    }
    func joinVolumes() {
        guard !busy else { return }
        let p = NSOpenPanel(); p.message = "Selecione o primeiro volume (.001)."
        guard p.runModal() == .OK, let first = p.url else { return }
        let save = NSSavePanel(); save.nameFieldStringValue = first.deletingPathExtension().lastPathComponent
        guard save.runModal() == .OK, let dest = save.url else { return }
        job("Reunindo volumes…",work:{ control,_ in try ArchiveEngine.join(first,destination:dest,control:control); return dest },done:{ [weak self] in self?.open($0) })
    }
    func batchExtract() {
        guard !busy else { return }
        let files = NSOpenPanel(); files.allowsMultipleSelection = true; files.message = "Escolha os arquivos compactados para extrair em lote."
        guard files.runModal() == .OK else { return }
        extractBatchURLs(files.urls)
    }
    func extractBatchURLs(_ urls:[URL]) {
        guard !busy, !urls.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let pass = password, policy = conflict
        job("Extração em lote…",work:{ control,update in
            var log: [String] = []
            for (i,url) in urls.enumerated() {
                try control.check(); update(Double(i)/Double(urls.count),"\(i+1)/\(urls.count): \(url.lastPathComponent)")
                do {
                    let working = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:working) }
                    let (index,source) = try ArchiveEngine.resolve(url,in:working,password:pass,control:control)
                    let folder = ArchiveEngine.unique(dest.appendingPathComponent(url.deletingPathExtension().lastPathComponent))
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    do { try ArchiveEngine.extract(entries:index.entries,archive:source,password:pass,destination:folder,conflict:policy,control:control,progress:{_,_ in}) }
                    catch { try? FileManager.default.removeItem(at:folder); throw error }
                    log.append("✓ " + url.lastPathComponent)
                } catch is CancellationError { throw CancellationError() }
                catch { DiagnosticLog.record("batch-extract",error:error,context:["archive":url.path]); log.append("✗ \(url.lastPathComponent): \(error.localizedDescription)") }
            }
            return log
        },done:{ [weak self] in self?.batchLog = $0; self?.message = $0.joined(separator:"\n") })
    }
    func batchCompress() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; panel.message = "Cada item será compactado em um arquivo separado."
        guard panel.runModal() == .OK else { return }; let urls = panel.urls
        let destPanel = NSOpenPanel(); destPanel.canChooseFiles = false; destPanel.canChooseDirectories = true; destPanel.canCreateDirectories = true
        guard destPanel.runModal() == .OK, let destination = destPanel.url else { return }
        let opts = options
        if opts.encrypt, savePassword == nil { guard let p = askPassword(title:"Senha dos arquivos",confirm:true) else { return }; savePassword = p }
        let pass = savePassword
        job("Compactando em lote…",work:{ control,update in
            var log:[String] = []
            for (i,url) in urls.enumerated() {
                try control.check(); update(Double(i)/Double(urls.count),"Compactando \(url.lastPathComponent)")
                let stage = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:stage) }
                do {
                    let entries = try ArchiveEngine.scan([url],prefix:"",staging:stage,control:control)
                    let target = ArchiveEngine.unique(destination.appendingPathComponent(url.lastPathComponent + "." + opts.format))
                    _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:target,options:opts,password:pass,originalPassword:nil,expectedStamp:nil,control:control,progress:{_,_ in})
                    log.append("✓ " + target.lastPathComponent)
                } catch is CancellationError { throw CancellationError() }
                catch { DiagnosticLog.record("batch-compress",error:error,context:["source":url.path],secrets:pass.map { [$0] } ?? []); log.append("✗ \(url.lastPathComponent): \(error.localizedDescription)") }
            }
            return log
        },done:{ [weak self] in self?.batchLog = $0; self?.message = $0.joined(separator:"\n") })
    }
    func savePreset() {
        guard let name = prompt("Nome da configuração salva"), !name.isEmpty else { return }
        presets.removeAll { $0.name == name }; presets.append(SavedPreset(name:name,options:options,conflict:conflict))
        if let data = try? JSONEncoder().encode(presets) { preferencesStore.defaults.set(data,forKey:"presets") }
    }
}

struct ArchiveLocation: Equatable { var folder: String; var search: String }

struct ConflictDetails: Sendable {
    var name: String
    var directory: Bool
    var bytes: Int64
    var modified: Date?
    static func entry(_ entry: ArchiveEntry, in entries: [ArchiveEntry]) -> Self {
        let bytes = entry.directory ? entries.filter { !$0.directory && $0.path.hasPrefix(entry.path + "/") }.reduce(Int64(0)) { $0 + max(0,$1.size) } : entry.size
        return Self(name:entry.name,directory:entry.directory,bytes:bytes,modified:entry.modified)
    }
    static func disk(_ url: URL, control: JobControl) throws -> Self {
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            return Self(name:url.lastPathComponent,directory:false,bytes:(attributes[.size] as? NSNumber)?.int64Value ?? 0,modified:attributes[.modificationDate] as? Date)
        }
        let values = try url.resourceValues(forKeys:[.isDirectoryKey,.fileSizeKey,.contentModificationDateKey,.isSymbolicLinkKey])
        var bytes = Int64(values.fileSize ?? 0)
        if values.isDirectory == true {
            bytes = 0
            if let enumerator = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey],options:[]) {
                for case let child as URL in enumerator {
                    try control.check()
                    let v = try child.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                    if v.isRegularFile == true { bytes += Int64(v.fileSize ?? 0) }
                }
            }
        }
        return Self(name:url.lastPathComponent,directory:values.isDirectory == true,bytes:bytes,modified:values.contentModificationDate)
    }
    var description: String {
        (directory ? "Pasta · " : "") + ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file) + " (\(bytes) bytes)\nÚltima modificação: " + (modified?.formatted(date:.numeric,time:.standard) ?? "Não informada")
    }
}

/// Each operation gets its own policy; “apply to all” never changes the app preference.
final class ConflictPrompter: @unchecked Sendable {
    private var policy: ArchiveEngine.Conflict
    init(policy: ArchiveEngine.Conflict) { self.policy = policy }
    func choose(incoming: ConflictDetails, existing: ConflictDetails) throws -> ArchiveEngine.Conflict {
        if policy != .ask { return policy }
        let result: (ArchiveEngine.Conflict?,Bool) = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                let alert = NSAlert(); alert.messageText = "Já existe \(existing.name)."
                alert.informativeText = "Novo item\n\(incoming.description)\n\nItem existente\n\(existing.description)" + (incoming.directory || existing.directory ? "\n\nSubstituir troca o item inteiro, incluindo o conteúdo da pasta." : "")
                ["Manter ambos","Substituir","Pular","Cancelar"].forEach { alert.addButton(withTitle:$0) }
                let checkbox = NSButton(checkboxWithTitle:"Aplicar aos demais conflitos desta operação",target:nil,action:nil)
                checkbox.frame = NSRect(x:0,y:0,width:350,height:24); alert.accessoryView = checkbox
                NSApp.activate(ignoringOtherApps:true)
                let response = alert.runModal()
                let choice: ArchiveEngine.Conflict? = response == .alertFirstButtonReturn ? .keepBoth : response == .alertSecondButtonReturn ? .replace : response == .alertThirdButtonReturn ? .skip : nil
                return (choice,checkbox.state == .on)
            }
        }
        guard let choice = result.0 else { throw CancellationError() }
        if result.1 { policy = choice }
        return choice
    }
}

extension Notification.Name { static let archiveRecentsChanged = Notification.Name("TabajaraZip.recentsChanged") }
