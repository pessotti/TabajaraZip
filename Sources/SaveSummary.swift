import Foundation

struct SaveChange: Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case added = "Adicionados", modified = "Alterados", renamed = "Renomeados", removed = "Removidos", excluded = "Excluídos por limpeza ou filtros"
        var icon: String {
            switch self { case .added: return "plus.circle"; case .modified: return "pencil.circle"; case .renamed: return "arrow.right.circle"; case .removed: return "minus.circle"; case .excluded: return "line.3.horizontal.decrease.circle" }
        }
    }
    var kind: Kind
    var path: String
    var previousPath: String?
    var id: String { kind.rawValue + ":" + path }
}
struct SaveSummary: Sendable {
    var changes: [SaveChange]
    var totalFiles: Int
    var totalBytes: Int64
    func count(_ kind: SaveChange.Kind) -> Int { changes.filter { $0.kind == kind }.count }
    init(entries: [ArchiveEntry], original: [ArchiveEntry], options: SaveOptions, excludeMetadata: Bool) {
        let wanted = ArchiveEngine.filtered(entries,options:options,excludeMetadata:excludeMetadata)
        let kept = Set(wanted.map(\.path)), old = Dictionary(uniqueKeysWithValues:original.map { ($0.path,$0) })
        let excluded = entries.filter { !kept.contains($0.path) }
        let excludedOriginals = Set(excluded.compactMap(\.original) + excluded.map(\.path))
        var matched = Set<String>(), changes: [SaveChange] = []
        for entry in wanted {
            if let path = entry.original, old[path] != nil {
                matched.insert(path)
                if path != entry.path { changes.append(SaveChange(kind:.renamed,path:entry.path,previousPath:path)) }
                else if entry.staged != nil { changes.append(SaveChange(kind:.modified,path:entry.path)) }
            } else if let previous = old[entry.path] {
                matched.insert(previous.path)
                if entry.staged != nil || previous.directory != entry.directory { changes.append(SaveChange(kind:.modified,path:entry.path)) }
            } else { changes.append(SaveChange(kind:.added,path:entry.path)) }
        }
        for entry in original where !matched.contains(entry.path) && !excludedOriginals.contains(entry.path) {
            changes.append(SaveChange(kind:.removed,path:entry.path))
        }
        changes += excluded.map { SaveChange(kind:.excluded,path:$0.path) }
        self.changes = changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        totalFiles = wanted.filter { !$0.directory }.count
        totalBytes = wanted.filter { !$0.directory }.reduce(0) { $0 + max(0,$1.size) }
    }
}
