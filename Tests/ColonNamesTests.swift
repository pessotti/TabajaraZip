import Foundation
@main struct ColonNamesTests {
 static func check(_ value: @autoclosure () -> Bool,_ message: String) throws { if !value() { throw ArchiveError("TEST: "+message) } }
 static func main() throws {
  let fm = FileManager.default, token = JobControl(), root = try ArchiveEngine.workspace(); defer { ArchiveEngine.removeTemporary(root) }
  let input = root.appendingPathComponent("sample_project"), upload = input.appendingPathComponent("upload")
  try fm.createDirectory(at:upload.appendingPathComponent("logs:ipv6"),withIntermediateDirectories:true)
  var values:[String:String] = ["sample_project/upload/php_errors_::1.log":"dummy log", "sample_project/upload/logs:ipv6/request:2026.txt":"request"]
  for n in 0..<12 { values["sample_project/upload/php_errors_::\(n+2).log"] = "log \(n)" }
  for (path,value) in values { try Data(value.utf8).write(to:root.appendingPathComponent(path)) }
  let stage = try ArchiveEngine.workspace(in:root)
  let entries = try ArchiveEngine.scan([input],prefix:"",staging:stage,control:token)
  let archive = root.appendingPathComponent("logs.zip")
  let index = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:archive,options:SaveOptions(),password:nil,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
  try check(index.entries.filter { !$0.directory }.count == values.count,"colon names retained in ZIP")
  let out = root.appendingPathComponent("extracted"); try fm.createDirectory(at:out,withIntermediateDirectories:true)
  try ArchiveEngine.extract(entries:index.entries,archive:archive,password:nil,destination:out,conflict:.ask,control:token,progress:{_,_ in})
  for (path,value) in values { try check((try? String(contentsOf:out.appendingPathComponent(path),encoding:.utf8)) == value,"colon name and content roundtrip") }
  let member = index.entries.first { $0.path.hasSuffix("php_errors_::1.log") }!
  try ArchiveEngine.materialize(member,archive:archive,password:nil,to:root.appendingPathComponent("single.log"),control:token)
  try check((try? String(contentsOf:root.appendingPathComponent("single.log"),encoding:.utf8)) == "dummy log","single member preview")
  let wanted = index.entries.filter { !$0.path.contains("php_errors_::") }
  let saved = try ArchiveEngine.write(entries:wanted,originalEntries:index.entries,archive:archive,destination:archive,options:SaveOptions(),password:nil,originalPassword:nil,expectedStamp:try DiskStamp(archive),excludeMetadata:false,control:token,progress:{_,_ in})
  try check(saved.entries.filter { !$0.directory }.count == 1,"delete colon names from existing ZIP")
  for unsafe in ["../outside","folder/../outside","/absolute","C:/outside","C:relative","a\\b","a//b","a\nb"] {
   do { _ = try ArchiveEngine.validatePath(unsafe); throw NSError(domain:"unsafe path accepted",code:1) } catch is ArchiveError { }
  }
  print("PASS: IPv6 log names, colons in file/directory names, compression, bulk/single extraction, deletion, traversal and drive-prefix protection")
 }
}
