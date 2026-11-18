import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArchiveEntryMenu: View {
    @ObservedObject var document: ArchiveDocument
    let entry: ArchiveEntry
    var paths: Set<String> { document.selection.contains(entry.path) ? document.selection : [entry.path] }
    var body: some View {
        Button(entry.directory ? "Abrir pasta" : "Abrir arquivo") { document.enter(entry) }
        if !entry.directory { Button("Visualizar") { document.quickLook(entry) }; Button("Editar texto") { document.editText(entry) } }
        Button("Renomear…") { document.rename([entry.path]) }
        Button("Mover para…") { document.move(paths) }
        Button("Extrair seleção…") { document.extract(paths) }
        Divider()
        Button("Remover",role:.destructive) { document.remove(paths) }
    }
}

struct ArchiveIconsView: View {
    @ObservedObject var document: ArchiveDocument
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:110,maximum:150),spacing:12)],spacing:12) {
                ForEach(document.visibleEntries) { entry in
                    VStack(spacing:6) {
                        Image(nsImage:NSWorkspace.shared.icon(for:entry.directory ? .folder : (UTType(filenameExtension:(entry.name as NSString).pathExtension) ?? .data))).resizable().scaledToFit().frame(width:48,height:48)
                        Text(document.displayName(entry)).font(.system(size:CGFloat(document.preferences.nameSize))).lineLimit(2).multilineTextAlignment(.center)
                            .foregroundStyle(document.selection.contains(entry.path) ? Color.white : Color.primary)
                    }.frame(maxWidth:.infinity).frame(height:110).padding(4)
                        .overlay(ArchiveDragLabel(document:document,entry:entry,iconMode:true,drawsContent:false))
                        .background(document.selection.contains(entry.path) ? Color.accentColor : Color.clear,in:RoundedRectangle(cornerRadius:8))
                        .help(entry.path)
                        .contextMenu { ArchiveEntryMenu(document:document,entry:entry) }
                }
            }.padding(14).frame(width:max(0,geometry.size.width-28),alignment:.topLeading)
        }.frame(width:geometry.size.width,height:geometry.size.height)
        }.focusable().onKeyPress(.space) { document.quickLook(); return .handled }.onDeleteCommand { document.remove(document.selection) }
    }
}

struct ArchiveColumnsView: View {
    @ObservedObject var document: ArchiveDocument
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing:0) {
                    ForEach(document.columnFolders,id:\.self) { parent in
                        VStack(alignment:.leading,spacing:0) {
                            Text(parent.isEmpty ? (document.archiveURL?.lastPathComponent ?? "Novo arquivo") : (parent as NSString).lastPathComponent).font(.caption.bold()).lineLimit(1).padding(8)
                            Divider()
                            List(selection:$document.selection) {
                                ForEach(document.children(in:parent)) { entry in
                                    HStack(spacing:4) {
                                        ArchiveDragLabel(document:document,entry:entry,onSelect:{ document.selectInColumn($0) }).frame(minHeight:CGFloat(document.preferences.nameSize + (document.preferences.comfortableRows ? 22 : 9)))
                                        if entry.directory { Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary) }
                                    }.padding(.vertical,2)
                                        .background(entry.directory && (document.folder == entry.path || document.folder.hasPrefix(entry.path + "/")) ? Color.accentColor.opacity(0.15) : Color.clear)
                                        .contextMenu { ArchiveEntryMenu(document:document,entry:entry) }
                                        .tag(entry.path)
                                }
                            }.listStyle(.inset)
                        }.frame(width:240).id(parent)
                        Divider()
                    }
                }
            }.onChange(of:document.folder) { _,path in withAnimation { proxy.scrollTo(path,anchor:.trailing) } }
        }.onKeyPress(.space) { document.quickLook(); return .handled }.onDeleteCommand { document.remove(document.selection) }
    }
}
