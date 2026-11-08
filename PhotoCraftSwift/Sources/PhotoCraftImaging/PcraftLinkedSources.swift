import Foundation
import PhotoCraftCore

/// Rust can use a PSD resource ID as a SmartSource.Linked path. Resolve only
/// originals already inside known linked-data blocks; paths never open files.
enum PcraftLinkedSources {
  static func embedded(_ identifier:String,in document:CraftDocument,
    cache:inout [String:PSDSmartObjects.File]?)throws->PSDSmartObjects.File {
    try Task.checkCancellation()
    if cache==nil{cache=try files(in:document)}
    guard let file=cache?[identifier],file.link==nil,!file.data.isEmpty else {
      throw CraftError.unsupported("The linked Smart Object has no embedded original. External and alias sources require explicit authorized resolution; no file was opened.")
    }
    return file
  }
  static func files(in document:CraftDocument)throws->[String:PSDSmartObjects.File] {
    var result=[String:PSDSmartObjects.File]()
    let tags=["6c6e6b32":"lnk2","6c6e6b33":"lnk3","6c6e6b44":"lnkD","6c6e6b45":"lnkE"]
    for(key,data)in (document.sourceMetadata ?? [:]).sorted(by:{$0.key<$1.key}) {
      try Task.checkCancellation()
      let fields=key.split(separator:".",omittingEmptySubsequences:false)
      guard fields.count==5,fields[0]=="pcraft",fields[1]=="psdGlobal",Int(fields[2]) != nil,
        ["3842494d","38423634"].contains(fields[3].lowercased()),let tag=tags[fields[4].lowercased()] else{continue}
      // Do not promote any source global into the imported document. The
      // temporary wrapper supplies only this one validated known block.
      var wrapper=try CraftDocument(width:1,height:1);wrapper.sourceMetadata=["psdGlobal_"+tag:data]
      for(id,file)in try PSDSmartObjects.files(wrapper){
        guard result[id]==nil else{throw CraftError.invalid("Duplicate embedded source identifier in PhotoCraft linked blocks.")}
        result[id]=file
      }
    }
    try Task.checkCancellation();return result
  }
}
