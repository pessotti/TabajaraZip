import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main struct DragTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let root = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:root) }
        let input = root.appendingPathComponent("original.txt"); try "arraste ç".write(to:input,atomically:true,encoding:.utf8)
        let doc = ArchiveDocument(storage:root); doc.create(); defer { doc.timer?.invalidate() }
        let entry = ArchiveEntry(path:"Pasta/ação.txt",directory:false,size:10,staged:input.path)
        let folder = ArchiveEntry(path:"Pasta",directory:true,size:0)
        let origin = NSPoint(x:10,y:10)
        precondition(!DragLabelView.shouldStartDrag(pressedAt:1,from:origin,eventTime:1.1,at:NSPoint(x:50,y:10)))
        precondition(!DragLabelView.shouldStartDrag(pressedAt:1,from:origin,eventTime:1.3,at:NSPoint(x:12,y:11)))
        precondition(DragLabelView.shouldStartDrag(pressedAt:1,from:origin,eventTime:1.3,at:NSPoint(x:20,y:10)))
        let dragImage = ArchiveDragPreview.image(for:entry)
        precondition(dragImage.size.height == 30 && dragImage.size.width >= 100 && dragImage.size.width <= 400 && dragImage.tiffRepresentation != nil)
        let originalStatus = doc.status
        let batch = DragExportBatch(document:doc,count:1)
        precondition(doc.dragPreparing && doc.status == originalStatus)
        let delegate = ArchiveFilePromise(root:folder,entries:[folder,entry],archive:nil,password:nil,batch:batch)
        let provider = NSFilePromiseProvider(fileType:UTType.folder.identifier,delegate:delegate)
        precondition(delegate.filePromiseProvider(provider,fileNameForType:UTType.folder.identifier) == "Pasta")
        let target = root.appendingPathComponent("nome escolhido pelo Finder")
        let error: Error? = await withCheckedContinuation { continuation in
            delegate.filePromiseProvider(provider,writePromiseTo:target) { error in continuation.resume(returning:error) }
        }
        if let error { throw error }
        let text = try String(contentsOf:target.appendingPathComponent("ação.txt"),encoding:.utf8)
        precondition(text == "arraste ç")
        precondition(!doc.busy && !doc.dragPreparing)
        let statusBeforeCancel = doc.status
        let cancelled = DragExportBatch(document:doc,count:1); cancelled.abandon()
        precondition(!doc.busy && !doc.dragPreparing && cancelled.control.cancelled && doc.status == statusBeforeCancel)
        let cancelledWrite = DragExportBatch(document:doc,count:1); cancelledWrite.control.cancel()
        let rejected = ArchiveFilePromise(root:folder,entries:[folder,entry],archive:nil,password:nil,batch:cancelledWrite)
        let cancelTarget = root.appendingPathComponent("cancelado")
        let failure: Error? = await withCheckedContinuation { continuation in
            rejected.filePromiseProvider(provider,writePromiseTo:cancelTarget) { error in continuation.resume(returning:error) }
        }
        precondition(failure is CancellationError && !FileManager.default.fileExists(atPath:cancelTarget.path) && !doc.busy)
        print("PASS: native Finder promise, folder and Unicode contents, Finder-selected name, cancelled drag and cancelled extraction")
    }
}
