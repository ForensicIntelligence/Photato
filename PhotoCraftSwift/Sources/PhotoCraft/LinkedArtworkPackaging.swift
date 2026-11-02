import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct LinkedPackageOptions:Sendable {
  var name:String
  var format:DocumentIO.Format = .native
  var replaceExisting=false
  func validate()throws {
    guard !name.isEmpty,name.utf8.count<=150,!name.hasPrefix("."),!name.contains("/"),!name.contains("\\"),!name.contains(":"),
      !name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),[.native,.psd,.psb].contains(format) else{throw CraftError.invalid("Choose a package folder name without path components and Photato, PSD or PSB format.")}
  }
  static func safeName(_ value:String)->String {
    var name=String(value.map{c in c.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) || "/\\:".contains(c) ? Character("_"):c}).trimmingCharacters(in:.whitespacesAndNewlines)
    while name.hasPrefix("."){name.removeFirst()};while name.utf8.count>140{name.removeLast()}
    return name.isEmpty ? "Artwork":name
  }
}

/// Owned directory descriptors keep every staged write within this transaction's directories.
/// One worker prepares it, then one caller publishes/discards it; access is sequential.
final class LinkedPackageDirectory:@unchecked Sendable {
  let parentURL:URL
  let name:String
  let stagingName=".photato-package-"+UUID().uuidString
  private var parentFD:Int32 = -1
  private var stagingFD:Int32 = -1
  private var linksFD:Int32 = -1
  private var files:[(Int32,String,dev_t,ino_t)]=[]
  private var published=false
  private var committed=false
  private var preserveStaging=false
  private var merge:LinkedPackageMerge?
  private let requestedDocumentName:String
  private let operations:LinkedPackageOperations
  private var assetNames=Set<String>()
  var documentName:String{merge?.documentName ?? requestedDocumentName}
  var manifestName:String{merge?.manifestName ?? "package.json"}
  var updatedExisting:Bool{merge != nil}
  private static func failure()->NSError{NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
  init(parent:URL,name:String,documentName:String="Document.photato",replaceExisting:Bool=false,operations:LinkedPackageOperations = .native)throws {
    try LinkedPackageOptions(name:name).validate()
    let physical=parent.withUnsafeFileSystemRepresentation{p -> UnsafeMutablePointer<CChar>? in guard let p else{return nil};return realpath(p,nil)}
    guard let physical else{throw Self.failure()};defer{free(physical)}
    parentURL=URL(fileURLWithFileSystemRepresentation:physical,isDirectory:true,relativeTo:nil);self.name=name;requestedDocumentName=documentName;self.operations=operations
    do {
      parentFD=Darwin.open("/",O_SEARCH|O_CLOEXEC);guard parentFD>=0 else{throw Self.failure()}
      for component in parentURL.pathComponents.filter({$0 != "/"}) {
        let next=component.withCString{openat(parentFD,$0,O_SEARCH|O_NOFOLLOW|O_CLOEXEC)}
        guard next>=0 else{throw Self.failure()};close(parentFD);parentFD=next
      }
      guard mkdirat(parentFD,stagingName,0o700)==0 else{throw Self.failure()}
      stagingFD=openat(parentFD,stagingName,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard stagingFD>=0 else{throw Self.failure()}
      guard mkdirat(stagingFD,"Links",0o700)==0 else{throw Self.failure()}
      linksFD=openat(stagingFD,"Links",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard linksFD>=0 else{throw Self.failure()}
      if replaceExisting,try LinkedPackageNode.at(parentFD,name) != nil {merge=try LinkedPackageMerge(parent:parentFD,name:name,documentName:documentName)}
    }catch{discard();throw error}
  }
  private func write(_ name:String,links:Bool,count:Int,next:()throws->Data?)throws {
    guard !name.isEmpty,!name.contains("/"),!name.hasPrefix("."),count>=0 else{throw CraftError.invalid("Invalid package file.")}
    let directory=links ? linksFD:stagingFD
    let fd=openat(directory,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600);guard fd>=0 else{throw Self.failure()};defer{close(fd)}
    var info=stat();guard fstat(fd,&info)==0 else{throw Self.failure()};files.append((directory,name,info.st_dev,info.st_ino))
    var offset=0
    while let chunk=try next(),!chunk.isEmpty {
      guard chunk.count<=count-offset else{throw CraftError.invalid("Package output changed while writing.")}
      try chunk.withUnsafeBytes {raw in
        var index=0
        while index<raw.count {
          try Task.checkCancellation()
          let written=pwrite(fd,raw.baseAddress!.advanced(by:index),min(65536,raw.count-index),off_t(offset+index))
          if written<0,errno==EINTR{continue};guard written>0 else{throw Self.failure()};index+=written
        }
      };offset+=chunk.count
    }
    guard offset==count else{throw CraftError.invalid("Package output was truncated.")};guard fsync(fd)==0 else{throw Self.failure()}
  }
  func write(_ data:Data,name:String,links:Bool=false)throws {
    var offset=0
    try write(name,links:links,count:data.count){guard offset<data.count else{return nil};let end=min(data.count,offset+65536);defer{offset=end};return data.subdata(in:offset..<end)}
  }
  func write(_ output:PreparedDocumentOutput,name:String)throws {
    switch output {
    case .data(let bytes):try write(bytes,name:name)
    case .file(let file):
      let input=try FileHandle(forReadingFrom:file.url);defer{try? input.close()}
      try write(name,links:false,count:file.count){try Task.checkCancellation();return try input.read(upToCount:65536)}
    }
  }
  func selectAsset(_ base:String,fingerprint:String,count:Int)throws->(name:String,reused:Bool) {
    if let merge{return try merge.selectAsset(base,fingerprint:fingerprint,count:count)}
    var candidate=base,index=2
    while !assetNames.insert(LinkedPackageMerge.folded(candidate)).inserted {
      let ext=(base as NSString).pathExtension,stem=(base as NSString).deletingPathExtension
      candidate=stem+"-\(index)"+(ext.isEmpty ? "":"."+ext);index+=1
    }
    return(candidate,false)
  }
  func commit()throws {
    guard !committed else{throw CraftError.invalid("This package has already been published.")}
    try Task.checkCancellation();var parent=stat(),current=stat(),stage=stat(),named=stat()
    guard fstat(parentFD,&parent)==0,lstat(parentURL.path,&current)==0,parent.st_dev==current.st_dev,parent.st_ino==current.st_ino,
      fstat(stagingFD,&stage)==0,fstatat(parentFD,stagingName,&named,AT_SYMLINK_NOFOLLOW)==0,stage.st_dev==named.st_dev,stage.st_ino==named.st_ino else{throw DocumentPersistenceConflict.changed}
    guard fsync(linksFD)==0,fsync(stagingFD)==0 else{throw Self.failure()}
    if let merge {
      do {
        let assets=files.filter{$0.0==linksFD}.map{$0.1}
        let backups=try merge.commit(staging:stagingFD,links:linksFD,assets:assets,operations:operations)
        for(name,device,inode)in backups {
          files.removeAll{$0.0==stagingFD && $0.1==name};files.append((stagingFD,name,device,inode))
        }
        committed=true;discard()
      }catch is LinkedPackageRecoveryRequired{preserveStaging=true;throw LinkedPackageRecoveryRequired(stagingName:stagingName)}
    }else{
      guard operations.move(parentFD,stagingName,parentFD,name,UInt32(RENAME_EXCL))==0 else{throw Self.failure()};published=true;committed=true
    }
  }
  func discard() {
    if !published && !preserveStaging {
      for (directory,name,device,inode)in files {
        var info=stat();if fstatat(directory,name,&info,AT_SYMLINK_NOFOLLOW)==0,info.st_dev==device,info.st_ino==inode{_ = unlinkat(directory,name,0)}
      }
      if stagingFD>=0,linksFD>=0 {
        var a=stat(),b=stat();if fstat(linksFD,&a)==0,fstatat(stagingFD,"Links",&b,AT_SYMLINK_NOFOLLOW)==0,a.st_dev==b.st_dev,a.st_ino==b.st_ino{_ = unlinkat(stagingFD,"Links",AT_REMOVEDIR)}
      }
      if parentFD>=0,stagingFD>=0 {
        var a=stat(),b=stat();if fstat(stagingFD,&a)==0,fstatat(parentFD,stagingName,&b,AT_SYMLINK_NOFOLLOW)==0,a.st_dev==b.st_dev,a.st_ino==b.st_ino{_ = unlinkat(parentFD,stagingName,AT_REMOVEDIR)}
      }
    }
    for fd in [linksFD,stagingFD,parentFD] where fd>=0{close(fd)};linksFD = -1;stagingFD = -1;parentFD = -1;files=[]
  }
  deinit{discard()}
}

struct LinkedPackageSource:Sendable {
  let sourceID:UUID
  let name:String
  let grant:LinkedArtworkGrant
  let fingerprint:String
  let signature:String
  let byteLength:Int
}
final class PreparedLinkedPackage:Sendable {
  let directory:LinkedPackageDirectory
  let document:CraftDocument
  let documentName:String
  let sources:[LinkedPackageSource]
  var folderURL:URL{directory.parentURL.appendingPathComponent(directory.name,isDirectory:true)}
  var documentURL:URL{folderURL.appendingPathComponent(documentName)}
  init(directory:LinkedPackageDirectory,document:CraftDocument,documentName:String,sources:[LinkedPackageSource]){
    self.directory=directory;self.document=document;self.documentName=documentName;self.sources=sources
  }
  func validateSources()throws {
    for source in sources {guard try LinkedArtworkRead.signature(source.grant)==source.signature else{throw DocumentPersistenceConflict.changed}}
  }
  static func prepare(_ original:CraftDocument,grants:[UUID:LinkedArtworkGrant],parent:URL,options:LinkedPackageOptions,operations:LinkedPackageOperations = .native)throws->PreparedLinkedPackage {
    try options.validate();try original.validate()
    let access=parent.startAccessingSecurityScopedResource();defer{if access{parent.stopAccessingSecurityScopedResource()}}
    let plannedName=LinkedPackageOptions.safeName((original.name as NSString).deletingPathExtension)+"."+options.format.rawValue
    let directory=try LinkedPackageDirectory(parent:parent,name:options.name,documentName:plannedName,replaceExisting:options.replaceExisting,operations:operations)
    var completed=false;defer{if !completed{directory.discard()}}
    var result=original,sources:[LinkedPackageSource]=[],seen=Set<UUID>(),copied:[String:String]=[:]
    for layer in original.layers {
      guard let object=layer.smartObject,let link=object.linkedSource,seen.insert(object.sourceID).inserted else{continue}
      try Task.checkCancellation()
      guard let grant=grants[object.sourceID]else{throw CraftError.invalid("Locate every linked source before packaging.")}
      let file=try LinkedArtworkRead.read(grant)
      guard link.contentHash==file.fingerprint,try layer.linkedSmartObjectPreview()==nil else{throw CraftError.invalid("Update the linked artwork before packaging its original source.")}
      let key=grant.url.path+":"+file.fingerprint
      let name:String
      if let previous=copied[key]{name=previous}else{
        let choice=try directory.selectAsset(LinkedPackageOptions.safeName(file.fileName),fingerprint:file.fingerprint,count:file.data.count)
        name=choice.name;copied[key]=name;if !choice.reused{try directory.write(file.data,name:name,links:true)}
      }
      let reference=try LinkedSmartObjectSource(reference:"Links/"+name,contentHash:file.fingerprint,byteLength:UInt64(file.data.count),modificationDate:file.modified)
      for i in result.layers.indices where result.layers[i].smartObject?.sourceID==object.sourceID {
        var source=result.layers[i].smartObject!;source.data=options.format == .native ? Data():file.data;source.linkedSource=reference;source.fileName=name;try source.validate();result.layers[i].smartObject=source
        for tag in ["SoLd","SoLE","PlLd"]{result.layers[i].sourceTags?.removeValue(forKey:tag)}
      }
      sources.append(.init(sourceID:object.sourceID,name:name,grant:file.grant,fingerprint:file.fingerprint,signature:file.signature,byteLength:file.data.count))
    }
    guard !sources.isEmpty else{throw CraftError.invalid("This document has no linked artwork to package.")}
    let documentName=directory.documentName
    let output=try DocumentIO.prepareOutput(result,format:options.format,persistence:true);try directory.write(output,name:documentName)
    let metadata:[String:Any]=["format":"photato-linked-package","version":1,"document":documentName,"outputFormat":options.format.rawValue,
      "sources":sources.map{["sourceID":$0.sourceID.uuidString,"file":"Links/"+$0.name,"sha256":$0.fingerprint,"bytes":$0.byteLength]as[String:Any]}]
    try directory.write(JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys,.prettyPrinted]),name:directory.manifestName)
    let prepared=PreparedLinkedPackage(directory:directory,document:result,documentName:documentName,sources:sources);try prepared.validateSources();completed=true;return prepared
  }
}
