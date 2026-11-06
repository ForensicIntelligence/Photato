import Foundation
import PhotoCraftCore

public struct PathFillOptions:Equatable,Sendable {
  public enum Contents:String,CaseIterable,Sendable {
    case foreground,background,color,pattern,history,black,gray,white
    public var title:String {switch self{case .foreground:"Foreground Color";case .background:"Background Color";case .color:"Color";case .pattern:"Pattern";case .history:"History (unavailable)";case .black:"Black";case .gray:"50% Gray";case .white:"White"}}
  }
  public var contents=Contents.foreground
  public var color=Pixel.black
  public var patternID:String?
  public var placement=PatternPlacement()
  public var opacity:Float=1
  public var mode=BlendMode.normal
  public var clear=false,preserveTransparency=false,antiAlias=true
  public var feather:Double=0
  public init(){}
  public func validate()throws {
    guard opacity.isFinite,(0.01...1).contains(opacity),feather.isFinite,(0...100).contains(feather),color.isFinite,
      [color.r,color.g,color.b,color.a].allSatisfy({(0...1).contains($0)})else{throw CraftError.invalid("Use opacity1–100%, finite RGBA colors and feather0–100px.")}
    guard contents != .history else{throw CraftError.unsupported("History Fill requires a history source and is not implemented yet.")}
    guard contents == .pattern || patternID==nil,contents != .pattern || patternID.map({!$0.isEmpty && $0.utf8.count<=255})==true else{throw CraftError.invalid("Choose a saved pattern only for Pattern contents.")}
    try placement.validate()
  }
}
public struct PathFillContext:Sendable {
  public let foreground:Pixel,background:Pixel,patterns:[RasterPattern],patternBusy:Bool
  public init(foreground:Pixel,background:Pixel,patterns:[RasterPattern],patternBusy:Bool=false){self.foreground=foreground;self.background=background;self.patterns=patterns;self.patternBusy=patternBusy}
}
public enum PathFill {
  public static let maximumPixels=16_777_216
  public static func command(_ path:VectorPath,document:CraftDocument,layerID:UUID,options:PathFillOptions,context:PathFillContext)throws->Command {
    try Task.checkCancellation();try path.validate();try options.validate()
    guard !path.isEmpty,document.width<=maximumPixels/document.height,PixelFillStroke.available(document,target:.layer(layerID)) else{throw CraftError.unsupported("Path Fill needs a nonempty path, static RGB raster target and a canvas up to16MP.")}
    let ink:Pixel,pattern:RasterPattern?
    switch options.contents {
    case .foreground:ink=context.foreground;pattern=nil
    case .background:ink=context.background;pattern=nil
    case .color:ink=options.color;pattern=nil
    case .black:ink = .black;pattern=nil
    case .gray:ink=Pixel(0.5,0.5,0.5);pattern=nil
    case .white:ink = .white;pattern=nil
    case .pattern:
      guard !context.patternBusy else{throw CraftError.invalid("Wait for the pattern library operation to finish.")}
      guard let chosen=((document.patterns ?? [])+context.patterns).first(where:{$0.id==options.patternID})else{throw CraftError.invalid("The saved pattern is unavailable.")}
      ink = .white;pattern=chosen
    case .history:throw CraftError.unsupported("History Fill is unavailable.")
    }
    var settings=PixelPaintSettings(color:ink);settings.opacity=options.opacity;settings.mode=options.mode;settings.preserveTransparency=options.preserveTransparency
    var request=PixelPaintRequest(.fill,target:.layer(layerID),settings:settings,pattern:pattern,placement:pattern == nil ? nil:options.placement)
    request.pathCoverage=try VectorRasterizer.coverage(path,width:document.width,height:document.height,antiAlias:options.antiAlias).feathered(radius:options.feather)
    request.pathClear=options.clear
    return .pixelPaint(request)
  }
}
