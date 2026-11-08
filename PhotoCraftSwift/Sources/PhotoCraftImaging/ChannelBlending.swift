import Foundation
import PhotoCraftCore

enum ChannelBlending {
  static func unrestricted(_ layer:Layer)->Layer {
    var result=layer
    if layer.style?.isChannelBlendingOnly==true{result.style=nil}
    else{result.style?.restrictedChannels=nil}
    return result
  }
  static func restore(_ after:Surface,over before:Surface,channels:[Int])throws->Surface {
    if channels.isEmpty{return after};if channels.count==3{return before}
    return try after.combiningStoredSamples(with:before){after,before in BlendChannelRestrictions.applying(channels,after:after,before:before)}
  }
}
