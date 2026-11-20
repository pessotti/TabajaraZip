import Foundation
import Dispatch
@main struct DiagnosticsTests {
 static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws { if !condition() { throw ArchiveError(message) } }
 static func main() throws {
  let fm = FileManager.default, root = try ArchiveEngine.workspace(); defer { ArchiveEngine.removeTemporary(root) }
  let directory = root.appendingPathComponent("logs")
  let logger = DiagnosticLog(directory:directory,maximumBytes:2_000_000)
  DispatchQueue.concurrentPerform(iterations:100) { n in logger.write("concurrent",message:"failure \(n) senha-secreta",context:["path":"/tmp/ação.zip"],secrets:["senha-secreta"]) }
  let current = directory.appendingPathComponent("TabajaraZip.jsonl")
  let content = try String(contentsOf:current,encoding:.utf8), lines = content.split(separator:"\n")
  try check(lines.count == 100,"concurrent log lines")
  try check(!content.contains("senha-secreta"),"password redaction")
  for line in lines { let event = try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]; try check(event["timestamp"] != nil && event["appVersion"] != nil,"metadata") }
  let attrs = try fm.attributesOfItem(atPath:current.path); try check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,"private log file")
  let rotating = DiagnosticLog(directory:root.appendingPathComponent("rotate"),maximumBytes:600,backups:2)
  for n in 0..<30 { rotating.write("rotate",message:"event-\(n)") }
  let retained = try fm.contentsOfDirectory(at:rotating.directory,includingPropertiesForKeys:nil).filter { $0.pathExtension == "jsonl" }
  try check(retained.count == 3,"bounded rotation")
  for file in retained { for line in try String(contentsOf:file,encoding:.utf8).split(separator:"\n") { _ = try JSONSerialization.jsonObject(with:Data(line.utf8)) } }
  let denied = root.appendingPathComponent("not-a-directory"); try Data().write(to:denied)
  DiagnosticLog(directory:denied).write("logger-failure",message:"does not interrupt operation")
  let shared = root.appendingPathComponent("engine-logs"); setenv("TABAJARA_LOG_DIRECTORY",shared.path,1)
  let script = root.appendingPathComponent("broken-tool")
  try "#!/bin/sh\nprintf 'PRIVATE_FILE_CONTENT\\n'\nprintf 'senha-secreta: synthetic tool error\\n' >&2\nexit 7\n".write(to:script,atomically:true,encoding:.utf8)
  try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
  do { _ = try ArchiveEngine.run(["test"],password:"senha-secreta",executable:script); throw ArchiveError("accepted failing process") }
  catch { DiagnosticLog.record("outer-layer",error:error,secrets:["senha-secreta"]) }
  let records = try String(contentsOf:shared.appendingPathComponent("TabajaraZip.jsonl"),encoding:.utf8)
  try check(records.contains("synthetic tool error") && records.contains("exitCode"),"persistent engine failure")
  try check(!records.contains("senha-secreta") && !records.contains("PRIVATE_FILE_CONTENT"),"engine privacy")
  let payloadOnly = root.appendingPathComponent("stdout-tool")
  try "#!/bin/sh\nprintf 'FILE_PAYLOAD_ONLY\\n'\nexit 4\n".write(to:payloadOnly,atomically:true,encoding:.utf8); try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:payloadOnly.path)
  do { _ = try ArchiveEngine.run(["extract"],executable:payloadOnly) } catch { DiagnosticLog.record("outer-stdout-layer",error:error) }
  let final = try String(contentsOf:shared.appendingPathComponent("TabajaraZip.jsonl"),encoding:.utf8)
  try check(!final.contains("FILE_PAYLOAD_ONLY"),"outer error cannot leak stdout")
  print("PASS: persistent engine errors, outer errors, private file permissions, concurrent JSON records, rotation, password/content omission and logger failure isolation")
 }
}
