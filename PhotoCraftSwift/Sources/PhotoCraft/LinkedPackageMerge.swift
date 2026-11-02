import CryptoKit
import Darwin
import Foundation
import PhotoCraftCore

struct LinkedPackageOperations:Sendable {
  var move:@Sendable(Int32,String,Int32,String,UInt32)->Int32
  static let native=Self(move:{renameatx_np($0,$1,$2,$3,$4)})
}
struct LinkedPackageNode:Equatable,Sendable {
  let device:dev_t,inode:ino_t,size:off_t,mode:mode_t,flags:UInt32
  let modifiedSeconds:Int,modifiedNanoseconds:Int,changedSeconds:Int,changedNanoseconds:Int
  init(_ s:stat){device=s.st_dev;inode=s.st_ino;size=s.st_size;mode=s.st_mode;flags=s.st_flags;modifiedSeconds=s.st_mtimespec.tv_sec;modifiedNanoseconds=s.st_mtimespec.tv_nsec;changedSeconds=s.st_ctimespec.tv_sec;changedNanoseconds=s.st_ctimespec.tv_nsec}
  var regular:Bool{mode&S_IFMT==S_IFREG}
  func sameFile(_ other:Self)->Bool{device==other.device && inode==other.inode}
  func sameContentVersion(_ other:Self)->Bool{sameFile(other) && size==other.size && mode==other.mode && flags==other.flags && modifiedSeconds==other.modifiedSeconds && modifiedNanoseconds==other.modifiedNanoseconds}
  static func at(_ directory:Int32,_ name:String)throws->Self? {
    var info=stat();if fstatat(directory,name,&info,AT_SYMLINK_NOFOLLOW)==0{return Self(info)}
    if errno==ENOENT{return nil};throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))
  }
  static func descriptor(_ fd:Int32)throws->Self {var info=stat();guard fstat(fd,&info)==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};return Self(info)}
}
struct LinkedPackageRecoveryRequired:LocalizedError {
  var stagingName:String? = nil
  var errorDescription:String?{"Package publication stopped after an output changed. Existing edits and recovery files were retained in " + (stagingName ?? "the hidden package staging folder") + ". Review them before retrying."}
}

/// In-place publication touches only new assets and the explicitly replaced document/inventory.
/// Unrelated entries are never copied, renamed or removed.
final class LinkedPackageMerge:@unchecked Sendable {
  let documentName:String
  let manifestName:String
  private let parentFD:Int32
  private let name:String
  private let destinationFD:Int32
  private let destinationIdentity:LinkedPackageNode
  private var linksFD:Int32 = -1
  private var linksIdentity:LinkedPackageNode?
  private var linksCreated=false
  private var names:[String:String]=[:]
  private var reused:[String:LinkedPackageNode]=[:]
  private let documentIdentity:LinkedPackageNode?
  private let manifestIdentity:LinkedPackageNode?
  private static func failure()->NSError{NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
  static func folded(_ text:String)->String{text.precomposedStringWithCanonicalMapping.lowercased()}
  private static func entries(_ fd:Int32)throws->[String] {
    let copied=dup(fd);guard copied>=0 else{throw failure()}
    guard let directory=fdopendir(copied)else{close(copied);throw failure()};defer{closedir(directory)}
    var names:[String]=[];errno=0
    while let entry=readdir(directory) {
      let length=Int(entry.pointee.d_namlen)
      let name=withUnsafeBytes(of:entry.pointee.d_name){String(decoding:$0.prefix(length),as:UTF8.self)}
      if name != "." && name != ".."{names.append(name)}
    }
    guard errno==0 else{throw failure()};return names.sorted()
  }
  private static func actualName(_ requested:String,directory:Int32,entries:[String])throws->(String,LinkedPackageNode?) {
    guard let node=try LinkedPackageNode.at(directory,requested)else{return(requested,nil)}
    if entries.contains(requested){return(requested,node)}
    for entry in entries where folded(entry)==folded(requested) {
      if try LinkedPackageNode.at(directory,entry)?.sameFile(node)==true{return(entry,node)}
    }
    throw DocumentPersistenceConflict.changed
  }
  private static func bytes(_ directory:Int32,_ name:String,maximum:Int)throws->Data? {
    guard let before=try LinkedPackageNode.at(directory,name),before.regular,before.size>=0,before.size<=maximum else{return nil}
    let fd=openat(directory,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);guard fd>=0 else{return nil};defer{close(fd)}
    guard try LinkedPackageNode.descriptor(fd)==before else{throw DocumentPersistenceConflict.changed}
    var data=Data(),buffer=[UInt8](repeating:0,count:65536)
    while data.count<Int(before.size) {
      try Task.checkCancellation()
      let count=buffer.withUnsafeMutableBytes{pread(fd,$0.baseAddress,min($0.count,Int(before.size)-data.count),off_t(data.count))}
      if count<0,errno==EINTR{continue};guard count>0 else{throw failure()};data.append(contentsOf:buffer.prefix(count))
    }
    let after=try LinkedPackageNode.descriptor(fd),named=try LinkedPackageNode.at(directory,name)
    guard after==before,named==before else{throw DocumentPersistenceConflict.changed};return data
  }
  init(parent:Int32,name:String,documentName requested:String)throws {
    let parentCopy=dup(parent);guard parentCopy>=0 else{throw Self.failure()}
    let root=openat(parentCopy,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
    guard root>=0 else{close(parentCopy);throw Self.failure()}
    var complete=false;defer{if !complete{close(root);close(parentCopy)}}
    let identity=try LinkedPackageNode.descriptor(root),entries=try Self.entries(root)
    let rootNames=Dictionary(entries.map{(Self.folded($0),$0)},uniquingKeysWith:{a,_ in a})
    let(documentName,documentIdentity)=try Self.actualName(requested,directory:root,entries:entries)
    guard documentIdentity?.regular != false else{throw CraftError.invalid("The packaged document destination is not a regular file.")}
    var manifestName="package.json",manifestIdentity:LinkedPackageNode?
    let(existingInventory,inventoryNode)=try Self.actualName(manifestName,directory:root,entries:entries)
    if inventoryNode != nil {
      let existing=existingInventory
      let inventorySnapshot=try LinkedPackageNode.at(root,existing)
      let data=try Self.bytes(root,existing,maximum:1024*1024)
      guard try LinkedPackageNode.at(root,existing)==inventorySnapshot else{throw DocumentPersistenceConflict.changed}
      let object=data.flatMap{try? JSONSerialization.jsonObject(with:$0)as?[String:Any]}
      if object?["format"]as?String=="photato-linked-package",object?["version"]as?Int==1,object?["document"]as?String==documentName {
        manifestName=existing;manifestIdentity=try LinkedPackageNode.at(root,existing)
      }else{
        var index=2;while rootNames[Self.folded(manifestName)] != nil{manifestName="package-\(index).json";index+=1}
      }
    }
    self.parentFD=parentCopy;self.name=name;self.destinationFD=root;self.destinationIdentity=identity
    self.documentName=documentName;self.documentIdentity=documentIdentity;self.manifestName=manifestName;self.manifestIdentity=manifestIdentity
    complete=true
    do {
      if let node=try LinkedPackageNode.at(root,"Links") {
        guard node.mode&S_IFMT==S_IFDIR else{throw CraftError.invalid("The existing Links entry is not a directory.")}
        linksFD=openat(root,"Links",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard linksFD>=0 else{throw Self.failure()}
        linksIdentity=try LinkedPackageNode.descriptor(linksFD)
        guard linksIdentity==node else{throw DocumentPersistenceConflict.changed}
        names=Dictionary(try Self.entries(linksFD).map{(Self.folded($0),$0)},uniquingKeysWith:{a,_ in a})
      }
    }catch{throw error}
  }
  func selectAsset(_ base:String,fingerprint:String,count:Int)throws->(name:String,reused:Bool) {
    var candidate=base,index=2
    while let actual=names[Self.folded(candidate)] {
      if linksFD>=0,let node=try LinkedPackageNode.at(linksFD,actual),node.regular,node.size==count,
        let data=try Self.bytes(linksFD,actual,maximum:SmartObject.maximumSourceBytes),
        LinkedSmartObjectSource.fingerprint(data)==fingerprint {
        reused[actual]=node;return(actual,true)
      }
      let ext=(base as NSString).pathExtension,stem=(base as NSString).deletingPathExtension
      candidate=stem+"-\(index)"+(ext.isEmpty ? "":"."+ext);index+=1
    }
    names[Self.folded(candidate)]=candidate;return(candidate,false)
  }
  private struct Step {
    let from:Int32,to:Int32,name:String,replaced:Bool,published:LinkedPackageNode
  }
  func commit(staging:Int32,links stagedLinks:Int32,assets:[String],operations:LinkedPackageOperations)throws->[(String,dev_t,ino_t)] {
    guard let destination=try LinkedPackageNode.at(parentFD,name),destination.sameFile(destinationIdentity),
      try LinkedPackageNode.descriptor(destinationFD).sameFile(destinationIdentity)else{throw DocumentPersistenceConflict.changed}
    if let linksIdentity {
      guard try LinkedPackageNode.at(destinationFD,"Links")?.sameFile(linksIdentity)==true else{throw DocumentPersistenceConflict.changed}
    }else{
      guard try LinkedPackageNode.at(destinationFD,"Links")==nil else{throw DocumentPersistenceConflict.changed}
    }
    for (name,node)in reused{guard try LinkedPackageNode.at(linksFD,name)==node else{throw DocumentPersistenceConflict.changed}}
    let currentDocument=try LinkedPackageNode.at(destinationFD,documentName),currentManifest=try LinkedPackageNode.at(destinationFD,manifestName)
    guard currentDocument==documentIdentity,currentManifest==manifestIdentity else{throw DocumentPersistenceConflict.changed}
    var steps:[Step]=[],backups:[(String,dev_t,ino_t)]=[]
    func publish(_ file:String,from:Int32,to:Int32,expected:LinkedPackageNode?)throws {
      try Task.checkCancellation()
      guard try LinkedPackageNode.at(to,file)==expected else{throw DocumentPersistenceConflict.changed}
      guard operations.move(from,file,to,file,UInt32(expected==nil ? RENAME_EXCL:RENAME_SWAP))==0 else{throw Self.failure()}
      let post=try LinkedPackageNode.at(to,file);guard let post else{throw DocumentPersistenceConflict.changed}
      steps.append(.init(from:from,to:to,name:file,replaced:expected != nil,published:post))
      if let expected {
        guard let old=try LinkedPackageNode.at(from,file),old.sameContentVersion(expected)else{throw DocumentPersistenceConflict.changed}
        backups.append((file,old.device,old.inode))
      }
    }
    do {
      if linksFD<0 {
        guard mkdirat(destinationFD,"Links",0o755)==0 else{throw Self.failure()};linksCreated=true
        linksFD=openat(destinationFD,"Links",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard linksFD>=0 else{throw Self.failure()};linksIdentity=try LinkedPackageNode.descriptor(linksFD)
      }
      for asset in assets.sorted(){try publish(asset,from:stagedLinks,to:linksFD,expected:nil)}
      guard fsync(linksFD)==0 else{throw Self.failure()}
      try publish(manifestName,from:staging,to:destinationFD,expected:manifestIdentity)
      // The document is the commit point; all of its sources already exist.
      try publish(documentName,from:staging,to:destinationFD,expected:documentIdentity)
      return backups
    }catch {
      var recovered=true
      for step in steps.reversed() {
        do {
          guard let current=try LinkedPackageNode.at(step.to,step.name),current==step.published else{recovered=false;continue}
          if step.replaced {
            guard try LinkedPackageNode.at(step.from,step.name) != nil,LinkedPackageOperations.native.move(step.from,step.name,step.to,step.name,UInt32(RENAME_SWAP))==0 else{recovered=false;continue}
          }else{
            guard LinkedPackageOperations.native.move(step.to,step.name,step.from,step.name,UInt32(RENAME_EXCL))==0 else{recovered=false;continue}
          }
        }catch{recovered=false}
      }
      if linksCreated,let linksIdentity {
        if (try? LinkedPackageNode.at(destinationFD,"Links")?.sameFile(linksIdentity))==true{_ = unlinkat(destinationFD,"Links",AT_REMOVEDIR)}
      }
      if !recovered{throw LinkedPackageRecoveryRequired()};throw error
    }
  }
  deinit{if linksFD>=0{close(linksFD)};close(destinationFD);close(parentFD)}
}
