import Foundation
@main struct FinderPermissionsTests {
 static func check(_ b:Bool,_ m:String)throws{if !b{throw ArchiveError(m)}}
 static func main() throws {
 setbuf(stdout,nil)
 let fm=FileManager.default, root=try ArchiveEngine.workspace();defer{ArchiveEngine.removeTemporary(root)}
 let input=root.appendingPathComponent("pasta ação");try fm.createDirectory(at:input,withIntermediateDirectories:true)
 let script=input.appendingPathComponent("script.sh"), icon=input.appendingPathComponent("Icon\r")
 try Data("#!/bin/sh\necho ok\n".utf8).write(to:script);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:script.path)
 try Data("icon bytes".utf8).write(to:icon)
 try Data("appledouble bytes".utf8).write(to:input.appendingPathComponent("._Icon\r"))
 for n in 0..<10{try Data("file \(n)".utf8).write(to:input.appendingPathComponent("file\(n).txt"))}
 let stage=try ArchiveEngine.workspace(in:root), token=JobControl()
 try fm.setAttributes([.posixPermissions:0o555],ofItemAtPath:input.path)
 let entries=try ArchiveEngine.scan([input],prefix:"",staging:stage,control:token)
 for format in ["zip","7z","tar","tgz"] + (ArchiveEngine.rarTool == nil ? [] : ["rar"]) {
 var opts=SaveOptions();opts.format=format
 let archive=root.appendingPathComponent("archive."+format)
 _=try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:archive,options:opts,password:nil,originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
 let space=try ArchiveEngine.workspace(in:root), (index,source)=try ArchiveEngine.resolve(archive,in:space)
 let out=root.appendingPathComponent("out-"+format)
 try ArchiveEngine.extract(entries:index.entries,archive:source,password:nil,destination:out,conflict:.ask,control:token,progress:{_,_ in})
 let path=out.appendingPathComponent("pasta ação/script.sh")
 let mode=(try fm.attributesOfItem(atPath:path.path)[.posixPermissions] as! NSNumber).intValue
 let folderMode=(try fm.attributesOfItem(atPath:out.appendingPathComponent("pasta ação").path)[.posixPermissions] as! NSNumber).intValue
 try check(folderMode==0o555,"Readonly folder mode lost")
 try check(mode==0o755,"Executable permission lost in "+format)
 try check(try Data(contentsOf:out.appendingPathComponent("pasta ação/Icon\r"))==Data("icon bytes".utf8),"Icon data lost in "+format)
 try check(try Data(contentsOf:out.appendingPathComponent("pasta ação/._Icon\r"))==Data("appledouble bytes".utf8),"AppleDouble Icon data lost")
 let member=index.entries.first{$0.name=="Icon\r"}!
 try ArchiveEngine.materialize(member,archive:source,password:nil,to:root.appendingPathComponent("preview-"+format),control:token)
 if format=="zip" || format=="7z" {
 let wanted=index.entries.filter{$0.name != "Icon\r"}
 _=try ArchiveEngine.write(entries:wanted,originalEntries:index.entries,archive:source,destination:root.appendingPathComponent("deleted."+format),options:opts,password:nil,originalPassword:nil,expectedStamp:try DiskStamp(source),excludeMetadata:false,control:token,progress:{_,_ in})
 }
 print("PASS permissions 755, Icon CR data, preview and save: "+format)
 }
 for format in ["zip","7z"] + (ArchiveEngine.rarTool == nil ? [] : ["rar"]) {
 var opts=SaveOptions();opts.format=format;opts.encrypt=true
 let archive=root.appendingPathComponent("encrypted."+format)
 _=try ArchiveEngine.write(entries:entries,originalEntries:[],archive:nil,destination:archive,options:opts,password:"secret",originalPassword:nil,expectedStamp:nil,excludeMetadata:false,control:token,progress:{_,_ in})
 let workspace=try ArchiveEngine.workspace(in:root), (index,source)=try ArchiveEngine.resolve(archive,in:workspace,password:"secret")
 let out=root.appendingPathComponent("encrypted-out-"+format)
 try ArchiveEngine.extract(entries:index.entries,archive:source,password:"secret",destination:out,conflict:.ask,control:token,progress:{_,_ in})
 try check(try Data(contentsOf:out.appendingPathComponent("pasta ação/Icon\r"))==Data("icon bytes".utf8),"encrypted Icon failed")
 print("PASS encrypted Icon: "+format)
 }
 let aes=root.appendingPathComponent("aes.zip")
 try ArchiveEngine.run(["a","-tzip","-mem=AES256","-p","--",aes.path,"."],at:input,password:"secret",control:token)
 let aesIndex=try ArchiveEngine.list(aes,password:"secret")
 let aesOut=root.appendingPathComponent("aes-out")
 try ArchiveEngine.extract(entries:aesIndex.entries,archive:aes,password:"secret",destination:aesOut,conflict:.ask,control:token,progress:{_,_ in})
 try check(try Data(contentsOf:aesOut.appendingPathComponent("Icon\r"))==Data("icon bytes".utf8),"AES ZIP Icon failed")
 print("PASS AES ZIP Icon with authentication verified by engine")
 for path in ["bad\r.txt","Icon\r/../escape","bad\nPath = injected","../Icon\r"] {
 do{_=try ArchiveEngine.validatePath(path);throw NSError(domain:"unsafe accepted",code:1)}catch is ArchiveError{}
 }
 print("PASS other control characters and traversal remain blocked")
 }
}
