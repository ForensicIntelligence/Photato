import AVFoundation
import CoreImage
import Foundation
import PhotoCraftCore

/// Native movie decoding on the caller's background worker. Synchronous asset
/// properties match the existing synchronous document reader contract on macOS14.
/// Original bytes are copied into a private container before AVFoundation sees it.
public enum MovieIO {
  public static let mediaTypes=["video/quicktime","video/mp4","video/x-m4v"]
  public static func recognizes(_ data:Data)->Bool {
    guard data.count>=12 else{return false}
    let tag=String(data:data[4..<8],encoding:.ascii)
    if tag == "ftyp" {
      // HEIF/AVIF are image containers and remain on their image decoder path.
      let brand=String(data:data[8..<12],encoding:.ascii) ?? ""
      return ["qt  ","isom","iso2","iso3","iso4","iso5","iso6","iso8","iso9","mp41","mp42","avc1","dash","M4V ","M4VH","M4VP","MSNV"].contains(brand)
    }
    return ["moov","mdat","wide"].contains(tag ?? "")
  }
  public static func read(_ url:URL,maximumBytes:Int=1_073_741_824,maximumPixels:Int=Surface.maximumDensePixels)throws->CraftDocument {
    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
    var data=Data()
    while true {
      try Task.checkCancellation()
      guard let chunk=try file.read(upToCount:min(1_048_576,MovieSource.maximumBytes+1-data.count)),!chunk.isEmpty else{break}
      data.append(chunk);guard data.count<=MovieSource.maximumBytes else{throw CraftError.invalid("Movie source exceeds 64 MiB.")}
    }
    return try decode(data,name:url.deletingPathExtension().lastPathComponent,maximumBytes:maximumBytes,maximumPixels:maximumPixels)
  }
  public static func decode(_ data:Data,name:String,maximumBytes:Int=1_073_741_824,maximumPixels:Int=Surface.maximumDensePixels,frameOptions:MovieFrameImportOptions?=nil,maximumLayers:Int=512)throws->CraftDocument {
    try Task.checkCancellation();try frameOptions?.validate()
    guard (1...512).contains(maximumLayers) else {throw CraftError.invalid("Choose at most512 output layers.")}
    guard recognizes(data),data.count<=MovieSource.maximumBytes,maximumBytes>data.count else {throw CraftError.invalid("Choose a supported MOV/MP4 movie within the source and decoded-memory limits.")}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("photato-movie-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("source.mov");try data.write(to:url,options:.atomic)
    let asset=AVURLAsset(url:url,options:[AVURLAssetPreferPreciseDurationAndTimingKey:true,AVURLAssetReferenceRestrictionsKey:UInt(0xffff)])
    let tracks=asset.tracks(withMediaType:.video)
    guard tracks.count==1,let track=tracks.first,!asset.hasProtectedContent else{throw CraftError.unsupported("Choose an unprotected movie with one video track.")}
    let transform=track.preferredTransform
    guard [transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty].allSatisfy({$0.isFinite}) else {throw CraftError.invalid("Invalid movie orientation.")}
    let dimensions=CGRect(origin:.zero,size:track.naturalSize).applying(transform).standardized
    guard dimensions.width.isFinite,dimensions.height.isFinite,dimensions.width>0,dimensions.height>0,dimensions.width<=Double(Surface.maxDimension),dimensions.height<=Double(Surface.maxDimension) else{throw CraftError.invalid("Movie dimensions or orientation are invalid.")}
    let w=Int(dimensions.width.rounded()),h=Int(dimensions.height.rounded())
    guard w>0,h>0,w<=Surface.maxDimension,h<=Surface.maxDimension,w<=maximumPixels/h else {throw CraftError.invalid("Movie dimensions exceed the document limit.")}
    let bytesPerFrame=((w+63)/64)*((h+63)/64)*65_536
    guard bytesPerFrame<=maximumBytes-data.count else{throw CraftError.invalid("Movie exceeds the decoded-frame memory budget.")}
    let reader=try AVAssetReader(asset:asset)
    let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_64RGBAHalf])
    output.alwaysCopiesSampleData=false
    guard reader.canAdd(output) else{throw CraftError.unsupported("The native movie decoder cannot read this video track.")};reader.add(output)
    guard reader.startReading() else{throw reader.error ?? CraftError.invalid("Could not start native movie decoding.")}
    defer{reader.cancelReading()}
    let context=CIContext(options:[.cacheIntermediates:false]),space=try RasterIO.colorSpace()
    var frames:[Surface]=[],times:[MovieTime]=[],indices:[Int]=[]
    var lastDuration=CMTime.invalid,lastTime=CMTime.invalid,previous=CMTime.invalid,ordinal=0,eligible=0,stoppedAtRange=false
    let range=track.timeRange,trackEnd=CMTimeRangeGetEnd(range)
    if let options=frameOptions,options.selectedRange {
      guard options.start < trackEnd.seconds else {throw CraftError.invalid("The selected range starts after the movie ends.")}
    }
    while let sample=output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      let pts=CMSampleBufferGetPresentationTimeStamp(sample)
      guard pts.isNumeric,pts.epoch==0,pts.seconds>=0,pts.seconds<=86_400,!previous.isNumeric || CMTimeCompare(pts,previous)>0 else{throw CraftError.invalid("Movie presentation times must increase within one day.")}
      previous=pts
      if let options=frameOptions,options.selectedRange,pts.seconds>=options.end {stoppedAtRange=true;break}
      let sourceIndex=ordinal;ordinal+=1
      guard ordinal<=20_736_001 else{throw CraftError.invalid("Movie source has too many presentation frames.")}
      lastTime=pts;lastDuration=CMSampleBufferGetDuration(sample)
      if let options=frameOptions {
        if options.selectedRange,pts.seconds<options.start {continue}
        let keep=eligible % options.every == 0;eligible+=1
        if !keep {continue}
      }
      let count=frames.count+1
      let metadataBytes=frameOptions?.makeAnimation == true ? count*count*192+count*128:0
      guard count<=VideoClip.maximumFrames,count<=maximumLayers,
        frameOptions?.makeAnimation != true || count*count<=FrameAnimation.maximumLayerStates,
        metadataBytes<=maximumBytes-data.count,bytesPerFrame<=(maximumBytes-data.count-metadataBytes)/count else {throw CraftError.invalid("Movie exceeds the output layer/frame or decoded-memory budget. Select a shorter range or a larger frame interval.")}
      guard let buffer=CMSampleBufferGetImageBuffer(sample) else{throw CraftError.invalid("Movie pixels are invalid.")}
      // Track matrices use top-left coordinates; Core Image uses bottom-left.
      // Conjugate the matrix with vertical flips, then normalize the output extent.
      let inputFlip=CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:CGFloat(CVPixelBufferGetHeight(buffer)))
      let outputFlip=CGAffineTransform(scaleX:1,y:-1)
      var image=CIImage(cvPixelBuffer:buffer).transformed(by:inputFlip).transformed(by:transform).transformed(by:outputFlip)
      let extent=image.extent.integral
      guard extent.width.isFinite,extent.height.isFinite,extent.width==Double(w),extent.height==Double(h) else{throw CraftError.unsupported("Variable movie dimensions or non-integral display transforms are not yet supported.")}
      image=image.transformed(by:CGAffineTransform(translationX:-extent.minX,y:-extent.minY))
      guard let cg=context.createCGImage(image,from:CGRect(x:0,y:0,width:w,height:h),format:.RGBA16,colorSpace:space) else{throw CraftError.invalid("Native movie frame conversion failed.")}
      frames.append(try RasterIO.surface(cg,depth:.u16));times.append(MovieTime(value:pts.value,timescale:pts.timescale));indices.append(sourceIndex)
    }
    try Task.checkCancellation()
    guard (reader.status == .completed || stoppedAtRange),!frames.isEmpty else{throw reader.error ?? CraftError.invalid("The movie decoder did not finish. No partial clip was imported.")}
    var end=trackEnd
    let last=times.last!.seconds
    if lastDuration.isNumeric,lastDuration.seconds>0 {end=CMTimeAdd(lastTime,lastDuration)}
    if let options=frameOptions,options.selectedRange,end.seconds>options.end {end=CMTime(seconds:options.end,preferredTimescale:1_000_000_000)}
    guard end.isNumeric,end.seconds>last,end.seconds<=86_400 else{throw CraftError.invalid("Movie duration is invalid.")}
    if let options=frameOptions {return try MovieFrames.document(frames:frames,times:times,end:MovieTime(value:end.value,timescale:end.timescale),indices:indices,name:name,options:options,maximumBytes:maximumBytes)}
    let nominal=Double(track.nominalFrameRate),rate=(nominal>=1 && nominal<=240) ? nominal : Double(frames.count)/(end.seconds-times[0].seconds)
    let source=MovieSource(data:data,presentationTimes:times,endTime:MovieTime(value:end.value,timescale:end.timescale),originalFrameRate:rate,audioTracks:asset.tracks(withMediaType:.audio).count)
    try source.validate(frameCount:frames.count)
    var clip=VideoClip(frames:frames,frameRate:rate);clip.movie=source;clip.startTime=times[0].seconds
    var layer=Layer(name:name,content:.raster(frames[0]));layer.video=clip
    var result=try CraftDocument(width:w,height:h,depth:.u16,name:name);result.layers=[layer];result.activeLayerID=layer.id
    result.videoTimeline=VideoTimeline(frameRate:rate,durationFrames:max(1,Int(ceil(end.seconds*rate-1e-9))))
    try result.selectVideoFrame(0);try result.validate();return result
  }
  public static func layer(from source:CraftDocument,into target:CraftDocument,maximumBytes:Int=1_073_741_824)throws->Layer {
    try source.validate();try target.validate()
    guard source.layers.count==1,var clip=source.layers[0].video,target.animation==nil,!target.hasArtboards,!target.hasAuthoritativeModeStorage,target.layers.count<LayerLimits.maximumLayers else{throw CraftError.unsupported("Choose one video source and an RGB target without frame animation or artboards.")}
    guard clip.estimatedBytes<=maximumBytes-target.estimatedBytes else{throw CraftError.invalid("Video layer exceeds the document memory budget.")}
    for i in clip.frames.indices {try Task.checkCancellation();clip.frames[i]=try ColorManagement.converted(clip.frames[i],from:source,to:target)}
    clip.startTime=target.videoTimeline?.seconds ?? 0
    var layer=Layer(name:source.layers[0].name,content:.raster(clip.frames[clip.inFrame]));layer.video=clip
    layer.x=(target.width-clip.frames[0].width)/2;layer.y=(target.height-clip.frames[0].height)/2
    return layer
  }
}
