import Foundation

public struct SelectionModification:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable {
    case border,smooth,expand,contract
    public var title:String {switch self {case .border:"Border";case .smooth:"Smooth";case .expand:"Expand";case .contract:"Contract"}}
    public var maximum:Int {self == .border ? 200:100}
  }
  public var operation:Kind
  public var amount:Int
  public var atCanvasBounds:Bool
  public init(_ operation:Kind,amount:Int=1,atCanvasBounds:Bool=false){self.operation=operation;self.amount=amount;self.atCanvasBounds=atCanvasBounds}
  public func validate()throws {guard (1...operation.maximum).contains(amount) else {throw CraftError.invalid("\(operation.title) requires1–\(operation.maximum) pixels.")}}
  public func command(in document:CraftDocument)throws->Command {
    try validate();guard let mask=try document.coverageSelection() else {throw CraftError.invalid("Make a pixel selection first.")}
    return .modifiedSelection(try applied(to:mask),operation)
  }
  public func applied(to mask:SelectionMask)throws->SelectionMask {
    try validate();let source=try mask.coverageSurface()
    if operation == .border {
      let lower=amount/2,upper=(amount+1)/2
      func band(_ radius:Int)throws->Surface {
        let outside=try Self.filter(source,radius:radius,rank:.maximum,edge:atCanvasBounds)
        let inside=try Self.filter(source,radius:radius,rank:.minimum,edge:atCanvasBounds)
        return try outside.combiningStoredSamples(with:inside){a,b in
          let value=Float(max(0,Int((a.r*255).rounded())-Int((b.r*255).rounded())))
          return Pixel(value,value,value)
        }
      }
      let a=try band(lower),b=upper==lower ? a:try band(upper)
      // Round the symmetric half-width result in integer coverage units, avoiding
      // cancellation around half-byte ties in normalized floating-point masks.
      return try SelectionMask(coverage:a.combiningStoredSamples(with:b){x,y in
        let value=Float((Int(x.r)+Int(y.r)+1)/2)/255
        return Pixel(value,value,value)
      })
    }
    let rank:Rank=operation == .expand ? .maximum:operation == .contract ? .minimum:.median
    return try SelectionMask(coverage:Self.filter(source,radius:amount,rank:rank,edge:atCanvasBounds))
  }
  static func strokeExtremum(_ source:Surface,radius:Int,maximum:Bool)throws->Surface{guard (0...250).contains(radius) else{throw CraftError.invalid("Stroke radius exceeds the current250-pixel working limit.")};return try filter(source,radius:radius,rank:maximum ? .maximum:.minimum,edge:true)}
  private enum Rank {case minimum,maximum,median}
  /// A disc histogram slides horizontally inside a bounded tile halo. GRAY8 ranks
  /// retain soft coverage; median is majority voting for binary selections.
  private static func filter(_ source:Surface,radius:Int,rank:Rank,edge:Bool)throws->Surface {
    try Task.checkCancellation();if radius==0{return source}
    let w=source.width,h=source.height,canvas=IntRect(x:0,y:0,width:w,height:h)
    let implicit=UInt8((unit(source.defaultPixel.r)*255).rounded()),v=Float(implicit)/255
    if source.tileCount==0 && (!edge || implicit==0 || rank == .maximum) {return source}
    var regions=source.tileCount*4096>w*h/4 ? [canvas]:try source.projectedGeometrySupport(.identity,bounds:canvas,halo:radius)
    if edge && implicit>0 {
      regions += [IntRect(x:0,y:0,width:w,height:min(h,radius)),IntRect(x:0,y:max(0,h-radius),width:w,height:min(h,radius)),IntRect(x:0,y:0,width:min(w,radius),height:h),IntRect(x:max(0,w-radius),y:0,width:min(w,radius),height:h)]
    }
    let builder=try Surface.PagedBuilder(width:w,height:h,depth:.u8,fill:Pixel(v,v,v))
    let spans=(-radius...radius).map{($0,Int(floor(sqrt(Double(radius*radius-$0*$0)))))}
    let population=spans.reduce(0){$0+2*$1.1+1},target=rank == .minimum ? 0:rank == .maximum ? population-1:population/2
    for region in GeometryPatchRegions(width:w,height:h,rectangles:regions) {
      let pw=region.width+2*radius,ph=region.height+2*radius
      var input=[UInt8](repeating:0,count:pw*ph)
      for y in 0..<ph {try Task.checkCancellation();let sy=region.y+y-radius
        for x in 0..<pw {let sx=region.x+x-radius
          if edge && (sx<0 || sy<0 || sx>=w || sy>=h) {continue}
          input[y*pw+x]=UInt8((unit(source.pixel(x:min(w-1,max(0,sx)),y:min(h-1,max(0,sy))).r)*255).rounded())
        }
      }
      var patch=try Surface(width:region.width,height:region.height,depth:.u8,fill:Pixel(v,v,v))
      for y in 0..<region.height {
        try Task.checkCancellation();var histogram=[Int](repeating:0,count:256)
        for (dy,half) in spans {let row=(y+radius+dy)*pw;for x in (radius-half)...(radius+half) {histogram[Int(input[row+x])]+=1}}
        var median=0,below=0
        while below+histogram[median]<=target {below+=histogram[median];median+=1}
        for x in 0..<region.width {
          if x>0 {
            for (dy,half) in spans {
              let row=(y+radius+dy)*pw,removed=Int(input[row+x-1+radius-half]),added=Int(input[row+x+radius+half])
              histogram[removed]-=1;histogram[added]+=1
              if removed<median {below-=1};if added<median {below+=1}
            }
            while below>target {median-=1;below-=histogram[median]}
            while below+histogram[median]<=target {below+=histogram[median];median+=1}
          }
          if median != Int(implicit) {let q=Float(median)/255;patch.setPixel(x:x,y:y,Pixel(q,q,q))}
        }
      }
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return try builder.finish()
  }
}
