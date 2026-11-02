import Foundation

/// Pixel offsets are rounded after an optional45-degree direction constraint.
public struct SelectedPixelMoveRequest:Codable,Equatable,Sendable {
  public var layerID:UUID
  public var dx:Double,dy:Double
  public var copy:Bool,constrain:Bool
  public var backgroundColor:Pixel?
  public init(layerID:UUID,dx:Double,dy:Double,copy:Bool=false,constrain:Bool=false,backgroundColor:Pixel? = nil){self.layerID=layerID;self.dx=dx;self.dy=dy;self.copy=copy;self.constrain=constrain;self.backgroundColor=backgroundColor}
  public func offset()throws->(x:Int,y:Int) {
    guard dx.isFinite,dy.isFinite,abs(dx)<=1_000_000,abs(dy)<=1_000_000 else{throw CraftError.invalid("Invalid selected-pixel movement.")}
    var x=dx,y=dy
    if constrain {let length=hypot(x,y),angle=(atan2(y,x)/(.pi/4)).rounded()*(.pi/4);x=cos(angle)*length;y=sin(angle)*length}
    x=x.rounded();y=y.rounded();guard abs(x)<=1_000_000,abs(y)<=1_000_000 else{throw CraftError.invalid("Constrained movement exceeds the coordinate limit.")};return(Int(x),Int(y))
  }
  public func transform()throws->SelectedPixelTransformRequest {let value=try offset();return .init(layerID:layerID,matrix:.init(.translation(Double(value.x),Double(value.y))),interpolation:.nearest,backgroundColor:backgroundColor,copy:copy)}
}
