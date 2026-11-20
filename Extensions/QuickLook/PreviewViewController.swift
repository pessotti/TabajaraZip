import Cocoa
import Quartz

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() { self.view = NSView(frame:NSRect(x:0,y:0,width:720,height:520)) }
    func preparePreviewOfFile(at url:URL,completionHandler handler:@escaping (Error?) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            let result:Result<ArchiveIndex,Error> = Result { try ArchiveEngine.list(url) }
            DispatchQueue.main.async {
                let scroll = NSScrollView(frame:self.view.bounds); scroll.autoresizingMask = [.width,.height]; scroll.hasVerticalScroller = true
                let text = NSTextView(frame:scroll.bounds); text.isEditable = false; text.font = .monospacedSystemFont(ofSize:12,weight:.regular); text.textContainerInset = NSSize(width:18,height:18)
                switch result {
                case .success(let index):
                    let lines = index.entries.map { e in
                        (e.directory ? "📁 " : "   ") + e.path + (e.directory ? "/" : "  •  " + (e.size < 0 ? "" : ByteCountFormatter.string(fromByteCount:e.size,countStyle:.file)))
                    }
                    text.string = "TABAJARA ZIP — Seus arquivos no aperto!\n\(url.lastPathComponent)\n\(index.entries.count) itens\n\n" + lines.joined(separator:"\n")
                case .failure(let error): DiagnosticLog.record("quick-look",error:error,context:["archive":url.path]); text.string = "TabajaraZip\n\n" + error.localizedDescription + "\n\nAbra o arquivo no app para informar uma senha ou ver os detalhes."
                }
                scroll.documentView = text; self.view.addSubview(scroll); handler(nil)
            }
        }
    }
}
