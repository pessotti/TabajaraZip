import Foundation
@main struct ZIPCompatibilityTests {
    static func main() throws {
        let fm = FileManager.default, token = JobControl()
        let root = try ArchiveEngine.workspace(); defer { try? fm.removeItem(at:root) }
        let input = root.appendingPathComponent("ação e texto.txt")
        let content = String(repeating:"Texto para testar compatibilidade com unzip.\n",count:100)
        try content.write(to:input,atomically:true,encoding:.utf8)
        let staging = try ArchiveEngine.workspace(in:root)
        let entries = try ArchiveEngine.scan([input],prefix:"",staging:staging,control:token)
        var options = SaveOptions(); options.encrypt = true
        let zip = root.appendingPathComponent("protected.zip")
        _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:zip,options:options,password:"senha-teste-123",originalPassword:nil,expectedStamp:nil,control:token,progress:{_,_ in})
        let listing = try ArchiveEngine.run(["l","-slt","--",zip.path])
        precondition(listing.contains("ZipCrypto") && !listing.contains("AES-256"))
        let index = try ArchiveEngine.list(zip)
        precondition(ArchiveProtection.detect(index.entries) == .zipCrypto)
        // This is a public test password, never a real user password.
        try ArchiveEngine.run(["-t","-P","senha-teste-123",zip.path],executable:URL(fileURLWithPath:"/usr/bin/unzip"),control:token)
        let output = root.appendingPathComponent("decoded.txt")
        try ArchiveEngine.run(["-p","-P","senha-teste-123",zip.path],output:output,executable:URL(fileURLWithPath:"/usr/bin/unzip"),control:token)
        let decoded = try String(contentsOf:output,encoding:.utf8)
        precondition(decoded == content)
        print("PASS: ZIP uses ZipCrypto; macOS unzip tests and extracts encrypted contents correctly")
    }
}
