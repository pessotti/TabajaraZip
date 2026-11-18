import Foundation
@main struct SaveSummaryTests {
    static func main() throws {
        func file(_ name:String,_ bytes:Int64 = 10) -> ArchiveEntry { ArchiveEntry(path:name,directory:false,size:bytes,original:name) }
        let old = [file("same.txt"),file("edit.txt"),file("old.txt"),file("gone.txt"),file("folder/.DS_Store"),file("replace.txt"),file("filtered.csv")]
        var edit = file("edit.txt"); edit.staged = "/test/edited"
        var renamed = file("old.txt"); renamed.path = "new.txt"
        let added = ArchiveEntry(path:"added.txt",directory:false,size:15,staged:"/test/new")
        let replacement = ArchiveEntry(path:"replace.txt",directory:false,size:20,staged:"/test/replacement")
        let current = [file("same.txt"),edit,renamed,file("folder/.DS_Store"),replacement,added,file("filtered.csv")]
        var options = SaveOptions(); options.exclude = "*.csv"
        let summary = SaveSummary(entries:current,original:old,options:options,excludeMetadata:true)
        precondition(summary.count(.added) == 1)
        precondition(summary.count(.modified) == 2)
        precondition(summary.count(.renamed) == 1)
        precondition(summary.count(.removed) == 1)
        precondition(summary.count(.excluded) == 2)
        precondition(summary.totalFiles == 5 && summary.totalBytes == 65)
        let unchanged = SaveSummary(entries:old,original:old,options:SaveOptions(),excludeMetadata:false)
        precondition(unchanged.changes.isEmpty)
        let raw = ArchiveEntry(path:"raw",directory:false,size:1)
        let zip = ArchiveEntry(path:"zip",directory:false,size:1,encrypted:true,encryptionMethod:"ZipCrypto Deflate")
        let aes = ArchiveEntry(path:"aes",directory:false,size:1,encrypted:true,encryptionMethod:"AES-256 Deflate")
        let seven = ArchiveEntry(path:"7z",directory:false,size:1,encrypted:true,encryptionMethod:"LZMA2:12 7zAES:19")
        let unknown = ArchiveEntry(path:"rar",directory:false,size:1,encrypted:true,encryptionMethod:"m3:17")
        precondition(ArchiveProtection.detect([raw]) == .none)
        precondition(ArchiveProtection.detect([zip]) == .zipCrypto)
        precondition(ArchiveProtection.detect([aes]) == .aes256)
        precondition(ArchiveProtection.detect([seven]) == .aes256)
        precondition(ArchiveProtection.detect([unknown]) == .other)
        precondition(ArchiveProtection.detect([raw,zip]) == .mixed)
        precondition(ArchiveProtection.detect([aes,zip]) == .mixed)
        options.format = "zip"; options.encrypt = true
        precondition(ArchiveProtection.output(options) == .zipCrypto)
        options.format = "7z"
        precondition(ArchiveProtection.output(options) == .aes256)
        print("PASS: accurate save counts, rename/replacement, cleanup/filter exclusions, unchanged save, totals, all protection labels")
    }
}
