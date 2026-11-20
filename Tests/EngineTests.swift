import Foundation

@main struct EngineTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw ArchiveError("TEST FAILED: " + message) } }
    static func rejects(_ label: String,_ body: () throws -> Void) throws {
        do { try body() } catch { print("PASS reject: " + label); return }
        throw ArchiveError("TEST FAILED: accepted " + label)
    }
    static func main() throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, token = JobControl()
        let root = try ArchiveEngine.workspace(); defer { try? fm.removeItem(at:root) }
        let input = root.appendingPathComponent("Pasta ação")
        try fm.createDirectory(at:input.appendingPathComponent("vazia"),withIntermediateDirectories:true)
        try "olá mundo".write(to:input.appendingPathComponent("[teste]*.txt"),atomically:true,encoding:.utf8)
        try "outro".write(to:input.appendingPathComponent("documento.txt"),atomically:true,encoding:.utf8)
        try "ignorar".write(to:input.appendingPathComponent(".DS_Store"),atomically:true,encoding:.utf8)
        let stage = try ArchiveEngine.workspace(in:root)
        let entries = try ArchiveEngine.scan([input],prefix:"",staging:stage,control:token)
        var opts = SaveOptions()
        let zip = root.appendingPathComponent("archive.zip")
        let first = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:zip,options:opts,password:nil,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
        try expect(first.entries.filter { !$0.directory }.count == 3,"ZIP roundtrip count")
        let out = root.appendingPathComponent("out"); try fm.createDirectory(at:out,withIntermediateDirectories:true)
        try ArchiveEngine.extract(entries:first.entries,archive:zip,password:nil,destination:out,conflict:.ask,control:token,progress:{_,_ in})
        let decoded = try String(contentsOf:out.appendingPathComponent("Pasta ação/[teste]*.txt"),encoding:.utf8)
        try expect(decoded == "olá mundo","literal wildcard extraction")
        print("PASS: ZIP, Unicode, wildcard, nested folders, empty folders")
        var modified = first.entries.filter { !$0.path.hasSuffix("documento.txt") }
        modified = modified.map { e in var e = e; if e.path.hasSuffix("[teste]*.txt") { e.path = "Pasta ação/renomeado.txt" }; return e }
        let updated = try ArchiveEngine.write(entries:modified,originalEntries:first.entries,archive:zip,destination:zip,options:opts,password:nil,originalPassword:nil,expectedStamp:try DiskStamp(zip),excludeMetadata:false,control:token,progress:{_,_ in})
        try expect(updated.entries.contains { $0.path == "Pasta ação/renomeado.txt" },"incremental rename")
        try expect(!updated.entries.contains { $0.path.hasSuffix("documento.txt") },"incremental delete")
        print("PASS: incremental rename/delete with literal wildcard")
        let stamp = try DiskStamp(zip), before = try Data(contentsOf:zip)
        try rejects("changed source stamp") { _ = try ArchiveEngine.write(entries:modified,originalEntries:updated.entries,archive:zip,destination:zip,options:opts,password:nil,originalPassword:nil,expectedStamp:DiskStamp(size:stamp.size + 1,date:stamp.date),control:token,progress:{_,_ in}) }
        try expect(tryData(zip) == before,"failed save preserves original")
        let cancelled = JobControl(); cancelled.cancel()
        try rejects("cancel") { _ = try ArchiveEngine.write(entries:modified,originalEntries:updated.entries,archive:zip,destination:zip,options:opts,password:nil,originalPassword:nil,expectedStamp:stamp,excludeMetadata:false,control:cancelled,progress:{_,_ in}) }
        try expect(tryData(zip) == before,"cancel preserves original")
        let empty = root.appendingPathComponent("empty.zip")
        let emptyIndex = try ArchiveEngine.write(entries:[],originalEntries:[],archive:nil,destination:empty,options:opts,password:nil,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
        try expect(emptyIndex.entries.isEmpty,"empty ZIP")
        print("PASS: empty ZIP and atomic preservation")
        for format in ["7z","tar","tgz","tbz2","txz"] {
            opts.format = format
            let dest = root.appendingPathComponent("archive." + format)
            let index = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:dest,options:opts,password:nil,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
            try expect(!index.entries.isEmpty,"format \(format)")
            let resolved = try ArchiveEngine.resolve(dest,in:stage,control:token)
            try expect(resolved.0.entries.filter { !$0.directory }.count == 3,"nested contents \(format)")
            print("PASS format: " + format)
        }
        for format in ["zip","7z"] {
            opts.format = format; opts.encrypt = true
            let secret = format == "zip" ? "segredo seguro" : "segredo ç"
            let encrypted = root.appendingPathComponent("encrypted." + format)
            let index = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:encrypted,options:opts,password:secret,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
            try expect(index.encrypted,"AES \(format)")
            try ArchiveEngine.test(encrypted,password:secret,control:token)
            try rejects("wrong password \(format)") { try ArchiveEngine.test(encrypted,password:"errada",control:token) }
            if let e = index.entries.first(where:{ !$0.directory }) {
                try ArchiveEngine.materialize(e,archive:encrypted,password:secret,to:root.appendingPathComponent("decrypted-" + format),control:token)
            }
            print("PASS encryption: " + format)
        }
        for path in ["../escape","/absolute","a/../b","a\\b","a\nb","C:/test","C:relative","z:/test","a//b"] { try rejects("unsafe " + path.debugDescription) { _ = try ArchiveEngine.validatePath(path) } }
        try rejects("case collision") { try ArchiveEngine.validateEntries([ArchiveEntry(path:"A",directory:false,size:0),ArchiveEntry(path:"a",directory:false,size:0)]) }
        let link = root.appendingPathComponent("link"); try fm.createSymbolicLink(at:link,withDestinationURL:input)
        try rejects("symbolic link") { _ = try ArchiveEngine.scan([link],prefix:"",staging:stage,control:token) }
        let conflictDest = root.appendingPathComponent("conflict"); try fm.createDirectory(at:conflictDest,withIntermediateDirectories:true)
        try ArchiveEngine.extract(entries:updated.entries,archive:zip,password:nil,destination:conflictDest,conflict:.ask,control:token,progress:{_,_ in})
        try rejects("extraction conflict") { try ArchiveEngine.extract(entries:updated.entries,archive:zip,password:nil,destination:conflictDest,conflict:.ask,control:token,progress:{_,_ in}) }
        try ArchiveEngine.extract(entries:updated.entries,archive:zip,password:nil,destination:conflictDest,conflict:.keepBoth,control:token,progress:{_,_ in})
        try expect((try? fm.contentsOfDirectory(atPath:conflictDest.path).count) == 2,"keep both folders")
        print("PASS: conflict policies")
        // Resolve separately per collision and exercise rollback after a replacement has started.
        let policyOut = root.appendingPathComponent("per-item"); try fm.createDirectory(at:policyOut,withIntermediateDirectories:true)
        let stagedA = root.appendingPathComponent("incoming-a"); try "new-a".write(to:stagedA,atomically:true,encoding:.utf8)
        let stagedB = root.appendingPathComponent("incoming-b"); try "new-b".write(to:stagedB,atomically:true,encoding:.utf8)
        let pair = [ArchiveEntry(path:"a.txt",directory:false,size:5,staged:stagedA.path),ArchiveEntry(path:"b.txt",directory:false,size:5,staged:stagedB.path)]
        for name in ["a.txt","b.txt"] { try ("old-" + name).write(to:policyOut.appendingPathComponent(name),atomically:true,encoding:.utf8) }
        try ArchiveEngine.extract(entries:pair,archive:nil,password:nil,destination:policyOut,conflict:.ask,control:JobControl(),progress:{_,_ in},resolveConflict:{ entry,_ in entry.name == "a.txt" ? .skip : .keepBoth })
        try expect(tryData(policyOut.appendingPathComponent("a.txt")) == Data("old-a.txt".utf8),"per-item skip")
        try expect(tryData(policyOut.appendingPathComponent("b (2).txt")) == Data("new-b".utf8),"per-item keep both")
        let cancelCommit = JobControl()
        try rejects("cancel while committing replacement") {
            try ArchiveEngine.extract(entries:pair,archive:nil,password:nil,destination:policyOut,conflict:.replace,control:cancelCommit,progress:{ value,_ in if value > 0.8 { cancelCommit.cancel() } })
        }
        try expect(tryData(policyOut.appendingPathComponent("a.txt")) == Data("old-a.txt".utf8),"cancel restores replaced item")
        try expect(tryData(policyOut.appendingPathComponent("b.txt")) == Data("old-b.txt".utf8),"cancel preserves remaining items")
        let cancelDialog = JobControl()
        try rejects("cancel conflict prompt after earlier replacement") {
            try ArchiveEngine.extract(entries:pair,archive:nil,password:nil,destination:policyOut,conflict:.ask,control:cancelDialog,progress:{_,_ in},resolveConflict:{ entry,_ in if entry.name == "b.txt" { throw CancellationError() }; return .replace })
        }
        try expect(tryData(policyOut.appendingPathComponent("a.txt")) == Data("old-a.txt".utf8),"prompt cancel rolls back previous replacement")
        let cancelScan = JobControl(), cancelStage = try ArchiveEngine.workspace(in:root)
        try rejects("cancel scan cleans staged files") {
            _ = try ArchiveEngine.scan([stagedA],prefix:"",staging:cancelStage,control:cancelScan,progress:{_,_ in cancelScan.cancel() })
        }
        try expect((try? fm.contentsOfDirectory(atPath:cancelStage.path).isEmpty) == true,"cancel removes partial staging files")
        print("PASS: per-item conflicts and cancellation rollback during commit and prompt")
        let big = root.appendingPathComponent("large.bin"); try Data(repeating:0xAB,count:2_500_000).write(to:big)
        let parts = root.appendingPathComponent("parts"); try fm.createDirectory(at:parts,withIntermediateDirectories:true)
        try ArchiveEngine.split(big,destination:parts,megabytes:1,control:token,progress:{_,_ in})
        let joined = root.appendingPathComponent("joined.bin")
        try ArchiveEngine.join(parts.appendingPathComponent("large.bin.001"),destination:joined,control:token)
        try expect(tryData(big) == tryData(joined),"split/join")
        let hash = try ArchiveEngine.sha256(big,control:token)
        try expect(hash.count == 64,"SHA256")
        try fm.removeItem(at:parts.appendingPathComponent("large.bin.002"))
        try rejects("missing volume") { try ArchiveEngine.join(parts.appendingPathComponent("large.bin.001"),destination:root.appendingPathComponent("bad.bin"),control:token) }
        print("PASS: split, join, missing volumes, SHA-256")
        let fixture = URL(fileURLWithPath:"/tmp/tabajara-probe")
        if fm.fileExists(atPath:fixture.appendingPathComponent("traversal.zip").path) {
            for name in ["traversal","newline"] {
                try rejects("archive " + name) { _ = try ArchiveEngine.list(fixture.appendingPathComponent(name + ".zip")) }
            }
            let links = try ArchiveEngine.list(fixture.appendingPathComponent("symlink.zip"))
            try expect(links.entries[0].blockedLink,"link flagged")
            try rejects("symlink extraction") { try ArchiveEngine.materialize(links.entries[0],archive:fixture.appendingPathComponent("symlink.zip"),password:nil,to:root.appendingPathComponent("forbidden"),control:token) }
            if fm.fileExists(atPath:fixture.appendingPathComponent("normal.rar").path) {
                let rar = fixture.appendingPathComponent("normal.rar")
                let rarIndex = try ArchiveEngine.list(rar)
                let safe = rarIndex.entries.first { !$0.directory && !$0.blockedLink }!
                let extracted = root.appendingPathComponent("rar-decoded")
                try ArchiveEngine.materialize(safe,archive:rar,password:nil,to:extracted,control:token)
                try expect(tryData(extracted)?.count == Int(safe.size),"RAR decompression")
                print("PASS: RAR listing and compressed member extraction")
            }
            let recovered = root.appendingPathComponent("repaired.zip")
            let count = try ArchiveEngine.repairZIP(fixture.appendingPathComponent("damaged.zip"),destination:recovered,control:token)
            try expect(count == 1,"ZIP recovery")
            print("PASS: salvage truncated ZIP into separate validated copy")
        }
        print("ALL ENGINE TESTS PASSED")
    }
    static func tryData(_ url:URL) -> Data? { try? Data(contentsOf:url) }
}
extension DiskStamp { init(size:Int64,date:Date) { self.size = size; self.date = date } }
