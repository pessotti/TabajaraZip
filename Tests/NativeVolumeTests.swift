import Foundation
import Security
@main struct NativeVolumeTests {
 static func main() throws {
  let root = try ArchiveEngine.workspace(); defer { try? FileManager.default.removeItem(at:root) }
  let input = root.appendingPathComponent("ação"); try FileManager.default.createDirectory(at:input.appendingPathComponent("vazia"),withIntermediateDirectories:true)
  var data = Data(count: 11_100_000); _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault,$0.count,$0.baseAddress!) }; try data.write(to:input.appendingPathComponent("[arquivo]*.bin"))
  let stage = try ArchiveEngine.workspace(in:root), token = JobControl()
  let entries = try ArchiveEngine.scan([input],prefix:"",staging:stage,control:token)
  var options = SaveOptions(); options.format = "rar"; options.encrypt = true; options.volumeMB = 1
  let dest = root.appendingPathComponent("volume.rar")
  let index = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:dest,options:options,password:"abc123",originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
  let first = ArchiveEngine.savedURL(dest,options:options)
  let files = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension == "rar" }; guard files.count == 11 else { throw ArchiveError("volume count: \(files)") }
  let out = root.appendingPathComponent("out"); try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  try ArchiveEngine.extract(entries:index.entries,archive:first,password:"abc123",destination:out,conflict:.ask,control:token,progress:{_,_ in})
  guard try Data(contentsOf:out.appendingPathComponent("ação/[arquivo]*.bin")) == data else { throw ArchiveError("bytes") }
  do { _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:dest,options:options,password:"abc123",originalPassword:nil,expectedStamp:nil,control:token,progress:{_,_ in}); throw NSError(domain:"test",code:1) } catch is ArchiveError { }
  try ArchiveEngine.test(first,password:"abc123",control:token)
  let absent = files.first { $0.lastPathComponent.contains("part02") }!
  let absentCopy = root.appendingPathComponent("missing-rar-part")
  try FileManager.default.moveItem(at:absent,to:absentCopy)
  do { try ArchiveEngine.test(first,password:"abc123",control:token); throw NSError(domain:"missing RAR accepted",code:1) } catch is ArchiveError { }
  try FileManager.default.moveItem(at:absentCopy,to:absent)
  try ArchiveEngine.test(first,password:"abc123",control:token)
  options.volumeMB = nil
  let single = root.appendingPathComponent("single.rar")
  _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:single,options:options,password:"abc123",originalPassword:nil,expectedStamp:nil,control:token,progress:{_,_ in})
  guard try Data(contentsOf:single).prefix(8) == Data([0x52,0x61,0x72,0x21,0x1a,0x07,0x01,0x00]) else { throw ArchiveError("RAR5 signature") }
  let old = try JSONDecoder().decode(SaveOptions.self,from:Data(#"{"format":"zip","level":5,"encrypt":false,"include":"","exclude":""}"#.utf8)); guard old.volumeMB == nil else { throw ArchiveError("preset migration") }
  for format in ["zip","7z"] {
   options.format = format; options.volumeMB = 1
   let destination = root.appendingPathComponent("native." + format)
   let saved = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:destination,options:options,password:"abc123",originalPassword:nil,expectedStamp:nil,control:token,progress:{_,_ in})
   let primary = ArchiveEngine.savedURL(destination,options:options)
   let extracted = root.appendingPathComponent("extract-" + format); try FileManager.default.createDirectory(at:extracted,withIntermediateDirectories:true)
   try ArchiveEngine.extract(entries:saved.entries,archive:primary,password:"abc123",destination:extracted,conflict:.ask,control:token,progress:{_,_ in})
   guard try Data(contentsOf:extracted.appendingPathComponent("ação/[arquivo]*.bin")) == data else { throw ArchiveError("native roundtrip " + format) }
   let missing = format == "zip" ? destination.deletingPathExtension().appendingPathExtension("z02") : destination.appendingPathExtension("002")
   let hidden = root.appendingPathComponent("missing-part"); try FileManager.default.moveItem(at:missing,to:hidden)
   do { try ArchiveEngine.test(primary,password:"abc123",control:token); throw NSError(domain:"missing volume accepted",code:1) } catch is ArchiveError { }
   try FileManager.default.moveItem(at:hidden,to:missing)
   print("PASS native " + format + ": encrypted byte-for-byte roundtrip, missing-volume rejection")
  }
  options.format = "7z"; options.encrypt = false; options.volumeMB = nil
  let plain = root.appendingPathComponent("plain.7z")
  let plainIndex = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:plain,options:options,password:nil,originalPassword:nil,expectedStamp:nil,control:token,progress:{_,_ in})
  options.volumeMB = 1
  let converted = root.appendingPathComponent("converted.7z")
  let convertedIndex = try ArchiveEngine.write(entries:plainIndex.entries,originalEntries:plainIndex.entries,archive:plain,destination:converted,options:options,password:nil,originalPassword:nil,expectedStamp:try DiskStamp(plain),control:token,progress:{_,_ in})
  guard Set(convertedIndex.entries.map(\.path)) == Set(plainIndex.entries.map(\.path)) else { throw ArchiveError("unchanged entries lost converting to native volumes") }
  print("PASS conversion from existing unencrypted 7z preserves unchanged entries")
  let tinyFile = root.appendingPathComponent("tiny.txt"); try Data("tiny".utf8).write(to:tinyFile)
  let tinyEntries = try ArchiveEngine.scan([tinyFile],prefix:"",staging:stage,control:token)
  for format in ["rar","zip","7z"] {
   options.format = format; options.encrypt = false; options.volumeMB = 1
   let tiny = root.appendingPathComponent("tiny." + format)
   _ = try ArchiveEngine.write(entries:tinyEntries,originalEntries:[],archive:nil,destination:tiny,options:options,password:nil,originalPassword:nil,expectedStamp:nil,control:token,progress:{_,_ in})
   try ArchiveEngine.test(ArchiveEngine.savedURL(tiny,options:options),password:nil,control:token)
  }
  print("PASS native volume option when contents fit in one part")
  let cancelled = JobControl(); cancelled.cancel()
  let cancelledDest = root.appendingPathComponent("cancelled.7z")
  do { _ = try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:cancelledDest,options:options,password:"abc123",originalPassword:nil,expectedStamp:nil,control:cancelled,progress:{_,_ in}); throw NSError(domain:"cancel accepted",code:1) } catch is CancellationError { }
  guard !FileManager.default.fileExists(atPath:cancelledDest.appendingPathExtension("001").path) else { throw ArchiveError("cancel left output") }
  print("PASS RAR5, AES password stdin, native multipart, Unicode, literal wildcards, collision preservation, old presets")
 }
}
