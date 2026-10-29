import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreVideo
import Foundation
import PhotoCraftCore

/// Owns a private completed movie; callers must discard it after publication or delivery.
public struct RenderedVideo: Sendable {
  public let url: URL
  public let plan: VideoRenderPlan
  public let codec: VideoRenderCodec
  public let hasAudio: Bool
  public let bytes: Int
  public func discard() { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
  public func publish(to destination: URL) throws {
    let writer=try AtomicFileWriter(to:destination,maximumBytes:bytes)
    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
    while let data=try file.read(upToCount:AtomicFileWriter.chunkBytes),!data.isEmpty {
      try Task.checkCancellation();try writer.append(data)
    }
    guard writer.count == bytes else { throw CraftError.invalid("The completed video changed before publication.") }
    try writer.commit()
  }
}
public enum VideoRender {
  public static let maximumBytes = 2_147_483_648
  public static let apiMaximumBytes = 128*1024*1024
  public static func render(_ document: CraftDocument, options: VideoRenderOptions,
    maximumBytes: Int = maximumBytes, maximumAudioBytes: Int = TimelineAudioIO.maximumDecodedBytes) throws -> RenderedVideo {
    try Task.checkCancellation();try document.validate()
    let plan=try options.plan(for:document)
    guard maximumBytes > 0, maximumBytes <= Self.maximumBytes else { throw CraftError.invalid("Invalid video output budget.") }
    let pcm = options.includeAudio ? try TimelineAudioMixer.render(document,maximumBytes:maximumAudioBytes,
      startTime:plan.sourceStart,duration:plan.duration) : nil
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("photato-render-video-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let url=directory.appendingPathComponent("render."+options.codec.fileExtension)
    var completed=false
    defer{if !completed{try? FileManager.default.removeItem(at:directory)}}
    let writer=try AVAssetWriter(outputURL:url,fileType:options.codec.fileType)
    defer{if !completed{writer.cancelWriting()}}
    let color: [String:Any] = [AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,
      AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2]
    var settings:[String:Any]?
    if let codec=options.codec.avCodec {
      settings=[AVVideoCodecKey:codec,AVVideoWidthKey:plan.width,AVVideoHeightKey:plan.height,AVVideoColorPropertiesKey:color]
      if options.codec.usesBitRate {
        let bitRate=options.bitRate ?? min(50_000_000,max(1_000_000,Int(Double(plan.width*plan.height)*plan.frameRate*0.15)))
        settings?[AVVideoCompressionPropertiesKey]=[AVVideoAverageBitRateKey:bitRate,AVVideoExpectedSourceFrameRateKey:plan.frameRate]
      }
      guard writer.canApply(outputSettings:settings,forMediaType:.video) else { throw CraftError.unsupported("The selected video encoder/settings are unavailable on this Mac.") }
    }
    let video=AVAssetWriterInput(mediaType:.video,outputSettings:settings)
    video.expectsMediaDataInRealTime=false;video.mediaTimeScale=plan.rateNumerator
    let attributes:[String:Any]=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String:plan.width,kCVPixelBufferHeightKey as String:plan.height,
      kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true]
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:attributes)
    guard writer.canAdd(video) else{throw CraftError.unsupported("The selected video track cannot be written.")};writer.add(video)
    var audio:AVAssetWriterInput?
    if pcm != nil {
      let audioSettings:[String:Any] = options.codec.usesBitRate
        ? [AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVEncoderBitRateKey:192000]
        : [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false]
      guard writer.canApply(outputSettings:audioSettings,forMediaType:.audio) else{throw CraftError.unsupported("The native audio encoder is unavailable.")}
      let input=AVAssetWriterInput(mediaType:.audio,outputSettings:audioSettings)
      input.expectsMediaDataInRealTime=false
      guard writer.canAdd(input) else{throw CraftError.unsupported("The movie cannot include an audio track.")};writer.add(input);audio=input
    }
    guard writer.startWriting() else{throw writer.error ?? CraftError.invalid("Video encoding could not start.")}
    writer.startSession(atSourceTime:.zero)
    var frame=0,audioFrame=0,lastProgress=Date(),videoFinished=false,audioFinished=audio == nil
    while !videoFinished || !audioFinished {
      try Task.checkCancellation()
      guard writer.status == .writing else{throw writer.error ?? CraftError.invalid("Video encoding stopped unexpectedly.")}
      var advanced=false
      if !videoFinished,video.isReadyForMoreMediaData {
        let time=plan.sourceStart+Double(frame)/plan.frameRate
        let surface:Surface
        if let animation=document.animation {
          var end=0.0,index=animation.frames.count-1
          for i in animation.frames.indices{end+=animation.playbackDelay(at:i);if time<end-1e-10{index=i;break}}
          surface=try Renderer.composite(document.animationDocument(at:animation.frames[index].id))
        } else { surface=try Renderer.composite(document,videoTime:time) }
        let buffer=try pixelBuffer(surface,in:document,plan:plan,preserveAlpha:options.preserveAlpha,attributes:attributes)
        guard adaptor.append(buffer,withPresentationTime:plan.timestamp(frame)) else{throw writer.error ?? CraftError.invalid("The video encoder rejected a frame.")}
        frame+=1;advanced=true
        if frame==plan.frameCount{video.markAsFinished();videoFinished=true}
      }
      // Feed both tracks on every pass. Serializing whole tracks can deadlock the muxer's backpressure.
      if let audio,let pcm,!audioFinished,audio.isReadyForMoreMediaData {
        let count=min(1024,pcm.frames-audioFrame)
        let buffer=try audioBuffer(pcm,first:audioFrame,count:count)
        guard audio.append(buffer) else{throw writer.error ?? CraftError.invalid("The audio encoder rejected PCM samples.")}
        audioFrame+=count;advanced=true
        if audioFrame==pcm.frames{audio.markAsFinished();audioFinished=true}
      }
      if advanced {
        lastProgress=Date()
        if frame % 8 == 0 {try checkSize(url,maximumBytes:maximumBytes)}
      } else {
        guard Date().timeIntervalSince(lastProgress)<30 else{throw CraftError.invalid("The video encoder stopped making progress.")}
        Thread.sleep(forTimeInterval:0.002)
      }
    }
    writer.endSession(atSourceTime:plan.timestamp(plan.frameCount))
    let finished=DispatchSemaphore(value:0);writer.finishWriting{finished.signal()}
    let deadline=Date().addingTimeInterval(60)
    while finished.wait(timeout:.now()+0.02) == .timedOut {
      try Task.checkCancellation();try checkSize(url,maximumBytes:maximumBytes)
      guard Date()<deadline else{throw CraftError.invalid("The video encoder could not finalize the movie.")}
    }
    try Task.checkCancellation()
    guard writer.status == .completed else{throw writer.error ?? CraftError.invalid("Video encoding did not complete.")}
    let bytes=try checkSize(url,maximumBytes:maximumBytes)
    guard bytes>0 else{throw CraftError.invalid("Video encoding produced an empty file.")}
    completed=true;return RenderedVideo(url:url,plan:plan,codec:options.codec,hasAudio:pcm != nil,bytes:bytes)
  }
  @discardableResult static func checkSize(_ url:URL,maximumBytes:Int)throws->Int {
    let bytes=(try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
    guard bytes<=maximumBytes else{throw CraftError.invalid("Video export exceeds its file size budget.")};return bytes
  }
  static func pixelBuffer(_ surface:Surface,in document:CraftDocument,plan:VideoRenderPlan,preserveAlpha:Bool,attributes:[String:Any])throws->CVPixelBuffer {
    var optional:CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault,plan.width,plan.height,kCVPixelFormatType_32BGRA,attributes as CFDictionary,&optional)==kCVReturnSuccess,let buffer=optional else{throw CraftError.invalid("Could not allocate a video frame.")}
    CVPixelBufferLockBaseAddress(buffer,[]);defer{CVPixelBufferUnlockBaseAddress(buffer,[])}
    let row=CVPixelBufferGetBytesPerRow(buffer)
    let colorTags:[CFString:CFString]=[kCVImageBufferColorPrimariesKey:kCVImageBufferColorPrimaries_ITU_R_709_2,
      kCVImageBufferTransferFunctionKey:kCVImageBufferTransferFunction_ITU_R_709_2,
      kCVImageBufferYCbCrMatrixKey:kCVImageBufferYCbCrMatrix_ITU_R_709_2]
    // The named CG Rec.709 space and Core Video's transfer attachment are not
    // interchangeable. Derive the conversion space from the exact video tags.
    guard let base=CVPixelBufferGetBaseAddress(buffer),
      let space=CVImageBufferCreateColorSpaceFromAttachments(colorTags as CFDictionary)?.takeRetainedValue(),
      let context=CGContext(data:base,width:plan.width,height:plan.height,bitsPerComponent:8,bytesPerRow:row,space:space,
        bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue)
    else{throw CraftError.invalid("Could not prepare the video color conversion.")}
    let rectangle=CGRect(x:0,y:0,width:plan.width,height:plan.height)
    context.clear(rectangle)
    if !preserveAlpha{context.setFillColor(CGColor(gray:0,alpha:1));context.fill(rectangle)}
    context.interpolationQuality = .high
    context.draw(try ColorManagement.image(surface,in:document),in:rectangle)
    // Core Graphics produces premultiplied BGRA. Writers receive straight RGB + explicit alpha tagging.
    if preserveAlpha {
      let pixels=base.assumingMemoryBound(to:UInt8.self)
      for y in 0..<plan.height {
        try Task.checkCancellation()
        for x in 0..<plan.width {let i=y*row+x*4,a=Int(pixels[i+3]);if a>0 && a<255{
          for c in 0..<3{pixels[i+c]=UInt8(min(255,(Int(pixels[i+c])*255+a/2)/a))}
        }}
      }
    }
    CVBufferSetAttachment(buffer,kCVImageBufferColorPrimariesKey,kCVImageBufferColorPrimaries_ITU_R_709_2,.shouldPropagate)
    CVBufferSetAttachment(buffer,kCVImageBufferTransferFunctionKey,kCVImageBufferTransferFunction_ITU_R_709_2,.shouldPropagate)
    CVBufferSetAttachment(buffer,kCVImageBufferYCbCrMatrixKey,kCVImageBufferYCbCrMatrix_ITU_R_709_2,.shouldPropagate)
    CVBufferSetAttachment(buffer,kCVImageBufferAlphaChannelModeKey,kCVImageBufferAlphaChannelMode_StraightAlpha,.shouldPropagate)
    return buffer
  }
  static func audioBuffer(_ pcm:TimelinePCM,first:Int,count:Int)throws->CMSampleBuffer {
    guard count>0,first>=0,first+count<=pcm.frames else{throw CraftError.invalid("Invalid movie audio range.")}
    var format=AudioStreamBasicDescription(mSampleRate:48000,mFormatID:kAudioFormatLinearPCM,
      mFormatFlags:kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,mBytesPerPacket:8,mFramesPerPacket:1,
      mBytesPerFrame:8,mChannelsPerFrame:2,mBitsPerChannel:32,mReserved:0)
    var description:CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&format,layoutSize:0,layout:nil,
      magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&description)==noErr,
      let description else{throw CraftError.invalid("Could not create the PCM description.")}
    var block:CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:count*8,
      blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:count*8,flags:0,blockBufferOut:&block)==noErr,
      let block else{throw CraftError.invalid("Could not allocate audio samples.")}
    let copied=pcm.samples.withUnsafeBytes{CMBlockBufferReplaceDataBytes(with:$0.baseAddress!.advanced(by:first*8),blockBuffer:block,offsetIntoDestination:0,dataLength:count*8)}
    guard copied==noErr else{throw CraftError.invalid("Could not prepare audio samples.")}
    var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:48000),presentationTimeStamp:CMTime(value:Int64(first),timescale:48000),decodeTimeStamp:.invalid)
    var size=8,result:CMSampleBuffer?
    guard CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:description,sampleCount:count,
      sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&result)==noErr,
      let result else{throw CraftError.invalid("Could not create movie audio samples.")}
    return result
  }
}
