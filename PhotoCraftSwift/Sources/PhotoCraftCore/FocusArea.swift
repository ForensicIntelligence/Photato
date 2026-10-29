import Foundation

public struct FocusAreaSettings:Codable,Equatable,Sendable {
  public var range=5.0,noise=0.0
  public var autoRange=true,autoNoise=true,softenEdge=false
  public init() {}
  public func validate()throws {
    guard range.isFinite,(0...10).contains(range),noise.isFinite,(0...1).contains(noise) else{throw CraftError.invalid("Focus range must be0–10 and noise0–1.")}
  }
}
/// Source-derived Laplacian focus measure and guided cleanup. Auto thresholds are native
/// heuristics; Photoshop's proprietary detection and exact pixel results are unqualified.
public struct FocusAreaAnalysis:Sendable {
  public let width:Int,height:Int,step:Int
  public let estimatedNoise:Double
  let image:SelectionImage
  let energy:[Float]
  public static func prepare(_ source:Surface,workingPixels:Int=1_000_000)throws->Self {
    try SelectionMatting.checkSize(source.width,source.height)
    guard (16...1_000_000).contains(workingPixels) else{throw CraftError.invalid("Invalid focus working resolution.")}
    let w=source.width,h=source.height,step=max(1,Int(ceil(sqrt(Double(w*h)/Double(workingPixels)))))
    let image=try SelectionImage(source,rect:.init(x:0,y:0,width:w,height:h),step:step),iw=image.width,ih=image.height
    let luma=image.pixels.map{0.299*$0.x+0.587*$0.y+0.114*$0.z};var lap=[Float](repeating:0,count:iw*ih)
    func at(_ x:Int,_ y:Int)->Float{luma[min(ih-1,max(0,y))*iw+min(iw-1,max(0,x))]}
    for y in 0..<ih{try Task.checkCancellation();for x in 0..<iw{let c=2*at(x,y);lap[y*iw+x]=abs(c-at(x-1,y)-at(x+1,y))+abs(c-at(x,y-1)-at(x,y+1))}}
    let local=try MattingFilters.box(lap,iw,ih,max(3,min(iw,ih)/60)),ordered=local.sorted(),p99=ordered[min(ordered.count-1,ordered.count*99/100)]
    let energy=local.map{min(1,max(0,$0/max(p99,1e-6)))},median=lap.sorted()[lap.count/2]
    // Conservative global high-frequency floor. Auto is intentionally discoverable, not an Adobe claim.
    let noise=min(1,max(0,Double(median/max(p99,1e-6))*0.25))
    return Self(width:w,height:h,step:step,estimatedNoise:noise,image:image,energy:energy)
  }
  func scores(_ noise:Double)->[Float]{let floor=Float(noise)*0.5;return energy.map{max(0,$0-floor)/max(0.001,1-floor)}}
  static func threshold(_ values:[Float])->Float {
    var hist=[Int](repeating:0,count:256);for v in values{hist[min(255,max(0,Int((v*255).rounded())))]+=1}
    let sum=hist.indices.reduce(0.0){$0+Double($1*hist[$1])};var count=0,total=0.0,best = -1.0,index=127
    for i in 0..<255 {
      count+=hist[i];total+=Double(i*hist[i]);let other=values.count-count;guard count>0,other>0 else{continue}
      let difference=total/Double(count)-(sum-total)/Double(other),score=Double(count)*Double(other)*difference*difference
      if score>best{best=score;index=i}
    }
    return min(0.95,max(0.05,Float(index+1)/255))
  }
  public func effectiveSettings(_ settings:FocusAreaSettings)throws->FocusAreaSettings {
    try settings.validate();var value=settings
    if value.autoNoise{value.noise=estimatedNoise}
    if value.autoRange{value.range=sqrt(max(0,Double(Self.threshold(scores(value.noise)))-0.05)/0.9)*10}
    return value
  }
  public func mask(settings:FocusAreaSettings)throws->SelectionMask {
    try Task.checkCancellation();let p=try effectiveSettings(settings),w=image.width,h=image.height
    if !settings.autoRange && settings.range==0{return try .init(width:width,height:height,bytes:[UInt8](repeating:255,count:width*height))}
    let scores=scores(p.noise),threshold:Float=0.05+0.9*Float(pow(p.range/10,2)),bin=scores.map{$0>=threshold ? Float(1):0}
    let smooth=try MattingFilters.guided(image.pixels,bin,w,h,max(2,min(w,h)/50),epsilon:1e-2)
    var mask=smooth.map{$0>=0.5}
    let (labels,sizes)=try SelectionSegmentation.components(mask,w,h),largest=sizes.dropFirst().max() ?? 0,minimum=max(1,Int(ceil(Float(largest)*0.05)))
    mask=labels.map{$0>0 && sizes[$0]>=minimum}
    let (holes,counts)=try SelectionSegmentation.components(mask.map{!$0},w,h,four:true);var edge=[Bool](repeating:false,count:counts.count)
    for x in 0..<w{edge[holes[x]]=true;edge[holes[(h-1)*w+x]]=true};for y in 0..<h{edge[holes[y*w]]=true;edge[holes[y*w+w-1]]=true}
    let holeLimit=Int(Float(mask.filter{$0}.count)*0.02)
    for i in mask.indices where holes[i]>0 && !edge[holes[i]] && counts[holes[i]]<=holeLimit{mask[i]=true}
    // A hard mask must use the cleaned labels; thresholding a pruned region clamped
    // to0.5 would otherwise resurrect it as opaque when Soften Edge is disabled.
    let field:[Float]=p.softenEdge ? mask.indices.map{mask[$0] ? min(1,max(0.5,smooth[$0])):min(0.5,max(0,smooth[$0]))}:mask.map{$0 ? 1:0}
    var bytes=[UInt8](repeating:0,count:width*height)
    func at(_ x:Int,_ y:Int)->Float{field[min(h-1,max(0,y))*w+min(w-1,max(0,x))]}
    for y in 0..<height{try Task.checkCancellation();for x in 0..<width{
      let fx=(Float(x)+0.5)/Float(step)-0.5,fy=(Float(y)+0.5)/Float(step)-0.5,x0=Int(floor(fx)),y0=Int(floor(fy)),ax=fx-floor(fx),ay=fy-floor(fy)
      let value=(at(x0,y0)*(1-ax)+at(x0+1,y0)*ax)*(1-ay)+(at(x0,y0+1)*(1-ax)+at(x0+1,y0+1)*ax)*ay
      bytes[y*width+x]=p.softenEdge ? UInt8((min(1,max(0,(value-0.5)*3+0.5))*255).rounded()):(value>=0.5 ? 255:0)
    }}
    return try .init(width:width,height:height,bytes:bytes)
  }
}
