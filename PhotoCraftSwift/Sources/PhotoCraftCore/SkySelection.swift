import Foundation

public struct SkySelectionSettings:Codable,Equatable,Sendable {
  public var threshold=50.0,softness=50.0
  public init() {}
  public func validate()throws {
    guard [threshold,softness].allSatisfy({$0.isFinite && (0...100).contains($0)}) else {throw CraftError.invalid("Sky threshold and softness must be0–100.")}
  }
}
/// Native translation of PhotoCraft segment/sky.rs (MIT OR Apache-2.0).
/// Classical color/texture segmentation, not Adobe's proprietary sky model.
public enum SkySelection {
  static func smooth(_ a:Float,_ b:Float,_ x:Float)->Float {let t=min(1,max(0,(x-a)/(b-a)));return t*t*(3-2*t)}
  static func luma(_ p:SelectionRGB)->Float {0.299*p.x+0.587*p.y+0.114*p.z}
  static func prior(_ p:SelectionRGB)->Float {
    let y=luma(p),mx=max(p.x,max(p.y,p.z)),mn=min(p.x,min(p.y,p.z)),sat=mx>1e-4 ? (mx-mn)/mx:0
    let blue=smooth(0.02,0.12,p.z-p.x)*smooth(-0.12,0,p.z-p.y)*smooth(0.18,0.4,y)
    let white=smooth(0.5,0.75,y)*(1-smooth(0.12,0.3,sat))
    let warm=0.6*smooth(0.55,0.8,y)*smooth(0,0.1,p.x-p.z)*(1-smooth(0.05,0.25,p.y-p.z-0.2))
    return max(blue,max(white,warm))
  }
  static func low(_ image:SelectionImage,threshold:Float)throws->[Bool]? {
    let w=image.width,h=image.height;guard w>=2,h>=2 else{return nil}
    let y=image.pixels.map(luma);var gradient=[Float](repeating:0,count:w*h)
    func at(_ x:Int,_ yy:Int)->Float {y[min(h-1,max(0,yy))*w+min(w-1,max(0,x))]}
    for yy in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let gx=(at(x+1,yy-1)+2*at(x+1,yy)+at(x+1,yy+1))-(at(x-1,yy-1)+2*at(x-1,yy)+at(x-1,yy+1))
      let gy=(at(x-1,yy+1)+2*at(x,yy+1)+at(x+1,yy+1))-(at(x-1,yy-1)+2*at(x,yy-1)+at(x+1,yy-1))
      gradient[yy*w+x]=hypot(gx,gy)/8
    }}
    let texture=try MattingFilters.box(gradient,w,h,2)
    let likelihood=zip(image.pixels,texture).map{prior($0.0)*(1-smooth(0.015,0.07,$0.1))},t:Float=0.12+0.6*threshold/100,top=max(h/40,1)
    var mask=[Bool](repeating:false,count:w*h),stack:[Int]=[]
    for i in 0..<top*w where likelihood[i]>t {mask[i]=true;stack.append(i)}
    guard stack.count*20>=top*w else{return nil}
    var ticks=0
    while let i=stack.popLast() {
      ticks+=1;if ticks%4096==0{try Task.checkCancellation()};let x=i%w,yy=i/w
      for (dx,dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
        let nx=x+dx,ny=yy+dy;guard nx>=0,nx<w,ny>=0,ny<h else{continue};let j=ny*w+nx
        if !mask[j] && likelihood[j]>t && selectionDistance(image.pixels[i],image.pixels[j]).squareRoot()<0.12 {mask[j]=true;stack.append(j)}
      }
    }
    let samples=image.pixels.indices.compactMap{mask[$0] ? image.pixels[$0]:nil}
    if samples.count>=16,let g=try SelectionColorModel.fit(SelectionSegmentation.subsample(samples,4000),count:3,ridge:1e-4) {
      let costs=SelectionSegmentation.subsample(samples,2000).map{Float(-g.logProbability($0))}.sorted(),cut=costs[min(costs.count-1,costs.count*95/100)]
      for i in mask.indices {
        if i%4096==0{try Task.checkCancellation()}
        if !mask[i] && likelihood[i]>t+0.1 && Float(-g.logProbability(image.pixels[i]))<=cut {mask[i]=true}
      }
    }
    // Sky preserves small gaps; its component/hole ratios differ from object selection.
    let (labels,sizes)=try SelectionSegmentation.components(mask,w,h),largest=sizes.dropFirst().max() ?? 0
    let minimum=max(1,Int(ceil(Float(largest)*0.002)))
    mask=labels.map{$0>0 && sizes[$0]>=minimum}
    let holeLimit=Int(Float(mask.filter{$0}.count)*0.01)
    let (holes,counts)=try SelectionSegmentation.components(mask.map{!$0},w,h,four:true);var edge=[Bool](repeating:false,count:counts.count)
    for x in 0..<w{edge[holes[x]]=true;edge[holes[(h-1)*w+x]]=true};for yy in 0..<h{edge[holes[yy*w]]=true;edge[holes[yy*w+w-1]]=true}
    for i in mask.indices where holes[i]>0 && !edge[holes[i]] && counts[holes[i]]<=holeLimit {mask[i]=true}
    return mask.contains(true) ? mask:nil
  }
  static func guided(_ guide:[Float],_ input:[Float],_ w:Int,_ h:Int,_ radius:Int,_ epsilon:Float)throws->[Float] {
    let mean=try MattingFilters.box(guide,w,h,radius),p=try MattingFilters.box(input,w,h,radius)
    let ii=try MattingFilters.box(guide.map{$0*$0},w,h,radius),ip=try MattingFilters.box(zip(guide,input).map(*),w,h,radius)
    var a=input,b=input
    for i in input.indices {a[i]=(ip[i]-mean[i]*p[i])/(max(0,ii[i]-mean[i]*mean[i])+epsilon);b[i]=p[i]-a[i]*mean[i]}
    a=try MattingFilters.box(a,w,h,radius);b=try MattingFilters.box(b,w,h,radius)
    return input.indices.map{a[$0]*guide[$0]+b[$0]}
  }
  public static func mask(_ source:Surface,settings:SkySelectionSettings = .init(),workingPixels:Int=160_000)throws->SelectionMask? {
    try settings.validate();try SelectionSegmentation.check(source)
    guard (16...160_000).contains(workingPixels) else{throw CraftError.invalid("Invalid sky working resolution.")}
    let w=source.width,h=source.height;guard w>=4,h>=4 else{return nil}
    let step=max(1,Int(ceil(sqrt(Double(w*h)/Double(workingPixels)))))
    let image=try SelectionImage(source,rect:.init(x:0,y:0,width:w,height:h),step:step)
    guard let low=try low(image,threshold:Float(settings.threshold)) else{return nil}
    let lw=image.width,lh=image.height,soft=Float(settings.softness/100),radius=max(3,Int(ceil(Float(step)*(1+2*soft)))),epsilon:Float=1e-4+4e-3*soft,k:Float=0.08+0.42*soft
    func coarse(_ x:Int,_ y:Int)->Float {
      let fx=(Float(x)+0.5)/Float(step)-0.5,fy=(Float(y)+0.5)/Float(step)-0.5,x0=Int(floor(fx)),y0=Int(floor(fy)),ax=fx-floor(fx),ay=fy-floor(fy)
      func at(_ xx:Int,_ yy:Int)->Float {low[min(lh-1,max(0,yy))*lw+min(lw-1,max(0,xx))] ? 1:0}
      return (at(x0,y0)*(1-ax)+at(x0+1,y0)*ax)*(1-ay)+(at(x0,y0+1)*(1-ax)+at(x0+1,y0+1)*ax)*ay
    }
    var bytes=[UInt8](repeating:0,count:w*h)
    for ty in stride(from:0,to:h,by:256){for tx in stride(from:0,to:w,by:256){
      try Task.checkCancellation()
      // Two box-filter stages need a2r halo to avoid artificial tile edges.
      let halo=2*radius+2,x0=max(0,tx-halo),y0=max(0,ty-halo),x1=min(w,tx+256+halo),y1=min(h,ty+256+halo),ww=x1-x0,hh=y1-y0
      let input=(0..<ww*hh).map{coarse(x0+$0%ww,y0+$0/ww)},lo=input.min()!,hi=input.max()!
      let output:[Float]
      if hi<=0 || lo>=1 {output=input}
      else{let guide=try SelectionImage(source,rect:.init(x:x0,y:y0,width:ww,height:hh));output=try guided(guide.pixels.map(luma),input,ww,hh,radius,epsilon)}
      for y in ty..<min(h,ty+256){for x in tx..<min(w,tx+256){bytes[y*w+x]=UInt8((smooth(0.5-k,0.5+k,output[(y-y0)*ww+x-x0])*255).rounded())}}
    }}
    let result=try SelectionMask(width:w,height:h,bytes:bytes);return result.bounds==nil ? nil:result
  }
}
