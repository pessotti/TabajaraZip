import AppIntents
import UniformTypeIdentifiers
import Foundation

struct CompressTabajaraIntent: AppIntent {
    static var title: LocalizedStringResource = "Compactar com TabajaraZip"
    static var description = IntentDescription("Cria um ZIP a partir dos arquivos recebidos, sem abrir a interface.")
    @Parameter(title:"Arquivos") var files:[IntentFile]
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let incoming = files
        let output = try await Task.detached {
            let workspace = try ArchiveEngine.workspace()
            let inputs = workspace.appendingPathComponent("inputs"); let staged = workspace.appendingPathComponent("staged")
            try FileManager.default.createDirectory(at:inputs,withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:staged,withIntermediateDirectories:true)
            var urls:[URL] = []
            for file in incoming {
                _ = try ArchiveEngine.validatePath(file.filename)
                let url = inputs.appendingPathComponent((file.filename as NSString).lastPathComponent)
                guard !FileManager.default.fileExists(atPath:url.path) else { throw ArchiveError("Arquivos com o mesmo nome não podem ser combinados nesta ação.") }
                if let source = file.fileURL { try FileManager.default.copyItem(at:source,to:url) } else { try file.data.write(to:url) }
                urls.append(url)
            }
            let entries = try ArchiveEngine.scan(urls,prefix:"",staging:staged,control:JobControl())
            let zip = workspace.appendingPathComponent("Arquivo Tabajara.zip")
            _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:zip,options:SaveOptions(),password:nil,originalPassword:nil,expectedStamp:nil,control:JobControl(),progress:{_,_ in})
            try? FileManager.default.removeItem(at:inputs); try? FileManager.default.removeItem(at:staged)
            return zip
        }.value
        return .result(value:IntentFile(fileURL:output,filename:output.lastPathComponent,type:.zip))
    }
}
struct ExtractTabajaraIntent: AppIntent {
    static var title: LocalizedStringResource = "Extrair com TabajaraZip"
    static var description = IntentDescription("Extrai os itens de um arquivo compactado e os devolve ao Atalhos. Arquivos com senha devem ser abertos no app.")
    @Parameter(title:"Arquivo compactado") var archive:IntentFile
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let incoming = archive
        let urls = try await Task.detached {
            let workspace = try ArchiveEngine.workspace()
            let source = workspace.appendingPathComponent("source-" + (incoming.filename as NSString).lastPathComponent)
            if let original = incoming.fileURL { try FileManager.default.copyItem(at:original,to:source) } else { try incoming.data.write(to:source) }
            let (index,resolved) = try ArchiveEngine.resolve(source,in:workspace)
            let output = workspace.appendingPathComponent("output"); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            try ArchiveEngine.extract(entries:index.entries,archive:resolved,password:nil,destination:output,conflict:.ask,control:JobControl(),progress:{_,_ in})
            try? FileManager.default.removeItem(at:source)
            return try FileManager.default.contentsOfDirectory(at:output,includingPropertiesForKeys:nil)
        }.value
        return .result(value:urls.map { IntentFile(fileURL:$0,filename:$0.lastPathComponent) })
    }
}
struct TabajaraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:CompressTabajaraIntent(),phrases:["Compactar arquivos com \(.applicationName)"],shortTitle:"Compactar arquivos",systemImageName:"archivebox.fill")
        AppShortcut(intent:ExtractTabajaraIntent(),phrases:["Extrair arquivos com \(.applicationName)"],shortTitle:"Extrair arquivos",systemImageName:"archivebox")
    }
}
