import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class StylePresetRenderingTests:XCTestCase {
  func testEveryEffectAndDepthPresetRoundTripKeepsExactCompositeAndNativeData()throws {
    let old=LayerStyleTests()
    for depth in PixelDepth.allCases {for kind in LayerEffect.Kind.allCases {
      var source=try old.fixture(depth);source.layers[0].style=LayerStyle(effects:[old.effect(kind)]);source.layers[0].opacity=0.7
      let preset=try StylePreset.capture(layerID:source.layers[0].id,in:source,includesBlending:true)
      let saved=try StyleLibraryState(nodes:[.init(name:"Owned",preset:preset)]).encoded();let decoded=try XCTUnwrap(StyleLibraryState.decode(saved).nodes[0].preset)
      var target=source;target.layers[0].style=nil;target.layers[0].opacity=1;target.patterns=nil
      var session=EditorSession(document:target);try session.execute(.layerStyles(try decoded.edit(layerIDs:[target.layers[0].id],in:target)));let changed=session.document
      XCTAssertEqual(try Renderer.composite(changed).rgbaData(depth:.f32),try Renderer.composite(source).rgbaData(depth:.f32),"\(kind) \(depth)")
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(changed)),changed)
      try session.undo();XCTAssertEqual(session.document,target);try session.redo();XCTAssertEqual(session.document,changed)
    }}
  }
  func testPresetResourcesAndBlendingRemainInPortableRecordedStyleReplay()throws {
    var source=try LayerStyleTests().fixture(.f32);source.layers[0].style=LayerStyle(effects:[LayerStyleTests().effect(.patternOverlay)]);source.layers[0].blendMode = .multiply;source.layers[0].opacity=0.6
    let preset=try StylePreset.capture(layerID:source.layers[0].id,in:source,includesBlending:true)
    var blank=source;blank.patterns=nil;blank.layers[0].style=nil;blank.layers[0].opacity=1;blank.layers[0].blendMode = .normal
    var first=EditorSession(document:blank);try first.startActionRecording(name:"Style");try first.execute(.layerStyles(try preset.edit(layerIDs:[blank.layers[0].id],in:blank)));let action=try XCTUnwrap(first.actionRecording?.snapshot);first.stopActionRecording()
    var replay=EditorSession(document:blank);try replay.execute(.action(action));XCTAssertEqual(replay.document,first.document);XCTAssertEqual(try Renderer.composite(replay.document).rgbaData(depth:.f32),try Renderer.composite(source).rgbaData(depth:.f32))
  }
}
