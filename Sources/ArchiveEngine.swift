import Foundation
import CryptoKit
import Darwin

struct ArchiveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

final class JobControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func check() throws { if cancelled { throw CancellationError() } }
}

typealias JobProgress = @Sendable (Double, String) -> Void

struct ArchiveEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String { path }
    var path: String
    var directory: Bool
    var size: Int64
    var packed: Int64?
    var modified: Date?
    var encrypted: Bool = false
    var encryptionMethod: String?
    var blockedLink: Bool = false
    var original: String?
    var staged: String?
    var name: String { (path as NSString).lastPathComponent }
    var packedSort: Int64 { packed ?? -1 }
    var modifiedSort: Date { modified ?? .distantPast }
    var ratioSort: Double { size > 0 && packed != nil ? 1 - Double(packed!) / Double(size) : -.infinity }
    var parent: String { let p = (path as NSString).deletingLastPathComponent; return p == "." ? "" : p }
    var kind: String { blockedLink ? "Link bloqueado" : directory ? "Pasta" : ((path as NSString).pathExtension.uppercased()) }
}

struct ArchiveIndex: Sendable {
    var entries: [ArchiveEntry]
    var format: String
    var encrypted: Bool { entries.contains(where: \.encrypted) }
}

enum ArchiveProtection: String, Hashable, Sendable {
    case none, zipCrypto, aes256, other, mixed
    var label: String {
        switch self {
        case .none: return "Sem senha"
        case .zipCrypto: return "ZipCrypto · proteção fraca"
        case .aes256: return "AES-256"
        case .other: return "Criptografado"
        case .mixed: return "Proteção mista"
        }
    }
    var icon: String { self == .none ? "lock.open" : "lock.shield" }
    static func detect(_ entries: [ArchiveEntry]) -> Self {
        let files = entries.filter { !$0.directory }
        let encrypted = files.filter(\.encrypted)
        guard !encrypted.isEmpty else { return .none }
        let methods = Set(encrypted.map { entry -> Self in
            let method = (entry.encryptionMethod ?? "").lowercased()
            if method.contains("zipcrypto") { return .zipCrypto }
            if method.contains("aes-256") || method.contains("7zaes") || method.contains("rar5 aes") { return .aes256 }
            return .other
        })
        if methods.count > 1 || encrypted.count != files.count { return .mixed }
        return methods.first ?? .other
    }
    static func output(_ options: SaveOptions) -> Self {
        options.encrypt ? (options.format == "zip" ? .zipCrypto : .aes256) : .none
    }
}

enum ArchivePreferences {
    static let metadataKey = "excludeArchiveMetadata"
    static var excludeMetadata: Bool {
        UserDefaults.standard.object(forKey:metadataKey) as? Bool ?? true
    }
}

struct SaveOptions: Codable, Equatable, Sendable {
    var format = "zip"
    var level = 5
    var encrypt = false
    var include = ""
    var exclude = ""
    var volumeMB: Int? = nil
}

struct DiskStamp: Codable, Equatable, Sendable {
    var size: Int64
    var date: Date
    init(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        size = Int64(v.fileSize ?? 0); date = v.contentModificationDate ?? .distantPast
    }
}

enum ArchiveEngine {
    static var rarTool: URL? {
        let candidates = [ProcessInfo.processInfo.environment["TABAJARA_RAR"], UserDefaults.standard.string(forKey:"rarExecutable"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TabajaraZip/RAR/rar").path, "/opt/homebrew/bin/rar", "/usr/local/bin/rar"].compactMap { $0 }
        return candidates.map { URL(fileURLWithPath:$0) }.first { fm.isExecutableFile(atPath:$0.path) }
    }
    static func savedURL(_ destination: URL, options: SaveOptions) -> URL {
        guard options.volumeMB != nil else { return destination }
        if options.format == "7z" { return destination.appendingPathExtension("001") }
        guard options.format == "rar" else { return destination }
        // RAR keeps a plain .rar name when the content fits in one volume.
        if fm.fileExists(atPath:destination.path) { return destination }
        let base = destination.deletingPathExtension().lastPathComponent
        let pattern = "^" + NSRegularExpression.escapedPattern(for:base) + "\\.part0*1\\.rar$"
        let files = (try? fm.contentsOfDirectory(at:destination.deletingLastPathComponent(),includingPropertiesForKeys:nil)) ?? []
        return files.first { $0.lastPathComponent.range(of:pattern,options:.regularExpression) != nil } ?? destination.deletingPathExtension().appendingPathExtension("part1.rar")
    }
    static let fm = FileManager.default
    static var tool: URL {
        if let override = ProcessInfo.processInfo.environment["TABAJARA_7ZZ"] { return URL(fileURLWithPath: override) }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/7zz")
        if fm.isExecutableFile(atPath: bundled.path) { return bundled }
        // The Quick Look extension shares the enclosing app's tool.
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Tools/7zz")
        if fm.isExecutableFile(atPath: parent.path) { return parent }
        return URL(fileURLWithPath: "/opt/homebrew/bin/7zz")
    }
    static func workspace(in parent: URL? = nil) throws -> URL {
        let custom = UserDefaults.standard.string(forKey:"customTemporaryDirectory") ?? ""
        let root = custom.isEmpty ? fm.temporaryDirectory : URL(fileURLWithPath:custom)
        let u = (parent ?? root).appendingPathComponent("Tabajara-" + UUID().uuidString)
        try fm.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    @discardableResult static func run(_ args: [String], at: URL? = nil, password: String? = nil,
                                      output: URL? = nil, executable: URL? = nil, control: JobControl = JobControl(), progress: JobProgress = { _,_ in }) throws -> String {
        try control.check()
        guard fm.isExecutableFile(atPath: (executable ?? tool).path) else { throw ArchiveError("O motor 7-Zip não foi encontrado no aplicativo.") }
        let temp = try workspace(); defer { try? fm.removeItem(at: temp) }
        let log = output ?? temp.appendingPathComponent("stdout")
        let errors = temp.appendingPathComponent("stderr")
        fm.createFile(atPath: log.path, contents: nil); fm.createFile(atPath: errors.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: log), stderr = try FileHandle(forWritingTo: errors)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process(); process.executableURL = executable ?? tool; process.arguments = executable == nil ? [args[0], "-sccUTF-8", "-bsp2"] + Array(args.dropFirst()) : args
        process.currentDirectoryURL = at
        var env = ProcessInfo.processInfo.environment; env["LC_ALL"] = "en_US.UTF-8"; process.environment = env
        process.standardOutput = stdout; process.standardError = stderr
        let input = Pipe(); process.standardInput = input
        try process.run()
        if let password { try? input.fileHandleForWriting.write(contentsOf: Data((password + "\n" + password + "\n").utf8)) }
        try? input.fileHandleForWriting.close()
        while process.isRunning {
            if control.cancelled {
                process.terminate()
                for _ in 0..<20 { if !process.isRunning { break }; Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit(); throw CancellationError()
            }
            if let reader = try? FileHandle(forReadingFrom: errors) {
                let end = (try? reader.seekToEnd()) ?? 0
                try? reader.seek(toOffset: end > 1024 ? end - 1024 : 0)
                if let data = try? reader.readToEnd(), let text = String(data:data,encoding:.utf8),
                   let range = text.range(of:"[0-9]{1,3}%",options:[.regularExpression,.backwards]),
                   let number = Double(text[range].dropLast()) { progress(min(number/100,1), "Processando…") }
                try? reader.close()
            }
            Thread.sleep(forTimeInterval: 0.10)
        }
        process.waitUntilExit(); try stdout.synchronize(); try stderr.synchronize(); try control.check()
        let message = String(decoding: (try? Data(contentsOf: errors)) ?? Data(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let info = message.isEmpty ? String(decoding: (try? Data(contentsOf: log)) ?? Data(), as: UTF8.self) : message
            if info.lowercased().contains("password") || info.lowercased().contains("encrypted") { throw ArchiveError("Senha necessária ou incorreta. Informe a senha e tente novamente.") }
            throw ArchiveError(String(info.suffix(2400)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Não foi possível processar o arquivo." : String(info.suffix(2400)))
        }
        return output == nil ? String(decoding: try Data(contentsOf: log), as: UTF8.self) : ""
    }
    static func validatePath(_ raw: String) throws -> String {
        let path = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ArchiveError("Caminho inseguro ou incompatível no arquivo compactado: \(raw.debugDescription)")
        }
        return path
    }
    static func collisionKey(_ path: String) -> String { path.decomposedStringWithCanonicalMapping.lowercased() }
    static func validateEntries(_ entries: [ArchiveEntry]) throws {
        var seen = Set<String>(), files = Set<String>()
        for e in entries {
            _ = try validatePath(e.path)
            guard seen.insert(collisionKey(e.path)).inserted else { throw ArchiveError("Há nomes duplicados ou que diferem apenas em maiúsculas/minúsculas: \(e.path)") }
            if !e.directory { files.insert(collisionKey(e.path)) }
        }
        for e in entries {
            var parent = e.parent
            while !parent.isEmpty {
                if files.contains(collisionKey(parent)) { throw ArchiveError("Um arquivo está sendo usado como pasta: \(parent)") }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
    }
    static func validateZIPDirectory(_ url: URL) throws {
        let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
        let size = try file.seekToEnd(); guard size >= 22 else { throw ArchiveError("ZIP incompleto.") }
        let start = size > 65_557 ? size - 65_557 : 0
        try file.seek(toOffset:start); let tail = try file.readToEnd() ?? Data()
        func number(_ bytes:Data,_ offset:Int,_ width:Int) -> UInt64 {
            guard offset >= 0, offset + width <= bytes.count else { return 0 }
            return (0..<width).reduce(UInt64(0)) { $0 | (UInt64(bytes[offset + $1]) << ($1 * 8)) }
        }
        var eocd:Int?
        if tail.count >= 22 {
            for i in stride(from:tail.count-22,through:0,by:-1) {
                if number(tail,i,4) == 0x06054b50 && i + 22 + Int(number(tail,i+20,2)) == tail.count { eocd = i; break }
            }
        }
        guard let eocd else { throw ArchiveError("O ZIP não tem um diretório final válido. Use Tentar recuperar ZIP.") }
        // Split ZIPs use a different offset space and are validated by 7-Zip.
        if number(tail,eocd+4,2) != 0 { return }
        var count = number(tail,eocd+10,2), offset = number(tail,eocd+16,4)
        if count == 0xffff || offset == 0xffffffff {
            let locator = eocd - 20
            guard locator >= 0, number(tail,locator,4) == 0x07064b50 else { throw ArchiveError("Diretório ZIP64 inválido.") }
            try file.seek(toOffset:number(tail,locator+8,8)); let record = try file.read(upToCount:56) ?? Data()
            guard record.count == 56, number(record,0,4) == 0x06064b50 else { throw ArchiveError("Diretório ZIP64 inválido.") }
            count = number(record,32,8); offset = number(record,48,8)
        }
        guard count <= 2_000_000, offset <= size else { throw ArchiveError("Diretório ZIP inválido ou grande demais para esta versão.") }
        try file.seek(toOffset:offset)
        for _ in 0..<count {
            let header = try file.read(upToCount:46) ?? Data()
            guard header.count == 46, number(header,0,4) == 0x02014b50 else { throw ArchiveError("Diretório ZIP inválido.") }
            let length = Int(number(header,28,2)), extra = number(header,30,2), comment = number(header,32,2)
            let name = try file.read(upToCount:length) ?? Data()
            guard name.count == length, !name.contains(where:{ $0 < 32 || $0 == 127 }) else { throw ArchiveError("O ZIP contém nomes com caracteres de controle não suportados.") }
            if let decoded = String(data:name,encoding:.utf8) { _ = try validatePath(decoded) }
            else {
                // ASCII path separators remain unambiguous in legacy ZIP name encodings.
                let ascii = String(decoding:name,as:UTF8.self); _ = try validatePath(ascii)
            }
            let current = try file.offset(); try file.seek(toOffset:current + extra + comment)
        }
    }
    static func list(_ url: URL, password: String? = nil, control: JobControl = JobControl()) throws -> ArchiveIndex {
        let listing = try run(["l", "-slt", "--", url.path], password: password, control: control)
        let sections = listing.components(separatedBy: "\n----------\n")
        let header = sections.first ?? ""
        let detected = header.components(separatedBy: "\n").first(where: { $0.hasPrefix("Type = ") }).map { String($0.dropFirst(7)).lowercased() } ?? url.pathExtension.lowercased()
        let raw = sections.count > 1 ? sections.dropFirst().joined(separator: "\n----------\n") : ""
        if detected == "zip", url.pathExtension.lowercased() != "001" { try validateZIPDirectory(url) }
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var entries: [ArchiveEntry] = []
        for block in raw.components(separatedBy: "\n\n") where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var fields: [String:String] = [:]
            for line in block.components(separatedBy: "\n") where !line.isEmpty {
                guard let sep = line.range(of: " = ") else {
                    if line.hasPrefix("Enter password:") { continue }
                    throw ArchiveError("O arquivo contém nomes ou comentários incompatíveis com esta versão.")
                }
                let key = String(line[..<sep.lowerBound])
                if fields[key] != nil { throw ArchiveError("Metadados ambíguos no arquivo compactado.") }
                fields[key] = String(line[sep.upperBound...])
            }
            guard let rawPath = fields["Path"] else { continue }
            let path = try validatePath(rawPath)
            let attributes = fields["Attributes"] ?? ""
            let mode = fields["Mode"] ?? ""
            let blockedLink = !(fields["Symbolic Link"] ?? "").isEmpty || !(fields["Hard Link"] ?? "").isEmpty || attributes.contains("l") || mode.hasPrefix("l") || attributes.contains("p") || attributes.contains("s")
            let isDir = fields["Folder"] == "+" || attributes.hasPrefix("D") || mode.hasPrefix("d") || rawPath.hasSuffix("/")
            entries.append(ArchiveEntry(path: path, directory: isDir, size: Int64(fields["Size"] ?? "0") ?? 0,
                                        packed: Int64(fields["Packed Size"] ?? ""), modified: date.date(from: String((fields["Modified"] ?? "").prefix(19))),
                                        encrypted: fields["Encrypted"] == "+", encryptionMethod:fields["Method"], blockedLink:blockedLink, original: path))
        }
        if entries.isEmpty && ["gzip", "bzip2", "xz"].contains(detected) {
            var name = url.deletingPathExtension().lastPathComponent
            if ["tgz", "tbz", "tbz2", "txz"].contains(url.pathExtension.lowercased()) { name += ".tar" }
            entries = [ArchiveEntry(path:try validatePath(name),directory:false,size:-1,original:"")]
        }
        try validateEntries(entries)
        var known = Set(entries.map(\.path))
        for e in entries {
            var parent = e.parent
            while !parent.isEmpty {
                if known.insert(parent).inserted { entries.append(ArchiveEntry(path: parent, directory: true, size: 0)) }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        try validateEntries(entries)
        let ext = detected
        let format: String
        switch ext {
        case "7z": format = "7z"
        case "tar": format = "tar"
        case "gz", "tgz": format = "gzip"
        case "bz2", "tbz": format = "bzip2"
        case "xz", "txz": format = "xz"
        case "rar", "rar5", "r00": format = "rar"
        default: format = ext == "zip" || ext == "cbz" ? "zip" : ext
        }
        return ArchiveIndex(entries: entries.sorted { $0.path < $1.path }, format: format)
    }
    static func resolve(_ url: URL, in directory: URL, password: String? = nil, control: JobControl = JobControl()) throws -> (ArchiveIndex,URL) {
        var index = try list(url,password:password,control:control)
        if ["gzip","bzip2","xz"].contains(index.format), index.entries.count == 1, let inner = index.entries.first, inner.path.lowercased().hasSuffix(".tar") {
            let source = directory.appendingPathComponent("content-" + UUID().uuidString + ".tar")
            try materialize(inner,archive:url,password:password,to:source,control:control)
            let format = index.format == "gzip" ? "tgz" : index.format == "bzip2" ? "tbz2" : "txz"
            index = try list(source,password:password,control:control); index.format = format
            return (index,source)
        }
        return (index,url)
    }
    /// Copies in bounded chunks so Cancel also works for large uncompressed/staged files.
    static func copy(_ source: URL, to destination: URL, control: JobControl, progress: JobProgress = {_,_ in}) throws {
        try control.check()
        let values = try source.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey])
        guard values.isSymbolicLink != true else { throw ArchiveError("Links não são copiados.") }
        if values.isDirectory == true {
            try fm.createDirectory(at:destination,withIntermediateDirectories:true)
            for child in try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil) {
                try copy(child,to:destination.appendingPathComponent(child.lastPathComponent),control:control,progress:progress)
            }
        } else {
            let input = try FileHandle(forReadingFrom:source); defer { try? input.close() }
            guard fm.createFile(atPath:destination.path,contents:nil) else { throw ArchiveError("Não foi possível criar \(destination.lastPathComponent).") }
            let output = try FileHandle(forWritingTo:destination); defer { try? output.close() }
            var bytes: Int64 = 0
            while true {
                try control.check()
                guard let data = try input.read(upToCount:1024*1024), !data.isEmpty else { break }
                try output.write(contentsOf:data); bytes += Int64(data.count)
                progress(Double(bytes)/Double(max(values.fileSize ?? 1,1)),source.lastPathComponent)
            }
        }
        if let date = values.contentModificationDate { try fm.setAttributes([.modificationDate:date],ofItemAtPath:destination.path) }
        try control.check()
    }
    static func materialize(_ entry: ArchiveEntry, archive: URL?, password: String?, to dest: URL, control: JobControl, progress: JobProgress = {_,_ in}) throws {
        try control.check(); _ = try validatePath(entry.path)
        guard !entry.blockedLink else { throw ArchiveError("Links e arquivos especiais podem ser listados, mas não extraídos ou convertidos: \(entry.path)") }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if entry.directory { try fm.createDirectory(at: dest, withIntermediateDirectories: true); return }
        if let staged = entry.staged {
            try copy(URL(fileURLWithPath:staged),to:dest,control:control,progress:progress)
        } else if let original = entry.original, let archive {
            // Streaming one member to a file avoids extraction path and symlink interpretation entirely.
            try run(["x", "-so", "-spd", "--", archive.path] + (original.isEmpty ? [] : [original]), password: password, output: dest, control: control, progress:progress)
            let size = (try dest.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard entry.size < 0 || Int64(size) == entry.size else { throw ArchiveError("Tamanho inesperado ao extrair \(entry.path).") }
        } else { throw ArchiveError("O conteúdo de \(entry.path) não está disponível.") }
        if let modified = entry.modified { try fm.setAttributes([.modificationDate: modified], ofItemAtPath: dest.path) }
    }
    static func selectedEntries(_ entries: [ArchiveEntry], paths: Set<String>) -> [ArchiveEntry] {
        paths.isEmpty ? entries : entries.filter { e in paths.contains(e.path) || paths.contains(where: { e.path.hasPrefix($0 + "/") }) }
    }
    static func scan(_ urls: [URL], prefix: String, staging: URL, control: JobControl, progress: JobProgress = {_,_ in}) throws -> [ArchiveEntry] {
        var result: [ArchiveEntry] = []
        var stagedFiles: [URL] = []; var success = false
        defer { if !success { for url in stagedFiles { try? fm.removeItem(at:url) } } }
        func visit(_ url: URL, path: String) throws {
            try control.check(); _ = try validatePath(path)
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard v.isSymbolicLink != true, v.isDirectory == true || v.isRegularFile == true else { throw ArchiveError("Links e arquivos especiais não são aceitos: \(url.lastPathComponent)") }
            if v.isDirectory == true {
                result.append(ArchiveEntry(path: path, directory: true, size: 0, modified: v.contentModificationDate))
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try visit(child, path: path + "/" + child.lastPathComponent) }
            } else {
                let target = staging.appendingPathComponent(UUID().uuidString)
                stagedFiles.append(target)
                let number = result.count + 1
                try copy(url,to:target,control:control,progress:{_,_ in progress(-1,"Adicionando \(number)º item: \(url.lastPathComponent)") })
                result.append(ArchiveEntry(path: path, directory: false, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate, staged: target.path))
            }
        }
        for url in urls { try visit(url, path: prefix.isEmpty ? url.lastPathComponent : prefix + "/" + url.lastPathComponent) }
        try validateEntries(result); try control.check(); success = true; return result
    }
    static func matches(_ path: String, patterns: String) -> Bool {
        patterns.split(separator: ";").contains { pattern in
            let p = pattern.trimmingCharacters(in: .whitespaces)
            return fnmatch(p, path, 0) == 0 || fnmatch(p, (path as NSString).lastPathComponent, 0) == 0
        }
    }
    static func filtered(_ entries: [ArchiveEntry], options: SaveOptions, excludeMetadata: Bool = ArchivePreferences.excludeMetadata) -> [ArchiveEntry] {
        let files = entries.filter { e in
            if excludeMetadata && e.path.split(separator: "/").contains(where: { $0 == ".DS_Store" || $0 == "_MACOSX" || $0 == "__MACOSX" }) { return false }
            if !options.exclude.isEmpty && matches(e.path, patterns: options.exclude) { return false }
            return e.directory || options.include.isEmpty || matches(e.path, patterns: options.include)
        }
        if options.include.isEmpty { return files }
        return files.filter { e in !e.directory || files.contains(where: { !$0.directory && $0.path.hasPrefix(e.path + "/") }) }
    }
    static func test(_ url: URL, password: String?, control: JobControl) throws {
        try run(["t", "--", url.path], password: password, control: control)
    }
    static func sha256(_ url: URL, control: JobControl) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }; var hash = SHA256()
        while let chunk = try h.read(upToCount: 1024 * 1024), !chunk.isEmpty { try control.check(); hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func write(entries: [ArchiveEntry], originalEntries: [ArchiveEntry], archive: URL?, destination: URL,
                      options: SaveOptions, password: String?, originalPassword: String?, expectedStamp: DiskStamp?,
                      excludeMetadata: Bool = ArchivePreferences.excludeMetadata, control: JobControl, progress: JobProgress) throws -> ArchiveIndex {
        try validateEntries(entries)
        if let size = options.volumeMB { guard ["zip","7z","rar"].contains(options.format), (1...1_000_000).contains(size) else { throw ArchiveError("Volumes nativos exigem ZIP, 7z ou RAR e tamanho entre 1 e 1.000.000 MB.") } }
        guard ["zip","7z","rar","tar","tgz","tbz2","txz"].contains(options.format) else { throw ArchiveError("Formato de gravação não suportado.") }
        if options.encrypt && (password?.isEmpty != false || !["zip","7z","rar"].contains(options.format)) { throw ArchiveError("Defina uma senha para criar ZIP, 7z ou RAR criptografado.") }
        if options.encrypt && options.format == "zip", let password, !password.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value <= 126 }) { throw ArchiveError("Para ZIP compatível com unzip, use uma senha sem acentos ou emojis. O formato 7z aceita senhas Unicode.") }
        if let archive, let expectedStamp, try DiskStamp(archive) != expectedStamp { throw ArchiveError("O arquivo original foi alterado por outro programa. Reabra-o antes de salvar.") }
        let temp = try workspace(in: destination.deletingLastPathComponent()); defer { try? fm.removeItem(at: temp) }
        let output = temp.appendingPathComponent("result." + options.format)
        let input = temp.appendingPathComponent("input"); try fm.createDirectory(at: input, withIntermediateDirectories: true)
        let wanted = filtered(entries, options: options, excludeMetadata: excludeMetadata)
        let originalFormat = archive?.pathExtension.lowercased()
        let incremental = options.volumeMB == nil && archive != nil && originalFormat == options.format && ["zip","7z"].contains(options.format) && !options.encrypt && !originalEntries.contains(where: \.encrypted)
        let changed = incremental ? wanted.filter { $0.staged != nil || $0.original != $0.path } : wanted
        for (i,e) in changed.enumerated() {
            progress(Double(i) / Double(max(changed.count, 1)) * 0.50, "Preparando \(e.name)")
            try materialize(e, archive: archive, password: originalPassword, to: input.appendingPathComponent(e.path), control: control)
        }
        if options.format == "rar" || (options.format == "7z" && options.volumeMB != nil) {
            return try writeNativeArchive(input:input, temp:temp, wanted:wanted, destination:destination, options:options, password:password, archive:archive, expectedStamp:expectedStamp, control:control, progress:progress)
        }
        let compression = "-mx\(options.level)"
        var params = ["-t" + (options.format == "tgz" || options.format == "tbz2" || options.format == "txz" ? "tar" : options.format), compression, "-spd", "-sse"]
        if options.format == "tar" { params.removeAll { $0.hasPrefix("-mx") } }
        if options.format == "zip" { params.append(options.level == 0 ? "-mm=Copy" : "-mm=Deflate") }
        if options.encrypt { params += options.format == "zip" ? ["-mem=ZipCrypto", "-p"] : ["-mhe=on", "-p"] }
        progress(0.53, "Gravando arquivo compactado…")
        if incremental, let archive {
            try fm.copyItem(at: archive, to: output)
            let wantedByPath = Dictionary(uniqueKeysWithValues: wanted.map { ($0.path, $0) })
            let removed = originalEntries.filter { old in
                guard old.original != nil else { return false }
                return wantedByPath[old.path]?.original != old.path || wantedByPath[old.path]?.staged != nil
            }.map(\.path)
            if !removed.isEmpty { try run(["d", "-spd", "--", output.path] + removed, control: control) }
            if !changed.isEmpty { try run(["a"] + params + ["--", output.path, "."], at: input, control: control, progress:{ p,_ in progress(0.53 + p * 0.22,"Compactando… \(Int(p*100))%") }) }
        } else if wanted.isEmpty && options.format == "zip" && !options.encrypt {
            try (Data([0x50,0x4b,0x05,0x06]) + Data(repeating: 0, count: 18)).write(to: output)
        } else {
            let tarBased = ["tgz","tbz2","txz"].contains(options.format)
            let target = tarBased ? temp.appendingPathComponent("content.tar") : output
            try run(["a"] + params + ["--", target.path, "."], at: input, password: options.encrypt ? password : nil, control: control, progress:{ p,_ in progress(0.53 + p * 0.22,"Compactando… \(Int(p*100))%") })
            if tarBased {
                let type = options.format == "tgz" ? "gzip" : options.format == "tbz2" ? "bzip2" : "xz"
                try run(["a", "-t" + type, compression, "--", output.path, target.path], control: control)
            }
        }
        progress(0.78, "Verificando integridade…")
        try test(output, password: options.encrypt ? password : nil, control: control)
        let (saved,_) = try resolve(output,in:temp,password:options.encrypt ? password : nil,control:control)
        do {
            let expected = Set(wanted.filter { !$0.directory }.map(\.path))
            let actual = Set(saved.entries.filter { !$0.directory }.map(\.path))
            guard expected == actual else { throw ArchiveError("A verificação encontrou conteúdo diferente do esperado. O original foi preservado.") }
        }
        try control.check()
        if let archive, let expectedStamp, try DiskStamp(archive) != expectedStamp { throw ArchiveError("O original mudou durante a gravação. Nenhuma substituição foi feita.") }
        if options.format == "zip", let size = options.volumeMB {
            guard size >= 1 && size <= 1_000_000 else { throw ArchiveError("Tamanho de volume inválido.") }
            let folder = temp.appendingPathComponent("zip-volumes"); try fm.createDirectory(at:folder,withIntermediateDirectories:true)
            let primary = folder.appendingPathComponent(destination.lastPathComponent)
            try run(["-q", "-s", "\(size)m",output.path,"--out",primary.path],executable:URL(fileURLWithPath:"/usr/bin/zip"),control:control)
            try test(primary,password:options.encrypt ? password : nil,control:control)
            if let archive, let expectedStamp, try DiskStamp(archive) != expectedStamp { throw ArchiveError("O original mudou durante a criação dos volumes. Nenhuma substituição foi feita.") }
            try publishVolumes(folder:folder,destination:destination,control:control)
            progress(1,"Volumes ZIP salvos e verificados")
            return saved
        }
        progress(0.95, "Concluindo…")
        if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: output) }
        else { try fm.moveItem(at: output, to: destination) }
        progress(1, "Concluído")
        return saved
    }
    // RAR is intentionally external: its license forbids bundling it with this app.
    static func writeNativeArchive(input: URL, temp: URL, wanted: [ArchiveEntry], destination: URL, options: SaveOptions, password: String?, archive: URL?, expectedStamp: DiskStamp?, control: JobControl, progress: JobProgress) throws -> ArchiveIndex {
        if options.format == "rar", rarTool == nil { throw ArchiveError("Para criar RAR/RAR5, selecione o executável RAR oficial em Ajustes → Avançado. Baixe a versão para macOS em rarlab.com.") }
        guard !wanted.isEmpty else { throw ArchiveError("Adicione pelo menos um item para criar este arquivo compactado.") }
        if let size = options.volumeMB { guard size >= 1 && size <= 1_000_000 else { throw ArchiveError("Use volumes entre 1 e 1.000.000 MB.") } }
        let outputFolder = temp.appendingPathComponent("native-output")
        try fm.createDirectory(at:outputFolder,withIntermediateDirectories:true)
        let output = outputFolder.appendingPathComponent(destination.lastPathComponent)
        var args = options.format == "rar" ? ["a", "-cfg-", "-ma5", "-r", "-idq", "-m\(options.level == 5 ? 3 : min(5,max(0,options.level)))"] : ["a", "-t7z", "-mx\(options.level)", "-spd", "-sse"]
        if let size = options.volumeMB { args.append("-v\(size)m") }
        if options.encrypt { args.append("-p"); if options.format == "7z" { args.append("-mhe=on") } }
        progress(0.53,"Criando arquivo compactado e volumes…")
        try run(args + ["--",output.path,"."],at:input,password:options.encrypt ? password : nil,executable:options.format == "rar" ? rarTool : nil,control:control)
        let primary = savedURL(output,options:options)
        progress(0.78,"Verificando todos os volumes…")
        try test(primary,password:options.encrypt ? password : nil,control:control)
        let saved = try list(primary,password:options.encrypt ? password : nil,control:control)
        guard Set(saved.entries.filter { !$0.directory }.map(\.path)) == Set(wanted.filter { !$0.directory }.map(\.path)) else { throw ArchiveError("Conteúdo diferente do esperado. O original foi preservado.") }
        let parts = try fm.contentsOfDirectory(at:outputFolder,includingPropertiesForKeys:nil)
        let targets = parts.map { destination.deletingLastPathComponent().appendingPathComponent($0.lastPathComponent) }
        if options.volumeMB != nil {
            if options.format == "rar" {
                guard !fm.fileExists(atPath:destination.path) else { throw ArchiveError("Já existe um RAR com esse nome. Escolha outro nome para os volumes.") }
                let base = NSRegularExpression.escapedPattern(for:destination.deletingPathExtension().lastPathComponent)
                let existing = try fm.contentsOfDirectory(at:destination.deletingLastPathComponent(),includingPropertiesForKeys:nil)
                guard !existing.contains(where:{ $0.lastPathComponent.range(of:"^" + base + "\\.part[0-9]+\\.rar$",options:.regularExpression) != nil }) else { throw ArchiveError("Já existe um conjunto RAR com esse nome. Escolha outro nome.") }
            }
            guard targets.allSatisfy({ !fm.fileExists(atPath:$0.path) }) else { throw ArchiveError("Já existem volumes com esse nome. Use Salvar como e escolha outro nome para preservar o conjunto anterior.") }
        }
        try control.check()
        if let archive, let expectedStamp, try DiskStamp(archive) != expectedStamp { throw ArchiveError("O original mudou durante a gravação. Nenhuma substituição foi feita.") }
        var moved: [URL] = []
        do {
            for (part,target) in zip(parts,targets) {
                try control.check()
                if options.volumeMB == nil && fm.fileExists(atPath:target.path) { _ = try fm.replaceItemAt(target,withItemAt:part) }
                else { try fm.moveItem(at:part,to:target); moved.append(target) }
            }
        } catch {
            for target in moved { try? fm.removeItem(at:target) }
            throw error
        }
        progress(1,"Arquivo salvo e verificado")
        return saved
    }
    static func publishVolumes(folder: URL, destination: URL, control: JobControl) throws {
        let parts = try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
        let targets = parts.map { destination.deletingLastPathComponent().appendingPathComponent($0.lastPathComponent) }
        guard targets.allSatisfy({ !fm.fileExists(atPath:$0.path) }) else { throw ArchiveError("Já existem volumes com esse nome. Escolha outro nome para preservar o conjunto anterior.") }
        var moved: [URL] = []
        do {
            for (part,target) in zip(parts,targets) { try control.check(); try fm.moveItem(at:part,to:target); moved.append(target) }
        } catch { for target in moved { try? fm.removeItem(at:target) }; throw error }
    }
    enum Conflict: String, CaseIterable, Codable, Sendable { case ask = "Perguntar", replace = "Substituir", skip = "Ignorar", keepBoth = "Manter ambos" }
    static func unique(_ url: URL) -> URL {
        var n = 2; var result = url
        while fm.fileExists(atPath: result.path) {
            let ext = url.pathExtension; let base = url.deletingPathExtension().lastPathComponent
            result = url.deletingLastPathComponent().appendingPathComponent(base + " (\(n))" + (ext.isEmpty ? "" : "." + ext)); n += 1
        }
        return result
    }
    static func extract(entries: [ArchiveEntry], archive: URL?, password: String?, destination: URL,
                        conflict: Conflict, control: JobControl, progress: JobProgress, resolveConflict: (@Sendable (ArchiveEntry, URL) throws -> Conflict)? = nil) throws {
        try validateEntries(entries)
        let stage = try workspace(); defer { try? fm.removeItem(at: stage) }
        // All contents are prepared first: wrong passwords/cancellation cannot leave half-decoded files at the destination.
        for (i,e) in entries.enumerated() {
            progress(Double(i) / Double(max(entries.count,1)) * 0.8, "Extraindo \(i+1)/\(entries.count): \(e.name)")
            try materialize(e, archive: archive, password: password, to: stage.appendingPathComponent(e.path), control: control, progress:{ value,_ in progress((Double(i) + value)/Double(max(entries.count,1))*0.8,"Extraindo \(i+1)/\(entries.count): \(e.name)") })
        }
        try control.check()
        let paths = Set(entries.map(\.path))
        let roots = entries.filter { e in !paths.contains(where: { e.path.hasPrefix($0 + "/") }) }
        let destinations = roots.map { destination.appendingPathComponent($0.name) }
        if conflict == .ask, resolveConflict == nil, let existing = destinations.first(where: { fm.fileExists(atPath: $0.path) }) { throw ArchiveError("Já existe \(existing.lastPathComponent). Escolha como tratar arquivos existentes nas opções de extração.") }
        // Commit uses a rollback journal, including replacements, so failures preserve destination contents.
        var created: [URL] = []; var backups: [(URL,URL)] = []
        do {
            for (i,e) in roots.enumerated() {
                try control.check()
                let source = stage.appendingPathComponent(e.path); var target = destinations[i]
                if fm.fileExists(atPath: target.path) {
                    let choice = conflict == .ask ? try resolveConflict!(e,target) : conflict
                    try control.check()
                    if choice == .skip { continue }
                    if choice == .keepBoth { target = unique(target) }
                    else {
                        let backup = stage.appendingPathComponent("backup-" + UUID().uuidString)
                        try fm.moveItem(at: target, to: backup); backups.append((backup,target))
                    }
                }
                created.append(target)
                try copy(source,to:target,control:control,progress:{ value,_ in progress(0.8 + (Double(i)+value)/Double(max(roots.count,1))*0.19,"Copiando \(i+1)/\(roots.count): \(e.name)") })
            }
            try control.check()
        } catch {
            for u in created.reversed() { try? fm.removeItem(at: u) }
            for (backup,target) in backups.reversed() { try? fm.moveItem(at: backup, to: target) }
            throw error
        }
        progress(1, "Extração concluída")
    }
    static func split(_ url: URL, destination: URL, megabytes: Int, control: JobControl, progress: JobProgress) throws {
        guard megabytes >= 1 else { throw ArchiveError("Tamanho de volume inválido.") }
        let temp = try workspace(in: destination); defer { try? fm.removeItem(at: temp) }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        let total = try DiskStamp(url).size; var done: Int64 = 0; var number = 1
        while done < total {
            try control.check()
            let part = temp.appendingPathComponent(url.lastPathComponent + String(format: ".%03d", number))
            fm.createFile(atPath: part.path, contents: nil); let out = try FileHandle(forWritingTo: part)
            var remaining = Int64(megabytes) * 1024 * 1024
            do {
                while remaining > 0, let chunk = try input.read(upToCount: Int(min(remaining, 1024*1024))), !chunk.isEmpty {
                    try control.check(); try out.write(contentsOf: chunk); remaining -= Int64(chunk.count); done += Int64(chunk.count)
                    progress(Double(done)/Double(max(total,1)), "Volume \(number)")
                }
                try out.close()
            } catch { try? out.close(); throw error }
            number += 1
        }
        let parts = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
        guard parts.allSatisfy({ !fm.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path) }) else { throw ArchiveError("Já existem volumes com esse nome no destino.") }
        var moved: [URL] = []
        do { for p in parts { let dest = destination.appendingPathComponent(p.lastPathComponent); try fm.moveItem(at: p,to:dest); moved.append(dest) } }
        catch { for p in moved { try? fm.removeItem(at:p) }; throw error }
    }
    static func repairZIP(_ source: URL, destination: URL, control: JobControl) throws -> Int {
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else { throw ArchiveError("A recuperação deve ser salva em outro arquivo.") }
        let temp = try workspace(in:destination.deletingLastPathComponent()); defer { try? fm.removeItem(at:temp) }
        let result = temp.appendingPathComponent("recovered.zip")
        try run(["-FF",source.path,"--out",result.path],password:"y",executable:URL(fileURLWithPath:"/usr/bin/zip"),control:control)
        let index = try list(result,control:control)
        guard !index.entries.isEmpty else { throw ArchiveError("Não foi possível recuperar itens deste ZIP.") }
        try test(result,password:nil,control:control); try control.check()
        if fm.fileExists(atPath:destination.path) { _ = try fm.replaceItemAt(destination,withItemAt:result) } else { try fm.moveItem(at:result,to:destination) }
        return index.entries.filter { !$0.directory }.count
    }
    static func join(_ first: URL, destination: URL, control: JobControl) throws {
        guard first.pathExtension == "001" else { throw ArchiveError("Selecione o primeiro volume (.001).") }
        let base = first.deletingPathExtension()
        let parts = try fm.contentsOfDirectory(at: first.deletingLastPathComponent(), includingPropertiesForKeys:nil).filter { $0.deletingPathExtension().lastPathComponent == base.lastPathComponent && Int($0.pathExtension) != nil }.sorted { (Int($0.pathExtension) ?? 0) < (Int($1.pathExtension) ?? 0) }
        guard !parts.isEmpty, parts.enumerated().allSatisfy({ Int($0.element.pathExtension) == $0.offset + 1 }) else { throw ArchiveError("A sequência de volumes contém partes ausentes.") }
        let temp = try workspace(in: destination.deletingLastPathComponent()); defer { try? fm.removeItem(at:temp) }
        let result = temp.appendingPathComponent("joined"); fm.createFile(atPath:result.path,contents:nil)
        let out = try FileHandle(forWritingTo:result); defer { try? out.close() }
        for p in parts {
            try control.check(); let input = try FileHandle(forReadingFrom:p); defer { try? input.close() }
            while let data = try input.read(upToCount:1024*1024), !data.isEmpty { try control.check(); try out.write(contentsOf:data) }
        }
        try out.synchronize(); try control.check()
        if fm.fileExists(atPath:destination.path) { _ = try fm.replaceItemAt(destination,withItemAt:result) } else { try fm.moveItem(at:result,to:destination) }
    }
}
