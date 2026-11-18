import Foundation

enum ArchiveCLI {
    static func main() {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            args.removeAll { $0 == "--cli" }
            guard let command = args.first else { print(help); return }
            args.removeFirst()
            var format = "zip", level = 5, encrypted = false, include = "", exclude = ""
            var volumeMB: Int? = nil
            if let i = args.firstIndex(of:"--volume-size"), i+1 < args.count { guard let value = Int(args[i+1]), value > 0 else { throw ArchiveError("Tamanho de volume inválido.") }; volumeMB = value; args.removeSubrange(i...i+1) }
            if let i = args.firstIndex(of:"--format"), i+1 < args.count { format = args[i+1]; args.removeSubrange(i...i+1) }
            if let i = args.firstIndex(of:"--level"), i+1 < args.count { level = Int(args[i+1]) ?? 5; args.removeSubrange(i...i+1) }
            if let i = args.firstIndex(of:"--include"), i+1 < args.count { include = args[i+1]; args.removeSubrange(i...i+1) }
            if let i = args.firstIndex(of:"--exclude"), i+1 < args.count { exclude = args[i+1]; args.removeSubrange(i...i+1) }
            if let i = args.firstIndex(of:"--encrypt") { encrypted = true; args.remove(at:i) }
            // A password is accepted on stdin, never as a command-line argument or in presets/journals.
            let password = ProcessInfo.processInfo.environment["TABAJARA_PASSWORD_STDIN"] == "1" ? readLine(strippingNewline:true) : nil
            let control = JobControl()
            switch command {
            case "list":
                guard args.count == 1 else { throw ArchiveError(help) }
                let index = try ArchiveEngine.list(URL(fileURLWithPath:args[0]),password:password,control:control)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; print(String(decoding:try encoder.encode(index.entries),as:UTF8.self))
            case "test":
                guard args.count == 1 else { throw ArchiveError(help) }; try ArchiveEngine.test(URL(fileURLWithPath:args[0]),password:password,control:control); print("OK")
            case "hash":
                guard args.count == 1 else { throw ArchiveError(help) }; print(try ArchiveEngine.sha256(URL(fileURLWithPath:args[0]),control:control))
            case "extract":
                guard args.count >= 2 else { throw ArchiveError(help) }
                let archive = URL(fileURLWithPath:args[0]); let destination = URL(fileURLWithPath:args[1]); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
                let stage = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:stage) }
                let (index,source) = try ArchiveEngine.resolve(archive,in:stage,password:password,control:control)
                let selected = ArchiveEngine.selectedEntries(index.entries,paths:Set(args.dropFirst(2)))
                try ArchiveEngine.extract(entries:selected,archive:source,password:password,destination:destination,conflict:.ask,control:control,progress:{_,_ in}); print("OK")
            case "create", "convert":
                guard args.count >= 2 else { throw ArchiveError(help) }
                let destination = URL(fileURLWithPath:args[0]); guard !FileManager.default.fileExists(atPath:destination.path) else { throw ArchiveError("O destino já existe.") }
                let stage = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:stage) }
                var source:URL? = nil
                let entries:[ArchiveEntry]
                if command == "convert" {
                    let (index,resolved) = try ArchiveEngine.resolve(URL(fileURLWithPath:args[1]),in:stage,password:password,control:control)
                    entries = index.entries; source = resolved
                } else { entries = try ArchiveEngine.scan(Array(args.dropFirst()).map { URL(fileURLWithPath:$0) },prefix:"",staging:stage,control:control) }
                var options = SaveOptions(); options.format = format; options.level = level; options.encrypt = encrypted; options.include = include; options.exclude = exclude; options.volumeMB = volumeMB
                _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:source,destination:destination,options:options,password:password,originalPassword:password,expectedStamp:try source.map { try DiskStamp($0) },control:control,progress:{_,_ in}); print(ArchiveEngine.savedURL(destination,options:options).path)
            case "split":
                guard args.count == 3, let size = Int(args[2]) else { throw ArchiveError(help) }
                let destination = URL(fileURLWithPath:args[1]); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
                try ArchiveEngine.split(URL(fileURLWithPath:args[0]),destination:destination,megabytes:size,control:control,progress:{_,_ in}); print("OK")
            case "join":
                guard args.count == 2 else { throw ArchiveError(help) }; let destination = URL(fileURLWithPath:args[1]); guard !FileManager.default.fileExists(atPath:destination.path) else { throw ArchiveError("O destino já existe.") }
                try ArchiveEngine.join(URL(fileURLWithPath:args[0]),destination:destination,control:control); print("OK")
            default: print(help)
            }
        } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
    }
    static let help = """
    TabajaraZip — automação
    --cli list ARQUIVO                       Índice JSON
    --cli test ARQUIVO                       Testa integridade
    --cli hash ARQUIVO                       SHA-256
    --cli extract ARQUIVO DESTINO [CAMINHOS]  Extrai sem sobrescrever
    --cli create DESTINO ENTRADAS...          Cria arquivo compactado
    --cli convert DESTINO ORIGEM              Converte formatos
    --cli split ARQUIVO PASTA TAMANHO_MB       Divide em .001, .002…
    --cli join PRIMEIRO.001 DESTINO           Reúne volumes
    Opções: --format zip|7z|rar|tar|tgz|tbz2|txz --level 0|1|5|9
            --volume-size MB (ZIP/7z/RAR nativos)
            --encrypt --include '*.pdf;*.txt' --exclude '*.tmp'
    Senha: TABAJARA_PASSWORD_STDIN=1, com a senha na primeira linha da entrada padrão.
    """
}
