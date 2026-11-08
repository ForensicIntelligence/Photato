import Foundation
import PhotoCraftCore

public enum ClipboardPlaneIO {
  /// A numeric grayscale payload does not pass through its RGB display cache.
  public static func image(_ content:ClipboardContent,depth:PixelDepth,settings:ColorSettings)throws->ClipboardPlaneImage {
    if let numeric=try ClipboardPlane.numericImage(content){return numeric}
    let profile=try settings.profile(.grayscale,depth:depth)
    let native:NativeModeRaster
    if content.kind == .pixels,let source=content.document.layers.first?.nativeMode {
      native=try source.converted(to:.grayscale,depth:depth,profile:profile,intent:settings.intent)
    }else {
      let source=try ClipboardRenderer.preview(content)
      let preview=try source.depth == .f32 && source.colorEncoding == .sRGB ? source.mappedStoredSamples(encoding:.linearRGB){SRGBTransfer.linear($0)}:source
      let sourceProfile=try content.document.modeDescriptor != nil ? NativeModeProfile.standard(.rgb,depth:preview.depth):ColorProfileInput.effectiveProfile(content.document)
      native=try NativeModeRaster.converting(preview,to:.grayscale,depth:depth,profile:profile,intent:settings.intent,sourceProfile:sourceProfile)
    }
    return try .init(values:native.channel(0),coverage:native.opacityChannel(),bounds:content.bounds)
  }
  public static func gray(_ color:Pixel)->Float {unit(0.2126*color.r+0.7152*color.g+0.0722*color.b)}
}
