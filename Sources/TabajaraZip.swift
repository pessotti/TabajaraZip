import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PDFKit

struct PreviewPane: View {
    @ObservedObject var doc: ArchiveDocument
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Prévia").font(.headline); Spacer(); Button { doc.previewVisible = false } label:{ Image(systemName:"xmark") }.buttonStyle(.plain) }
            if let entry = doc.selectedEntry {
                Label(entry.name,systemImage:entry.directory ? "folder.fill" : "doc").font(.headline).lineLimit(2)
                Text(entry.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                if entry.directory { Label("Pasta",systemImage:"folder") }
                else if let url = doc.previewURL {
                    if let image = NSImage(contentsOf:url) { Image(nsImage:image).resizable().scaledToFit().frame(maxHeight:360) }
                    else if url.pathExtension.lowercased() == "pdf" { PDFPreview(url:url).frame(minHeight:300) }
                    else if let text = doc.previewText { ScrollView { Text(text).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) } }
                    else { ContentUnavailableView("Prévia externa",systemImage:"eye",description:Text("Pressione espaço para usar o Quick Look.")) }
                } else { Text(entry.size > Int64(doc.preferences.previewLimitMB) * 1_000_000 ? "Arquivo acima do limite de prévia definido nas preferências." : entry.encrypted && doc.password == nil ? "Informe a senha ao abrir o item." : "Selecione Abrir ou pressione espaço para visualizar.").foregroundStyle(.secondary) }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount:entry.size,countStyle:.file)).font(.caption)
                if entry.encrypted { Label("Criptografado",systemImage:"lock.fill").font(.caption) }
                if !entry.directory { Button(doc.preferences.editorApplication.isEmpty ? "Abrir no aplicativo padrão" : "Abrir no editor externo") { doc.openExternal(entry) }.disabled(doc.busy || doc.saveReview != nil); Button("Editar como texto") { doc.editText(entry) }.disabled(doc.busy || doc.saveReview != nil) }
            } else { Text("Selecione um arquivo para visualizar.").foregroundStyle(.secondary); Spacer() }
        }.padding().frame(maxWidth:.infinity,minHeight:geometry.size.height,alignment:.topLeading)
        }
        }.frame(minWidth:180,idealWidth:280,maxWidth:340)
    }
}
struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context:Context) -> PDFView { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url:url); return v }
    func updateNSView(_ view:PDFView,context:Context) { if view.document?.documentURL != url { view.document = PDFDocument(url:url) } }
}

enum AppTheme: String, CaseIterable {
    case system, light, dark
    var label: String { switch self { case .system: return "Sistema"; case .light: return "Claro"; case .dark: return "Escuro" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
    @MainActor func apply() {
        switch self { case .system: NSApp.appearance = nil; case .light: NSApp.appearance = NSAppearance(named:.aqua); case .dark: NSApp.appearance = NSAppearance(named:.darkAqua) }
    }
}

struct SaveReviewView: View {
    @ObservedObject var doc: ArchiveDocument
    let review: PendingSave
    var body: some View {
        let summary = review.summary
        VStack(alignment:.leading,spacing:16) {
            Text("Resumo antes de salvar").font(.title2.bold())
            Text(review.destination.lastPathComponent).font(.headline)
            Text(review.destination.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing:24) {
                ForEach(SaveChange.Kind.allCases,id:\.self) { kind in
                    VStack(alignment:.leading,spacing:4) { Text("\(summary.count(kind))").font(.title2.monospacedDigit().bold()); Text(kind == .excluded ? "Limpeza / filtros" : kind.rawValue).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Divider()
            Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:8) {
                GridRow { Text("Formato").foregroundStyle(.secondary); Text(review.options.format.uppercased()) }
                if let size = review.options.volumeMB { GridRow { Text("Volumes nativos").foregroundStyle(.secondary); Text("\(review.options.format.uppercased()) • até \(size) MB por parte") } }
                GridRow { Text("Proteção atual").foregroundStyle(.secondary); Text(review.userURL == nil ? "Novo arquivo" : review.currentProtection.label) }
                GridRow { Text("Após salvar").foregroundStyle(.secondary); Label(ArchiveProtection.output(review.options).label,systemImage:ArchiveProtection.output(review.options).icon) }
                GridRow { Text("Conteúdo final").foregroundStyle(.secondary); Text("\(summary.totalFiles) arquivos • \(ByteCountFormatter.string(fromByteCount:summary.totalBytes,countStyle:.file))") }
            }.font(.callout)
            if summary.changes.isEmpty {
                Text("Nenhuma alteração nos itens. As opções de formato, compressão e proteção acima serão aplicadas.").foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical)
            } else {
                List {
                    ForEach(SaveChange.Kind.allCases,id:\.self) { kind in
                        let rows = summary.changes.filter { $0.kind == kind }
                        if !rows.isEmpty {
                            Section(kind.rawValue) {
                                ForEach(rows) { row in
                                    HStack(alignment:.top) {
                                        Image(systemName:kind.icon).foregroundStyle(.secondary)
                                        VStack(alignment:.leading,spacing:3) {
                                            Text(row.path).textSelection(.enabled)
                                            if let previous = row.previousPath { Text("Antes: " + previous).font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.listStyle(.inset).frame(minHeight:150,maxHeight:270)
            }
            Text("O arquivo será gravado após sua confirmação. Pastas também entram na contagem de itens.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancelar",action:doc.cancelSaveReview).keyboardShortcut(.cancelAction); Button("Salvar",action:doc.confirmSaveReview).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.padding(24).frame(width:700).foregroundStyle(.primary)
            .background(Color(nsColor:.windowBackgroundColor))
    }
}

struct OptionsView: View {
    @ObservedObject var doc: ArchiveDocument
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Aperta que cabe — opções").font(.title2.bold())
            Form {
                Picker("Formato de saída",selection:$doc.options.format) {
                    Text("ZIP").tag("zip"); Text("7z").tag("7z"); Text("RAR (RAR5)").tag("rar"); Text("TAR").tag("tar")
                    Text("TAR + Gzip").tag("tgz"); Text("TAR + Bzip2").tag("tbz2"); Text("TAR + XZ").tag("txz")
                }
                Picker("Compressão",selection:$doc.options.level) { Text("Sem compressão").tag(0); Text("Rápida").tag(1); Text("Equilibrada").tag(5); Text("Máxima").tag(9) }.disabled(doc.options.format == "tar")
                Toggle(doc.options.format == "zip" ? "Proteger com senha (compatível com unzip)" : "Criptografar com AES-256",isOn:$doc.options.encrypt).disabled(!["zip","7z","rar"].contains(doc.options.format))
                if doc.options.encrypt {
                    Button(doc.savePassword == nil ? "Definir senha…" : "Alterar senha…") { if let pass = doc.askPassword(title:"Senha de gravação",confirm:true) { doc.savePassword = pass } }
                    Text(doc.options.format == "zip" ? "ZIP usa ZipCrypto para compatibilidade com unzip. É uma proteção fraca. A senha fica apenas na memória desta sessão." : "A senha fica apenas na memória desta sessão.").font(.caption).foregroundStyle(.secondary)
                }
                if ["zip","7z","rar"].contains(doc.options.format) {
                    Toggle("Dividir em volumes nativos",isOn:Binding(get:{ doc.options.volumeMB != nil },set:{ doc.options.volumeMB = $0 ? 100 : nil }))
                    if doc.options.volumeMB != nil {
                        TextField("Tamanho de cada volume (MB)",value:Binding(get:{ doc.options.volumeMB ?? 100 },set:{ doc.options.volumeMB = $0 }),format:.number)
                        Text(doc.options.format == "rar" ? "Gera .part1.rar, .part2.rar… Abra a primeira parte." : doc.options.format == "7z" ? "Gera .7z.001, .7z.002… Abra a primeira parte." : "Gera .z01, .z02… e .zip. Abra o arquivo .zip.").font(.caption).foregroundStyle(.secondary)
                    }
                    if doc.options.format == "rar", ArchiveEngine.rarTool == nil { Text("Requer o RAR oficial, configurado em Ajustes → Avançado.").font(.caption).foregroundStyle(.secondary) }
                }
                TextField("Incluir nomes (ex.: *.pdf;*.txt)",text:$doc.options.include)
                TextField("Excluir nomes (ex.: *.tmp;build/*)",text:$doc.options.exclude)
                Picker("Nomes repetidos ao adicionar/extrair",selection:$doc.conflict) { ForEach(ArchiveEngine.Conflict.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                if !doc.presets.isEmpty {
                    Menu("Carregar configuração salva") { ForEach(doc.presets) { preset in Button(preset.name) { doc.options = preset.options; doc.conflict = preset.conflict } } }
                }
                Button("Salvar como configuração…",action:doc.savePreset)
            }
            Text("Substituir uma pasta troca seu conteúdo inteiro. Filtros são aplicados na gravação. Para converter um arquivo, escolha o formato e use Salvar como.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Concluir") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:540)
        .onAppear { doc.optionsBaseline = doc.options }
        .onChange(of:doc.options.format) { _,format in if !["zip","7z","rar"].contains(format) { doc.options.encrypt = false }; if !["zip","7z","rar"].contains(format) { doc.options.volumeMB = nil } }
        .onDisappear { if doc.optionsBaseline != doc.options, doc.opened { doc.dirty = true } }
    }
}

struct ContentView: View {
    @ObservedObject var doc: ArchiveDocument
    @State private var removedExpanded = false
    var body: some View {
        VStack(spacing:0) {
            if !doc.opened {
            HStack(spacing:12) {
                ApplicationIcon(size:38)
                VStack(alignment:.leading,spacing:3) {
                    Text("TabajaraZip").font(.system(.headline,design:.rounded).weight(.black))
                    Text("Tecnologia de ponta. De estoque.").font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text(doc.directMode ? "MODO DIRETO: APERTOU, SALVOU!" : "SEUS ARQUIVOS NO APERTO!").font(.system(.caption,design:.rounded).weight(.heavy))
            }.padding(.horizontal,18).padding(.vertical,12).foregroundStyle(.white).background(Color(red:0.65,green:0.04,blue:0.10))
            }
            if doc.busy && !doc.dragPreparing {
                HStack(spacing:12) {
                    if doc.progressIndeterminate { ProgressView().controlSize(.small) }
                    else { ProgressView(value:doc.progress).frame(width:160); Text(doc.progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().frame(width:40) }
                    Text(doc.status).lineLimit(1); Spacer()
                    Button(doc.cancelling ? "Cancelando…" : "Cancelar",action:doc.cancelOperation).disabled(doc.cancelling)
                }.padding(10).background(.yellow.opacity(0.10))
            }
            if doc.opened { pathBar }
            HSplitView {
                if doc.opened { browser }
                else { welcome }
                if doc.opened && doc.previewVisible { PreviewPane(doc:doc) }
            }
            Divider()
            HStack {
                Text("\(doc.visibleEntries.count) itens • \(ByteCountFormatter.string(fromByteCount:doc.entries.filter { !$0.directory }.reduce(0) { $0 + max(0,$1.size) },countStyle:.file))")
                Spacer()
                if doc.opened {
                    Label(doc.protectionLabel,systemImage:doc.savedProtection.icon)
                        .foregroundStyle(.primary).fixedSize(horizontal:true,vertical:false)
                        .help("Proteção do arquivo já salvo. Mudanças pendentes serão mostradas no resumo antes de salvar.")
                    Divider().frame(height:12)
                }
                Text(doc.busy && !doc.dragPreparing ? "Trabalhando…" : doc.dirty ? "Alterações pendentes — ⌘S para salvar" : doc.status).lineLimit(1)
            }.font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(minWidth:640,minHeight:400)
        .background(Color(nsColor:.windowBackgroundColor))
        .tint(Color(nsColor:.controlAccentColor))
        .background(NativeArchiveToolbar(document:doc).frame(width:0,height:0))
        .alert("Não foi possível concluir",isPresented:Binding(get:{ doc.error != nil },set:{ if !$0 { doc.error = nil } })) { Button("OK") { doc.error = nil } } message:{ Text(doc.error ?? "") }
        .sheet(isPresented:$doc.optionsVisible) { OptionsView(doc:doc) }
        .sheet(item:$doc.saveReview) { review in SaveReviewView(doc:doc,review:review) }
        .sheet(isPresented:Binding(get:{ doc.message != nil },set:{ if !$0 { doc.message = nil } })) {
            VStack(alignment:.leading,spacing:18) { Text("Relatório Tabajara").font(.title2.bold()); ScrollView { Text(doc.message ?? "").font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }; HStack { Spacer(); Button("Fechar") { doc.message = nil }.keyboardShortcut(.defaultAction) } }.padding(24).frame(width:660,height:360)
        }
        .sheet(isPresented:$doc.editorVisible) {
            VStack { HStack { Text(doc.editorPath ?? "Editar texto").font(.headline); Spacer(); Button("Cancelar") { doc.editorVisible = false }; Button("Aplicar à sessão",action:doc.saveText).buttonStyle(.borderedProminent) }; TextEditor(text:$doc.editorText).font(.system(.body,design:.monospaced)) }.padding().frame(width:800,height:560)
        }
        .onChange(of:doc.selection) { _,_ in doc.updatePreview() }
        .onChange(of:doc.previewVisible) { _,_ in doc.updatePreview() }
        .onDrop(of:[UTType.fileURL.identifier],isTargeted:nil,perform:acceptDrop)


    }
    var welcome: some View {
        GeometryReader { geometry in
        ScrollView {
        let layout = geometry.size.width < 850 ? AnyLayout(VStackLayout(spacing:28)) : AnyLayout(HStackLayout(spacing:48))
        layout {
        VStack(spacing:20) {
            Text("CHEGA DE PASTA FOLGADA!").font(.system(.caption,design:.rounded).weight(.black)).tracking(3).padding(.horizontal,18).padding(.vertical,8).foregroundStyle(.black).background(.yellow,in:Capsule())
            ApplicationIcon(size:140)
            Text("TabajaraZip").font(.system(size:48,weight:.black,design:.rounded))
            Text("Se compactar, é tecnologia.\nSe sumir, é pegadinha.").font(.system(size:22,weight:.bold,design:.rounded)).multilineTextAlignment(.center)
            Text("Arraste arquivos para criar. Abra ZIP, 7z, RAR, TAR e mais.").foregroundStyle(.secondary)
            HStack { Button("Abrir arquivo…",action:doc.openPanel).buttonStyle(.borderedProminent); Button("Novo arquivo") { doc.newArchive() } }.controlSize(.large)
            Text("EDIÇÃO PARÓDIA • QUALIDADE TABAJARA DE COMPACTAÇÃO").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity)
        if !doc.recent.isEmpty {
            VStack(alignment:.leading,spacing:14) {
                HStack { Label("Arquivos recentes",systemImage:"clock").font(.title3.bold()); Spacer(); Button("Limpar",action:doc.clearRecent).font(.caption).disabled(doc.busy) }
                ScrollView {
                    VStack(spacing:6) {
                        ForEach(doc.recent,id:\.self) { path in RecentArchiveRow(doc:doc,path:path) }
                    }
                }
            }.frame(width:340).frame(maxHeight:440)
        }
        }.padding(30).frame(maxWidth:.infinity,minHeight:geometry.size.height)
        }.background(.yellow.opacity(0.04))
        }
    }
    var pathBar: some View { ArchivePathBar(document:doc) }
    var browser: some View {
        let changes = Dictionary(doc.pendingChanges.filter { $0.kind != .removed }.map { ($0.path,$0) },uniquingKeysWith:{ first,_ in first })
        return VStack(spacing:0) {
        Group {
        if doc.search.isEmpty && doc.viewMode == .columns { ArchiveColumnsView(document:doc) }
        else if doc.search.isEmpty && doc.viewMode == .icons { ArchiveIconsView(document:doc) }
        else {
        Table(doc.visibleEntries,selection:$doc.selection,sortOrder:$doc.sortOrder) {
            TableColumn("Nome",value:\.name) { entry in
                HStack(spacing:4) {
                    if doc.viewMode == .outline && doc.search.isEmpty {
                        if entry.directory {
                            Button { doc.toggleExpanded(entry.path) } label: { Image(systemName:doc.expandedFolders.contains(entry.path) ? "chevron.down" : "chevron.right").font(.system(size:9)).frame(width:12) }.buttonStyle(.plain).help("Expandir ou recolher pasta")
                        } else { Color.clear.frame(width:12,height:1) }
                    }
                    ArchiveDragLabel(document:doc,entry:entry).frame(minHeight:CGFloat(doc.preferences.nameSize + (doc.preferences.comfortableRows ? 22 : 9))).help(entry.path)
                }.padding(.leading,doc.viewMode == .outline && doc.search.isEmpty ? CGFloat(doc.indentation(entry))*16 : 0)
            }.width(min:180,ideal:300)
            TableColumn("Alteração") { entry in
                if let change = changes[entry.path] {
                    Label(change.kind == .added ? "Adicionado" : change.kind == .renamed ? "Renomeado" : "Alterado",systemImage:change.kind.icon)
                        .font(.caption).foregroundStyle(.primary).help(change.previousPath.map { "Antes: " + $0 } ?? "Alteração pendente de salvar")
                }
            }.width(min:90,ideal:110,max:250)
            TableColumn("Tamanho",value:\.size) { entry in Text(entry.directory ? "—" : ByteCountFormatter.string(fromByteCount:entry.size,countStyle:.file)) }.width(min:65,ideal:85,max:250)
            TableColumn("Comprimido",value:\.packedSort) { entry in Text(entry.packed.map { ByteCountFormatter.string(fromByteCount:$0,countStyle:.file) } ?? "—") }.width(min:65,ideal:85,max:250)
            TableColumn("Taxa",value:\.ratioSort) { entry in Text(entry.size > 0 && entry.packed != nil ? String(format:"%.0f%%",100 * (1 - Double(entry.packed!)/Double(entry.size))) : "—") }.width(min:45,ideal:55,max:150)
            TableColumn("Data",value:\.modifiedSort) { entry in Text(entry.modified?.formatted(date:.numeric,time:.shortened) ?? "—") }.width(min:100,ideal:130,max:300)
            TableColumn("Tipo",value:\.kind) { entry in Text(entry.kind) }.width(min:50,ideal:60,max:180)
        }
        .contextMenu(forSelectionType:String.self) { paths in
            if paths.count == 1, let entry = doc.entries.first(where:{ paths.contains($0.path) }) {
                Button(entry.directory ? "Abrir pasta" : doc.preferences.editorApplication.isEmpty ? "Abrir no aplicativo padrão" : "Abrir no editor externo") { doc.enter(entry) }
                if !entry.directory { Button("Visualizar (espaço)") { doc.quickLook(entry) }; Button("Editar texto") { doc.editText(entry) } }
                Button("Renomear…") { doc.rename(paths) }
            }
            if !paths.isEmpty {
                Button("Mover para…") { doc.move(paths) }
                Button("Extrair seleção…") { doc.extract(paths) }
                Button("Extrair aqui") { doc.selection = paths; doc.quickExtract(inFolder:false) }.disabled(doc.archiveURL == nil)
                Button("Extrair em pasta com o nome do arquivo") { doc.selection = paths; doc.quickExtract(inFolder:true) }.disabled(doc.archiveURL == nil)
                Divider()
                Button(role:.destructive) { doc.remove(paths) } label:{ Label(paths.count == 1 ? "Remover" : "Remover \(paths.count) itens",systemImage:"trash") }
            } else { Button("Nova pasta…",action:doc.newFolder); Button("Adicionar…",action:doc.addPanel) }
        } primaryAction: { paths in if paths.count == 1, let e = doc.entries.first(where:{ paths.contains($0.path) }) { doc.enter(e) } }
        .background(ArchiveColumnPreferences(remember:doc.preferences.rememberColumns).frame(width:0,height:0))
        .onKeyPress(.space) { doc.quickLook(); return .handled }
        .onDeleteCommand { doc.remove(doc.selection) }
        }
        }.disabled(doc.busy || doc.saveReview != nil)
        if !doc.removedEntries.isEmpty {
            Divider()
            VStack(alignment:.leading,spacing:6) {
                Button { removedExpanded.toggle() } label: {
                    HStack(spacing:6) {
                        Image(systemName:removedExpanded ? "chevron.down" : "chevron.right").font(.system(size:10))
                        Text("Removidos ao salvar (\(doc.removedEntries.count))")
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(removedExpanded ? "Expandido" : "Recolhido")
                if removedExpanded {
                ScrollView {
                    LazyVStack(spacing:4) {
                        ForEach(doc.removedEntries) { entry in
                            HStack { Label(entry.path,systemImage:"minus.circle").strikethrough().lineLimit(1); Spacer(); Button("Restaurar") { doc.restoreRemoved(entry.path) }.disabled(doc.busy || doc.saveReview != nil) }.padding(.vertical,3)
                        }
                    }
                }.frame(maxHeight:120)
                }
            }.padding(10)
        }
        }
    }
    func acceptDrop(_ providers:[NSItemProvider]) -> Bool {
        guard !doc.busy else { return false }
        let group = DispatchGroup(); let collector = DroppedURLs()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { value,_ in
                defer { group.leave() }
                if let url = value as? URL { collector.append(url) }
                else if let data = value as? Data, let url = URL(dataRepresentation:data,relativeTo:nil) { collector.append(url) }
            }
        }
        group.notify(queue:.main) {
            let urls = collector.values
            if !doc.opened, urls.count == 1, ["zip","7z","rar","tar","gz","tgz","bz2","xz","001"].contains(urls[0].pathExtension.lowercased()) { doc.requestOpen(urls[0]) }
            else if doc.opened { doc.add(urls) } else { doc.create(urls) }
        }
        return true
    }
}
struct RecentArchiveRow: View {
    @ObservedObject var doc: ArchiveDocument
    let path: String
    var exists: Bool { FileManager.default.fileExists(atPath:path) }
    var url: URL { URL(fileURLWithPath:path) }
    var body: some View {
        HStack(spacing:6) {
            Button {
                if exists { doc.requestOpen(url) } else { doc.locateRecent(path) }
            } label: {
                HStack(spacing:10) {
                    Image(nsImage:NSWorkspace.shared.icon(forFile:path)).resizable().frame(width:30,height:30)
                    VStack(alignment:.leading,spacing:3) {
                        Text(url.lastPathComponent).fontWeight(.medium).foregroundStyle(.primary).lineLimit(1)
                        Text(exists ? url.deletingLastPathComponent().path : "Não encontrado — clique para localizar").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength:0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                if exists { Button("Abrir") { doc.requestOpen(url) }; Button("Mostrar no Finder") { doc.revealRecent(path) } }
                Button("Localizar arquivo…") { doc.locateRecent(path) }
                Divider(); Button("Remover dos recentes") { doc.removeRecent(path) }
            } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help("Ações do arquivo recente")
        }.padding(10).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:8)).help(path).disabled(doc.busy)
        .contextMenu {
            if exists { Button("Mostrar no Finder") { doc.revealRecent(path) } }
            Button("Localizar arquivo…") { doc.locateRecent(path) }
            Button("Remover dos recentes") { doc.removeRecent(path) }
        }
    }
}
final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock(); private var urls:[URL] = []
    func append(_ url:URL) { lock.lock(); urls.append(url); lock.unlock() }
    var values:[URL] { lock.lock(); defer { lock.unlock() }; return urls }
}
extension Notification.Name {
    static let tabajaraCompress = Notification.Name("tabajara.compress")
    static let tabajaraExtract = Notification.Name("tabajara.extract")
}

@MainActor class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.servicesProvider = self; NSUpdateDynamicServices()
        if let url = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"), let icon = NSImage(contentsOf:url) { NSApp.applicationIconImage = icon }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { ArchiveWorkspace.shared.welcomeIfNeeded() }
    }
    func application(_ application: NSApplication, open urls: [URL]) { for url in urls { ArchiveWorkspace.shared.openArchive(url) } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { ArchiveWorkspace.shared.welcomeIfNeeded(); return true }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.main.async { ArchiveWorkspace.shared.prepareToTerminate { approved in NSApp.reply(toApplicationShouldTerminate:approved) } }
        return .terminateLater
    }
    @objc func extractArchives(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard !urls.isEmpty else { error.pointee = "Selecione arquivos compactados no Finder."; return }
        ArchiveWorkspace.shared.makeWindow().archiveDocument.extractBatchURLs(urls)
    }
    @objc func compressFiles(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard !urls.isEmpty else { error.pointee = "Selecione arquivos ou pastas no Finder."; return }
        ArchiveWorkspace.shared.newArchive(urls)
    }
}

struct TabajaraZipApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var workspace = ArchiveWorkspace.shared
    var doc: ArchiveDocument { workspace.activeDocument ?? workspace.fallbackDocument }
    @AppStorage("appAppearance") private var appearance = "system"
    var theme: AppTheme { AppTheme(rawValue:appearance) ?? .system }
    var body:some Scene {
        Settings { AppSettingsView().preferredColorScheme(theme.colorScheme).onAppear { theme.apply() }.onChange(of:appearance) { _,_ in theme.apply() } }.commands {
            CommandGroup(replacing:.toolbar) {
                Button("Personalizar Barra de Ferramentas…") {
                    (NSApp.keyWindow ?? NSApp.mainWindow)?.toolbar?.runCustomizationPalette(nil)
                }
            }
            CommandGroup(replacing:.newItem) {
                Button("Novo arquivo") { workspace.newArchive() }.keyboardShortcut("n")
                Button("Abrir…",action:doc.openPanel).keyboardShortcut("o")
                Button("Abrir com senha…",action:doc.openWithPassword)
                Menu("Abrir recente") {
                    ForEach(doc.recent,id:\.self) { path in
                        Button(URL(fileURLWithPath:path).lastPathComponent + (FileManager.default.fileExists(atPath:path) ? "" : " — Não encontrado")) {
                            if FileManager.default.fileExists(atPath:path) { doc.requestOpen(URL(fileURLWithPath:path)) } else { doc.locateRecent(path) }
                        }
                    }
                    Divider(); Button("Limpar recentes",action:doc.clearRecent).disabled(doc.recent.isEmpty)
                }.disabled(doc.busy || doc.saveReview != nil)

            }
            CommandGroup(after:.newItem) {
                Divider()
                Button("Fechar janela") { workspace.closeActiveWindow() }.keyboardShortcut("w")
                SettingsLink { Text("Preferências do app…") }
            }
            CommandGroup(replacing:.saveItem) {
                Button("Salvar") { doc.save() }.keyboardShortcut("s").disabled(!doc.canSave)
                Button("Salvar como / Converter…") { doc.save(as:true) }.keyboardShortcut("s",modifiers:[.command,.shift]).disabled(!doc.canSave)
            }
            CommandGroup(replacing:.undoRedo) {
                Button("Desfazer",action:doc.undo).keyboardShortcut("z").disabled(doc.undoCount == 0 || doc.busy || doc.directMode || doc.saveReview != nil)
                Button("Refazer",action:doc.redo).keyboardShortcut("z",modifiers:[.command,.shift]).disabled(doc.redoCount == 0 || doc.busy || doc.directMode || doc.saveReview != nil)
            }
            CommandMenu("Ir") {
                Button("Voltar",action:doc.navigateBack).keyboardShortcut("[").disabled(!doc.canNavigateBack || doc.saveReview != nil)
                Button("Avançar",action:doc.navigateForward).keyboardShortcut("]").disabled(!doc.canNavigateForward || doc.saveReview != nil)
                Button("Pasta superior",action:doc.navigateUp).keyboardShortcut(.upArrow,modifiers:.command).disabled(!doc.opened || doc.folder.isEmpty || doc.busy || doc.saveReview != nil)
                Button("Abrir seleção") { if let entry = doc.selectedEntry { doc.enter(entry) } }.keyboardShortcut(.downArrow,modifiers:.command).disabled(doc.selectedEntry == nil || doc.busy || doc.saveReview != nil)
                Button("Raiz do arquivo") { doc.navigate(to:"") }.disabled(!doc.opened || doc.busy || doc.saveReview != nil)
            }
            CommandMenu("Arquivo compactado") {
                Button("Adicionar…",action:doc.addPanel).keyboardShortcut("a",modifiers:[.command,.shift]).disabled(!doc.opened || doc.busy || doc.saveReview != nil)
                Button("Nova pasta…",action:doc.newFolder).keyboardShortcut("n",modifiers:[.command,.shift]).disabled(!doc.opened || doc.busy || doc.saveReview != nil)
                Button("Extrair seleção ou tudo…") { doc.extract(doc.selection) }.keyboardShortcut("e").disabled(!doc.opened || doc.busy || doc.saveReview != nil)
                Button("Extrair aqui") { doc.quickExtract(inFolder:false) }.keyboardShortcut("e",modifiers:[.command,.shift]).disabled(doc.archiveURL == nil || doc.busy || doc.saveReview != nil)
                Button("Extrair em pasta com o nome do arquivo") { doc.quickExtract(inFolder:true) }.disabled(doc.archiveURL == nil || doc.busy || doc.saveReview != nil)
                Button("Renomear…") { doc.rename(doc.selection) }.disabled(doc.selection.count != 1 || doc.busy || doc.saveReview != nil)
                Button("Remover seleção") { doc.remove(doc.selection) }.disabled(doc.selection.isEmpty || doc.busy || doc.saveReview != nil)
                Divider()
                Button("Testar integridade",action:doc.testArchive).disabled(doc.archiveURL == nil || doc.busy || doc.saveReview != nil)
                Button("Tentar recuperar ZIP…",action:doc.repairZIP).disabled(doc.busy || doc.saveReview != nil)
                Button("Calcular SHA-256",action:doc.hashArchive).disabled(doc.archiveURL == nil || doc.busy || doc.saveReview != nil)
                Button("Informar senha…",action:doc.setSourcePassword).disabled(!doc.opened || doc.busy || doc.saveReview != nil)
                Button(doc.directMode ? "Desativar modo direto" : "Ativar modo direto…",action:doc.toggleDirect).disabled(!doc.opened || doc.busy || doc.saveReview != nil)
                Button("Opções do arquivo…",action:doc.showFileOptions).disabled(!doc.canEditFileOptions)
                Divider()
                Button("Compactar em lote…",action:doc.batchCompress).disabled(doc.busy || doc.saveReview != nil)
                Button("Extrair em lote…",action:doc.batchExtract).disabled(doc.busy || doc.saveReview != nil)
                Button("Dividir arquivo em volumes…",action:doc.splitArchive).disabled(doc.archiveURL == nil || doc.busy || doc.saveReview != nil)
                Button("Reunir volumes…",action:doc.joinVolumes).disabled(doc.busy || doc.saveReview != nil)
            }
            CommandGroup(after:.help) {
                Button("Abrir pasta de logs") {
                    do { try FileManager.default.createDirectory(at:DiagnosticLog.defaultDirectory,withIntermediateDirectories:true); NSWorkspace.shared.open(DiagnosticLog.defaultDirectory) }
                    catch { doc.fail(error) }
                }
                Button("Guia de uso e automação") { if let url = Bundle.main.url(forResource:"Guia",withExtension:"md") { NSWorkspace.shared.open(url) } }
            }
        }
    }
}
#if !SNAPSHOT_TEST
@main struct Launcher {
    static func main() {
        DiagnosticLog.shared.write("application-start",message:"Diagnóstico iniciado",level:"info")
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticLog.shared.write("uncaught-exception",message:exception.name.rawValue,context:["stack":exception.callStackSymbols.joined(separator:"\n")])
        }
        if CommandLine.arguments.contains("--cli") { ArchiveCLI.main() }
        else { TabajaraZipApp.main() }
    }
}

#endif
