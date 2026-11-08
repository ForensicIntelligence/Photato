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
  /// Logical component geometry; dense legacy codecs/operations keep their own
  /// maximumPixels admission until their streaming implementations are ready.
  public static let maximumDocumentPixels = Surface.maxPixels
  public let width:Int
  public let height:Int
  public let mode:DocumentColorMode
  public let depth:PixelDepth
  public let profile:Data
  public let intent:ModeRenderingIntent
  private var componentStorage: [ComponentPlane]
  /// Checked legacy export. A large document must use raw rows or native86;
  /// requesting a dense representation must never allocate the logical canvas.
  public var planes: [Data] {
    get throws { try requireDensePlanes(); return componentStorage.map(\.legacyBytes) }
  }
  public var residentComponentEditBytes: Int { componentStorage.reduce(0) { $0 + $1.residentEditBytes } }
  public func rawWord(component: Int, index: Int) -> UInt32 {
    componentStorage.indices.contains(component) ? componentStorage[component].word(at: index) : 0
  }
  public func planeBytes(_ component: Int) throws -> Data {
    guard componentStorage.indices.contains(component) else { throw CraftError.invalid("Native component not found.") }
    try requireDensePlanes()
    return componentStorage[component].legacyBytes
  }
  public func hasAlphaContent() throws -> Bool {
    try componentStorage[mode.componentCount].containsPositiveSample()
  }
  public var isOpaque: Bool {
    componentStorage[mode.componentCount].allWordsEqual(depth == .u8 ? 255 : depth == .u16 ? 65535 : Float(1).bitPattern)
  }
  public var bytesPerSample:Int {depth == .u8 ? 1:depth == .u16 ? 2:4}
  public var logicalSampleBytes: Int { width * height * bytesPerSample * (mode.componentCount + 1) }
  public var mappedComponentSampleBytes: Int { componentStorage.reduce(0) { $0 + $1.mappedSampleBytes } }
  public var mappedComponentIndexBytes: Int { componentStorage.reduce(0) { $0 + $1.mappedIndexBytes } }
  public var mappedComponentVirtualBytes: Int { componentStorage.reduce(0) { $0 + $1.mappedVirtualBytes } }
  public var requiresPagedArchive: Bool { width > Self.maximumPixels / height }
  public var estimatedBytes:Int { profile.count + componentStorage.reduce(0) { $0 + $1.estimatedResidentBytes } }
  private static func requireLegacyDimensions(_ width: Int, _ height: Int) throws {
    guard width > 0, height > 0, width <= maximumPixels / height else { throw CraftError.unsupported("Large component planes require native86 pages.") }
  }
  private func requireDensePlanes() throws {
    guard !requiresPagedArchive else { throw CraftError.unsupported("Dense component export supports up to8,388,608pixels. Save this document as native86 or use bounded component rows.") }
  }
  private static func dimensions(_ w:Int,_ h:Int,mode:DocumentColorMode,depth:PixelDepth)throws {
    guard w>0,h>0,w<=Surface.maxDimension,h<=Surface.maxDimension,w<=maximumDocumentPixels/h,mode.depths.contains(depth) else{throw CraftError.unsupported("Native components support up to300,000pixels per dimension; CMYK/Lab require8 or16 bits.")}
  }
  public init(width:Int,height:Int,mode:DocumentColorMode,depth:PixelDepth,profile:Data?=nil,intent:ModeRenderingIntent = .relativeColorimetric)throws {
    try Self.dimensions(width,height,mode:mode,depth:depth)
    let profile=try profile ?? NativeModeProfile.standard(mode,depth:depth);try NativeModeProfile.validate(profile,mode:mode,depth:depth)
    self.width=width;self.height=height;self.mode=mode;self.depth=depth;self.profile=profile;self.intent=intent
    componentStorage = try (0...mode.componentCount).map { _ in try ComponentPlane(width: width, height: height, depth: depth) }
  }
  /// Numeric RGB interpretation used by component tools; no colour transform.
  public static func retainingRGBSamples(_ pixels: Surface, profile: Data? = nil) throws -> Self {
    var result = try Self(width:pixels.width,height:pixels.height,mode:.rgb,depth:pixels.depth,profile:profile)
    let fill = pixels.depth == .f32 ? (pixels.colorEncoding == .linearRGB ? try pixels.interpretingSamples(as:.sRGB).defaultPixel : SRGBTransfer.linear(pixels.defaultPixel)) : pixels.defaultPixel
    try result.setDefaults([fill.r,fill.g,fill.b,fill.a])
    try forEachStoredPixel([pixels]) { x,y in
      let p = pixels.depth == .f32 ? pixels.linearPixel(x:x,y:y) : pixels.pixel(x:x,y:y)
      for (c,value) in [p.r,p.g,p.b,p.a].enumerated() {try result.set(value,component:c,index:y*pixels.width+x)}
    }
    return result
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
  private func forEachStoredIndex(components:[Int]? = nil,_ body: (Int) throws -> Void) throws {
    try Task.checkCancellation()
    var iterators = (components ?? Array(componentStorage.indices)).map { componentStorage[$0].storedSampleRanges.makeIterator() }
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
  /// Resample numerical components with the shared premultiplied kernel. Source
  /// samples are read directly; bounded scratch candidates replace RGBA planes.
  public func transformed(by transform:Transform2D,bounds:IntRect,method:Resampling,clampEdges:Bool=false)throws->Self {
    try resampled(by:transform,bounds:bounds,method:method,clampEdges:clampEdges,
      scratchMaximumBytes:RasterTileStore.defaultMaximumBytes,directory:nil)
  }
  func resampled(by transform:Transform2D,bounds:IntRect,method:Resampling,clampEdges:Bool,
    scratchMaximumBytes:Int,directory:URL?)throws->Self {
    try Task.checkCancellation();try validate()
    guard (0...RasterTileStore.defaultMaximumBytes).contains(scratchMaximumBytes) else {throw CraftError.invalid("Invalid component geometry scratch budget.")}
    let inverse=try transform.inverted()
    var result=try Self(width:bounds.width,height:bounds.height,mode:mode,depth:depth,profile:profile,intent:intent)
    let budget=ComponentScratchBudget(limit:scratchMaximumBytes)
    func normalized(_ value:Float,alpha:Bool)->UInt32 {Self.word(alpha ? Pixel(0,0,0,value).quantized(.f32).a:value,depth:depth)}
    let defaults=defaultComponents()
    let grid=method == .nearest ? RasterGridMap(transform,inverse:inverse,width:width,height:height,bounds:bounds):nil
    let corners=[inverse.point(Double(bounds.x)+0.5,Double(bounds.y)+0.5),
      inverse.point(Double(bounds.x)+Double(bounds.width)-0.5,Double(bounds.y)+0.5),
      inverse.point(Double(bounds.x)+0.5,Double(bounds.y)+Double(bounds.height)-0.5),
      inverse.point(Double(bounds.x)+Double(bounds.width)-0.5,Double(bounds.y)+Double(bounds.height)-0.5)]
    let complete=method == .nearest && (grid != nil || corners.allSatisfy {$0.x>=0 && $0.y>=0 && $0.x<Double(width) && $0.y<Double(height)})
    if complete {
      result.componentStorage=try componentStorage.indices.map { c in
        try ComponentPlane(width:bounds.width,height:bounds.height,depth:depth,defaultWord:normalized(defaults[c],alpha:c==mode.componentCount))
      }
    }
    let builders=try result.componentStorage.map {try ComponentPlaneBuilder(plane:$0,maximumBytes:scratchMaximumBytes,directory:directory,reserve:budget.reserve)}
    if let grid {
      for c in componentStorage.indices {
        try componentStorage[c].forEachStoredBlock { key,block in
          let start=key*ComponentPlane.blockSamples,valid=min(ComponentPlane.blockSamples,width*height-start)
          for offset in 0..<valid {
            let raw=block.word(offset,stride:bytesPerSample)
            if raw==componentStorage[c].defaultWord {continue}
            let v=depth == .f32 ? Float(bitPattern:raw):Float(raw)/Float(depth == .u8 ? 255:65535)
            let word=normalized(v,alpha:c==mode.componentCount)
            if word==result.componentStorage[c].defaultWord {continue}
            let i=start+offset,d=grid.destination(i%width,i/width)
            try builders[c].setWord(word,at:d.1*bounds.width+d.0)
          }
        }
      }
    } else if method != .nearest && componentStorage[mode.componentCount].allWordsEqual(0) {
      // Every premultiplied sample has zero coverage, including hidden colour.
    } else {
      let supports:[IntRect]
      if complete, let sparse=try projectedComponentSupport(transform,bounds:bounds,maximumBlocks:256) {supports=sparse}
      else {supports=[IntRect(x:0,y:0,width:bounds.width,height:bounds.height)]}
      for c in 0..<mode.componentCount {
        for region in GeometryPatchRegions(width:bounds.width,height:bounds.height,rectangles:supports) {
          for y in region.y..<region.y+region.height {
            try Task.checkCancellation()
            for x in region.x..<region.x+region.width {
              let point=inverse.point(Double(bounds.x)+Double(x)+0.5,Double(bounds.y)+Double(y)+0.5)
              guard point.x>=0,point.y>=0,point.x<Double(width),point.y<Double(height) else {continue}
              let pixel=RasterGeometry.sampleValues(width:width,height:height,x:point.x,y:point.y,method:method,clampEdges:clampEdges) { sx,sy in
                guard sx>=0,sy>=0,sx<width,sy<height else {return .clear}
                let i=sy*width+sx,v=value(component:c,index:i)
                return Pixel(v,v,v,value(component:mode.componentCount,index:i)).quantized(.f32)
              }
              guard pixel.r.isFinite,pixel.a.isFinite else {throw CraftError.invalid("Non-finite component geometry sample.")}
              let i=y*bounds.width+x
              try builders[c].setWord(Self.word(pixel.r,depth:depth),at:i)
              if c==0 {try builders[mode.componentCount].setWord(Self.word(pixel.a,depth:depth),at:i)}
            }
          }
        }
      }
    }
    result.componentStorage=try builders.map {try $0.finish()}
    try result.validate();return result
  }
  /// A bounded sparse support list; dense inputs use complete bounded evaluation.
  private func projectedComponentSupport(_ transform:Transform2D,bounds:IntRect,maximumBlocks:Int)throws->[IntRect]? {
    var ranges:[Range<Int>]=[]
    for plane in componentStorage {
      for range in plane.storedSampleRanges {
        try Task.checkCancellation()
        if ranges.count==maximumBlocks {return nil};ranges.append(range)
      }
    }
    var rectangles:[IntRect]=[]
    func project(_ x:Int,_ y:Int,_ w:Int,_ h:Int) {
      guard w>0,h>0 else {return}
      let p=[transform.point(Double(x),Double(y)),transform.point(Double(x+w),Double(y)),transform.point(Double(x),Double(y+h)),transform.point(Double(x+w),Double(y+h))]
      let x0=max(0,min(Double(bounds.width),floor(p.map(\.x).min()!)-Double(bounds.x)-1))
      let y0=max(0,min(Double(bounds.height),floor(p.map(\.y).min()!)-Double(bounds.y)-1))
      let x1=max(0,min(Double(bounds.width),ceil(p.map(\.x).max()!)-Double(bounds.x)+1))
      let y1=max(0,min(Double(bounds.height),ceil(p.map(\.y).max()!)-Double(bounds.y)+1))
      if x1>x0,y1>y0 {rectangles.append(.init(x:Int(x0),y:Int(y0),width:Int(x1-x0),height:Int(y1-y0)))}
    }
    for range in ranges {
      let first=range.lowerBound/width,last=(range.upperBound-1)/width
      if first==last {project(range.lowerBound%width,first,range.count,1)}
      else {
        project(range.lowerBound%width,first,width-range.lowerBound%width,1)
        if last>first+1 {project(0,first+1,width,last-first-1)}
        project(0,last,(range.upperBound-1)%width+1,1)
      }
    }
    return rectangles
  }
  private func defaultComponents() -> [Float] {
    componentStorage.map { depth == .f32 ? Float(bitPattern: $0.defaultWord) : Float($0.defaultWord) / (depth == .u8 ? 255 : 65535) }
  }
  public func surface(backing:RasterTileStore? = nil)throws->Surface {
    try validate()
    let transform=try NativeModeTransform(mode:mode,depth:depth,profile:profile,intent:intent)
    let fill=try transform.pixel(defaultComponents())
    return try projectedSurface(fill:fill,encoding:depth == .f32 ? .linearRGB:.sRGB,components:Array(componentStorage.indices),backing:backing) {i in
      try transform.pixel(self.components(index:i))
    }
  }
  /// Small local edits keep their direct path. Larger projections scan bounded
  /// component stripes and publish ordered RGB tile patches to immutable scratch.
  private func projectedSurface(fill:Pixel,encoding:SurfaceColorEncoding,components:[Int],backing:RasterTileStore? = nil,
    pixel:(Int)throws->Pixel)throws->Surface {
    var template=try Surface(width:width,height:height,depth:depth,fill:fill)
    template=try template.interpretingSamples(as:encoding)
    var retained=0
    for c in components {
      for _ in componentStorage[c].storedSampleRanges {retained+=1;if retained>32 {break}}
      if retained>32 {break}
    }
    if retained<=32 {
      var out=template
      try forEachStoredIndex(components:components) { i in
        let p=try pixel(i)
        if !p.hasSameBits(as:fill) {
          if encoding == .linearRGB {out.setLinearPixel(x:i%width,y:i/width,p)}
          else {out.setPixel(x:i%width,y:i/width,p)}
        }
      }
      return out
    }
    let builder=try Surface.PagedBuilder(template:template,backing:backing)
    let columns=(width+63)/64
    var iterators=components.map {componentStorage[$0].storedSampleRanges.makeIterator()}
    var ranges=iterators.indices.map {iterators[$0].next()}
    for top in stride(from:0,to:height,by:64) {
      try Task.checkCancellation()
      let bottom=min(height,top+64),start=top*width,end=bottom*width
      var occupied=[Bool](repeating:false,count:columns)
      for slot in components.indices {
        let plane=componentStorage[components[slot]]
        while let range=ranges[slot],range.lowerBound<end {
          if range.upperBound<=start {ranges[slot]=iterators[slot].next();continue}
          for index in max(start,range.lowerBound)..<min(end,range.upperBound) {
            if index%4096==0 {try Task.checkCancellation()}
            if plane.word(at:index) != plane.defaultWord {occupied[(index%width)/64]=true}
          }
          if range.upperBound<=end {ranges[slot]=iterators[slot].next()} else {break}
        }
      }
      var column=0
      while column<columns {
        if !occupied[column] {column+=1;continue}
        var last=column+1
        while last<columns,last-column<32,occupied[last] {last+=1}
        let left=column*64,w=min(width-left,(last-column)*64)
        var patch=try template.reframedImplicitValue(width:w,height:bottom-top)
        for y in top..<bottom {
          try Task.checkCancellation()
          for x in left..<left+w {
            let i=y*width+x
            if components.allSatisfy({componentStorage[$0].word(at:i)==componentStorage[$0].defaultWord}) {continue}
            let p=try pixel(i)
            if !p.hasSameBits(as:fill) {
              if encoding == .linearRGB {patch.setLinearPixel(x:x-left,y:y-top,p)}
              else {patch.setPixel(x:x-left,y:y-top,p)}
            }
          }
        }
        try builder.append(patch,atX:left,atY:top);column=last
      }
    }
    return try builder.finish()
  }
  /// Same numerical view-gray projection as the channel panel, using implicit
  /// fills and retained blocks rather than a whole-canvas loop.
  public func presentingComponents(_ visible: Set<Int>) throws -> Surface {
    let all = Set(0..<mode.componentCount)
    guard !visible.isEmpty, visible.isSubset(of: all) else { throw CraftError.invalid("Invalid visible components.") }
    if visible.count == 1, let c = visible.first {
      func pixel(_ values: [Float]) -> Pixel {
        let gray = mode == .cmyk ? 1 - values[c] : values[c]
        return Pixel(gray, gray, gray, values[mode.componentCount])
      }
      let fill=pixel(defaultComponents())
      return try projectedSurface(fill:fill,encoding:.sRGB,components:[c,mode.componentCount]) {i in pixel(self.components(index:i))}
    }
    var result = self
    for c in all.subtracting(visible) {
      let neutral: Float = mode == .lab && c != 0 ? 128 / 255 : 0
      result.componentStorage[c] = try ComponentPlane(width: width, height: height, depth: depth,
        defaultWord: Self.word(neutral, depth: depth))
    }
    return try result.surface()
  }
  /// Numeric channels retain raw floating values without an RGB transfer.
  public func channel(_ component:Int)throws->Surface {
    guard (0..<mode.componentCount).contains(component) else{throw CraftError.invalid("Mode component not found.")}
    return try numericPlane(component)
  }
  /// Numeric opacity is independent of all color components and their profiles.
  public func opacityChannel() throws -> Surface { try numericPlane(mode.componentCount) }
  private func numericPlane(_ component:Int) throws -> Surface {
    try Task.checkCancellation()
    let value=defaultComponents()[component],fill=Pixel(value,value,value)
    return try projectedSurface(fill:fill,encoding:.sRGB,components:[component]) {i in
      let v=self.value(component:component,index:i);return Pixel(v,v,v)
    }
  }
  public func replacingChannel(_ component:Int,with pixels:Surface)throws->Self {
    guard (0..<mode.componentCount).contains(component) else { throw CraftError.invalid("Mode component not found.") }
    return try replacingNumericPlane(component,with:pixels)
  }
  public func replacingOpacity(with pixels:Surface) throws -> Self {
    let result = try replacingNumericPlane(mode.componentCount,with:pixels)
    try result.validate(); return result
  }
  private func replacingNumericPlane(_ component:Int,with pixels:Surface)throws->Self {
    guard pixels.width==width,pixels.height==height,pixels.depth==depth else{throw CraftError.invalid("Mode channel layout differs.")}
    var result=self
    let plane=try ComponentPlane(width:width,height:height,depth:depth,defaultWord:Self.word(pixels.defaultPixel.r,depth:depth))
    let builder=try ComponentPlaneBuilder(plane:plane)
    try Self.forEachStoredPixel([pixels]) {x,y in
      try builder.setWord(Self.word(pixels.pixel(x:x,y:y).r,depth:depth),at:y*width+x)
    }
    result.componentStorage[component]=try builder.finish()
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
    func reconcile(_ x: Int, _ y: Int, restoring: Bool = false) throws {
      let old=depth == .f32 ? previous.linearPixel(x:x,y:y):previous.pixel(x:x,y:y),p=depth == .f32 ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y)
      let i=y*width+x
      if old.hasSameBits(as:p) {
        if restoring { for c in componentStorage.indices { result.componentStorage[c].setValidatedWord(rawWord(component:c,index:i),at:i) } }
        return
      }
      if old.r.bitPattern != p.r.bitPattern || old.g.bitPattern != p.g.bitPattern || old.b.bitPattern != p.b.bitPattern {
        let values=try transform.components(p);for c in 0..<mode.componentCount {try result.set(values[c],component:c,index:i)}
      } else if restoring {
        for c in 0..<mode.componentCount { result.componentStorage[c].setValidatedWord(rawWord(component:c,index:i),at:i) }
      }
      if old.a.bitPattern != p.a.bitPattern {try result.set(p.a,component:mode.componentCount,index:i)}
      else if restoring { result.componentStorage[mode.componentCount].setValidatedWord(rawWord(component:mode.componentCount,index:i),at:i) }
    }
    func cacheDefault(_ surface: Surface) throws -> Pixel {
      if depth != .f32 { return surface.defaultPixel }
      return surface.colorEncoding == .linearRGB ? try surface.interpretingSamples(as: .sRGB).defaultPixel : SRGBTransfer.linear(surface.defaultPixel)
    }
    let oldDefault = try cacheDefault(previous), newDefault = try cacheDefault(edited)
    if oldDefault.hasSameBits(as: newDefault) { try Self.forEachStoredPixel([previous, edited]) { try reconcile($0, $1) } }
    else {
      let rgbChanged = oldDefault.r.bitPattern != newDefault.r.bitPattern || oldDefault.g.bitPattern != newDefault.g.bitPattern || oldDefault.b.bitPattern != newDefault.b.bitPattern
      var converted = defaultComponents()
      if rgbChanged { converted = try transform.components(newDefault) }
      converted[mode.componentCount] = newDefault.a
      result.componentStorage = try componentStorage.indices.map { c in
        let changed = c == mode.componentCount ? oldDefault.a.bitPattern != newDefault.a.bitPattern : rgbChanged
        return try ComponentPlane(width:width,height:height,depth:depth,defaultWord:changed ? Self.word(converted[c],depth:depth):componentStorage[c].defaultWord)
      }
      try Self.forEachStoredPixel([previous, edited]) { try reconcile($0, $1, restoring:true) }
      try forEachStoredIndex { i in try reconcile(i % width, i / width, restoring:true) }
    }
    return result
  }
  private enum CodingKeys:String,CodingKey {case width,height,mode,depth,profile,intent,planes,planeBlobs,componentPages}
  public init(from decoder:Decoder)throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    width=try c.decode(Int.self,forKey:.width);height=try c.decode(Int.self,forKey:.height);mode=try c.decode(DocumentColorMode.self,forKey:.mode);depth=try c.decode(PixelDepth.self,forKey:.depth)
    try Self.dimensions(width,height,mode:mode,depth:depth)
    profile=try c.decode(Data.self,forKey:.profile);intent=try c.decode(ModeRenderingIntent.self,forKey:.intent)
    try NativeModeProfile.validate(profile,mode:mode,depth:depth)
    if c.contains(.componentPages) {
      guard !c.contains(.planes), !c.contains(.planeBlobs),
        let context = decoder.userInfo[.historyTileDecoder] as? any ComponentBlobDecoding,
        context.supportsComponentPages else { throw CraftError.invalid("Native component pages require a supported archive context.") }
      let budget = decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget
      try budget?.reserve(bytes: profile.count)
      var values = try c.nestedUnkeyedContainer(forKey: .componentPages)
      guard values.count == mode.componentCount + 1 else { throw CraftError.invalid("Invalid native component page plane count.") }
      var components: [ComponentPlane] = []
      while !values.isAtEnd {
        let record = try values.decode(ComponentPlaneArchive.Record.self)
        guard record.width == width, record.height == height, record.depth == depth else { throw CraftError.invalid("Native component page geometry mismatch.") }
        components.append(try ComponentPlaneArchive.decode(record, context: context, budget: budget, alpha: components.count == mode.componentCount))
      }
      componentStorage = components; try validate(); return
    }
    try Self.requireLegacyDimensions(width, height)
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
    if let context = encoder.userInfo[.historyTileEncoder] as? any ComponentBlobEncoding, context.supportsComponentPages {
      try c.encode(componentStorage.map { try ComponentPlaneArchive.encode($0, context: context) }, forKey: .componentPages)
    }
    else if let context=encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {try c.encode(planes.map{try context.storeBytes($0)},forKey:.planeBlobs)}
    else{try c.encode(planes,forKey:.planes)}
  }
}

public extension NativeModeRaster {
  func reframedExactly(bounds:IntRect,background:Pixel? = nil)throws->Self {
    guard (-1_000_000...1_000_000).contains(bounds.x),(-1_000_000...1_000_000).contains(bounds.y) else{throw CraftError.invalid("Invalid component frame origin.")}
    try Self.dimensions(bounds.width,bounds.height,mode:mode,depth:depth)
    if bounds == IntRect(x:0,y:0,width:width,height:height) { return self }
    if bounds.width > 0, bounds.height > 0, bounds == bounds.clipped(toWidth:width,height:height) { return try cropped(to:bounds) }
    var result=try Self(width:bounds.width,height:bounds.height,mode:mode,depth:depth,profile:profile,intent:intent)
    if let background {
      let fill=try NativeModeTransform(mode:mode,depth:depth,profile:profile,intent:intent).components(depth == .f32 ? SRGBTransfer.linear(background):background)
      try result.setDefaults(fill)
    }
    let x0=max(0,min(bounds.width,-bounds.x)),y0=max(0,min(bounds.height,-bounds.y))
    let x1=max(x0,min(bounds.width,width-bounds.x)),y1=max(y0,min(bounds.height,height-bounds.y))
    let inside=IntRect(x:x0,y:y0,width:x1-x0,height:y1-y0)
    let outside=[IntRect(x:0,y:0,width:bounds.width,height:y0),IntRect(x:0,y:y1,width:bounds.width,height:bounds.height-y1),
      IntRect(x:0,y:y0,width:x0,height:y1-y0),IntRect(x:x1,y:y0,width:bounds.width-x1,height:y1-y0)]
    let budget=ComponentScratchBudget()
    var planes:[ComponentPlane]=[]
    for c in componentStorage.indices {
      let source=componentStorage[c],padding=result.componentStorage[c].defaultWord
      let implicit=inside.width*inside.height>bounds.width*bounds.height/2 ? source.defaultWord:padding
      let template=try ComponentPlane(width:bounds.width,height:bounds.height,depth:depth,defaultWord:implicit)
      if inside.width==0 || inside.height==0 {planes.append(template);continue}
      let builder=try ComponentPlaneBuilder(plane:template,reserve:budget.reserve)
      func fill(_ rect:IntRect,_ word:UInt32)throws {
        guard word != implicit,rect.width>0,rect.height>0 else {return}
        for y in rect.y..<rect.y+rect.height {try Task.checkCancellation();for x in rect.x..<rect.x+rect.width {
          try builder.setWord(word,at:y*bounds.width+x)
        }}
      }
      try fill(inside,source.defaultWord)
      for rect in outside {try fill(rect,padding)}
      try source.forEachStoredBlock { key,block in
        let start=key*ComponentPlane.blockSamples,valid=min(ComponentPlane.blockSamples,width*height-start)
        for offset in 0..<valid {
          let i=start+offset,x=i%width-bounds.x,y=i/width-bounds.y
          if x>=0,y>=0,x<bounds.width,y<bounds.height {try builder.setWord(block.word(offset,stride:bytesPerSample),at:y*bounds.width+x)}
        }
      }
      planes.append(try builder.finish())
    }
    result.componentStorage=planes
    try result.validate();return result
  }
  func trimBounds(_ options:TrimOptions)throws->IntRect {
    if !options.hasEdges{return .init(x:0,y:0,width:width,height:height)}
    let reference=components(index:options.basis == .bottomRight ? width*height-1:0)
    let defaults=defaultComponents(),defaultKept=options.basis == .transparent ? defaults[mode.componentCount]>0:defaults != reference
    var x0=width,y0=height,x1=0,y1=0,previous=0
    func include(_ start:Int,_ end:Int) {
      guard end>start else {return}
      let first=start/width,last=(end-1)/width
      if first==last {x0=min(x0,start%width);x1=max(x1,(end-1)%width+1)}
      else {x0=0;x1=width}
      y0=min(y0,first);y1=max(y1,last+1)
    }
    try forEachStoredIndex(components:options.basis == .transparent ? [mode.componentCount]:nil) { i in
      if defaultKept {include(previous,i)}
      let keep=options.basis == .transparent ? value(component:mode.componentCount,index:i)>0:components(index:i) != reference
      if keep {include(i,i+1)}
      previous=i+1
    }
    if defaultKept {include(previous,width*height)}
    guard x1>x0,y1>y0 else{throw CraftError.invalid("No image content would remain after trimming.")}
    return options.bounds(content:.init(x:x0,y:y0,width:x1-x0,height:y1-y0),width:width,height:height)
  }
}

extension NativeModeRaster {
  /// Channel-major and interleaved codecs share bounded immutable component
  /// publication. Each plane owns at most two mutable 4Ki-sample blocks.
  public final class RowBuilder {
    private var candidate: NativeModeRaster
    private let backing: RasterTileStore
    private var builders: [ComponentPlaneBuilder?]
    private var planes: [ComponentPlane?]
    private var rows: [Int]
    private var failed = false
    private var finished = false
    public init(width: Int, height: Int, mode: DocumentColorMode, depth: PixelDepth,
      profile: Data? = nil, intent: ModeRenderingIntent = .relativeColorimetric,
      backing: RasterTileStore? = nil) throws {
      candidate = try NativeModeRaster(width:width,height:height,mode:mode,depth:depth,profile:profile,intent:intent)
      self.backing = try backing ?? RasterTileStore()
      builders = Array(repeating:nil,count:mode.componentCount+1)
      planes = Array(repeating:nil,count:mode.componentCount+1)
      rows = Array(repeating:0,count:mode.componentCount+1)
    }
    private func check(_ word: UInt32, component: Int) throws {
      try ComponentPlane.validate(word:word,depth:candidate.depth)
      if component == candidate.mode.componentCount, candidate.depth == .f32 {
        guard (0...1).contains(Float(bitPattern:word)) else {throw CraftError.invalid("Invalid floating component opacity.")}
      }
    }
    public func appendRow(_ words: [UInt32], component: Int) throws {
      do {
        guard !failed,!finished,rows.indices.contains(component),rows[component]<candidate.height,
          words.count == candidate.width else {throw CraftError.invalid("Invalid or repeated component row.")}
        try Task.checkCancellation()
        if builders[component] == nil {
          let word=words[words.count/2];try check(word,component:component)
          let plane=try ComponentPlane(width:candidate.width,height:candidate.height,depth:candidate.depth,defaultWord:word)
          planes[component]=plane
          builders[component]=try ComponentPlaneBuilder(plane:plane,cacheBlocks:2,reserve:backing.reserveComponentScratch)
        }
        let defaultWord=planes[component]!.defaultWord,offset=rows[component]*candidate.width
        for x in words.indices {
          if x%4096 == 0 {try Task.checkCancellation()}
          if words[x] == defaultWord {continue}
          try check(words[x],component:component)
          try builders[component]!.setWord(words[x],at:offset+x)
        }
        rows[component]+=1
      } catch {failed=true;throw error}
    }
    public func fill(component: Int, word: UInt32) throws {
      do {
        guard !failed,!finished,rows.indices.contains(component),rows[component] == 0 else {throw CraftError.invalid("Cannot replace an accepted component plane.")}
        try Task.checkCancellation();try check(word,component:component)
        planes[component]=try ComponentPlane(width:candidate.width,height:candidate.height,depth:candidate.depth,defaultWord:word)
        rows[component]=candidate.height
      } catch {failed=true;throw error}
    }
    public func finish() throws -> NativeModeRaster {
      do {
        guard !failed,!finished,rows.allSatisfy({$0 == candidate.height}) else {throw CraftError.invalid("Incomplete component rows cannot publish.")}
        try Task.checkCancellation()
        candidate.componentStorage=try rows.indices.map { c in
          if let builder=builders[c] {return try builder.finish()}
          guard let plane=planes[c] else {throw CraftError.invalid("Missing component plane.")};return plane
        }
        try candidate.validate();finished=true;builders=[];planes=[];return candidate
      } catch {failed=true;throw error}
    }
  }
  /// Transform one color component against its retained opacity. The implicit
  /// value and union of stored ranges cover every sample without dense storage.
  public func mappingColorComponent(_ component: Int, backing: RasterTileStore? = nil,
    _ transform: (Float,Float) throws -> Float) throws -> Self {
    guard (0..<mode.componentCount).contains(component) else {throw CraftError.invalid("Color component not found.")}
    try Task.checkCancellation()
    let defaults=defaultComponents(),fill=try transform(defaults[component],defaults[mode.componentCount])
    guard fill.isFinite else {throw CraftError.invalid("Non-finite mapped component.")}
    let plane=try ComponentPlane(width:width,height:height,depth:depth,defaultWord:Self.word(fill,depth:depth))
    let store=try backing ?? RasterTileStore()
    let builder=try ComponentPlaneBuilder(plane:plane,cacheBlocks:2,reserve:store.reserveComponentScratch)
    try forEachStoredIndex(components:[component,mode.componentCount]) { i in
      let value=try transform(self.value(component:component,index:i),self.value(component:mode.componentCount,index:i))
      guard value.isFinite else {throw CraftError.invalid("Non-finite mapped component.")}
      let word=Self.word(value,depth:depth)
      if word != plane.defaultWord {try builder.setWord(word,at:i)}
    }
    var result=self;result.componentStorage[component]=try builder.finish();return result
  }
}
