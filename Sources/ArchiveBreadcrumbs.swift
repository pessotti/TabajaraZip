import SwiftUI
import AppKit

/// Preserve root and current folder; collapse the oldest intermediate components first.
enum BreadcrumbFit {
    static func indices(titles: [String], width: CGFloat) -> [Int] {
        guard !titles.isEmpty else { return [] }
        var shown = Array(titles.indices)
        func estimatedWidth(_ indices: [Int]) -> CGFloat {
            indices.reduce(CGFloat(0)) { total,index in
                total + (index < 0 ? 28 : ceil((titles[index] as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:13)]).width) + 24)
            } + CGFloat(max(0,indices.count-1))*19
        }
        while estimatedWidth(shown) > max(0,width), shown.filter({ $0 > 0 && $0 < titles.count-1 }).count > 0 {
            guard let position = shown.firstIndex(where:{ $0 > 0 && $0 < titles.count-1 }) else { break }
            shown.remove(at:position)
            if !shown.contains(-1) { shown.insert(-1,at:1) }
        }
        return shown
    }
}

struct ArchivePathBar: View {
    @ObservedObject var document: ArchiveDocument
    var body: some View {
        HStack(spacing:14) {
            GeometryReader { geometry in
                trail(width:geometry.size.width).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
            }.frame(height:32)
            HStack(spacing:6) {
                if document.dirty { Image(systemName:"circle.fill").font(.system(size:6)).foregroundStyle(.secondary).help("Alterações pendentes") }
                Button(action:document.navigateBack) { Image(systemName:"chevron.left") }.disabled(!document.canNavigateBack).help("Voltar (⌘[)")
                Button(action:document.navigateForward) { Image(systemName:"chevron.right") }.disabled(!document.canNavigateForward).help("Avançar (⌘])")
                Button { document.navigate(to:"") } label: { Image(systemName:"house") }.help("Ir para a raiz")
                Button(action:document.navigateUp) { Image(systemName:"arrow.up") }.disabled(document.folder.isEmpty).help("Subir (⌘↑)")
                Button { document.previewVisible.toggle(); document.updatePreview() } label: { Image(systemName:"sidebar.right") }.help("Mostrar ou ocultar prévia")
            }.fixedSize()
        }.padding(.horizontal,14).padding(.vertical,5)
            .background(Color(nsColor:.controlBackgroundColor))
            .disabled(document.busy || document.saveReview != nil)
    }
    func trail(width: CGFloat) -> some View {
        let paths = document.breadcrumbs
        let titles = paths.map { $0.isEmpty ? (document.archiveURL?.lastPathComponent ?? "Novo arquivo") : ($0 as NSString).lastPathComponent }
        let shown = BreadcrumbFit.indices(titles:titles,width:width)
        let hidden = paths.indices.filter { !shown.contains($0) }
        return HStack(spacing:6) {
            ForEach(Array(shown.enumerated()),id:\.element) { position,index in
                if position > 0 { Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(.secondary).fixedSize() }
                if index == -1 {
                    Menu {
                        ForEach(hidden,id:\.self) { hiddenIndex in
                            Button(titles[hiddenIndex]) { document.navigate(to:paths[hiddenIndex]) }.help(paths[hiddenIndex])
                        }
                    } label: { Text("…").font(.body.bold()).padding(.horizontal,4) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Pastas intermediárias: " + hidden.map { titles[$0] }.joined(separator:" / "))
                } else {
                    Button { document.navigate(to:paths[index]) } label: {
                        HStack(spacing:5) {
                            Image(systemName:index == 0 ? "archivebox" : "folder").foregroundStyle(.secondary).fixedSize()
                            Text(titles[index]).lineLimit(1).truncationMode(.middle)
                        }
                    }.buttonStyle(.plain).font(.system(size:13))
                        .layoutPriority(index == shown.last ? 2 : index == 0 ? 1 : 0)
                        .help(index == 0 ? "Raiz do arquivo: " + titles[index] : paths[index])
                }
            }
        }.frame(maxWidth:width,alignment:.leading).clipped()
        .accessibilityElement(children:.contain).accessibilityLabel("Caminho no arquivo")
    }
}
