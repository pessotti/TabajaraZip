import Foundation
@main struct LargeEditTests {
 static func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw ArchiveError("TEST: " + message) } }
 @MainActor static func main() throws {
  setbuf(stdout,nil)
  let fm = FileManager.default, root = URL(fileURLWithPath:ProcessInfo.processInfo.environment["EDIT_TEST_ROOT"]!), token = JobControl()
  let source = root.appendingPathComponent("large.zip"), trace = root.appendingPathComponent("calls"), originalBytes = try Data(contentsOf:source)
  let index = try ArchiveEngine.list(source), folder = "Grande ação"
  let suiteName = "TabajaraLargeEdit-"+UUID().uuidString
  let isolatedDefaults = UserDefaults(suiteName:suiteName)!
  defer { isolatedDefaults.removePersistentDomain(forName:suiteName) }
  let preferences = AppPreferences(defaults:isolatedDefaults)
  let doc = ArchiveDocument(storage:nil,preferences:preferences); doc.entries = index.entries; doc.originalEntries = index.entries
  let start = Date(); doc.removeWithoutConfirmation([folder])
  let changes = doc.pendingChanges.count, removed = doc.removedEntries.count
  try check(removed > 4000 && changes == removed,"folder deletion summary")
  let warm = Date(); var observed = 0
  for _ in 0..<100 { observed += doc.pendingChanges.count + doc.removedEntries.count }
  try check(observed == 200*removed,"cached repeated summaries")
  print("Summary: first removal \(Date().timeIntervalSince(start))s; 100 cached reads \(Date().timeIntervalSince(warm))s")
  doc.undo(); try check(doc.pendingChanges.isEmpty && doc.removedEntries.isEmpty,"undo invalidates summary")
  doc.redo(); try check(doc.removedEntries.count == removed,"redo invalidates summary")
  doc.restoreRemoved(folder); try check(doc.removedEntries.isEmpty,"restore invalidates summary")
  let individual = Set(index.entries.filter { !$0.directory }.prefix(4000).map(\.path))
  doc.removeWithoutConfirmation(individual)
  try check(doc.removedEntries.count == 4000,"large file selection removal")
  doc.undo(); try check(doc.removedEntries.isEmpty,"undo large selection")
  doc.removeWithoutConfirmation([folder])
  var options = SaveOptions()
  func write(_ entries: [ArchiveEntry], _ archive: URL, _ old: [ArchiveEntry], _ dest: URL, _ opts: SaveOptions, _ oldPassword: String? = nil) throws -> ArchiveIndex {
   try ArchiveEngine.write(entries:entries,originalEntries:old,archive:archive,destination:dest,options:opts,password:opts.encrypt ? "secret" : nil,originalPassword:oldPassword,expectedStamp:try DiskStamp(archive),excludeMetadata:false,control:token,progress:{_,_ in})
  }
  try Data().write(to:trace)
  let deleted = root.appendingPathComponent("deleted.zip")
  let kept = try write(doc.entries,source,index.entries,deleted,options)
  let calls = try String(contentsOf:trace,encoding:.utf8).split(separator:"\n")
  try check(!calls.contains("x") && calls.filter { $0 == "d" }.count == 1,"single deletion, no decompression of retained entries")
  try check(kept.entries.filter { !$0.directory }.count == 100,"kept directory intact")
  let remaining = index.entries.filter { $0.directory || !$0.path.hasPrefix(folder+"/") || $0.path.contains("item-03999-") }
  let sparse = root.appendingPathComponent("sparse.zip")
  _ = try write(remaining,source,index.entries,sparse,options)
  print("PASS large folder deletion and oversized UTF-8 deletion list")
  options.encrypt = true
  try Data().write(to:trace)
  let protected = root.appendingPathComponent("protected.zip")
  let protectedIndex = try write(doc.entries,source,index.entries,protected,options)
  let encryptedCalls = try String(contentsOf:trace,encoding:.utf8).split(separator:"\n")
  try check(encryptedCalls.filter { $0 == "x" }.count == 1,"one stream when creating protected ZIP")
  let reduced = protectedIndex.entries.filter { $0.directory || $0.path.contains("keep-0000") }
  try Data().write(to:trace)
  let reducedZIP = root.appendingPathComponent("reduced.zip")
  let reducedIndex = try write(reduced,protected,protectedIndex.entries,reducedZIP,options,"secret")
  let protectedCalls = try String(contentsOf:trace,encoding:.utf8).split(separator:"\n")
  try check(!protectedCalls.contains("x"),"pure ZipCrypto deletion needs no decompression")
  try check(reducedIndex.entries.filter { !$0.directory }.count == 10,"protected ZIP deletion content")
  try ArchiveEngine.test(reducedZIP,password:"secret",control:token)
  try Data().write(to:trace)
  let changedPassword = root.appendingPathComponent("changed-password.zip")
  _ = try ArchiveEngine.write(entries:reduced,originalEntries:protectedIndex.entries,archive:protected,destination:changedPassword,options:options,password:"new-secret",originalPassword:"secret",expectedStamp:try DiskStamp(protected),excludeMetadata:false,control:token,progress:{_,_ in})
  try ArchiveEngine.test(changedPassword,password:"new-secret",control:token)
  let passwordCalls = try String(contentsOf:trace,encoding:.utf8).split(separator:"\n")
  try check(passwordCalls.filter { $0 == "x" }.count == 1,"password change rebuilds with one stream")
  let output = root.appendingPathComponent("verified"); try fm.createDirectory(at:output,withIntermediateDirectories:true)
  try ArchiveEngine.extract(entries:kept.entries,archive:deleted,password:nil,destination:output,conflict:.ask,control:token,progress:{_,_ in})
  for e in kept.entries where !e.directory { try check((try? String(contentsOf:output.appendingPathComponent(e.path),encoding:.utf8)) == "content:"+e.path,"retained file contents") }
  try check((try? Data(contentsOf:source)) == originalBytes,"original archive unchanged")
  let cancelled = JobControl(); cancelled.cancel()
  do { _ = try ArchiveEngine.write(entries:doc.entries,originalEntries:index.entries,archive:source,destination:source,options:SaveOptions(),password:nil,originalPassword:nil,expectedStamp:try DiskStamp(source),control:cancelled,progress:{_,_ in}); throw NSError(domain:"cancel accepted",code:1) } catch is CancellationError { }
  try check((try? Data(contentsOf:source)) == originalBytes,"cancel preserves original")
  let duringSave = JobControl(); var encryptedOptions = SaveOptions(); encryptedOptions.encrypt = true
  do { _ = try ArchiveEngine.write(entries:doc.entries,originalEntries:index.entries,archive:source,destination:source,options:encryptedOptions,password:"secret",originalPassword:nil,expectedStamp:try DiskStamp(source),excludeMetadata:false,control:duringSave,progress:{ value,_ in if value > 0.2 { duringSave.cancel() } }); throw NSError(domain:"mid-save cancel accepted",code:1) } catch is CancellationError { }
  try check(duringSave.cancelled && (try? Data(contentsOf:source)) == originalBytes,"mid-save cancellation preserves original")
  print("PASS summary invalidation, folder deletion, retained files, UTF-8/ARG_MAX, protected ZIP editing, single-stream preparation and cancellation")
 }
}
