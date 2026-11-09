import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoKeyframeEditingTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:12,height:8,depth:depth)
    d.layers=[Layer(name:"Source",content:.raster(try Surface(width:3,height:2,depth:depth,fill:Pixel(0.7,0.2,0.1,0.5)))),Layer(name:"Destination",content:.raster(try Surface(width:2,height:2,depth:depth,fill:Pixel(0,0,1))))]
    d.activeLayerID=d.layers[0].id;d.videoTimeline=VideoTimeline(frameRate:30,durationFrames:151)
    return d
  }
  func animated(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var s=EditorSession(document:try fixture(depth));let id=s.document.layers[0].id
    try s.execute(.video(.keyframe(.enable(id,.opacity))))
    try s.selectVideoFrame(30);try s.execute(.opacity(id,0.25));try s.selectVideoFrame(0)
    return s.document
  }
  func refs(_ d:CraftDocument,layer:Int=0)->Set<VideoKeyframeReference> {
    Set((d.layers[layer].videoKeyframes ?? []).map{.init(layerID:d.layers[layer].id,keyframeID:$0.id)})
  }
  func testPhotoshopObservedTwoKeyPasteKeepsSpacingValuesAndInterpolation()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let original=try animated(depth),clipboard=try VideoKeyframeClipboard.capture(refs(original),in:original),id=original.layers[0].id
      var s=EditorSession(document:original)
      try s.execute(.video(.keyframes(.paste(clipboard,layers:[id],time:2))))
      let keys=try XCTUnwrap(s.document.layers[0].videoKeyframes)
      XCTAssertEqual(keys.map(\.time),[0,1,2,3]);XCTAssertEqual(keys.map(\.opacity),[1,0.25,1,0.25]);XCTAssertTrue(keys.allSatisfy{$0.interpolation == .linear})
      for frame in [0,15,30] {
        XCTAssertEqual(try original.videoDocument(at:frame).layers[0].opacity,try s.document.videoDocument(at:frame+60).layers[0].opacity)
      }
      let after=s.document;try s.undo();XCTAssertEqual(s.document,original);try s.redo();XCTAssertEqual(s.document,after)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(after)),after)
      XCTAssertEqual(after.minimumArchiveVersion,53)
    }
  }
  func testClipboardSnapshotIsImmutableAndPastesAcrossLayersAndDocuments()throws {
    let original=try animated(.f32),clipboard=try VideoKeyframeClipboard.capture(refs(original),in:original)
    var source=EditorSession(document:original);try source.execute(.opacity(original.layers[0].id,0.4))
    var destination=try fixture(.f32);let ids=destination.layers.map(\.id)
    try VideoKeyframeEdit.paste(clipboard,layers:ids,time:0.5).apply(to:&destination)
    for layer in destination.layers {XCTAssertEqual(layer.videoKeyframes?.map(\.time),[0.5,1.5]);XCTAssertEqual(layer.videoKeyframes?.map(\.opacity),[1,0.25])}
    XCTAssertEqual(clipboard.tracks[0].keys.map(\.opacity),[1,0.25])
    XCTAssertEqual(Set(destination.layers.flatMap{$0.videoKeyframes ?? []}.map(\.id)).count,4)
  }
  func testGroupMoveRemovesSelectedTimesBeforeCollisionChecksAndIsAtomic()throws {
    let original=try animated();var s=EditorSession(document:original);let selected=refs(original)
    try s.execute(.video(.keyframes(.move(selected,seconds:1,duplicate:false))))
    XCTAssertEqual(s.document.layers[0].videoKeyframes?.map(\.time),[1,2]);XCTAssertEqual(Set(s.document.layers[0].videoKeyframes!.map(\.id)),Set(original.layers[0].videoKeyframes!.map(\.id)))
    let moved=s.document;var rejected=moved
    XCTAssertThrowsError(try VideoKeyframeEdit.move(refs(moved),seconds:-3,duplicate:false).apply(to:&rejected))
    XCTAssertEqual(rejected,moved);XCTAssertEqual(s.document,moved)
    try s.undo();XCTAssertEqual(s.document,original)
    XCTAssertThrowsError(try s.execute(.video(.keyframes(.move(selected,seconds:1,duplicate:true)))))
    XCTAssertEqual(s.document,original)
    try s.execute(.video(.keyframes(.move(selected,seconds:2,duplicate:true))))
    XCTAssertEqual(s.document.layers[0].videoKeyframes?.map(\.time),[0,1,2,3]);XCTAssertEqual(Set(s.document.layers[0].videoKeyframes!.map(\.id)).count,4)
  }
  func testPasteOverwritesOnlyMatchingPropertyTimeAndRetainsDestinationIdentity()throws {
    let original=try animated(),clipboard=try VideoKeyframeClipboard.capture(refs(original),in:original)
    var s=EditorSession(document:original);let id=original.layers[0].id,old=original.layers[0].videoKeyframes![1].id
    try s.execute(.video(.keyframes(.paste(clipboard,layers:[id],time:1))))
    let keys=s.document.layers[0].videoKeyframes!
    XCTAssertEqual(keys.map(\.time),[0,1,2]);XCTAssertEqual(keys.map(\.opacity),[1,1,0.25]);XCTAssertEqual(keys[1].id,old)
  }
  func testLockedDestinationsMissingKeysAndInvalidMappingsNeverPartiallyEdit()throws {
    var d=try animated();let clipboard=try VideoKeyframeClipboard.capture(refs(d),in:d),ids=d.layers.map(\.id)
    d.layers[1].locked=true;let before=d
    XCTAssertThrowsError(try VideoKeyframeEdit.paste(clipboard,layers:ids,time:2).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try VideoKeyframeEdit.paste(clipboard,layers:[ids[0],ids[0]],time:2).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try VideoKeyframeEdit.delete([.init(layerID:ids[0],keyframeID:UUID())]).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try VideoKeyframeEdit.move(refs(d),seconds:.nan,duplicate:false).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testMultipleLayerMappingPreservesGlobalRelativeTimesAndBulkHistory()throws {
    var s=EditorSession(document:try animated());let second=s.document.layers[1].id
    try s.selectVideoFrame(15);try s.execute(.video(.keyframe(.enable(second,.opacity))));try s.selectVideoFrame(45);try s.execute(.opacity(second,0.5));try s.selectVideoFrame(0)
    let original=s.document,selection=refs(original).union(refs(original,layer:1)),clipboard=try VideoKeyframeClipboard.capture(selection,in:original)
    try s.execute(.video(.keyframes(.paste(clipboard,layers:[second,original.layers[0].id],time:2))))
    XCTAssertEqual(s.document.layers[1].videoKeyframes?.map(\.time),[0.5,1.5,2,3])
    XCTAssertEqual(s.document.layers[0].videoKeyframes?.map(\.time),[0,1,2.5,3.5])
    try s.undo();XCTAssertEqual(s.document,original)
    try s.execute(.video(.keyframes(.interpolation(selection,.hold))));XCTAssertTrue(s.document.layers.flatMap{$0.videoKeyframes ?? []}.allSatisfy{$0.interpolation == .hold})
    try s.execute(.video(.keyframes(.delete(selection))));XCTAssertTrue(s.document.layers.allSatisfy{$0.videoKeyframes==nil})
    try s.undo();XCTAssertEqual(s.document.layers.flatMap{$0.videoKeyframes ?? []}.count,4)
  }
  func testLargeClipboardReplicationAndLayerBudgetsRejectAtomically()throws {
    var d=try fixture();let originalLayer=d.layers[0]
    d.videoTimeline=VideoTimeline(frameRate:30,durationFrames:4096)
    d.layers[0].videoKeyframes=(0..<4096).map{VideoKeyframe(property:.opacity,time:Double($0)/30,layer:originalLayer)}
    for i in 0..<16 {d.layers.append(Layer(name:"Target \(i)",content:.fill(.clear)))}
    try d.selectVideoFrame(0);try d.validate()
    let clipboard=try VideoKeyframeClipboard.capture(refs(d),in:d),before=d
    XCTAssertThrowsError(try VideoKeyframeEdit.paste(clipboard,layers:d.layers.dropFirst().map(\.id),time:0).apply(to:&d));XCTAssertEqual(d,before)
    let small=try VideoKeyframeClipboard.capture(Set(d.layers[0].videoKeyframes!.prefix(2).map{.init(layerID:d.layers[0].id,keyframeID:$0.id)}),in:d)
    XCTAssertThrowsError(try VideoKeyframeEdit.paste(small,layers:[d.layers[0].id],time:200).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try VideoKeyframeEdit.move(refs(d),seconds:200,duplicate:true).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testContentVisibilityAndGeometryTracksKeepPayloadsAndRejectInvalidInterpolation()throws {
    var d=try fixture(.f32);let id=d.layers[0].id
    let properties:[VideoProperty]=[.content,.visibility,.position,.style,.opacity]
    d.layers[0].videoKeyframes=properties.enumerated().map{VideoKeyframe(property:$0.element,time:Double($0.offset)/10,layer:d.layers[0])}
    try d.selectVideoFrame(0);try d.validate()
    let selection=refs(d),clipboard=try VideoKeyframeClipboard.capture(selection,in:d),before=d
    XCTAssertThrowsError(try VideoKeyframeEdit.interpolation(selection,.linear).apply(to:&d));XCTAssertEqual(d,before)
    try VideoKeyframeEdit.paste(clipboard,layers:[d.layers[1].id],time:2).apply(to:&d)
    XCTAssertEqual(d.layers[1].videoKeyframes?.count,5)
    XCTAssertEqual(d.layers[1].videoKeyframes?.first{$0.property == .content}?.content,clipboard.tracks[0].keys.first{$0.property == .content}?.content)
    var other=try fixture(.u16);let untouched=other
    XCTAssertThrowsError(try VideoKeyframeEdit.paste(clipboard,layers:[other.layers[0].id],time:0).apply(to:&other));XCTAssertEqual(other,untouched)
    var conflict=before;conflict.layers[1].videoKeyframes=[VideoKeyframe(property:.transform,time:0,layer:conflict.layers[1])];try conflict.selectVideoFrame(0);let safe=conflict
    XCTAssertThrowsError(try VideoKeyframeEdit.paste(clipboard,layers:[conflict.layers[1].id],time:2).apply(to:&conflict));XCTAssertEqual(conflict,safe)
    XCTAssertEqual(id,before.layers[0].id)
  }
}
