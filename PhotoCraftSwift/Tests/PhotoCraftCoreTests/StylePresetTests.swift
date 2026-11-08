import Foundation
import XCTest
@testable import PhotoCraftCore

final class StylePresetTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:12,height:10)
    d.layers[0].content = .raster(try Surface(width:12,height:10,fill:Pixel(0.2,0.5,0.8,0.7)))
    d.patterns=[try RasterPattern(name:"Owned tile",surface:Surface(width:2,height:2,fill:Pixel(0.8,0.3,0.1)),id:"owned-style")]
    var e=LayerEffect(.patternOverlay);e.pattern=PatternFill(patternID:"owned-style")
    d.layers[0].style=LayerStyle(effects:[e]);d.layers[0].style?.fillOpacity=0.4;d.layers[0].style?.restrictedChannels=[1]
    d.layers[0].opacity=0.35;d.layers[0].blendMode = .multiply;return d
  }
  func testEffectsAndBlendingCapturePreserveIndependentTargetCategories()throws {
    let source=try fixture(),id=source.layers[0].id
    var target=source;target.layers[0].opacity=0.8;target.layers[0].blendMode = .screen;target.layers[0].style=LayerStyle(effects:[LayerEffect(.dropShadow)]);target.layers[0].style?.fillOpacity=0.7;target.layers[0].style?.restrictedChannels=[2]
    let original=target
    let effects=try StylePreset.capture(layerID:id,in:source)
    XCTAssertNil(effects.blending);XCTAssertEqual(effects.patterns,source.patterns!)
    try effects.edit(layerIDs:[id],in:target).apply(to:&target)
    XCTAssertEqual(target.layers[0].style?.effects,source.layers[0].style?.effects);XCTAssertEqual(target.layers[0].style?.fillOpacity,0.7);XCTAssertEqual(target.layers[0].style?.restrictedChannels,[2]);XCTAssertEqual(target.layers[0].opacity,0.8);XCTAssertEqual(target.layers[0].blendMode,.screen)
    target=original
    let blend=try StylePreset.capture(layerID:id,in:source,includesEffects:false,includesBlending:true)
    XCTAssertTrue(blend.patterns.isEmpty);try blend.edit(layerIDs:[id],in:target).apply(to:&target)
    XCTAssertEqual(target.layers[0].style?.effects,original.layers[0].style?.effects);XCTAssertEqual(target.layers[0].style?.fillOpacity,0.4);XCTAssertEqual(target.layers[0].style?.restrictedChannels,[1]);XCTAssertEqual(target.layers[0].opacity,0.35);XCTAssertEqual(target.layers[0].blendMode,.multiply)
    XCTAssertThrowsError(try StylePreset.capture(layerID:id,in:source,includesEffects:false,includesBlending:false))
  }
  func testPatternIdentityConflictsRemapEveryReferenceWithoutReplacingPixels()throws {
    var source=try fixture(),bevel=LayerEffect(.bevelEmboss),advanced=LayerEffectAdvanced()
    advanced.texture=EffectBevelTexture(pattern:.init(patternID:"owned-style"));bevel.advanced=advanced;source.layers[0].style?.effects.append(bevel)
    let p=try StylePreset.capture(layerID:source.layers[0].id,in:source)
    var target=source;target.patterns=[try RasterPattern(name:"Other pixels",surface:Surface(width:2,height:2,fill:.black),id:"owned-style")];let old=target.patterns!
    let edit=try p.edit(layerIDs:[source.layers[0].id],in:target);try edit.apply(to:&target)
    XCTAssertEqual(target.patterns?.first,old[0]);XCTAssertEqual(target.patterns?.count,2)
    let ids=try XCTUnwrap(target.layers[0].style?.presetPatternIDs);XCTAssertEqual(ids.count,1);XCTAssertFalse(ids.contains("owned-style"));let newID=try XCTUnwrap(ids.first)
    XCTAssertEqual(target.pattern(newID)?.surface,p.patterns[0].surface);XCTAssertEqual(target.layers[0].style?.effects[1].advanced?.texture?.pattern.patternID,newID)
  }
  func testInvalidResourcesLockedTargetsAndRecordedBlendingFailAtomically()throws {
    let source=try fixture(),id=source.layers[0].id,p=try StylePreset.capture(layerID:id,in:source,includesBlending:true)
    var invalid=p;invalid.patterns=[];XCTAssertThrowsError(try invalid.validate())
    var target=source;target.layers[0].protection=[.all];let locked=target
    XCTAssertThrowsError(try p.edit(layerIDs:[id],in:target).apply(to:&target));XCTAssertEqual(target,locked)
    var edit=LayerStyleEdit(layerIDs:[id],style:nil);edit.blending=[id:.init(mode:.normal,opacity:0.5,passThrough:true)];target=source
    XCTAssertThrowsError(try edit.apply(to:&target));XCTAssertEqual(target,source)
    let good=try p.edit(layerIDs:[id],in:source),record=RecordedStyleEdit(good,in:source)
    XCTAssertNoThrow(try record.validate());let bytes=try JSONEncoder().encode(record);let decoded=try JSONDecoder().decode(RecordedStyleEdit.self,from:bytes)
    var replay=source;try decoded.resolved(in:replay).apply(to:&replay);XCTAssertEqual(replay,source)
  }
  func testRecordedPresetRetainsAlreadyInstalledResourcesAndRemapsReplayConflicts()throws {
    let source=try fixture(),id=source.layers[0].id,preset=try StylePreset.capture(layerID:id,in:source)
    let edit=try preset.edit(layerIDs:[id],in:source)
    XCTAssertEqual(edit.patterns,source.patterns,"Portable presets must retain dependencies even when already installed.")
    let recorded=RecordedStyleEdit(edit,in:source)
    var target=source;target.layers[0].style=nil;target.patterns=[try RasterPattern(name:"Foreign",surface:Surface(width:2,height:2,fill:.black),id:"owned-style")]
    let old=target.patterns!
    do {let command=try recorded.resolved(in:target);try command.apply(to:&target)}catch{XCTFail("Portable replay must remap resource collisions: \(error)");return}
    XCTAssertEqual(target.patterns?.first,old[0]);XCTAssertEqual(target.patterns?.count,2)
    let mapped=try XCTUnwrap(target.layers[0].style?.effects[0].pattern?.patternID);XCTAssertNotEqual(mapped,"owned-style");XCTAssertEqual(target.pattern(mapped)?.surface,source.patterns![0].surface)
  }
  func testRasterBlendingPresetUsesOrdinaryGroupBlendInsteadOfRetainingPassThrough()throws {
    let source=try fixture(),preset=try StylePreset.capture(layerID:source.layers[0].id,in:source,includesEffects:false,includesBlending:true)
    var target=source;target.layers[0].content = .group(.init(passThrough:true));let id=target.layers[0].id
    try preset.edit(layerIDs:[id],in:target).apply(to:&target)
    XCTAssertEqual(target.layers[0].group?.passThrough,false);XCTAssertEqual(target.layers[0].blendMode,.multiply);XCTAssertEqual(target.layers[0].opacity,source.layers[0].opacity)
  }
  func testLibraryHierarchyMovesCopiesAndCycleRejectionsAreAtomic()throws {
    let source=try fixture(),preset=try StylePreset.capture(layerID:source.layers[0].id,in:source)
    var state=StyleLibraryState();let group=try XCTUnwrap(state.apply(.group("Group",parent:nil)));let empty=try XCTUnwrap(state.apply(.group("Empty",parent:group)))
    let item=try XCTUnwrap(state.apply(.save("Layer look",preset,parent:group)));XCTAssertEqual(try state.ordered().map(\.id),[group,empty,item])
    let before=state;XCTAssertThrowsError(try state.apply(.move([group],parent:empty,before:nil)));XCTAssertEqual(state,before)
    let copy=try XCTUnwrap(state.apply(.duplicate([group,item],parent:nil,before:group)));XCTAssertEqual(state.nodes.count,6);XCTAssertEqual(state.descendants(copy).count,3)
    try state.apply(.rename(copy,"Copied"));try state.apply(.move([item],parent:nil,before:group));let order=try state.ordered().map(\.id);XCTAssertEqual(order.first,copy);XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of:item)),try XCTUnwrap(order.firstIndex(of:group)))
    try state.apply(.delete([copy]));XCTAssertEqual(state.nodes.count,3);try state.validate()
  }
  func testLibraryCodecVersionUnicodeAndMissingResourceGuards()throws {
    let source=try fixture(),preset=try StylePreset.capture(layerID:source.layers[0].id,in:source)
    let state=StyleLibraryState(nodes:[.init(name:"Éclat 🥔",preset:preset)])
    let data=try state.encoded();XCTAssertEqual(try StyleLibraryState.decode(data),state);XCTAssertThrowsError(try StyleLibraryState.decode(data.dropLast()))
    var raw=try XCTUnwrap(PropertyListSerialization.propertyList(from:data,format:nil)as?[String:Any]);raw["version"]=2
    XCTAssertThrowsError(try StyleLibraryState.decode(PropertyListSerialization.data(fromPropertyList:raw,format:.binary,options:0)))
    var invalid=state;invalid.nodes[0].parentID=invalid.nodes[0].id;XCTAssertThrowsError(try invalid.encoded())
    invalid=state;invalid.nodes[0].name="   ";XCTAssertThrowsError(try invalid.encoded())
  }
}
