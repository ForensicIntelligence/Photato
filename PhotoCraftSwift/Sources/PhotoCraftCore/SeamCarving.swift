import Foundation

/// Native port of PhotoCraft's algo/seam.rs (MIT OR Apache-2.0).
/// Deterministic backward-energy seam carving, with source-column tracking for enlargement.
public enum SeamCarving {
  public static let maximumPixels = 16_777_216
  public static let maximumWork: Double = 500_000_000
  public static func validate(width: Int,height: Int,channels: Int,image: [Float],protect: [Float]?,newWidth: Int,newHeight: Int) throws {
    guard (1...60000).contains(width),(1...60000).contains(height),(1...60000).contains(newWidth),(1...60000).contains(newHeight),
      (1...8).contains(channels),width <= maximumPixels/height,newWidth <= maximumPixels/newHeight,newWidth <= maximumPixels/height,
      image.count == width*height*channels,image.allSatisfy(\.isFinite),protect == nil || (protect!.count == width*height && protect!.allSatisfy(\.isFinite))
    else { throw CraftError.invalid("Invalid Content-Aware Scale dimensions or pixels (maximum16 megapixels).") }
    let work = Double(max(width,newWidth))*Double(height)*Double(abs(width-newWidth)) + Double(newWidth)*Double(max(height,newHeight))*Double(abs(height-newHeight))
    guard work <= maximumWork else { throw CraftError.invalid("This Content-Aware Scale exceeds the processing budget. Use a smaller region or a smaller size change.") }
  }
  public static func resize(width: Int,height: Int,channels: Int,image: [Float],protect: [Float]? = nil,newWidth: Int,newHeight: Int,amount: Float = 1,energyChannels: Int? = nil) throws -> [Float] {
    try validate(width:width,height:height,channels:channels,image:image,protect:protect,newWidth:newWidth,newHeight:newHeight)
    let ec = energyChannels ?? channels
    guard amount.isFinite,(0...1).contains(amount),(1...channels).contains(ec) else { throw CraftError.invalid("Invalid Content-Aware Scale amount or channels.") }
    try Task.checkCancellation()
    if width == newWidth && height == newHeight { return image }
    if amount == 0 { return try bilinear(width:width,height:height,channels:channels,image:image,newWidth:newWidth,newHeight:newHeight) }
    let wide = try carveWidth(width,height,channels,ec,image,protect,newWidth)
    var result = wide.image
    if newHeight != height {
      let tall = try carveWidth(height,newWidth,channels,ec,transpose(newWidth,height,channels,wide.image),wide.protect.map { transpose(newWidth,height,1,$0) },newHeight)
      result = transpose(newHeight,newWidth,channels,tall.image)
    }
    if amount < 1 {
      let plain = try bilinear(width:width,height:height,channels:channels,image:image,newWidth:newWidth,newHeight:newHeight)
      for i in result.indices { if i % 65536 == 0 { try Task.checkCancellation() }; result[i] = plain[i]+(result[i]-plain[i])*amount }
    }
    guard result.allSatisfy(\.isFinite) else { throw CraftError.invalid("Content-Aware Scale produced non-finite pixels.") }
    return result
  }
  public static func bilinear(width w: Int,height h: Int,channels c: Int,image: [Float],newWidth nw: Int,newHeight nh: Int) throws -> [Float] {
    guard w > 0,h > 0,nw > 0,nh > 0,(1...8).contains(c),w <= maximumPixels/h,nw <= maximumPixels/nh,image.count == w*h*c else { throw CraftError.invalid("Invalid resampling dimensions.") }
    var out = [Float](repeating:0,count:nw*nh*c)
    for y in 0..<nh { try Task.checkCancellation(); let fy = max(0,min(Float(h-1),(Float(y)+0.5)*Float(h)/Float(nh)-0.5)),y0 = Int(floor(fy)),ty = fy-Float(y0),y1 = min(h-1,y0+1)
      for x in 0..<nw { let fx = max(0,min(Float(w-1),(Float(x)+0.5)*Float(w)/Float(nw)-0.5)),x0 = Int(floor(fx)),tx = fx-Float(x0),x1 = min(w-1,x0+1)
        for k in 0..<c { let a = image[(y0*w+x0)*c+k],b = image[(y0*w+x1)*c+k],d = image[(y1*w+x0)*c+k],e = image[(y1*w+x1)*c+k];let top = a+(b-a)*tx,bot = d+(e-d)*tx;out[(y*nw+x)*c+k] = top+(bot-top)*ty }
      }
    }; return out
  }
  public static func skin(_ p: Pixel) -> Float {
    let r = p.r*255,g = p.g*255,b = p.b*255
    return r > 95 && g > 40 && b > 20 && max(r,max(g,b))-min(r,min(g,b)) > 15 && abs(r-g) > 15 && r > g && r > b && p.a > 0 ? 1:0
  }
  private static func transpose(_ w: Int,_ h: Int,_ c: Int,_ img: [Float]) -> [Float] {
    var out = img
    for y in 0..<h { for x in 0..<w { for k in 0..<c { out[(x*h+y)*c+k] = img[(y*w+x)*c+k] } } };return out
  }
  private struct Carver {
    let stride: Int,h: Int,c: Int,ec: Int
    var width: Int,image: [Float],protect: [Float]?,energy: [Float],indices: [Int]?
    init(_ w: Int,_ h: Int,_ c: Int,_ ec: Int,_ image: [Float],_ protect: [Float]?,track: Bool) throws {
      self.stride = w;self.width = w;self.h = h;self.c = c;self.ec = ec;self.image = image;self.protect = protect;energy = .init(repeating:0,count:w*h);indices = track ? (0..<w*h).map { $0%w }:nil
      for y in 0..<h { try Task.checkCancellation(); for x in 0..<w { energy[y*w+x] = value(x,y) } }
    }
    func value(_ x: Int,_ y: Int) -> Float {
      let xl = max(0,x-1),xr = min(width-1,x+1),yu = max(0,y-1),yd = min(h-1,y+1); var e: Float = 0
      for k in 0..<ec { let v = image[(y*stride+x)*c+k];e += abs(image[(y*stride+xr)*c+k]-v)+abs(v-image[(y*stride+xl)*c+k]);e += abs(image[(yd*stride+x)*c+k]-v)+abs(v-image[(yu*stride+x)*c+k]) }
      return e*0.5+unit(protect?[y*stride+x] ?? 0)*10000
    }
    mutating func remove() throws -> [Int] {
      try Task.checkCancellation();var cost = Array(energy[0..<width]),next = cost,from = [Int8](repeating:0,count:width*h)
      for y in 1..<h { try Task.checkCancellation(); for x in 0..<width {
        var best = cost[x],direction: Int8 = 0
        if x > 0 && cost[x-1] < best { best = cost[x-1];direction = -1 }
        if x+1 < width && cost[x+1] < best { best = cost[x+1];direction = 1 }
        next[x] = best+energy[y*stride+x];from[y*width+x] = direction
      };swap(&cost,&next) }
      var x = 0;for i in 1..<width where cost[i] < cost[x] { x = i }
      var seam = [Int](repeating:0,count:h)
      for y in (0..<h).reversed() { seam[y] = x;if y > 0 { x += Int(from[y*width+x]) } }
      let removed = (0..<h).map { indices?[$0*stride+seam[$0]] ?? seam[$0] }
      for y in 0..<h { try Task.checkCancellation();let sx = seam[y];if sx+1 < width { for xx in sx..<(width-1) {
        let a = y*stride+xx,b = a+1;for k in 0..<c { image[a*c+k] = image[b*c+k] };energy[a] = energy[b]
        if protect != nil { protect![a] = protect![b] };if indices != nil { indices![a] = indices![b] }
      } } }
      width -= 1
      if width > 0 { for y in 0..<h { let near = seam[max(0,y-1)...min(h-1,y+1)],lo = max(0,near.min()!-1),hi = min(width-1,near.max()!);if lo <= hi { for xx in lo...hi { energy[y*stride+xx] = value(xx,y) } } } }
      return removed
    }
    func packed() -> (image:[Float],protect:[Float]?) {
      var out = [Float]();out.reserveCapacity(width*h*c);var p: [Float]? = protect == nil ? nil:[]
      for y in 0..<h { out.append(contentsOf:image[(y*stride*c)..<(y*stride*c+width*c)]);if let protect { p!.append(contentsOf:protect[(y*stride)..<(y*stride+width)]) } };return (out,p)
    }
  }
  private static func carveWidth(_ w: Int,_ h: Int,_ c: Int,_ ec: Int,_ image: [Float],_ protect: [Float]?,_ nw: Int) throws -> (image:[Float],protect:[Float]?) {
    if nw == w { return (image,protect) }
    if nw < w { var carver = try Carver(w,h,c,ec,image,protect,track:false);while carver.width > nw { _ = try carver.remove() };return carver.packed() }
    var current = image,protection = protect,width = w
    while width < nw {
      let k = min(nw-width,max(1,width/2));var carver = try Carver(width,h,c,ec,current,protection,track:true),duplicates = [[Int]](repeating:[],count:h)
      for _ in 0..<k { let seam = try carver.remove();for y in 0..<h { duplicates[y].append(seam[y]) } }
      var out = [Float]();out.reserveCapacity((width+k)*h*c);var newProtection: [Float]? = protection == nil ? nil:[]
      for y in 0..<h { try Task.checkCancellation();duplicates[y].sort();var d = 0
        for x in 0..<width { let base = (y*width+x)*c;out.append(contentsOf:current[base..<(base+c)]);if let protection { newProtection!.append(protection[y*width+x]) }
          if d < k && duplicates[y][d] == x { let right = (y*width+min(width-1,x+1))*c;for i in 0..<c { out.append((current[base+i]+current[right+i])*0.5) };if let protection { newProtection!.append(protection[y*width+x]) };d += 1 }
        }
      };current = out;protection = newProtection;width += k
    };return (current,protection)
  }
}
