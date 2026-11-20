import Foundation
import Darwin
@main struct AuditRegressionTests {
 static func check(_ value: @autoclosure () -> Bool,_ message: String) throws { if !value() { throw ArchiveError("TEST: " + message) } }
 static func rejects(_ message: String,_ body: () throws -> Void) throws {
  do { try body() } catch { print("PASS rejected: " + message); return }
  throw ArchiveError("TEST: accepted " + message)
 }
 @MainActor static func main() async throws {
  setbuf(stdout,nil)
  let fm = FileManager.default, root = URL(fileURLWithPath:ProcessInfo.processInfo.environment["AUDIT_TEST_ROOT"]!), token = JobControl()
  for name in ["dots.tar","dots.zip","windows.zip"] {
   let archive = root.appendingPathComponent(name), index = try ArchiveEngine.list(archive)
   try check(index.entries.filter { !$0.directory }.count == 12,"compatible archive count")
   try check(SaveSummary(entries:index.entries,original:index.entries,options:SaveOptions(),excludeMetadata:false).changes.isEmpty,"normalized names do not show false changes")
   let out = root.appendingPathComponent(name+"-out"); try fm.createDirectory(at:out,withIntermediateDirectories:true)
   try ArchiveEngine.extract(entries:index.entries,archive:archive,password:nil,destination:out,conflict:.ask,control:token,progress:{_,_ in})
   for e in index.entries where !e.directory { try check((try? String(contentsOf:out.appendingPathComponent(e.path),encoding:.utf8)) == "content:"+e.path,"exact extracted content: " + name) }
   let copy = root.appendingPathComponent(name+"-saved.zip")
   let saved = try ArchiveEngine.write(entries:index.entries,originalEntries:index.entries,archive:archive,destination:copy,options:SaveOptions(),password:nil,originalPassword:nil,expectedStamp:try DiskStamp(archive),excludeMetadata:false,control:token,progress:{_,_ in})
   try check(Set(saved.entries.filter { !$0.directory }.map(\.path)) == Set(index.entries.filter { !$0.directory }.map(\.path)),"compatible archive can be edited/converted")
   print("PASS read/extract/save: " + name)
  }
  for name in ["traversal.zip","absolute.zip","drive.zip","aliases.zip","traversal.tar"] { try rejects(name) { _ = try ArchiveEngine.list(root.appendingPathComponent(name)) } }
  let fifo = try ArchiveEngine.list(root.appendingPathComponent("fifo.tar"))
  try check(fifo.entries.first!.blockedLink,"TAR FIFO recognized as special")
  let fifoOut = root.appendingPathComponent("fifo-out"); try fm.createDirectory(at:fifoOut,withIntermediateDirectories:true)
  try rejects("FIFO without blocking") { try ArchiveEngine.extract(entries:fifo.entries,archive:root.appendingPathComponent("fifo.tar"),password:nil,destination:fifoOut,conflict:.ask,control:token,progress:{_,_ in}) }
  let source = root.appendingPathComponent("payload"), outside = root.appendingPathComponent("outside-created"), destination = root.appendingPathComponent("links")
  try Data("incoming".utf8).write(to:source); try fm.createDirectory(at:destination,withIntermediateDirectories:true)
  let link = destination.appendingPathComponent("item.txt"); try fm.createSymbolicLink(at:link,withDestinationURL:outside)
  let linkDetails = try ConflictDetails.disk(link,control:token)
  try check(linkDetails.name == "item.txt","broken-link metadata available to conflict dialog")
  let item = ArchiveEntry(path:"item.txt",directory:false,size:8,staged:source.path)
  try rejects("dangling link conflict") { try ArchiveEngine.extract(entries:[item],archive:nil,password:nil,destination:destination,conflict:.ask,control:token,progress:{_,_ in}) }
  try check(!fm.fileExists(atPath:outside.path),"dangling link cannot write outside destination")
  try rejects("copy refuses existing symlink") { try ArchiveEngine.copy(source,to:link,control:token) }
  try ArchiveEngine.extract(entries:[item],archive:nil,password:nil,destination:destination,conflict:.keepBoth,control:token,progress:{_,_ in})
  try check(!fm.fileExists(atPath:outside.path) && ArchiveEngine.itemExists(link),"keep-both preserves dangling symlink")
  try ArchiveEngine.extract(entries:[item],archive:nil,password:nil,destination:destination,conflict:.replace,control:token,progress:{_,_ in})
  try check((try? String(contentsOf:link,encoding:.utf8)) == "incoming" && !fm.fileExists(atPath:outside.path),"replace changes link itself, not its target")
  let publication = root.appendingPathComponent("publication");try Data("existing".utf8).write(to:publication)
  try rejects("atomic publication cannot overwrite") { try ArchiveEngine.publishNewItem(source,to:publication) }
  try check((try? String(contentsOf:publication,encoding:.utf8)) == "existing" && fm.fileExists(atPath:source.path),"publication failure preserves both files")
  let incomingA = root.appendingPathComponent("a"), incomingB = root.appendingPathComponent("b")
  try Data("first".utf8).write(to:incomingA);try Data("second".utf8).write(to:incomingB)
  let pair = [ArchiveEntry(path:"A/same.txt",directory:false,size:5,staged:incomingA.path),ArchiveEntry(path:"B/same.txt",directory:false,size:6,staged:incomingB.path)]
  let rollbackOut = root.appendingPathComponent("rollback"); try fm.createDirectory(at:rollbackOut,withIntermediateDirectories:true)
  let original = rollbackOut.appendingPathComponent("same.txt"); try Data("original".utf8).write(to:original)
  let cancel = JobControl()
  do { try ArchiveEngine.extract(entries:pair,archive:nil,password:nil,destination:rollbackOut,conflict:.replace,control:cancel,progress:{ p,_ in if p > 0.9 { cancel.cancel() } }); throw NSError(domain:"cancel accepted",code:1) } catch is CancellationError { }
  try check((try? String(contentsOf:original,encoding:.utf8)) == "original","repeated output-name cancellation restores real original")
  let alias = rollbackOut.appendingPathComponent("alias.txt");try fm.createSymbolicLink(at:alias,withDestinationURL:original)
  let aliasPair = [pair[0],ArchiveEntry(path:"B/alias.txt",directory:false,size:6,staged:incomingB.path)], aliasCancel = JobControl()
  do { try ArchiveEngine.extract(entries:aliasPair,archive:nil,password:nil,destination:rollbackOut,conflict:.replace,control:aliasCancel,progress:{ p,_ in if p > 0.9 { aliasCancel.cancel() } });throw NSError(domain:"alias cancellation accepted",code:1) } catch is CancellationError { }
  let aliasType = try fm.attributesOfItem(atPath:alias.path)[.type] as? FileAttributeType
  try check(aliasType == .typeSymbolicLink && (try? String(contentsOf:original,encoding:.utf8)) == "original","rollback preserves preexisting link and its target")
  print("PASS dangling links, exclusive copy, conflict modes and repeated-name rollback")
  if geteuid() != 0 {
   let locked = root.appendingPathComponent("locked"); try fm.createDirectory(at:locked,withIntermediateDirectories:true)
   let target = locked.appendingPathComponent("same.txt");try Data("original backup".utf8).write(to:target)
   let stop = JobControl()
   do {
    try ArchiveEngine.extract(entries:pair,archive:nil,password:nil,destination:locked,conflict:.replace,control:stop,progress:{ p,_ in if p > 0.81 { try? FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:locked.path);stop.cancel() } })
    throw NSError(domain:"rollback failure not exposed",code:1)
   } catch let error as ArchiveError { try check(error.message.contains("preservadas"),"recovery directory exposed to user") }
   try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:locked.path)
   let journals = try fm.contentsOfDirectory(at:locked,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix(".TabajaraZip-backups-") }
   try check(journals.count == 1,"failed rollback journal retained")
   let backups = try fm.contentsOfDirectory(at:journals[0],includingPropertiesForKeys:nil)
   try check(backups.count == 1 && (try? String(contentsOf:backups[0],encoding:.utf8)) == "original backup","failed rollback cannot delete original backup")
   print("PASS failed rollback keeps recovery data")
  }
  let doc = ArchiveDocument(storage:root.appendingPathComponent("support"))
  doc.open(root.appendingPathComponent("invalid.zip"))
  for _ in 0..<400 { if !doc.busy { break }; try await Task.sleep(nanoseconds:50_000_000) }
  try check(!doc.busy && doc.error != nil && doc.session == nil,"failed open leaves no active session")
  let workspaces = doc.workingDirectory.appendingPathComponent("Workspaces")
  let abandoned = (try? fm.contentsOfDirectory(atPath:workspaces.path)) ?? []
  try check(abandoned.isEmpty,"failed open cleans orphan workspace")
  print("PASS failed-open cleanup")
 }
}
