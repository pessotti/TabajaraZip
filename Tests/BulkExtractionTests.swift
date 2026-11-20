import Foundation
@main struct BulkExtractionTests {
 static func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw ArchiveError("TEST: " + message) } }
 static func main() throws {
  setbuf(stdout,nil)
  let fm = FileManager.default, root = URL(fileURLWithPath:ProcessInfo.processInfo.environment["BULK_TEST_ROOT"]!), token = JobControl()
  let archive = root.appendingPathComponent("many.zip"), trace = root.appendingPathComponent("calls")
  let index = try ArchiveEngine.list(archive)
  try Data().write(to:trace)
  let out = root.appendingPathComponent("all"); try fm.createDirectory(at:out,withIntermediateDirectories:true)
  try ArchiveEngine.extract(entries:index.entries,archive:archive,password:nil,destination:out,conflict:.ask,control:token,progress:{_,_ in})
  let calls = try String(contentsOf:trace,encoding:.utf8).split(separator:"\n")
  try check(calls.filter { $0 == "x" }.count == 1,"one extraction process for many files")
  let originals = index.entries.filter { !$0.directory }
  for entry in originals { try check((try? String(contentsOf:out.appendingPathComponent(entry.path),encoding:.utf8)) == (entry.size == 0 ? "" : "content:" + entry.path),"correct order and data") }
  print("PASS all-file stream and order")
  var selected = Array(originals.prefix(12))
  let first = selected[0]; selected[0].path = "renamed/deep/arquivo.txt"
  var duplicate = first; duplicate.path = "copied/elsewhere/arquivo-copia.txt"; selected.append(duplicate)
  let staged = root.appendingPathComponent("edit.txt"); try Data("edited".utf8).write(to:staged)
  selected[1].staged = staged.path; selected[1].size = 6
  let subset = root.appendingPathComponent("subset"); try fm.createDirectory(at:subset,withIntermediateDirectories:true)
  try ArchiveEngine.extract(entries:selected,archive:archive,password:nil,destination:subset,conflict:.ask,control:token,progress:{_,_ in})
  for entry in selected {
   let value = try String(contentsOf:subset.appendingPathComponent(entry.name),encoding:.utf8)
   try check(value == (entry.staged != nil ? "edited" : "content:" + entry.original!),"partial selection, rename and staged edit")
  }
  print("PASS partial selection and edits")
  var colliding = Array(originals.prefix(12))
  colliding[0].path = "A/same.txt"; colliding[1].path = "B/same.txt"
  let conflictOut = root.appendingPathComponent("conflict"); try fm.createDirectory(at:conflictOut,withIntermediateDirectories:true)
  do { try ArchiveEngine.extract(entries:colliding,archive:archive,password:nil,destination:conflictOut,conflict:.ask,control:token,progress:{_,_ in}); throw NSError(domain:"collision accepted",code:1) } catch is ArchiveError { }
  let conflictNames = try fm.contentsOfDirectory(atPath:conflictOut.path); try check(conflictNames.isEmpty,"colliding output names throw and roll back without crash")
  print("PASS name collision rollback")
  let crcOut = root.appendingPathComponent("crc-out"); try fm.createDirectory(at:crcOut,withIntermediateDirectories:true)
  setenv("BULK_CORRUPT_STREAM","1",1)
  do { try ArchiveEngine.extract(entries:index.entries,archive:archive,password:nil,destination:crcOut,conflict:.ask,control:token,progress:{_,_ in}); throw ArchiveError("corrupt stream accepted") }
  catch let error as ArchiveError { try check(error.message.contains("CRC"),"CRC catches reordered/corrupt stream") }
  unsetenv("BULK_CORRUPT_STREAM")
  let crcNames = try fm.contentsOfDirectory(atPath:crcOut.path); try check(crcNames.isEmpty,"CRC failure leaves destination untouched")
  print("PASS CRC rejection")
  let cancelled = JobControl(), cancelledOut = root.appendingPathComponent("cancelled")
  try fm.createDirectory(at:cancelledOut,withIntermediateDirectories:true)
  let marker = cancelledOut.appendingPathComponent("preserved.txt"); try Data("original".utf8).write(to:marker)
  do { try ArchiveEngine.extract(entries:index.entries,archive:archive,password:nil,destination:cancelledOut,conflict:.replace,control:cancelled,progress:{ value,_ in if value > 0.5 { cancelled.cancel() } }); throw ArchiveError("cancellation accepted") } catch is CancellationError { }
  let cancelledNames = try fm.contentsOfDirectory(atPath:cancelledOut.path)
  try check(cancelledNames == ["preserved.txt"],"cancel preserves destination")
  print("PASS cancellation")
  try ArchiveEngine.materialize(originals[0],archive:archive,password:nil,to:root.appendingPathComponent("probe-original"),control:token)
  var options = SaveOptions(); options.encrypt = true
  let encrypted = root.appendingPathComponent("encrypted.zip")
  _ = try ArchiveEngine.write(entries:Array(originals.prefix(10)),originalEntries:index.entries,archive:archive,destination:encrypted,options:options,password:"secret",originalPassword:nil,expectedStamp:try DiskStamp(archive),control:token,progress:{_,_ in})
  print("PASS encrypted ZIP created")
  let protected = try ArchiveEngine.list(encrypted)
  let encryptedOut = root.appendingPathComponent("encrypted-out"); try fm.createDirectory(at:encryptedOut,withIntermediateDirectories:true)
  try ArchiveEngine.extract(entries:protected.entries,archive:encrypted,password:"secret",destination:encryptedOut,conflict:.ask,control:token,progress:{_,_ in})
  for entry in protected.entries where !entry.directory { try check((try? String(contentsOf:encryptedOut.appendingPathComponent(entry.path),encoding:.utf8)) == "content:" + entry.path,"ZipCrypto bulk roundtrip") }
  let wrongOut = root.appendingPathComponent("wrong-password"); try fm.createDirectory(at:wrongOut,withIntermediateDirectories:true)
  do { try ArchiveEngine.extract(entries:protected.entries,archive:encrypted,password:"wrong",destination:wrongOut,conflict:.ask,control:token,progress:{_,_ in}); throw NSError(domain:"wrong password accepted",code:1) } catch is ArchiveError { }
  let wrongNames = try fm.contentsOfDirectory(atPath:wrongOut.path); try check(wrongNames.isEmpty,"wrong password preserves destination")
  print("PASS: CRC rejects corrupt stream, wrong password, one extraction process, 2000 files, ZIP order, Unicode/wildcards/empty files, partial selection, renames, duplicates, staged edits, cancellation and ZipCrypto")
 }
}
