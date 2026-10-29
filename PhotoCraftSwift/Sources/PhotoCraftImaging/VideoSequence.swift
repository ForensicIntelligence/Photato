import Foundation
import PhotoCraftCore

public enum VideoSequence {
  /// Input ordering is explicit; file-picker callers use the same numeric sort.
  public static func ordered(_ urls: [URL]) -> [URL] {
    urls.sorted { a,b in
      let order = a.lastPathComponent.compare(b.lastPathComponent,options:[.numeric,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX"))
      return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }
  }
  public static func make(_ sources: [CraftDocument], frameRate: Double, name: String, maximumBytes: Int = 1_073_741_824) throws -> CraftDocument {
    try Task.checkCancellation()
    guard !sources.isEmpty, sources.count <= VideoClip.maximumFrames, frameRate.isFinite, (1...240).contains(frameRate), maximumBytes > 0 else { throw CraftError.invalid("Choose 1–512 images and a frame rate from 1 to 240.") }
    let first = sources[0]
    guard sources.allSatisfy({$0.width == first.width && $0.height == first.height && $0.animation == nil && $0.videoTimeline == nil && !$0.hasArtboards}) else { throw CraftError.invalid("An image sequence requires equally sized still images without artboards.") }
    let perFrame = ((first.width + 63)/64) * ((first.height + 63)/64) * 65_536
    guard perFrame <= maximumBytes / sources.count else { throw CraftError.invalid("Image sequence exceeds the decoded frame budget.") }
    var result = try CraftDocument(width:first.width,height:first.height,depth:first.depth,name:name)
    result.workingICC = first.workingICC; result.sourceICC = first.sourceICC; result.profileIsUntagged = first.profileIsUntagged; result.resolution = first.resolution
    var frames: [Surface] = []
    for source in sources {
      try Task.checkCancellation(); try source.validate()
      frames.append(try ColorManagement.converted(Renderer.composite(source),from:source,to:result))
    }
    var layer = Layer(name:name,content:.raster(frames[0])); layer.video = VideoClip(frames:frames,frameRate:frameRate)
    result.layers = [layer]; result.activeLayerID = layer.id; result.videoTimeline = VideoTimeline(frameRate:frameRate,durationFrames:frames.count)
    try result.validate(); return result
  }
}
