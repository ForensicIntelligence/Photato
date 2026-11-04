import CoreGraphics
import Foundation

/// Palette/one-bit modes use RestrictedModeRaster rather than component planes.
public enum DocumentColorMode:String,Codable,CaseIterable,Sendable {
  case rgb,grayscale,cmyk,lab,indexed,bitmap,duotone,multichannel
  public static let componentModes: [Self] = [.rgb, .grayscale, .cmyk, .lab]
  public var isRestricted: Bool { self == .indexed || self == .bitmap }
  public var isInkMode: Bool { self == .duotone || self == .multichannel }
  public var title:String {switch self {case .rgb:"RGB Color";case .grayscale:"Grayscale";case .cmyk:"CMYK Color";case .lab:"Lab Color";case .indexed:"Indexed Color";case .bitmap:"Bitmap";case .duotone:"Duotone";case .multichannel:"Multichannel"}}
  public var componentNames:[String] {switch self {case .rgb:["Red","Green","Blue"];case .grayscale:["Gray"];case .cmyk:["Cyan","Magenta","Yellow","Black"];case .lab:["Lightness","a","b"];case .indexed:["Index"];case .bitmap:["Bitmap"];case .duotone:["Duotone"];case .multichannel:[]}}
  public var componentCount:Int {componentNames.count}
  /// Bitmap has no component depth; its display cache is RGB8, its storage is1-bit.
  public var depths:[PixelDepth] {self == .bitmap ? [] : self == .indexed || self == .duotone ? [.u8] : self == .rgb || self == .grayscale ? PixelDepth.allCases:[.u8,.u16]}
  public var profileSignature:String {switch self {case .rgb,.indexed:"RGB ";case .grayscale,.bitmap,.duotone:"GRAY";case .cmyk:"CMYK";case .lab:"Lab ";case .multichannel:""}}
  var cgModel:CGColorSpaceModel {switch self {case .rgb,.indexed:.rgb;case .grayscale,.bitmap,.duotone:.monochrome;case .cmyk:.cmyk;case .lab:.lab;case .multichannel:.unknown}}
}

public enum ModeRenderingIntent:String,Codable,CaseIterable,Sendable {
  case perceptual,relativeColorimetric,saturation,absoluteColorimetric
  var cgIntent:CGColorRenderingIntent {switch self {case .perceptual:.perceptual;case .relativeColorimetric:.relativeColorimetric;case .saturation:.saturation;case .absoluteColorimetric:.absoluteColorimetric}}
}

/// ColorSync profiles are retained with the components they describe.
public enum NativeModeProfile {
  // ColorSync synthesizes generic Lab with a fresh creation timestamp. Retain
  // the first system profile so identical default requests in this process do
  // not acquire different metadata merely by crossing a clock-second boundary.
  // Explicit imported/custom profiles never pass through this cache.
  private static let standardLabProfile: Data? = {
    CGColorSpace(name: CGColorSpace.genericLab)?.copyICCData() as Data?
  }()
  public static func atDepth(_ data: Data, mode: DocumentColorMode, depth: PixelDepth) throws -> Data {
    try validate(data, mode: mode, depth: .u16)
    if depth != .f32 || (try? validate(data, mode: mode, depth: depth)) != nil { return data }
    guard let space = CGColorSpace(iccData: data as CFData),
      let linear = CGColorSpaceCreateLinearized(space), let bytes = linear.copyICCData() as Data? else {
      throw CraftError.unsupported("The working profile cannot be linearized for 32-bit storage.")
    }
    try validate(bytes, mode: mode, depth: depth)
    return bytes
  }
  public static func standard(_ mode:DocumentColorMode,depth:PixelDepth)throws->Data {
    guard mode.depths.contains(depth) else{throw CraftError.unsupported("\(mode.title) does not support32-bit components.")}
    let name:CFString
    switch mode {
    case .rgb:name=depth == .f32 ? CGColorSpace.linearSRGB:CGColorSpace.sRGB
    case .grayscale:name=depth == .f32 ? CGColorSpace.linearGray:CGColorSpace.genericGrayGamma2_2
    case .cmyk:name=CGColorSpace.genericCMYK
    case .lab:name=CGColorSpace.genericLab
    case .indexed,.bitmap,.duotone,.multichannel:throw CraftError.invalid("This mode requires its own palette, bit or ink storage, not component profiles.")
    }
    guard let bytes = mode == .lab ? standardLabProfile : CGColorSpace(name:name)?.copyICCData() as Data? else{throw CraftError.unsupported("The system color profile is unavailable.")}
    try validate(bytes,mode:mode,depth:depth);return bytes
  }
  public static func validate(_ data:Data,mode:DocumentColorMode,depth:PixelDepth)throws {
    guard DocumentColorMode.componentModes.contains(mode),mode.depths.contains(depth),data.count>=132,data.count<=ICCProfile.maximumBytes else{throw CraftError.invalid("Invalid document mode/profile size or depth.")}
    func n(_ i:Int)->Int {data[i..<i+4].reduce(0){($0<<8)|Int($1)}}
    func text(_ i:Int)->String {String(decoding:data[i..<i+4],as:UTF8.self)}
    guard n(0)==data.count,text(16)==mode.profileSignature,text(36)=="acsp",["XYZ ","Lab "].contains(text(20)),[2,4].contains(data[8]),n(128)<=ICCProfile.maximumTags,n(128)<=(data.count-132)/12 else{throw CraftError.invalid("ICC profile does not match the document mode.")}
    let end=132+n(128)*12;var tags=[String:Range<Int>]()
    for i in stride(from:132,to:end,by:12) {
      let start=n(i+4),size=n(i+8),key=text(i)
      guard start>=end,start%4==0,size>=8,start<=data.count,size<=data.count-start,tags[key]==nil else{throw CraftError.invalid("Invalid mode ICC tag table.")}
      tags[key]=start..<start+size
    }
    if depth == .f32 {
      if mode == .rgb {try ICCProfile.validate(data,linear:true)}
      else {
        guard let curve=tags["kTRC"],curve.count>=12 else{throw CraftError.unsupported("Gray32 requires a linear gray ICC profile.")}
        let i=curve.lowerBound,type=text(i)
        let linear=(type=="curv" && (n(i+8)==0 || (n(i+8)==1 && curve.count>=14 && data[i+12]==1 && data[i+13]==0))) || (type=="para" && curve.count>=16 && data[i+8]==0 && data[i+9]==0 && n(i+12)==65536)
        guard linear else{throw CraftError.unsupported("Gray32 requires a linear gray ICC profile.")}
      }
    }
    guard let space=CGColorSpace(iccData:data as CFData),space.model==mode.cgModel,space.numberOfComponents==mode.componentCount else{throw CraftError.invalid("ColorSync cannot use the mode profile.")}
  }
}

/// An operation owns its ColorSync objects; no mutable transform is shared across tasks.
struct NativeModeTransform {
  let mode:DocumentColorMode
  let depth:PixelDepth
  let profile:Data
  let space:CGColorSpace
  let rgb:CGColorSpace
  let intent:CGColorRenderingIntent
  init(mode:DocumentColorMode,depth:PixelDepth,profile:Data?=nil,intent:ModeRenderingIntent = .relativeColorimetric,rgbProfile:Data?=nil,rgbDepth:PixelDepth?=nil)throws {
    let data=try profile ?? NativeModeProfile.standard(mode,depth:depth)
    try NativeModeProfile.validate(data,mode:mode,depth:depth)
    let inputDepth=rgbDepth ?? depth
    let inputProfile=try rgbProfile ?? NativeModeProfile.standard(.rgb,depth:inputDepth)
    try NativeModeProfile.validate(inputProfile,mode:.rgb,depth:inputDepth)
    guard let retained=CGColorSpace(iccData:data as CFData),let input=CGColorSpace(iccData:inputProfile as CFData),let rgb=inputDepth == .f32 ? CGColorSpaceCreateExtended(input):input,let native=depth == .f32 ? CGColorSpaceCreateExtended(retained):retained else{throw CraftError.invalid("Mode color conversion is unavailable.")}
    self.mode=mode;self.depth=depth;self.profile=data;space=native;self.rgb=rgb;self.intent=intent.cgIntent
  }
  /// RGB is linear when depth is32. Native Lab stores L/100 and (a+128)/255.
  /// ICC-loaded CGColorSpace maps its reported [-128,127] chroma range onto
  /// ColorSync's normalized a/256+0.5. Reconcile both scales at the boundary;
  /// CGColorSpace.genericLab reports physical Lab directly and differs here.
  func components(_ p:Pixel)throws->[Float] {
    guard p.isFinite,(0...1).contains(p.a) else{throw CraftError.invalid("Invalid mode source pixel.")}
    if mode == .rgb,space==rgb{return [p.r,p.g,p.b,p.a]}
    guard let input=CGColor(colorSpace:rgb,components:[CGFloat(p.r),CGFloat(p.g),CGFloat(p.b),CGFloat(p.a)]),let converted=input.converted(to:space,intent:intent,options:nil)?.components,converted.count==mode.componentCount+1 else{throw CraftError.invalid("ColorSync mode conversion failed.")}
    var values=converted.map{Float($0)};values[mode.componentCount]=p.a
    if mode == .lab {values[0]/=100;values[1]=(values[1]+128)*256/(255*255);values[2]=(values[2]+128)*256/(255*255)}
    guard values.allSatisfy(\.isFinite) else{throw CraftError.invalid("Non-finite mode conversion result.")};return values
  }
  func pixel(_ components:[Float])throws->Pixel {
    guard components.count==mode.componentCount+1,components.allSatisfy(\.isFinite) else{throw CraftError.invalid("Invalid native color components.")}
    let alpha=components[mode.componentCount]
    if mode == .rgb,space==rgb{return Pixel(components[0],components[1],components[2],alpha)}
    var values=components.map{CGFloat($0)}
    if mode == .lab {values[0]*=100;values[1]=values[1]*(255*255)/256-128;values[2]=values[2]*(255*255)/256-128}
    guard let color=CGColor(colorSpace:space,components:values),let converted=color.converted(to:rgb,intent:intent,options:nil)?.components,converted.count==4 else{throw CraftError.invalid("ColorSync display conversion failed.")}
    let p=Pixel(Float(converted[0]),Float(converted[1]),Float(converted[2]),alpha)
    guard p.isFinite else{throw CraftError.invalid("Non-finite mode display result.")};return p
  }
}

/// Authoritative planar mode samples, including a separate alpha plane.
/// The RGB Surface produced for existing tools is a derived display/editing cache.
public struct NativeModeRaster:Codable,Equatable,Sendable {
  public static let maximumPixels=8_388_608
  public let width:Int
  public let height:Int
  public let mode:DocumentColorMode
  public let depth:PixelDepth
  public let profile:Data
  public let intent:ModeRenderingIntent
  private var componentStorage: [ComponentPlane]
  /// Legacy portable planes; application/codec admission remains8MP.
  public var planes: [Data] { componentStorage.map(\.legacyBytes) }
  public var residentComponentEditBytes: Int { componentStorage.reduce(0) { $0 + $1.residentEditBytes } }
  public func rawWord(component: Int, index: Int) -> UInt32 {
    componentStorage.indices.contains(component) ? componentStorage[component].word(at: index) : 0
  }
  public func planeBytes(_ component: Int) throws -> Data {
    guard componentStorage.indices.contains(component) else { throw CraftError.invalid("Native component not found.") }
    return componentStorage[component].legacyBytes
  }
  public var isOpaque: Bool {
    componentStorage[mode.componentCount].allWordsEqual(depth == .u8 ? 255 : depth == .u16 ? 65535 : Float(1).bitPattern)
  }
  public var bytesPerSample:Int {depth == .u8 ? 1:depth == .u16 ? 2:4}
  public var estimatedBytes:Int {profile.count + width * height * bytesPerSample * (mode.componentCount + 1)}
  private static func dimensions(_ w:Int,_ h:Int,mode:DocumentColorMode,depth:PixelDepth)throws {
    guard w>0,h>0,w<=Surface.maxDimension,h<=Surface.maxDimension,w<=maximumPixels/h,mode.depths.contains(depth) else{throw CraftError.unsupported("Native mode storage supports up to8,388,608 pixels; CMYK/Lab require8 or16 bits.")}
  }
  public init(width:Int,height:Int,mode:DocumentColorMode,depth:PixelDepth,profile:Data?=nil,intent:ModeRenderingIntent = .relativeColorimetric)throws {
    try Self.dimensions(width,height,mode:mode,depth:depth)
    let profile=try profile ?? NativeModeProfile.standard(mode,depth:depth);try NativeModeProfile.validate(profile,mode:mode,depth:depth)
    self.width=width;self.height=height;self.mode=mode;self.depth=depth;self.profile=profile;self.intent=intent
    componentStorage = try (0...mode.componentCount).map { _ in try ComponentPlane(width: width, height: height, depth: depth) }
  }
  /// Reinterpret identical component bytes; assignment never runs a color transform.
  public func assigning(profile: Data, intent: ModeRenderingIntent? = nil) throws -> Self {
    var result = try Self(width: width, height: height, mode: mode, depth: depth, profile: profile, intent: intent ?? self.intent)
    result.componentStorage = componentStorage; return result
  }
  public func validate()throws {
    try Self.dimensions(width,height,mode:mode,depth:depth);try NativeModeProfile.validate(profile,mode:mode,depth:depth)
    guard componentStorage.count == mode.componentCount + 1,
      componentStorage.allSatisfy({ $0.width == width && $0.height == height && $0.depth == depth }) else { throw CraftError.invalid("Native mode plane dimensions do not match.") }
    if depth == .f32 {
      for c in componentStorage.indices {
        func check(_ word: UInt32) throws {
          let value = Float(bitPattern: word)
          guard value.isFinite, c != mode.componentCount || (0...1).contains(value) else { throw CraftError.invalid("Invalid floating-point mode component.") }
        }
        try check(componentStorage[c].defaultWord)
        for range in componentStorage[c].storedSampleRanges {
          try Task.checkCancellation()
          for i in range { try check(componentStorage[c].word(at: i)) }
        }
      }
    }
  }
  public func value(component:Int,index:Int)->Float {
    let word = rawWord(component: component, index: index)
    return depth == .f32 ? Float(bitPattern: word) : Float(word) / (depth == .u8 ? 255 : 65535)
  }
  public func components(index:Int)->[Float] {(0...mode.componentCount).map{value(component:$0,index:index)}}
  public mutating func set(_ value:Float,component:Int,index:Int)throws {
    guard componentStorage.indices.contains(component),(0..<width*height).contains(index),value.isFinite,component != mode.componentCount || (0...1).contains(value) else{throw CraftError.invalid("Invalid native component write.")}
    componentStorage[component].setValidatedWord(Self.word(value, depth: depth), at: index)
  }
  private static func word(_ value: Float, depth: PixelDepth) -> UInt32 {
    depth == .f32 ? value.bitPattern : UInt32((unit(value) * (depth == .u8 ? 255 : 65535)).rounded())
  }
  private mutating func setDefaults(_ values: [Float]) throws {
    guard values.count == mode.componentCount + 1, values.allSatisfy(\.isFinite), (0...1).contains(values[mode.componentCount]) else { throw CraftError.invalid("Invalid component defaults.") }
    componentStorage = try values.map { try ComponentPlane(width: width, height: height, depth: depth, defaultWord: Self.word($0, depth: depth)) }
  }
  /// Merge at most five ordered block streams without a whole-plane key Set.
  private func forEachStoredIndex(_ body: (Int) throws -> Void) throws {
    try Task.checkCancellation()
    var iterators = componentStorage.map { $0.storedSampleRanges.makeIterator() }
    var ranges: [Range<Int>?] = iterators.indices.map { iterators[$0].next() }
    while let start = ranges.compactMap({ $0?.lowerBound }).min() {
      try Task.checkCancellation()
      for i in start..<min(width * height, start + ComponentPlane.blockSamples) { try body(i) }
      for c in ranges.indices where ranges[c]?.lowerBound == start { ranges[c] = iterators[c].next() }
    }
  }
  private static func forEachStoredPixel(_ surfaces: [Surface], _ body: (Int, Int) throws -> Void) throws {
    try Task.checkCancellation()
    let source = surfaces[0], columns = (source.width + Surface.tileSide - 1) / Surface.tileSide
    var iterators = surfaces.map { $0.storedTileKeys.makeIterator() }
    var keys: [Int?] = iterators.indices.map { iterators[$0].next() }
    while let key = keys.compactMap({ $0 }).min() {
      try Task.checkCancellation()
      let left = key % columns * Surface.tileSide, top = key / columns * Surface.tileSide
      for y in top..<min(source.height, top + Surface.tileSide) { for x in left..<min(source.width, left + Surface.tileSide) { try body(x, y) } }
      for c in keys.indices where keys[c] == key { keys[c] = iterators[c].next() }
    }
  }
  public static func converting(_ source:Surface,to mode:DocumentColorMode,depth:PixelDepth?=nil,profile:Data?=nil,intent:ModeRenderingIntent = .relativeColorimetric,sourceProfile:Data?=nil)throws->Self {
    let depth=depth ?? source.depth;var result=try Self(width:source.width,height:source.height,mode:mode,depth:depth,profile:profile,intent:intent)
    // Integer-document composites use unquantized Float32 buffers in encoded
    // working coordinates. Floating storage alone does not make those samples linear.
    let linear = source.depth == .f32 && source.colorEncoding == .linearRGB
    let inputDepth: PixelDepth = linear ? .f32 : source.depth == .f32 ? .u16 : source.depth
    let transform=try NativeModeTransform(mode:mode,depth:depth,profile:result.profile,intent:intent,rgbProfile:sourceProfile,rgbDepth:inputDepth)
    let fallback = linear ? try source.interpretingSamples(as: .sRGB).defaultPixel : source.defaultPixel
    try result.setDefaults(transform.components(fallback))
    try forEachStoredPixel([source]) { x, y in
      let p = linear ? source.linearPixel(x: x, y: y) : source.pixel(x: x, y: y)
      let values = try transform.components(p), i = y * source.width + x
      for c in values.indices { try result.set(values[c], component: c, index: i) }
    }
    return result
  }
  /// Convert retained components directly; routing CMYK/Lab through an RGB display
  /// cache would lose out-of-gamut colors and independent ink separations.
  public func converted(to target:DocumentColorMode,depth outputDepth:PixelDepth,profile outputProfile:Data?=nil,intent outputIntent:ModeRenderingIntent = .relativeColorimetric)throws->Self {
    try validate()
    let profile=try outputProfile ?? NativeModeProfile.standard(target,depth:outputDepth)
    if target==mode,outputDepth==depth,profile==self.profile,outputIntent==intent{return self}
    var result=try Self(width:width,height:height,mode:target,depth:outputDepth,profile:profile,intent:outputIntent)
    let from=try NativeModeTransform(mode:mode,depth:depth,profile:self.profile,intent:outputIntent)
    let to=try NativeModeTransform(mode:target,depth:outputDepth,profile:profile,intent:outputIntent)
    func convert(_ input: [Float]) throws -> [Float] {
      var output: [Float] = []
      var values=input.map{CGFloat($0)}
      if mode == .lab {values[0]*=100;values[1]=values[1]*(255*255)/256-128;values[2]=values[2]*(255*255)/256-128}
      guard let color=CGColor(colorSpace:from.space,components:values),let converted=color.converted(to:to.space,intent:outputIntent.cgIntent,options:nil)?.components,converted.count==target.componentCount+1 else{throw CraftError.invalid("Native component conversion failed.")}
      for c in 0..<target.componentCount {
        var value=Float(converted[c]);if target == .lab{value=c==0 ? value/100:(value+128)*256/(255*255)}
        output.append(value)
      }
      output.append(input[mode.componentCount])
      return output
    }
    try result.setDefaults(convert(componentStorage.indices.map { c in
      let word = componentStorage[c].defaultWord
      return depth == .f32 ? Float(bitPattern: word) : Float(word) / (depth == .u8 ? 255 : 65535)
    }))
    try forEachStoredIndex { i in
      let values = try convert(components(index: i))
      for c in values.indices { try result.set(values[c], component: c, index: i) }
    }
    return result
  }
  /// Resample numerical channel values and shared coverage without RGB conversion.
  public func transformed(by transform:Transform2D,bounds:IntRect,method:Resampling,clampEdges:Bool=false)throws->Self {
    let inverse=try transform.inverted()
    var result=try Self(width:bounds.width,height:bounds.height,mode:mode,depth:depth,profile:profile,intent:intent)
    for c in 0..<mode.componentCount {
      var channel=try Surface(width:width,height:height,depth:.f32)
      for y in 0..<height{try Task.checkCancellation();for x in 0..<width{let i=y*width+x,v=value(component:c,index:i);channel.setPixel(x:x,y:y,Pixel(v,v,v,value(component:mode.componentCount,index:i)))}}
      for y in 0..<bounds.height {try Task.checkCancellation();for x in 0..<bounds.width {
        let point=inverse.point(Double(bounds.x+x)+0.5,Double(bounds.y+y)+0.5)
        guard point.x>=0,point.y>=0,point.x<Double(width),point.y<Double(height) else{continue}
        let p=RasterGeometry.sample(channel,x:point.x,y:point.y,method:method,clampEdges:clampEdges),i=y*bounds.width+x
        try result.set(p.r,component:c,index:i)
        if c==0{try result.set(p.a,component:mode.componentCount,index:i)}
      }}
    };return result
  }
  private func defaultComponents() -> [Float] {
    componentStorage.map { depth == .f32 ? Float(bitPattern: $0.defaultWord) : Float($0.defaultWord) / (depth == .u8 ? 255 : 65535) }
  }
  public func surface()throws->Surface {
    try validate(); let transform = try NativeModeTransform(mode: mode, depth: depth, profile: profile, intent: intent)
    let fill = try transform.pixel(defaultComponents())
    var out = try Surface(width: width, height: height, depth: depth, fill: fill)
    if depth == .f32 { out = try out.interpretingSamples(as: .linearRGB) }
    try forEachStoredIndex { i in
      let p = try transform.pixel(components(index: i))
      guard !p.hasSameBits(as: fill) else { return }
      if depth == .f32 { out.setLinearPixel(x: i % width, y: i / width, p) }
      else { out.setPixel(x: i % width, y: i / width, p) }
    }
    return out
  }
  /// Numeric channels retain raw floating values without an RGB transfer.
  public func channel(_ component:Int)throws->Surface {
    try Task.checkCancellation()
    guard (0..<mode.componentCount).contains(component) else{throw CraftError.invalid("Mode component not found.")}
    let value = defaultComponents()[component]
    var out = try Surface(width: width, height: height, depth: depth, fill: Pixel(value, value, value))
    for range in componentStorage[component].storedSampleRanges {
      try Task.checkCancellation()
      for i in range { let v = self.value(component: component, index: i); if v.bitPattern != value.bitPattern { out.setPixel(x: i % width, y: i / width, Pixel(v, v, v)) } }
    }
    return out
  }
  public func replacingChannel(_ component:Int,with pixels:Surface)throws->Self {
    guard (0..<mode.componentCount).contains(component),pixels.width==width,pixels.height==height,pixels.depth==depth else{throw CraftError.invalid("Mode channel layout differs.")}
    var result = self
    result.componentStorage[component] = try ComponentPlane(width: width, height: height, depth: depth, defaultWord: Self.word(pixels.defaultPixel.r, depth: depth))
    try Self.forEachStoredPixel([pixels]) { x, y in
      try result.set(pixels.pixel(x: x, y: y).r, component: component, index: y * width + x)
    }
    return result
  }
  public func cropped(to area:IntRect)throws->Self {
    guard area.width>0,area.height>0,area==area.clipped(toWidth:width,height:height) else{throw CraftError.invalid("Native mode crop is outside its pixels.")}
    var result=try Self(width:area.width,height:area.height,mode:mode,depth:depth,profile:profile,intent:intent)
    result.componentStorage = try componentStorage.map { try ComponentPlane(width: area.width, height: area.height, depth: depth, defaultWord: $0.defaultWord) }
    try forEachStoredIndex { i in
      let x = i % width, y = i / width
      guard x >= area.x, x < area.x + area.width, y >= area.y, y < area.y + area.height else { return }
      for c in componentStorage.indices { result.componentStorage[c].setValidatedWord(rawWord(component: c, index: i), at: (y - area.y) * area.width + x - area.x) }
    }
    return result
  }
  /// Existing RGB algorithms may change their cache. Retain native samples for every
  /// pixel whose cached RGB and alpha are unchanged, including independent black ink.
  public func reconciled(with edited:Surface,previous:Surface)throws->Self {
    guard edited.width==width,edited.height==height,previous.width==width,previous.height==height,edited.depth==depth,previous.depth==depth else{throw CraftError.invalid("Reconcile geometry before native mode samples.")}
    let transform=try NativeModeTransform(mode:mode,depth:depth,profile:profile,intent:intent);var result=self
    func reconcile(_ x: Int, _ y: Int) throws {
      let old=depth == .f32 ? previous.linearPixel(x:x,y:y):previous.pixel(x:x,y:y),p=depth == .f32 ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y)
      if old.hasSameBits(as:p){return};let i=y*width+x
      if old.r.bitPattern != p.r.bitPattern || old.g.bitPattern != p.g.bitPattern || old.b.bitPattern != p.b.bitPattern {
        let values=try transform.components(p);for c in 0..<mode.componentCount {try result.set(values[c],component:c,index:i)}
      }
      if old.a.bitPattern != p.a.bitPattern{try result.set(p.a,component:mode.componentCount,index:i)}
    }
    func cacheDefault(_ surface: Surface) throws -> Pixel {
      if depth != .f32 { return surface.defaultPixel }
      return surface.colorEncoding == .linearRGB ? try surface.interpretingSamples(as: .sRGB).defaultPixel : SRGBTransfer.linear(surface.defaultPixel)
    }
    let oldDefault = try cacheDefault(previous), newDefault = try cacheDefault(edited)
    if oldDefault.hasSameBits(as: newDefault) { try Self.forEachStoredPixel([previous, edited], reconcile) }
    else { for y in 0..<height { try Task.checkCancellation(); for x in 0..<width { try reconcile(x, y) } } }
    return result
  }
  private enum CodingKeys:String,CodingKey {case width,height,mode,depth,profile,intent,planes,planeBlobs}
  public init(from decoder:Decoder)throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    width=try c.decode(Int.self,forKey:.width);height=try c.decode(Int.self,forKey:.height);mode=try c.decode(DocumentColorMode.self,forKey:.mode);depth=try c.decode(PixelDepth.self,forKey:.depth)
    try Self.dimensions(width,height,mode:mode,depth:depth)
    profile=try c.decode(Data.self,forKey:.profile);intent=try c.decode(ModeRenderingIntent.self,forKey:.intent)
    try NativeModeProfile.validate(profile,mode:mode,depth:depth)
    let planeBytes=width*height*(depth == .u8 ? 1:depth == .u16 ? 2:4),total=planeBytes*(mode.componentCount+1)+profile.count
    try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?.reserve(tiles:(total+TileArchive.byteCount-1)/TileArchive.byteCount)
    var decoded: [Data] = []
    if c.contains(.planeBlobs) {
      guard !c.contains(.planes),let context=decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding else{throw CraftError.invalid("Native mode blobs require their archive context.")}
      var values=try c.nestedUnkeyedContainer(forKey:.planeBlobs)
      guard values.count==mode.componentCount+1 else{throw CraftError.invalid("Invalid mode plane count.")}
      while !values.isAtEnd{decoded.append(try context.bytes(values.decode(String.self),maximumBytes:planeBytes))}
    }else{
      var values=try c.nestedUnkeyedContainer(forKey:.planes)
      guard values.count==mode.componentCount+1 else{throw CraftError.invalid("Invalid mode plane count.")}
      while !values.isAtEnd{let p=try values.decode(Data.self);guard p.count==planeBytes else{throw CraftError.invalid("Invalid mode plane size.")};decoded.append(p)}
    }
    let w = width, h = height, d = depth, stride = depth == .u8 ? 1 : depth == .u16 ? 2 : 4
    componentStorage = try decoded.map { bytes in
      guard bytes.count == planeBytes else { throw CraftError.invalid("Invalid mode plane size.") }
      var plane = try ComponentPlane(width: w, height: h, depth: d)
      for y in 0..<h {
        try plane.writeRow(y, bytes: Data(bytes[(y * w * stride)..<((y + 1) * w * stride)]))
      }
      return plane
    }
    try validate()
  }
  public func encode(to encoder:Encoder)throws {
    try validate();var c=encoder.container(keyedBy:CodingKeys.self)
    try c.encode(width,forKey:.width);try c.encode(height,forKey:.height);try c.encode(mode,forKey:.mode);try c.encode(depth,forKey:.depth);try c.encode(profile,forKey:.profile);try c.encode(intent,forKey:.intent)
    if let context=encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {try c.encode(planes.map{try context.storeBytes($0)},forKey:.planeBlobs)}
    else{try c.encode(planes,forKey:.planes)}
  }
}

public extension NativeModeRaster {
  func reframedExactly(bounds:IntRect,background:Pixel? = nil)throws->Self {
    guard (-1_000_000...1_000_000).contains(bounds.x),(-1_000_000...1_000_000).contains(bounds.y) else{throw CraftError.invalid("Invalid component frame origin.")}
    var result=try Self(width:bounds.width,height:bounds.height,mode:mode,depth:depth,profile:profile,intent:intent)
    if let background {
      let fill=try NativeModeTransform(mode:mode,depth:depth,profile:profile,intent:intent).components(depth == .f32 ? SRGBTransfer.linear(background):background)
      try result.setDefaults(fill)
    }
    let x0=max(0,bounds.x),y0=max(0,bounds.y),x1=min(width,bounds.x+bounds.width),y1=min(height,bounds.y+bounds.height)
    if x1>x0,y1>y0 {
      for c in componentStorage.indices { for y in y0..<y1 {
        try Task.checkCancellation()
        try result.componentStorage[c].writeRow(y - bounds.y, x: x0 - bounds.x,
          bytes: componentStorage[c].row(y, x: x0, count: x1 - x0))
      } }
    }
    try result.validate();return result
  }
  func trimBounds(_ options:TrimOptions)throws->IntRect {
    if !options.hasEdges{return .init(x:0,y:0,width:width,height:height)}
    let reference=components(index:options.basis == .bottomRight ? width*height-1:0)
    var x0=width,y0=height,x1=0,y1=0
    for y in 0..<height {try Task.checkCancellation();for x in 0..<width {
      let index=y*width+x
      let keep=options.basis == .transparent ? value(component:mode.componentCount,index:index)>0 : components(index:index) != reference
      if keep {x0=min(x0,x);y0=min(y0,y);x1=max(x1,x+1);y1=max(y1,y+1)}
    }}
    guard x1>x0,y1>y0 else{throw CraftError.invalid("No image content would remain after trimming.")}
    return options.bounds(content:.init(x:x0,y:y0,width:x1-x0,height:y1-y0),width:width,height:height)
  }
}
