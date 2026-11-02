import Foundation
import PhotoCraftCore

public struct MagneticLassoInput:Sendable {
  public let original:CraftDocument
  public let image:Surface
  public static func prepare(_ document:CraftDocument)throws->Self {
    guard document.depth != .f32 else {throw CraftError.unsupported("Magnetic Lasso is unavailable for32-bit images.")}
    let input=try ColorRangeInput.prepare(document)
    return Self(original:document,image:input.guide)
  }
  public func command(events:[MagneticLassoEvent],settings:MagneticLassoSettings,mode:SelectionMode,straight:Bool=false)throws->Command {
    let trace=try MagneticLassoTrace.replay(events,image:image,settings:settings)
    return .magneticSelection(try trace.mask(image:image,straight:straight),mode)
  }
}
