import Foundation

// Native Swift translation of PhotoCraft crates/algo/src/segment/gmm.rs and its RNG.
// Original project license: MIT OR Apache-2.0. See ATTRIBUTION.md.
struct SelectionRandom {
  var state:UInt64
  init(_ seed:UInt64) {state=(seed &* 0x9E3779B97F4A7C15) | 1}
  mutating func next()->UInt64 {state ^= state << 13;state ^= state >> 7;state ^= state << 17;return state}
  mutating func unit()->Float {Float(next() >> 40)/16_777_216}
}
typealias SelectionRGB = SIMD3<Float>
@inline(__always) func selectionDistance(_ a:SelectionRGB,_ b:SelectionRGB)->Float {
  let d=a-b;return d.x*d.x+d.y*d.y+d.z*d.z
}
struct SelectionGaussian {
  var mean:SelectionRGB
  var inverse:[Double]
  var logNorm:Double
  init?(weight:Double,mean:SIMD3<Double>,covariance:[Double],ridge:Float) {
    var c=covariance
    for i in 0..<3 {c[i*3+i] += Double(ridge)}
    let det=c[0]*(c[4]*c[8]-c[5]*c[7])-c[1]*(c[3]*c[8]-c[5]*c[6])+c[2]*(c[3]*c[7]-c[4]*c[6])
    guard det>1e-30,weight>0 else{return nil}
    inverse=[(c[4]*c[8]-c[5]*c[7])/det,(c[2]*c[7]-c[1]*c[8])/det,(c[1]*c[5]-c[2]*c[4])/det,
      (c[5]*c[6]-c[3]*c[8])/det,(c[0]*c[8]-c[2]*c[6])/det,(c[2]*c[3]-c[0]*c[5])/det,
      (c[3]*c[7]-c[4]*c[6])/det,(c[1]*c[6]-c[0]*c[7])/det,(c[0]*c[4]-c[1]*c[3])/det]
    self.mean=SelectionRGB(Float(mean.x),Float(mean.y),Float(mean.z))
    logNorm=log(weight)-0.5*log(det)-1.5*log(2*Double.pi)
  }
  func logWeighted(_ z:SelectionRGB)->Double {
    let d=z-mean,x=Double(d.x),y=Double(d.y),z=Double(d.z),m=inverse
    let q=x*(m[0]*x+m[1]*y+m[2]*z)+y*(m[3]*x+m[4]*y+m[5]*z)+z*(m[6]*x+m[7]*y+m[8]*z)
    return logNorm-0.5*q
  }
}
private struct SelectionAccumulator {
  var n=0.0,s=SIMD3<Double>(repeating:0),ss=[Double](repeating:0,count:9)
  mutating func add(_ point:SelectionRGB,_ weight:Double) {
    let z=SIMD3<Double>(Double(point.x),Double(point.y),Double(point.z));n+=weight
    for i in 0..<3 {s[i]+=weight*z[i];for j in 0..<3 {ss[i*3+j]+=weight*z[i]*z[j]}}
  }
  func component(total:Double,ridge:Float)->SelectionGaussian? {
    guard n>0 else{return nil};let mean=s/n
    var c=[Double](repeating:0,count:9)
    for i in 0..<3 {for j in 0..<3 {c[i*3+j]=ss[i*3+j]/n-mean[i]*mean[j]}}
    return .init(weight:n/total,mean:mean,covariance:c,ridge:ridge)
  }
}
struct SelectionColorModel {
  var components:[SelectionGaussian],ridge:Float
  static func fit(_ samples:[SelectionRGB],count:Int,ridge:Float)throws->Self? {
    guard !samples.isEmpty else{return nil}
    let centers=try kmeans(samples,count:min(max(1,count),samples.count))
    let labels=samples.map{nearest(centers,$0)}
    guard var model=fromLabels(samples,labels,count:centers.count,ridge:ridge) else{return nil}
    for _ in 0..<3 {
      try Task.checkCancellation()
      var acc=[SelectionAccumulator](repeating:.init(),count:model.components.count)
      for (i,z) in samples.enumerated() {
        if i%1024==0 {try Task.checkCancellation()}
        let lw=model.components.map{$0.logWeighted(z)},mx=lw.max()!
        let weights=lw.map{exp($0-mx)},sum=weights.reduce(0,+)
        for j in acc.indices where weights[j]/sum>1e-6 {acc[j].add(z,weights[j]/sum)}
      }
      let result=acc.compactMap{$0.component(total:Double(samples.count),ridge:ridge)}
      if !result.isEmpty {model.components=result}
    }
    return model
  }
  private static func fromLabels(_ samples:[SelectionRGB],_ labels:[Int],count:Int,ridge:Float)->Self? {
    var acc=[SelectionAccumulator](repeating:.init(),count:count)
    for (z,l) in zip(samples,labels) {acc[l].add(z,1)}
    let values=acc.compactMap{$0.component(total:Double(samples.count),ridge:ridge)}
    return values.isEmpty ? nil:.init(components:values,ridge:ridge)
  }
  func refit(_ samples:[SelectionRGB])throws->Self? {
    try Task.checkCancellation()
    let labels=samples.map{z in var best=0,value = -Double.greatestFiniteMagnitude;for i in components.indices {let v=components[i].logWeighted(z);if v>value{best=i;value=v}};return best}
    return Self.fromLabels(samples,labels,count:components.count,ridge:ridge)
  }
  func logProbability(_ z:SelectionRGB)->Double {
    let values=components.prefix(16).map{$0.logWeighted(z)},mx=values.max()!
    return mx+log(values.reduce(0){$0+exp($1-mx)})
  }
  func cost(_ z:SelectionRGB)->Float {Float(min(200,max(-50,-logProbability(z))))}
  static func broad()throws->Self {
    let corners=(0..<8).map{SelectionRGB(Float($0&1),Float(($0>>1)&1),Float(($0>>2)&1))}
    return try fit(corners,count:1,ridge:0)!
  }
  private static func nearest(_ centers:[SelectionRGB],_ z:SelectionRGB)->Int {
    var best=0,distance=Float.greatestFiniteMagnitude
    for (i,c) in centers.enumerated() {let d=selectionDistance(c,z);if d<distance {best=i;distance=d}}
    return best
  }
  private static func kmeans(_ samples:[SelectionRGB],count:Int)throws->[SelectionRGB] {
    var rng=SelectionRandom(0x5EED+UInt64(samples.count))
    var centers=[samples[Int(rng.next()%UInt64(samples.count))]]
    var distance=samples.map{selectionDistance($0,centers[0])}
    while centers.count<count {
      try Task.checkCancellation();let total=distance.reduce(0.0){$0+Double($1)}
      if total<=1e-12 {break};var t=Double(rng.unit())*total,pick=samples.count-1
      for i in distance.indices {t-=Double(distance[i]);if t<=0 {pick=i;break}}
      let c=samples[pick];centers.append(c)
      for i in samples.indices {distance[i]=min(distance[i],selectionDistance(samples[i],c))}
    }
    for _ in 0..<10 {
      try Task.checkCancellation();var sums=[SIMD3<Double>](repeating:.zero,count:centers.count),counts=[Int](repeating:0,count:centers.count)
      for z in samples {let i=nearest(centers,z);for c in 0..<3{sums[i][c]+=Double(z[c])};counts[i]+=1}
      let next=centers.indices.filter{counts[$0]>0}.map{i in let v=sums[i]/Double(counts[i]);return SelectionRGB(Float(v.x),Float(v.y),Float(v.z))}
      if next==centers {break};centers=next
    }
    return centers
  }
}
