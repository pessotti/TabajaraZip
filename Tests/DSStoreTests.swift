import Foundation
@main struct DSStoreTests {
    static func main() throws {
        let fm = FileManager.default, token = JobControl()
        let root = try ArchiveEngine.workspace(); defer { try? fm.removeItem(at:root) }
        let input = root.appendingPathComponent("input")
        try fm.createDirectory(at:input.appendingPathComponent("a/b"),withIntermediateDirectories:true)
        try fm.createDirectory(at:input.appendingPathComponent("__MACOSX"),withIntermediateDirectories:true)
        try fm.createDirectory(at:input.appendingPathComponent("a/_MACOSX"),withIntermediateDirectories:true)
        for name in [".DS_Store","a/.DS_Store","a/b/.DS_Store","__MACOSX/file","a/_MACOSX/file","a/b/manter.txt","a/b/.DS_Store.backup","a/b/._manter.txt"] {
            try "dados".write(to:input.appendingPathComponent(name),atomically:true,encoding:.utf8)
        }
        let stage = try ArchiveEngine.workspace(in:root)
        let files = try ArchiveEngine.scan([input],prefix:"",staging:stage,control:token)
        let options = SaveOptions(), archive = root.appendingPathComponent("test.zip")
        let preserved = try ArchiveEngine.write(entries:files,originalEntries:[],archive:nil,destination:archive,options:options,password:nil,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
        precondition(preserved.entries.filter { $0.name == ".DS_Store" }.count == 3)
        precondition(preserved.entries.contains { $0.path.contains("__MACOSX/") })
        let cleaned = try ArchiveEngine.write(entries:preserved.entries,originalEntries:preserved.entries,archive:archive,destination:archive,options:options,password:nil,originalPassword:nil,expectedStamp:try DiskStamp(archive),excludeMetadata:true,control:token,progress:{_,_ in})
        precondition(!cleaned.entries.contains { $0.name == ".DS_Store" || $0.path.contains("_MACOSX") })
        precondition(cleaned.entries.contains { $0.name == "manter.txt" })
        precondition(cleaned.entries.contains { $0.name == ".DS_Store.backup" })
        let ordinaryDotFile = ArchiveEntry(path:"a/._manter.txt",directory:false,size:5)
        precondition(ArchiveEngine.filtered([ordinaryDotFile],options:options,excludeMetadata:true).count == 1)
        precondition(fm.fileExists(atPath:input.appendingPathComponent("a/b/.DS_Store").path))
        let old = Data("{\"format\":\"zip\",\"level\":5,\"encrypt\":false,\"include\":\"\",\"exclude\":\"\",\"excludeMacMetadata\":false,\"removeDSStore\":false}".utf8)
        let legacy = try JSONDecoder().decode(SaveOptions.self,from:old)
        let encoded = try JSONEncoder().encode(legacy)
        let object = try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
        precondition(object["removeDSStore"] == nil && object["excludeMacMetadata"] == nil)
        let cleanFromLegacy = ArchiveEngine.filtered(files,options:legacy,excludeMetadata:true)
        precondition(!cleanFromLegacy.contains { $0.name == ".DS_Store" })
        print("PASS: global cleanup on/off; recursive .DS_Store and both MACOSX spellings; ._ files retained; source files preserved; old presets cannot override app preference")
    }
}
