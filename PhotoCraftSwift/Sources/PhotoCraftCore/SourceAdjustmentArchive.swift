import Foundation
extension CraftDocument {
  public var requiresSourceAdjustmentArchive:Bool {
    layers.contains{if case .adjustment(.source)=$0.content{return true};return false}
  }
}
