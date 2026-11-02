import Foundation
import CoreGraphics
import PhotoCraftCore
import PhotoCraftImaging

struct SelectedPixelTransformPreviewSource:Sendable {
  let document:CraftDocument
  let sx:Double,sy:Double
  static func prepare(_ original:CraftDocument)throws->Self {
    let ratio=min(1,1024/Double(max(original.width,original.height))),width=max(1,Int((Double(original.width)*ratio).rounded())),height=max(1,Int((Double(original.height)*ratio).rounded()))
    var proxy=original
    if width != original.width || height != original.height {try Command.imageSize(width,height,original.pixelsPerInch,.bilinear).apply(to:&proxy)}
    return Self(document:proxy,sx:Double(width)/Double(original.width),sy:Double(height)/Double(original.height))
  }
  func image(layerID:UUID,matrix:ProjectiveTransform,interpolation:Resampling,backgroundColor:Pixel? = nil,copy:Bool = false,pixelMask:Bool = false,maskViewMode:MaskViewMode? = nil,channelTarget:ChannelPlaneTarget? = nil,channelBackgroundValue:Float = 1,channelOverlay:Bool = false,collectionLayerIDs:[UUID]? = nil,collectionCopy:Bool=false)throws->SelectedPixelTransformPreviewImage {
    var proxy=document
    let projection=try matrix.preceded(by:.scale(1/sx,1/sy)).followed(by:.scale(sx,sy))
    if var ids=collectionLayerIDs{if collectionCopy{let before=Set(proxy.layers.map(\.id));try Command.duplicateLayers(Set(ids)).apply(to:&proxy);ids=proxy.layers.filter{!before.contains($0.id)}.map(\.id)};let request:LayerCollectionTransformRequest;if let affine=try projection.affineValue(){request = .init(layerIDs:ids,matrix:affine,interpolation:interpolation)}else{request = .init(layerIDs:ids,projection:projection,interpolation:interpolation)};try Command.transformLayers(request).apply(to:&proxy)}else if let target=channelTarget{try Command.transformChannel(.init(target:target,matrix:projection,interpolation:interpolation,backgroundValue:channelBackgroundValue)).apply(to:&proxy)}else if pixelMask{try Command.transformPixelMask(.init(layerID:layerID,matrix:projection,interpolation:interpolation)).apply(to:&proxy)}else{try Command.transformPixels(.init(layerID:layerID,matrix:projection,interpolation:interpolation,backgroundColor:backgroundColor,copy:copy)).apply(to:&proxy)}
    let surface=try Renderer.render(proxy).surface
    let maskImage=try maskViewMode.flatMap{mode in try proxy.layers.first(where:{$0.id==layerID}).map{try RasterIO.displayImage(Renderer.maskPresentation($0,mode:mode,width:proxy.width,height:proxy.height))}}
    let image=try channelTarget != nil ? ChannelPresentation.image(surface,document:proxy,target:channelTarget,overlay:channelOverlay):ColorManagement.displayImage(surface,in:proxy)
    return SelectedPixelTransformPreviewImage(image,maskImage:maskImage)
  }
}
struct SelectedPixelTransformPreviewImage:@unchecked Sendable {let image:CGImage;let maskImage:CGImage?;init(_ image:CGImage,maskImage:CGImage? = nil){self.image=image;self.maskImage=maskImage}}
