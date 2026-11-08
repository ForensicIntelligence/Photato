import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoFramesTests:XCTestCase {
  func testUniformLogicalIndexingCopyOnWriteAndCanonicalReset()throws {
    let clear=try Surface(width:4,height:3),red=try Surface(width:4,height:3,fill:Pixel(1,0,0))
    var frames=try VideoFrames(repeating:clear,count:VideoFrames.maximumLogicalFrames),copy=frames
    XCTAssertEqual(frames.count,20_736_001);XCTAssertEqual(frames.storedFrameCount,1)
    XCTAssertEqual(frames[0],clear);XCTAssertEqual(frames[20_736_000],clear)
    frames[9]=red;XCTAssertEqual(frames.storedFrameCount,2);XCTAssertEqual(copy[9],clear)
    copy[20_736_000]=red;XCTAssertNotEqual(frames,copy)
    frames[9]=clear;XCTAssertEqual(frames.storedFrameCount,1)
    XCTAssertLessThan(frames.estimatedBytes,1024);XCTAssertThrowsError(try VideoFrames(repeating:clear,count:0))
    XCTAssertThrowsError(try VideoFrames(repeating:clear,count:20_736_002))
  }
  func testDenseLegacyEncodingAndSparseEqualityKeepExactSamples()throws {
    let a=try Surface(width:2,height:2,fill:Pixel(0.25,0.5,1,0.5)),b=try Surface(width:2,height:2)
    let encoder=PropertyListEncoder();encoder.outputFormat = .binary
    let legacy=try encoder.encode([a,b]),frames=VideoFrames([a,b])
    XCTAssertEqual(try encoder.encode(frames),legacy)
    XCTAssertEqual(try PropertyListDecoder().decode(VideoFrames.self,from:legacy),frames)
    var uniform=try VideoFrames(repeating:a,count:2);uniform[1]=b
    XCTAssertEqual(uniform,frames);XCTAssertEqual(Array(uniform),[a,b])
    let bytes=try encoder.encode(uniform),decoded=try PropertyListDecoder().decode(VideoFrames.self,from:bytes)
    XCTAssertEqual(decoded,frames);XCTAssertTrue(decoded.isSparse);XCTAssertEqual(decoded.storedFrameCount,2)
    XCTAssertThrowsError(try PropertyListDecoder().decode(VideoFrames.self,from:encoder.encode(Array(repeating:a,count:513))))
  }
  func testSparseDecodeRejectsMalformedCountVersionAndDuplicateIndices()throws {
    let prototype=try Surface(width:1,height:1),encoder=PropertyListEncoder()
    let valid=try encoder.encode(VideoFrames(repeating:prototype,count:7))
    let original=try XCTUnwrap(PropertyListSerialization.propertyList(from:valid,format:nil)as?[String:Any])
    for pair in [("version",2),("count",0),("count",20_736_002)] {
      var value=original;value[pair.0]=pair.1
      let bytes=try PropertyListSerialization.data(fromPropertyList:value,format:.binary,options:0)
      XCTAssertThrowsError(try PropertyListDecoder().decode(VideoFrames.self,from:bytes))
    }
    let image=try PropertyListSerialization.propertyList(from:encoder.encode(prototype),format:nil)
    for indices in [[1,1],[-1],[7]] {
      var value=original;value["edits"]=indices.map{["index":$0,"surface":image]as[String:Any]}
      let bytes=try PropertyListSerialization.data(fromPropertyList:value,format:.binary,options:0)
      XCTAssertThrowsError(try PropertyListDecoder().decode(VideoFrames.self,from:bytes))
    }
  }
  func document(_ depth:PixelDepth = .u8,frames:Int=120)throws->CraftDocument {
    var doc=try CraftDocument(width:8,height:6,depth:depth)
    try Command.video(.create(frameRate:24,durationFrames:frames)).apply(to:&doc)
    return doc
  }
  func testBlankLayerAllDepthsPaintingFrameIsolationHistoryAndNative90()throws {
    for depth in PixelDepth.allCases {
      let before=try document(depth),originalLayer=before.layers[0]
      var session=EditorSession(document:before)
      try session.execute(.video(.blankLayer));let created=session.document,id=try XCTUnwrap(created.activeLayerID)
      XCTAssertEqual(created.layers.count,2);XCTAssertEqual(created.layers[0],originalLayer)
      let clip=try XCTUnwrap(created.layers.first(where:{$0.id==id})?.video)
      XCTAssertEqual(clip.frames.count,120);XCTAssertEqual(clip.frames.storedFrameCount,1)
      XCTAssertEqual(clip.frameRate,24);XCTAssertNil(clip.movie);XCTAssertEqual(clip.frames[0].pixel(x:0,y:0),.clear)
      try session.selectVideoFrame(17);try session.execute(.fill(id,Pixel(1,0,0)))
      let painted=session.document,frames=try XCTUnwrap(painted.layers.first(where:{$0.id==id})?.video?.frames)
      XCTAssertEqual(frames[17].pixel(x:0,y:0),Pixel(1,0,0));XCTAssertEqual(frames[16].pixel(x:0,y:0),.clear)
      XCTAssertEqual(frames[18].pixel(x:0,y:0),.clear);XCTAssertEqual(frames.storedFrameCount,2)
      XCTAssertEqual(painted.minimumArchiveVersion,90)
      let data=try NativeArchive.encodeChunked(painted),reopened=try NativeArchive.decodePaged(data)
      XCTAssertEqual(reopened,painted)
      try session.undo();XCTAssertEqual(session.document.layers.first(where:{$0.id==id})?.video?.frames,clip.frames)
      try session.redo();XCTAssertEqual(session.document,painted)
      try session.undo();try session.undo();XCTAssertEqual(session.document.layers,[originalLayer])
    }
  }
  func testMaximumCanvasAndOneDayTimelineRetainConstantEmptyStorage()throws {
    var doc=try CraftDocument(width:300_000,height:300_000,depth:.f32)
    try Command.video(.create(frameRate:240,durationFrames:20_736_000)).apply(to:&doc)
    try Command.video(.blankLayer).apply(to:&doc);try doc.selectVideoFrame(20_735_999);try doc.validate()
    let clip=try XCTUnwrap(doc.layers.last?.video)
    XCTAssertEqual(clip.frames.count,20_736_000);XCTAssertEqual(clip.frames.storedFrameCount,1)
    XCTAssertEqual(clip.frames.last?.width,300_000);XCTAssertEqual(clip.frames.last?.allocatedBytes,0)
    XCTAssertLessThan(doc.estimatedBytes,64*1024);XCTAssertEqual(doc.mappedRasterBytes,0)
    let data=try NativeArchive.encodeChunked(doc);XCTAssertLessThan(data.count,128*1024)
    let reopened=try NativeArchive.decodePaged(data);XCTAssertEqual(reopened,doc)
  }
  func testLegacySampledClipsAndRetainedConversionSourcesSelectCorrectArchive()throws {
    var doc=try document(frames:4);try Command.video(.blankLayer).apply(to:&doc)
    try doc.selectVideoFrame(2);try Command.fill(try XCTUnwrap(doc.activeLayerID),.white).apply(to:&doc)
    let animation=try doc.convertingVideoToFrameAnimation()
    XCTAssertEqual(animation.minimumArchiveVersion,90)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(animation)),animation)
    XCTAssertEqual(try animation.restoringFrameVideoSource(),doc)
    let legacy=try VideoTimelineTests().fixture();XCTAssertLessThan(legacy.minimumArchiveVersion,90)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(legacy)),legacy)
  }
  func testIndexed89And90RecoveryMetadataRetainsContext()throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
    for version in [89,90] {
      var doc=try CraftDocument(width:8,height:6)
      if version==90 {try Command.video(.create(frameRate:24,durationFrames:1200)).apply(to:&doc);try Command.video(.blankLayer).apply(to:&doc)}
      let file=root.appendingPathComponent("owned-\(version).photato"),writer=try AtomicFileWriter(to:file),context=Data("Owned recovery context".utf8)
      defer{writer.discard()}
      try NativeIndexedArchive.write(doc,output:.init(file:writer,maximumBytes:NativeArchive.maximumBytes),recoveryContext:context,minimumVersion:version)
      try writer.commit();XCTAssertNotNil(try NativeArchive.readRecoveryMetadata(file))
      let recovered=try NativeArchive.readRecoveryPaged(file);XCTAssertEqual(recovered.context,context);XCTAssertEqual(recovered.document,doc)
    }
  }
  func testBlankCreationRejectsInvalidContextsWithoutMutation()throws {
    var session=EditorSession(document:try CraftDocument(width:8,height:6));let original=session.document
    XCTAssertThrowsError(try session.execute(.video(.blankLayer)));XCTAssertEqual(session.document,original)
    XCTAssertTrue(session.undoStack.isEmpty)
    var doc=try document();doc.depth = .u16
    let invalid=VideoClip(frames:[try Surface(width:8,height:6)],frameRate:24)
    XCTAssertThrowsError(try invalid.validate(depth:doc.depth))
    var over=try document(frames:20_736_001);over.videoTimeline?.frameRate=240
    let before=over;XCTAssertThrowsError(try Command.video(.blankLayer).apply(to:&over));XCTAssertEqual(over,before)
  }
}
