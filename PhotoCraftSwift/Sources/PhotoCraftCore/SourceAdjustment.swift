import Foundation

/// Original PhotoCraft adjustment controls. Floating-point source controls are
/// kept separately from Photoshop's integer UI scales; import never rounds them.
/// Source renderer/model translation: PhotoCraft doc/compose/adjust.rs, MIT OR Apache-2.0.
public struct SourceAdjustment: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case brightnessContrast, levels, curves, exposure, vibrance, hueSaturation, colorBalance
    case blackWhite, photoFilter, channelMixer, colorLookup, invert, posterize, threshold, gradientMap, selectiveColor, unsupported
    public var title: String {
      switch self {
      case .brightnessContrast:"Brightness/Contrast";case .levels:"Levels";case .curves:"Curves";case .exposure:"Exposure"
      case .vibrance:"Vibrance";case .hueSaturation:"Hue/Saturation";case .colorBalance:"Color Balance"
      case .blackWhite:"Black & White";case .photoFilter:"Photo Filter";case .channelMixer:"Channel Mixer"
      case .colorLookup:"Color Lookup";case .invert:"Invert";case .posterize:"Posterize";case .threshold:"Threshold"
      case .gradientMap:"Gradient Map";case .selectiveColor:"Selective Color";case .unsupported:"Unsupported source adjustment"
      }
    }
  }
  public enum ToneSpace: String, Codable, Sendable {case rgb,cmyk,lab}
  public var kind:Kind
  public var parameters:[String:Float]
  public var records:[String:[[Float]]]
  public var options:[String:Bool]
  public var space:ToneSpace
  public var name:String?
  public var opaqueKey:String?
  public var opaqueData:Data?
  public init(_ kind:Kind, parameters:[String:Float]=[:],records:[String:[[Float]]]=[:],options:[String:Bool]=[:],space:ToneSpace = .rgb,name:String?=nil,opaqueKey:String?=nil,opaqueData:Data?=nil) {
    self.kind=kind;self.parameters=parameters;self.records=records;self.options=options;self.space=space
    self.name=name;self.opaqueKey=opaqueKey;self.opaqueData=opaqueData
  }
  public var estimatedBytes:Int {parameters.count*32+options.count*32+records.values.reduce(0){$0+$1.reduce(0){$0+$1.count*4}}+(name?.utf8.count ?? 0)+(opaqueKey?.utf8.count ?? 0)+(opaqueData?.count ?? 0)}
  public static let maximumOpaqueBytes=1024*1024
  public func validate() throws {
    let error=CraftError.invalid("Invalid original \(kind.title) adjustment controls.")
    guard parameters.values.allSatisfy({$0.isFinite}),records.values.allSatisfy({$0.allSatisfy({$0.allSatisfy({$0.isFinite && abs($0)<=65504})})}),
      (name?.utf8.count ?? 0)<=1024, name?.unicodeScalars.contains(where:{$0.value<32}) != true,
      (opaqueKey?.utf8.count ?? 0)<=64,(opaqueData?.count ?? 0)<=Self.maximumOpaqueBytes else {throw error}
    if kind != .unsupported,opaqueKey != nil || opaqueData != nil {throw error}
    if kind != .colorLookup,name != nil {throw error}
    if kind != .levels && kind != .curves,space != .rgb {throw error}
    func keys(_ p:String,_ g:String="",_ o:String="") throws {
      guard Set(parameters.keys)==Set(p.split(separator:" ").map(String.init)),Set(records.keys)==Set(g.split(separator:" ").map(String.init)),Set(options.keys)==Set(o.split(separator:" ").map(String.init)) else {throw error}
    }
    func number(_ key:String,_ range:ClosedRange<Float>) throws {guard let x=parameters[key],range.contains(x) else {throw error}}
    func rows(_ key:String,_ count:ClosedRange<Int>,_ columns:Int,_ range:ClosedRange<Float>) throws {
      guard let a=records[key],count.contains(a.count),a.allSatisfy({$0.count==columns && $0.allSatisfy(range.contains)}) else {throw error}
    }
    switch kind {
    case .brightnessContrast:try keys("brightness contrast","","legacy");try number("brightness",-150...150);try number("contrast",-100...100)
    case .levels:
      try keys("","channels");try rows("channels",5...5,5,-16...16)
      guard records["channels"]!.allSatisfy({$0[1]>$0[0] && (0.01...9.99).contains($0[2])}) else {throw error}
    case .curves:
      try keys("","master red green blue black")
      for key in records.keys {
        try rows(key,0...256,2,-16...16)
      }
    case .exposure:try keys("exposure offset gamma");try number("exposure",-20...20);try number("offset",-0.5...0.5);try number("gamma",0.01...9.99)
    case .vibrance:try keys("vibrance saturation");try number("vibrance",-100...100);try number("saturation",-100...100)
    case .hueSaturation:
      try keys("hue saturation lightness","ranges","colorize");try number("hue",-180...360);try number("saturation",-100...100);try number("lightness",-100...100)
      try rows("ranges",6...6,7,-720...1080)
      guard records["ranges"]!.allSatisfy({(-180...180).contains($0[0]) && (-100...100).contains($0[1]) && (-100...100).contains($0[2])}) else {throw error}
    case .colorBalance:try keys("","shadows midtones highlights","preserveLuminosity");for key in records.keys {try rows(key,1...1,3,-100...100)}
    case .blackWhite:
      guard Set(records.keys).isSubset(of:["weights","tint"]),records["weights"] != nil else {throw error}
      guard parameters.isEmpty && options.isEmpty else {throw error};try rows("weights",1...1,6,-200...300)
      if records["tint"] != nil {try rows("tint",1...1,3,0...1)}
    case .photoFilter:try keys("density","color","preserveLuminosity");try number("density",0...1);try rows("color",1...1,3,0...1)
    case .channelMixer:try keys("","matrix","monochrome");try rows("matrix",3...3,4,-2...2)
    case .colorLookup:
      guard parameters.keys.sorted()==["size"],Set(records.keys).isSubset(of:["lut"]),Set(options.keys)==["tetrahedral","dither"] else {throw error}
      let size=parameters["size"]!;guard size>=0 && size<=Float(ColorLUT.maximumSize) && size.rounded()==size else {throw error}
      if let table=records["lut"] {let n=Int(size);guard n>=2,table.count==1,table[0].count==n*n*n*3 else {throw error}}
    case .invert:try keys("")
    case .posterize:try keys("levels");try number("levels",2...255);guard parameters["levels"]!.rounded()==parameters["levels"] else {throw error}
    case .threshold:try keys("level");try number("level",0...1)
    case .gradientMap:
      try keys("","stops","reverse dither");try rows("stops",0...4096,4,0...1)
      guard zip(records["stops"]!,records["stops"]!.dropFirst()).allSatisfy({$0[0]<=$1[0]}) else {throw error}
    case .selectiveColor:try keys("","adjustments","relative");try rows("adjustments",9...9,4,-100...100)
    case .unsupported:try keys("");guard let key=opaqueKey,!key.isEmpty,opaqueData != nil else {throw error}
    }
  }
  public var isOpaque:Bool {kind == .unsupported || (kind == .colorLookup && records["lut"]==nil)}
}

extension SourceAdjustment {
  public func layer(in document:CraftDocument,name:String?=nil)throws->Layer {
    try validate();_ = try SourceAdjustmentTransfer(self,depth:document.depth)
    var layer=Layer(name:name ?? kind.title,content:.adjustment(.source(self)))
    if let selection=try document.coverageSelection() {layer.mask=try selection.coverageSurface();var p=MaskProperties();p.outside=0;layer.maskProperties=p}
    return layer
  }
}
