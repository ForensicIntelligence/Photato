import Foundation
import PhotoCraftCore

enum PSDChannelBlending {
  static func read(_ data:Data)throws->[Int] {
    guard data.count<=12,data.count%4==0 else{throw CraftError.invalid("Invalid PSD channel blending restrictions.")}
    var channels:[Int]=[]
    for i in stride(from:0,to:data.count,by:4){let value=data[i..<i+4].reduce(0){($0<<8)|Int($1)};channels.append(value)}
    try BlendChannelRestrictions.validate(channels);return channels
  }
  static func write(_ channels:[Int])throws->Data {
    try BlendChannelRestrictions.validate(channels)
    return Data(channels.sorted().flatMap{[0,0,0,UInt8($0)]})
  }
}
