import Foundation

public struct ScannedPhoto: Codable, Equatable, Sendable {
  public var centerX: Double
  public var centerY: Double
  public var width: Double
  public var height: Double
  public var angle: Double
  public var area: Double
  public init(centerX: Double, centerY: Double, width: Double, height: Double, angle: Double, area: Double = 0) {
    self.centerX = centerX;self.centerY = centerY;self.width = width;self.height = height;self.angle = angle;self.area = area
  }
  public var corners: [PathPoint] {
    let radians = angle * .pi / 180,c = cos(radians),s = sin(radians)
    return [(-width/2,-height/2),(width/2,-height/2),(width/2,height/2),(-width/2,height/2)].map {x,y in .init(centerX+c*x-s*y,centerY+s*x+c*y)}
  }
}
/// Native Swift port of PhotoCraft algo/scancrop.rs. The algorithm estimates a
/// uniform scanner background, segments by Otsu distance and fits hull rectangles.
/// This establishes licensed-source provenance, not Photoshop detector equality.
public enum ScanCropDetector {
  public static let maximumPixels = 67_108_864
  public static let maximumPhotos = 64
  public static func find(width: Int, height: Int, forceSingle: Bool = false,
                          pixel: (Int,Int) -> Pixel) throws -> [ScannedPhoto] {
    guard width > 0,height > 0,width <= maximumPixels/height else {throw CraftError.invalid("Scan detection supports up to64 megapixels.")}
    try Task.checkCancellation();guard width >= 8,height >= 8 else {return []}
    let k = max(1,(max(width,height)+799)/800),sw = (width+k-1)/k,sh = (height+k-1)/k
    var small = [SIMD3<Float>](repeating:.zero,count:sw*sh),count = [Int](repeating:0,count:sw*sh)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let p = pixel(x,y),i = (y/k)*sw+x/k
        guard p.isFinite,(0...1).contains(p.a) else {throw CraftError.invalid("Scan samples must be finite straight RGBA.")}
        small[i] += p.rgb*p.a + SIMD3(repeating:1-p.a);count[i] += 1
      }
    }
    for i in small.indices {small[i] /= Float(max(1,count[i]))}
    var border: [SIMD3<Float>] = []
    for x in 0..<sw {border.append(small[x]);border.append(small[(sh-1)*sw+x])}
    for y in 0..<sh {border.append(small[y*sw]);border.append(small[y*sw+sw-1])}
    var bg = SIMD3<Float>.zero
    for c in 0..<3 {let values = border.map{$0[c]}.sorted();bg[c] = values[values.count/2]}
    let distances = small.map {p -> Float in let d = p-bg;return (d.x*d.x+d.y*d.y+d.z*d.z).squareRoot()/Float(3).squareRoot()}
    let threshold = max(Float(0.04),otsu(distances)),radius = max(1,max(sw,sh)/200)
    var mask = distances.map{$0 > threshold}
    mask = try morph(width:sw,height:sh,values:morph(width:sw,height:sh,values:mask,radius:radius,dilate:true),radius:radius,dilate:false)
    mask = try morph(width:sw,height:sh,values:morph(width:sw,height:sh,values:mask,radius:1,dilate:false),radius:1,dilate:true)
    var visited = [Bool](repeating:false,count:mask.count),components: [[Int]] = []
    for start in mask.indices where mask[start] && !visited[start] {
      try Task.checkCancellation()
      var stack = [start],component: [Int] = [];visited[start] = true
      while let i = stack.popLast() {
        if component.count % 4096 == 0 {try Task.checkCancellation()};component.append(i)
        let x = i%sw,y = i/sw
        for dy in -1...1 {for dx in -1...1 {
          let xx = x+dx,yy = y+dy
          if xx >= 0,yy >= 0,xx < sw,yy < sh {
            let j = yy*sw+xx
            if mask[j],!visited[j] {visited[j] = true;stack.append(j)}
          }
        }}
      }
      if Double(component.count) > Double(sw*sh)*0.01 {components.append(component)}
    }
    if forceSingle,!components.isEmpty {components = [components.flatMap{$0}]}
    guard components.count <= maximumPhotos else {throw CraftError.unsupported("Choose a selection containing at most64 photographs.")}
    var result: [ScannedPhoto] = []
    for component in components {
      try Task.checkCancellation();var points: [PathPoint] = []
      for i in component {
        let x = i%sw,y = i/sw
        if x == 0 || y == 0 || x+1 == sw || y+1 == sh || !mask[i-1] || !mask[i+1] || !mask[i-sw] || !mask[i+sw] {
          let xx = Double(x*k),yy = Double(y*k),step = Double(k)
          points += [.init(xx,yy),.init(xx+step,yy),.init(xx,yy+step),.init(xx+step,yy+step)]
        }
      }
      var photo = try minimumRectangle(hull(points));photo.width = max(1,photo.width-2*Double(k));photo.height = max(1,photo.height-2*Double(k));photo.area = Double(component.count)/Double(sw*sh);result.append(photo)
    }
    let band = max(1,result.map{min($0.width,$0.height)}.min() ?? 1)/3
    result.sort {a,b in let ay = floor(a.centerY/band),by = floor(b.centerY/band);return ay == by ? a.centerX < b.centerX:ay < by}
    return result
  }
  private static func otsu(_ values: [Float]) -> Float {
    var histogram = [Double](repeating:0,count:256)
    for x in values {histogram[Int(min(1,max(0,x))*255)] += 1}
    let total = histogram.reduce(0,+),sum = histogram.enumerated().reduce(0){$0+Double($1.offset)*$1.element}
    var wb = 0.0,sb = 0.0,best = 0.0,threshold = 0
    for (i,h) in histogram.enumerated() {
      wb += h;if wb == 0 {continue};let wf = total-wb;if wf == 0 {break};sb += Double(i)*h
      let mb = sb/wb,mf = (sum-sb)/wf,between = wb*wf*(mb-mf)*(mb-mf)
      if between > best {best = between;threshold = i}
    }
    return (Float(threshold)+0.5)/255
  }
  private static func morph(width: Int,height: Int,values: [Bool],radius: Int,dilate: Bool) throws -> [Bool] {
    func pass(_ source: [Bool],horizontal: Bool) throws -> [Bool] {
      var output = [Bool](repeating:false,count:source.count)
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          var value = !dilate
          for delta in -radius...radius {
            let xx = horizontal ? x+delta:x,yy = horizontal ? y:y+delta
            let sample = xx >= 0 && yy >= 0 && xx < width && yy < height ? source[yy*width+xx]:false
            value = dilate ? value || sample:value && sample
          }
          output[y*width+x] = value
        }
      }
      return output
    }
    return try pass(pass(values,horizontal:true),horizontal:false)
  }
  private static func hull(_ input: [PathPoint]) -> [PathPoint] {
    let sorted = input.sorted {$0.x == $1.x ? $0.y < $1.y:$0.x < $1.x}
    var points: [PathPoint] = []
    for p in sorted where points.last != p {points.append(p)}
    guard points.count >= 3 else {return points}
    func cross(_ o: PathPoint,_ a: PathPoint,_ b: PathPoint) -> Double {(a.x-o.x)*(b.y-o.y)-(a.y-o.y)*(b.x-o.x)}
    var lower: [PathPoint] = [],upper: [PathPoint] = []
    for p in points {while lower.count >= 2 && cross(lower[lower.count-2],lower[lower.count-1],p) <= 0 {lower.removeLast()};lower.append(p)}
    for p in points.reversed() {while upper.count >= 2 && cross(upper[upper.count-2],upper[upper.count-1],p) <= 0 {upper.removeLast()};upper.append(p)}
    lower.removeLast();upper.removeLast();return lower+upper
  }
  private static func minimumRectangle(_ hull: [PathPoint]) throws -> ScannedPhoto {
    guard hull.count >= 3 else {throw CraftError.invalid("The detected photo has no rectangular area.")}
    var best = Double.greatestFiniteMagnitude,result = ScannedPhoto(centerX:0,centerY:0,width:0,height:0,angle:0)
    for i in hull.indices {
      try Task.checkCancellation()
      let a = hull[i],b = hull[(i+1)%hull.count],theta = atan2(b.y-a.y,b.x-a.x),s = sin(theta),c = cos(theta)
      var x0 = Double.greatestFiniteMagnitude,y0 = x0,x1 = -x0,y1 = -x0
      for p in hull {let u = c*p.x+s*p.y,v = -s*p.x+c*p.y;x0 = min(x0,u);x1 = max(x1,u);y0 = min(y0,v);y1 = max(y1,v)}
      let area = (x1-x0)*(y1-y0)
      if area < best {best = area;let cu = (x0+x1)/2,cv = (y0+y1)/2;result = .init(centerX:c*cu-s*cv,centerY:s*cu+c*cv,width:x1-x0,height:y1-y0,angle:theta*180 / .pi)}
    }
    while result.angle > 45 {result.angle -= 90;swap(&result.width,&result.height)}
    while result.angle < -45 {result.angle += 90;swap(&result.width,&result.height)}
    return result
  }
}
