import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Native file promises let Finder choose the destination before any contents are extracted.
struct ArchiveDragLabel: NSViewRepresentable {
    @ObservedObject var document: ArchiveDocument
    let entry: ArchiveEntry
    var iconMode = false
    var drawsContent = true
    var onSelect: ((ArchiveEntry) -> Void)? = nil
    func makeNSView(context: Context) -> DragLabelView { DragLabelView() }
    func updateNSView(_ view: DragLabelView, context: Context) {
        view.document = document; view.entry = entry; view.iconMode = iconMode; view.drawsContent = drawsContent; view.selectionAction = onSelect
        view.needsDisplay = true
        view.setAccessibilityElement(true); view.setAccessibilityLabel(document.displayName(entry))
        view.toolTip = "Arraste para o Finder para extrair. Clique duas vezes para abrir."
    }
}

@MainActor final class DragLabelView: NSView, NSDraggingSource {
    weak var document: ArchiveDocument?
    var entry: ArchiveEntry?
    var iconMode = false
    var drawsContent = true
    var selectionAction: ((ArchiveEntry) -> Void)?
    var promises: [ArchiveFilePromise] = []
    var batch: DragExportBatch?
    private var press: (time: TimeInterval, point: NSPoint)?
    static func shouldStartDrag(pressedAt: TimeInterval, from origin: NSPoint, eventTime: TimeInterval, at point: NSPoint) -> Bool {
        eventTime - pressedAt >= 0.18 && hypot(point.x-origin.x,point.y-origin.y) >= 6
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard let document, !document.busy, document.saveReview == nil else { return }
        if event.modifierFlags.contains(.command) { super.keyDown(with:event); return }
        switch event.keyCode {
        case 49: document.quickLook()
        case 51,117: document.remove(document.selection)
        case 36: if let entry = document.selectedEntry { document.enter(entry) }
        default: super.keyDown(with:event)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func draw(_ dirtyRect: NSRect) {
        guard drawsContent, let entry else { return }
        let selected = document?.selection.contains(entry.path) == true
        let color: NSColor = selected ? .alternateSelectedControlTextColor : .labelColor
        if iconMode {
            let type = entry.directory ? UTType.folder : (UTType(filenameExtension:(entry.name as NSString).pathExtension) ?? .data)
            NSWorkspace.shared.icon(for:type).draw(in:NSRect(x:(bounds.width-48)/2,y:6,width:48,height:48),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            let size = CGFloat(document?.preferences.nameSize ?? 13)
            ((document?.displayName(entry) ?? entry.name) as NSString).draw(in:NSRect(x:4,y:60,width:max(0,bounds.width-8),height:44),withAttributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color,.paragraphStyle:paragraph])
            return
        }
        let image = NSImage(systemSymbolName:entry.directory ? "folder.fill" : "doc",accessibilityDescription:nil)
        image?.withSymbolConfiguration(.init(paletteColors:[entry.directory ? .systemYellow : color]))?.draw(in:NSRect(x:0,y:max(0,(bounds.height-18)/2),width:18,height:18))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
        let size = CGFloat(document?.preferences.nameSize ?? 13)
        let name = document?.displayName(entry) ?? entry.name
        (name as NSString).draw(in:NSRect(x:25,y:max(0,(bounds.height-size-4)/2),width:max(0,bounds.width-25),height:size+5),withAttributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color,.paragraphStyle:paragraph])
    }
    override func mouseDown(with event: NSEvent) {
        press = nil
        guard let document, let entry, !document.busy, document.saveReview == nil else { return }
        var ancestor = superview
        var focusedTable = false
        while let view = ancestor {
            if let table = view as? NSTableView { window?.makeFirstResponder(table); focusedTable = true; break }
            ancestor = view.superview
        }
        if !focusedTable { window?.makeFirstResponder(self) }
        if event.modifierFlags.contains(.shift), let anchor = document.selection.first,
           let start = document.visibleEntries.firstIndex(where:{ $0.path == anchor }),
           let end = document.visibleEntries.firstIndex(where:{ $0.path == entry.path }) {
            document.selection.formUnion(document.visibleEntries[min(start,end)...max(start,end)].map(\.path))
        } else if event.modifierFlags.contains(.command) {
            if document.selection.contains(entry.path) { document.selection.remove(entry.path) } else { document.selection.insert(entry.path) }
        } else if !document.selection.contains(entry.path) { document.selection = [entry.path] }
        if event.clickCount == 1 { selectionAction?(entry) }
        if event.clickCount == 2 { document.enter(entry) }
        else if event.clickCount == 1 { press = (event.timestamp,event.locationInWindow) }
    }
    override func mouseUp(with event: NSEvent) { press = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let press, Self.shouldStartDrag(pressedAt:press.time,from:press.point,eventTime:event.timestamp,at:event.locationInWindow) else { return }
        guard let document, let entry, !document.busy, document.saveReview == nil, document.sourcePassword() else { return }
        let paths = document.selection.contains(entry.path) ? document.selection : [entry.path]
        let selected = ArchiveEngine.selectedEntries(document.entries,paths:paths)
        let roots = selected.filter { e in !selected.contains(where:{ e.path.hasPrefix($0.path + "/") }) }
        guard !roots.isEmpty else { return }
        self.press = nil
        let batch = DragExportBatch(document:document,count:roots.count); self.batch = batch
        promises = roots.map { root in
            ArchiveFilePromise(root:root,entries:selected.filter { $0.path == root.path || $0.path.hasPrefix(root.path + "/") },archive:document.contentArchive,password:document.password,batch:batch)
        }
        let cursor = convert(event.locationInWindow,from:nil)
        let items = promises.map { promise -> NSDraggingItem in
            let type = promise.root.directory ? UTType.folder : (UTType(filenameExtension:(promise.root.name as NSString).pathExtension) ?? .data)
            let provider = NSFilePromiseProvider(fileType:type.identifier,delegate:promise)
            let item = NSDraggingItem(pasteboardWriter:provider)
            let preview = ArchiveDragPreview.image(for:promise.root)
            item.setDraggingFrame(NSRect(x:cursor.x-16,y:cursor.y-15,width:preview.size.width,height:preview.size.height),contents:preview)
            return item
        }
        let session = beginDraggingSession(with:items,event:event,source:self)
        session.draggingFormation = items.count > 1 ? .list : .none
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty { batch?.abandon() }
    }
}

@MainActor final class DragExportBatch {
    weak var document: ArchiveDocument?
    let control = JobControl()
    let count: Int
    var completed = 0
    var ended = false
    let previousStatus: String
    init(document: ArchiveDocument,count: Int) {
        self.document = document; self.count = count; previousStatus = document.status
        document.dragPreparing = true
        document.busy = true; document.cancelling = false; document.control = control
        document.progress = -1
    }
    func start() {
        guard !ended else { return }
        document?.dragPreparing = false
        document?.status = "Extraindo para o Finder…"
    }
    func update(_ value: Double, _ text: String) {
        guard !ended, let document, !document.cancelling else { return }
        document.progress = (Double(completed)+value)/Double(count); document.status = text
    }
    func finish(_ error: Error?) {
        completed += 1
        if let error { control.cancel(); document?.fail(error) }
        if completed == count { ended = true; document?.dragPreparing = false; document?.busy = false; document?.cancelling = false; if error == nil && !control.cancelled { document?.status = "Extração para o Finder concluída." } }
    }
    func abandon() { control.cancel(); ended = true; document?.dragPreparing = false; document?.busy = false; document?.cancelling = false; document?.status = previousStatus }
}

@MainActor final class ArchiveFilePromise: NSObject, NSFilePromiseProviderDelegate {
    let root: ArchiveEntry
    let entries: [ArchiveEntry]
    let archive: URL?
    let password: String?
    let batch: DragExportBatch
    init(root: ArchiveEntry,entries: [ArchiveEntry],archive: URL?,password: String?,batch: DragExportBatch) {
        self.root = root; self.entries = entries; self.archive = archive; self.password = password; self.batch = batch
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { root.name }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let entries = entries, root = root, archive = archive, password = password, control = batch.control, batch = batch
        Task { @MainActor in
            batch.start()
            do {
                try await Task.detached(priority:.userInitiated) {
                    let temp = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:temp) }
                    try ArchiveEngine.extract(entries:entries,archive:archive,password:password,destination:temp,conflict:.ask,control:control,progress:{ value,text in Task { @MainActor in batch.update(value*0.8,text) } })
                    guard !FileManager.default.fileExists(atPath:url.path) else { throw ArchiveError("O Finder escolheu um destino que já existe: \(url.lastPathComponent)") }
                    do {
                        try ArchiveEngine.copy(temp.appendingPathComponent(root.name),to:url,control:control,progress:{ value,text in Task { @MainActor in batch.update(0.8+value*0.2,"Copiando para o Finder: " + text) } })
                    } catch { try? FileManager.default.removeItem(at:url); throw error }
                }.value
                completionHandler(nil); batch.finish(nil)
            } catch { completionHandler(error); batch.finish(error) }
        }
    }
}

/// A compact, correctly scaled drag image with a readable filename in either appearance.
@MainActor enum ArchiveDragPreview {
    static func image(for entry: ArchiveEntry) -> NSImage {
        let font = NSFont.systemFont(ofSize:13,weight:.medium)
        let textWidth = (entry.name as NSString).size(withAttributes:[.font:font]).width
        let size = NSSize(width:min(400,max(100,ceil(textWidth)+50)),height:30)
        let type = entry.directory ? UTType.folder : (UTType(filenameExtension:(entry.name as NSString).pathExtension) ?? .data)
        let icon = NSWorkspace.shared.icon(for:type)
        return NSImage(size:size,flipped:false) { rect in
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect:rect.insetBy(dx:0.5,dy:0.5),xRadius:7,yRadius:7).fill()
            icon.draw(in:NSRect(x:7,y:5,width:20,height:20))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
            (entry.name as NSString).draw(in:NSRect(x:34,y:6,width:rect.width-42,height:18),withAttributes:[.font:font,.foregroundColor:NSColor.white,.paragraphStyle:paragraph])
            return true
        }
    }
}
