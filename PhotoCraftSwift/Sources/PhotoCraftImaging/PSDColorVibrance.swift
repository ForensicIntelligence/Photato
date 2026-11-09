import Foundation
import PhotoCraftCore

/// Observed Photoshop 2026 records from owned images, not proprietary implementation code.
/// The modern transfer is still a work-alike; reading settings does not qualify pixel equality.
enum PSDColorVibrance {
  static func readAdjustment(_ data:Data,key:String)throws->Adjustment {
    guard key == "vibA" else{return .classic(try PSDClassicAdjustment.read(data,key:key))}
    let descriptor=try PSDDescriptor.read(data,padding:true)
    guard let flag=descriptor["useLegacy"] else{return .classic(try PSDClassicAdjustment.read(data,key:key))}
    guard case .boolean(let legacy)=flag else{throw CraftError.invalid("Invalid Color and vibrance legacy flag.")}
    guard !legacy else{return .classic(try PSDClassicAdjustment.read(data,key:key))}
    let keys=descriptor.items.map(\.key.text)
    guard descriptor.classID.text == "null",Set(keys).count==keys.count,
      Set(keys).isSubset(of:["useLegacy","temperature","tint","vibrance","Strt","whiteBalancePopupIndex"]) else {
      throw CraftError.unsupported("Unrepresented Photoshop Color and vibrance fields.")
    }
    func integer(_ key:String,_ fallback:Int)throws->Int {
      guard let field=descriptor[key] else{return fallback}
      guard case .integer(let value)=field else{throw CraftError.invalid("Invalid Color and vibrance control.")}
      return Int(value)
    }
    // Only the observed Default and Custom states are represented by the native controls.
    let whiteBalance=try integer("whiteBalancePopupIndex",0)
    guard [0,2].contains(whiteBalance) else{throw CraftError.unsupported("Unrepresented Photoshop white-balance preset.")}
    var value=ModernAdjustment(.colorVibrance)
    for (native,psd) in [("temperature","temperature"),("tint","tint"),("vibrance","vibrance"),("saturation","Strt")] {
      value.values[native]=Float(try integer(psd,0))
    }
    try value.validate();return .modern(value)
  }
}
