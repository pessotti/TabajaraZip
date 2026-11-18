import SwiftUI
import AppKit

@main struct UISnapshots {
    @MainActor static func snapshot<V:View>(_ view:V,name:String,width:CGFloat,height:CGFloat,to folder:URL) throws {
        let host = NSHostingView(rootView:view)
        host.frame = NSRect(x:0,y:0,width:width,height:height)
        let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.7))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw ArchiveError("No snapshot bitmap") }
        host.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in:host.bounds,to:bitmap) }
        guard let png = bitmap.representation(using:.png,properties:[:]) else { throw ArchiveError("No PNG representation") }
        try png.write(to:folder.appendingPathComponent(name + ".png")); window.close()
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let root = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:root) }
        let folder = URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let doc = ArchiveDocument(storage:root.appendingPathComponent("support")); doc.timer?.invalidate()
        let entries = [ArchiveEntry(path:"Documentos",directory:true,size:0), ArchiveEntry(path:"contrato.pdf",directory:false,size:24000,packed:15000,modified:Date(),encrypted:true,encryptionMethod:"ZipCrypto Deflate",original:"contrato.pdf"), ArchiveEntry(path:"relatório.txt",directory:false,size:1200,packed:600,modified:Date(),encrypted:true,encryptionMethod:"ZipCrypto Deflate",original:"relatório.txt")]
        doc.archiveURL = URL(fileURLWithPath:"/Exemplo/Projeto.zip"); doc.session = root; doc.entries = entries; doc.originalEntries = entries
        doc.recent = ["/Exemplo/Projeto.zip"]; doc.previewVisible = false
        var options = SaveOptions(); options.encrypt = true
        let request = PendingSave(destination:URL(fileURLWithPath:"/Exemplo/Projeto.zip"),entries:entries + [ArchiveEntry(path:"novo.txt",directory:false,size:100,staged:"/test")],original:entries,source:nil,sourceStamp:nil,options:options,password:nil,originalPassword:nil,userURL:doc.archiveURL,userStamp:nil,session:root,excludeMetadata:true,currentProtection:.zipCrypto)
        for (name,scheme,appearance) in [("dark",ColorScheme.dark,NSAppearance.Name.darkAqua),("light",.light,.aqua)] {
            NSApp.appearance = NSAppearance(named:appearance)
            try snapshot(ContentView(doc:doc).preferredColorScheme(scheme),name:"browser-"+name,width:1200,height:760,to:folder)
            try snapshot(SaveReviewView(doc:doc,review:request).preferredColorScheme(scheme),name:"save-review-"+name,width:750,height:650,to:folder)
            try snapshot(AppSettingsView().preferredColorScheme(scheme),name:"settings-"+name,width:560,height:330,to:folder)
        }
        print("PASS: six native UI snapshots generated")
    }
}
