import AppKit
import SwiftUI

@main struct ViewModeSnapshots {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let root = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:root) }
        let doc = ArchiveDocument(storage:root); doc.create(); doc.timer?.invalidate()
        doc.archiveURL = URL(fileURLWithPath:"/Exemplo/Projeto.zip"); doc.dirty = false
        doc.entries = [ArchiveEntry(path:"Documentos",directory:true,size:0),ArchiveEntry(path:"Documentos/Subpasta",directory:true,size:0),ArchiveEntry(path:"Documentos/notas.txt",directory:false,size:4200,modified:Date()),ArchiveEntry(path:"Documentos/Subpasta/final.txt",directory:false,size:1200),ArchiveEntry(path:"Imagem.png",directory:false,size:52000),ArchiveEntry(path:"Leia-me.txt",directory:false,size:250)]
        doc.originalEntries = doc.entries; doc.previewVisible = false
        let output = URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        for mode in ArchiveViewMode.allCases {
            doc.folder = ""; doc.viewMode = mode; doc.expandedFolders = ["Documentos","Documentos/Subpasta"]
            if mode == .columns { doc.folder = "Documentos/Subpasta" }
            let host = NSHostingView(rootView:ContentView(doc:doc).preferredColorScheme(.dark))
            host.frame = NSRect(x:0,y:0,width:1000,height:650)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = host; window.alphaValue = 0; window.orderFront(nil)
            host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.6)); host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw ArchiveError("No bitmap") }
            host.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in:host.bounds,to:bitmap) }
            guard let png = bitmap.representation(using:.png,properties:[:]) else { throw ArchiveError("No PNG") }
            try png.write(to:output.appendingPathComponent(mode.rawValue+".png"))
            window.close()
        }
        doc.dirty = false; try doc.discardSessionForExit()
        print("PASS: all four browser modes rendered without visible windows or Dock icon")
    }
}
