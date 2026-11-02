import Foundation
import XCTest
@testable import PhotoCraftCore

final class DocumentDuplicationTests: XCTestCase {
  func testWholeDocumentPreservesDocumentOwnedDataAndLocalReferences() throws {
    var source = try CraftDocument(width:4,height:3,depth:.u16,name:"Source")
    source.layers[0].mask = try Surface(width:4,height:3,depth:.u16,fill:Pixel(0.5,0.5,0.5))
    source.selection = IntRect(x:1,y:1,width:2,height:1)
    source.alphaChannels = [AlphaChannel(name:"Saved",pixels:try Surface(width:4,height:3,depth:.u16,fill:Pixel(0.25,0.25,0.25)))]
    source.guides = [DocumentGuide(axis:.vertical,position:1.5)]
    source.sourceMetadata = ["owned":Data([0,255,17])];source.resolution=300
    try Command.layerComp(.capture(id:UUID(),name:"Original",comment:"Owned",options:LayerCompOptions())).apply(to:&source)
    let copy = try DocumentDuplication.copy(source,name:"Independent")
    XCTAssertNotEqual(copy.id,source.id);XCTAssertEqual(copy.name,"Independent")
    var normalized = copy;normalized.id=source.id;normalized.name=source.name
    XCTAssertEqual(normalized,source);XCTAssertEqual(copy.activeLayerID,source.activeLayerID)
    XCTAssertEqual(copy.layerComps,source.layerComps)
  }
  func testCopyOnWriteMutationAndSparseMaximumDoNotChangeSource() throws {
    var source=try CraftDocument(width:300000,height:300000,depth:.f32)
    var pixels=try Surface(width:source.width,height:source.height,depth:.f32,fill:Pixel(4,-0.25,0.5,1)).interpretingSamples(as:.linearRGB)
    pixels.setLinearPixel(x:150000,y:150000,Pixel(-0.0,8,2,1));source.layers[0].content = .raster(pixels)
    var copy=try DocumentDuplication.copy(source,name:"Copy")
    guard case .raster(var changed)=copy.layers[0].content else{return XCTFail("Raster")}
    XCTAssertTrue(changed.linearPixel(x:150000,y:150000).hasSameBits(as:pixels.linearPixel(x:150000,y:150000)))
    XCTAssertLessThan(copy.estimatedBytes,2*1024*1024)
    changed.setLinearPixel(x:150000,y:150000,.white);copy.layers[0].content = .raster(changed)
    guard case .raster(let original)=source.layers[0].content else{return XCTFail("Raster")}
    XCTAssertTrue(original.linearPixel(x:150000,y:150000).hasSameBits(as:Pixel(-0.0,8,2,1)))
  }
  func testNativeModesKeepOriginalComponentPlanesAndDepths() throws {
    for mode in [DocumentColorMode.grayscale,.cmyk,.lab] {
      let source=try CraftDocument(width:3,height:2,depth:.u16).convertingMode(.init(mode:mode,depth:.u16))
      var copy=try DocumentDuplication.copy(source,name:"Native copy");copy.id=source.id;copy.name=source.name
      XCTAssertEqual(copy,source);XCTAssertEqual(copy.layers[0].nativeMode,source.layers[0].nativeMode)
      XCTAssertNotNil(DocumentDuplication.mergedUnavailableReason(source))
    }
  }
  func testInvalidNamesDoNotAlterInput() throws {
    let source=try CraftDocument(width:2,height:1)
    for name in ["", "  "] {XCTAssertThrowsError(try DocumentDuplication.copy(source,name:name))}
    XCTAssertEqual(source.layers.count,1)
  }
}
