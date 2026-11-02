import Foundation
import PhotoCraftCore

enum PcraftGuides {
  static func read(_ node:PcraftNode,namespace:Data)throws->[DocumentGuide]? {
    try node.keys("horizontal vertical");var result:[DocumentGuide]=[]
    for axis in [DocumentGuide.Axis.vertical,.horizontal] {
      for item in try node.field(axis.rawValue).array() {
        let line=DocumentGuide(id:PcraftImport.identity(namespace,role:"guide",id:UInt64(result.count)),axis:axis,position:Double(try item.float()))
        try line.validate();result.append(line)
        guard result.count<=DocumentGuide.maximumCount else{throw node.unsupported("Too many source document guides.")}
      }
    };return result.isEmpty ? nil:result
  }
}
