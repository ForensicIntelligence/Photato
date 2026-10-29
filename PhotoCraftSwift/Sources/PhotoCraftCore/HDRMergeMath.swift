import Foundation
import Accelerate

/// Native translation of PhotoCraft hdr.rs/photo_util.rs (MIT OR Apache-2.0).
/// Input samples are encoded RGB; output is linear scene radiance. No Adobe kernel claim.
public enum HDRMergeMath {
  public typealias Sample = SIMD4<Float>
  public struct Result: Sendable {
    public var pixels: [Sample]
    public let response: [[Double]]
    public let ghostBase: Int
    public let ghostFraction: Double
    public let stops: Double
  }
  static func luma(_ q: Sample) -> Float { 0.2126*q.x+0.7152*q.y+0.0722*q.z }
  static func hat(_ z: Double) -> Double { max(0,min(z,255-z)) }
  static func at(_ curve: [Double],_ v: Float) -> Double {
    let x = Double(unit(v)*255),i = min(254,Int(x)),t = x-Double(i)
    return curve[i]*(1-t)+curve[i+1]*t
  }
  public static func estimate(_ images: [[Sample]]) throws -> [Double] {
    guard !images.isEmpty else { return [] }
    let means = images.map { image in image.reduce(0.0){$0+Double(luma($1))}/Double(max(1,image.count)) }
    let order = images.indices.sorted{means[$0] < means[$1]};var factors = [Double](repeating:1,count:images.count)
    for k in 1..<order.count {
      try Task.checkCancellation();let a = order[k-1],b = order[k];var ratios = [Double]()
      for i in stride(from:0,to:min(images[a].count,images[b].count),by:7) {
        let la = luma(images[a][i]),lb = luma(images[b][i])
        if images[a][i].w > 0.99,images[b][i].w > 0.99,(0.08..<0.92).contains(la),(0.08..<0.92).contains(lb) { ratios.append(Double(SRGBTransfer.linear(lb)/max(1e-6,SRGBTransfer.linear(la)))) }
      }
      guard !ratios.isEmpty else { throw CraftError.invalid("Cannot estimate relative exposures from these images. Enter manual EV values.") }
      ratios.sort();factors[b] = factors[a]*max(1,ratios[ratios.count/2])
    }
    return factors
  }
  public static func offset(width w: Int,height h: Int,reference: [Float],image: [Float],levels: Int = 5) throws -> SIMD2<Int> {
    guard w > 0,h > 0,reference.count == w*h,image.count == w*h else { throw CraftError.invalid("Invalid HDR alignment image.") }
    if levels <= 0 || w < 16 || h < 16 { return .zero }
    try Task.checkCancellation()
    let nw = max(1,w/2),nh = max(1,h/2)
    func shrink(_ g: [Float]) -> [Float] { (0..<nw*nh).map { i in let x = 2*(i%nw),y = 2*(i/nw);return (g[y*w+x]+g[y*w+min(w-1,x+1)]+g[min(h-1,y+1)*w+x]+g[min(h-1,y+1)*w+min(w-1,x+1)])/4 } }
    let coarse = try offset(width:nw,height:nh,reference:shrink(reference),image:shrink(image),levels:levels-1),current = SIMD2(coarse.x*2,coarse.y*2)
    let rm = reference.sorted()[reference.count/2],im = image.sorted()[image.count/2]
    var best = current,bestError = Double.infinity,bestDistance = Int.max,bestCorrelation = -Double.infinity
    for dy in -1...1 { for dx in -1...1 {
      try Task.checkCancellation();let o = SIMD2(current.x+dx,current.y+dy);var errors = 0,valid = 0
      var sumA = 0.0,sumB = 0.0,squareA = 0.0,squareB = 0.0,product = 0.0,points = 0.0
      for y in 0..<h { let sy = y-o.y;guard sy >= 0,sy < h else { continue }
        for x in 0..<w { let sx = x-o.x;guard sx >= 0,sx < w else { continue };let a = reference[y*w+x],b = image[sy*w+sx]
          let da = Double(a),db = Double(b);sumA += da;sumB += db;squareA += da*da;squareB += db*db;product += da*db;points += 1
          if abs(a-rm) > 4/255,abs(b-im) > 4/255 { valid += 1;if (a > rm) != (b > im) { errors += 1 } }
        }
      }
      guard valid >= max(4,w*h/100) else { continue }
      let error = Double(errors)/Double(valid),distance = o.x*o.x+o.y*o.y
      let covariance = product-sumA*sumB/points,denominator = sqrt(max(0,squareA-sumA*sumA/points)*max(0,squareB-sumB*sumB/points))
      let correlation = denominator > 1e-12 ? covariance/denominator:0
      // Exclusion bands can give adjacent offsets the same bitmap score. Resolve
      // those plateaus using exposure-invariant normalized intensity correlation.
      if error < bestError || (error == bestError && (correlation > bestCorrelation+1e-12 || (abs(correlation-bestCorrelation) <= 1e-12 && distance < bestDistance))) { best = o;bestError = error;bestDistance = distance;bestCorrelation = correlation }
    } }
    return bestError.isFinite ? best:.zero
  }
  static func sampleIndices(_ w: Int,_ h: Int,_ middle: [Sample]) -> [Int] {
    if w < 5 || h < 5 { return Array(middle.indices.prefix(160)) }
    var bins = [[Int]](repeating:[],count:32);let step = max(1,Int(sqrt(Double(w*h)/6400)))
    for y in stride(from:2,to:h-2,by:step) { for x in stride(from:2,to:w-2,by:step) {
      let i = y*w+x,l = luma(middle[i]);if middle[i].w > 0.99,[i-2,i+2,i-2*w,i+2*w].allSatisfy({abs(luma(middle[$0])-l) < 0.04}) { bins[min(31,max(0,Int(l*31.99)))].append(i) }
    } }
    var out = [Int](),k = 0
    while out.count < 160,bins.contains(where:{$0.count > k}) {
      for bin in bins where k < bin.count { out.append(bin[k*7%bin.count]);if out.count == 160 { break } };k += 1
    }
    return Array(Set(out)).sorted()
  }
  public static func responseCurve(_ values: [[UInt8]],logExposures: [Double]) throws -> [Double] {
    let n = values.first?.count ?? 0,size = 256+n
    guard values.count == logExposures.count,values.allSatisfy({$0.count == n}),n <= 160 else { throw CraftError.invalid("Invalid HDR response samples.") }
    try Task.checkCancellation();var a = [Double](repeating:0,count:size*size),b = [Double](repeating:0,count:size)
    func add(_ row: [(Int,Double)],_ rhs: Double,_ weight: Double) {
      let ww = weight*weight
      for (i,x) in row { b[i] += ww*x*rhs;for (j,y) in row { a[i*size+j] += ww*x*y } }
    }
    for j in values.indices { for i in 0..<n { let z = Int(values[j][i]);add([(z,1),(256+i,-1)],logExposures[j],hat(Double(z))+1) } }
    add([(128,1)],0,100)
    for k in 1..<255 { add([(k-1,1),(k,-2),(k+1,1)],0,sqrt(40)*(hat(Double(k))+1)) }
    // Apple LAPACK solves the symmetric normal matrix in native Accelerate. A
    // separate dimension for each inout argument avoids overlapping Swift access.
    var order = __CLPK_integer(size),rhsCount: __CLPK_integer = 1,lda = __CLPK_integer(size),ldb = __CLPK_integer(size),info: __CLPK_integer = 0
    var pivots = [__CLPK_integer](repeating:0,count:size)
    if n >= 4 { dgesv_(&order,&rhsCount,&a,&lda,&pivots,&b,&ldb,&info) }
    guard n >= 4,info == 0,b.allSatisfy(\.isFinite) else {
      return (0..<256).map{log(Double(max(1e-5,SRGBTransfer.linear(Float($0)/255))))-log(Double(SRGBTransfer.linear(128/255)))}
    }
    try Task.checkCancellation();var g = Array(b.prefix(256))
    for k in (0..<128).reversed() { g[k] = min(g[k],g[k+1]-1e-4) }
    for k in 129..<256 { g[k] = max(g[k],g[k-1]+1e-4) };return g
  }
  public static func merge(width w: Int,height h: Int,images: [[Sample]],exposures: [Double],removeGhosts: Bool,ghostBase: Int?) throws -> Result {
    guard w > 0,h > 0,w <= 16_000_000/h,(2...16).contains(images.count),images.allSatisfy({$0.count == w*h}),exposures.count == images.count,exposures.allSatisfy({$0.isFinite && $0 > 0}),ghostBase == nil || images.indices.contains(ghostBase!) else { throw CraftError.invalid("Invalid HDR merge inputs.") }
    try Task.checkCancellation();let count = w*h,logs = exposures.map(log),order = images.indices.sorted{exposures[$0] < exposures[$1]}
    let well = images.map { image in stride(from:0,to:count,by:3).filter{image[$0].w > 0.99 && (0.1..<0.9).contains(luma(image[$0]))}.count }
    let base = ghostBase ?? images.indices.max(by:{well[$0] < well[$1]})!,samples = sampleIndices(w,h,images[order[order.count/2]])
    let validSamples = samples.filter { i in images.allSatisfy{$0[i].w > 0.99} }
    var response = [[Double]]()
    for c in 0..<3 { response.append(try responseCurve(images.map{im in validSamples.map{UInt8((unit(im[$0][c])*255).rounded())}},logExposures:logs)) }
    var output = [Sample](repeating:.zero,count:count),ghost = [Float](repeating:0,count:count)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let i = y*w+x,available = images.indices.filter{images[$0][i].w > 0.99};guard !available.isEmpty else { continue }
      for c in 0..<3 {
        var num = 0.0,den = 0.0
        for j in available { let v = images[j][i][c],wt = hat(Double(unit(v))*255);num += wt*(at(response[c],v)-logs[j]);den += wt }
        let e: Double
        if den > 1e-6 { e = num/den }
        else { let bright = available.reduce(Float(0)){$0+images[$1][i][c]}/Float(available.count) > 0.5
          let j = available.min { bright ? logs[$0] < logs[$1]:logs[$0] > logs[$1] }!;e = at(response[c],images[j][i][c])-logs[j]
        }
        output[i][c] = Float(exp(e))
      };output[i].w = 1
      if removeGhosts,available.count > 1,images[base][i].w > 0.99 {
        var s = 0.0,s2 = 0.0,sw = 0.0
        for j in available { let q = images[j][i],wt = hat(Double(luma(q))*255);if wt < 20 { continue }
          var lr = 0.0;for c in 0..<3 { lr += 0.33*(at(response[c],q[c])-logs[j]) };s += wt*lr;s2 += wt*lr*lr;sw += wt
        }
        if sw > 0 { let mean = s/sw;ghost[i] = sqrt(max(0,s2/sw-mean*mean)) > 0.35 ? 1:0 }
      }
    } }
    var fraction = 0.0
    if removeGhosts {
      ghost = try CameraRawMath.gaussian(ghost,w,h,max(2,Float(max(w,h))/200)).map{min(1,$0*3)}
      fraction = Double(ghost.filter{$0 > 0.5}.count)/Double(count)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i = y*w+x
        if ghost[i] > 0,images[base][i].w > 0.99 { for c in 0..<3 { let e = Float(exp(at(response[c],images[base][i][c])-logs[base]));output[i][c] = output[i][c]*(1-ghost[i])+e*ghost[i] } }
      } }
    }
    for c in 0..<3 {
      var ratios = [Double]()
      for i in stride(from:0,to:count,by:37) { let v = images[base][i][c]
        if images[base][i].w > 0.99,(0.15..<0.85).contains(v),output[i][c] > 0 { ratios.append(Double(SRGBTransfer.linear(v))/(Double(output[i][c])*exposures[base])) }
      };ratios.sort();let k = (ratios.isEmpty ? 1:ratios[ratios.count/2])*exposures[base]
      for i in output.indices { output[i][c] = Float(Double(output[i][c])*k) }
    }
    guard output.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}) else { throw CraftError.invalid("HDR response could not be recovered. Try different exposure values or source images.") }
    let luminance = stride(from:0,to:count,by:13).filter{output[$0].w > 0}.map{max(1e-9,luma(output[$0]))}.sorted()
    let stops = luminance.isEmpty ? 0:log2(Double(luminance[min(luminance.count-1,Int(Double(luminance.count)*0.999))])/Double(luminance[luminance.count/100]))
    return Result(pixels:output,response:response,ghostBase:base,ghostFraction:fraction,stops:stops)
  }
}
