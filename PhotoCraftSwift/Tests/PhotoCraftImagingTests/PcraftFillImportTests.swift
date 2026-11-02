import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftFillImportTests:XCTestCase {
  func file(_ name:String)throws->Data {try PcraftImportTests().fixture(name,folder:"PcraftFills")}
  func expected(_ bits:String)throws->[[String:Any]] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:file("expected-\(bits).json"))as?[[String:Any]])
  }
  func packed(_ values:[UInt32])->Data {
    var data=Data();for value in values{var word=value.littleEndian;withUnsafeBytes(of:&word){data.append(contentsOf:$0)}};return data
  }
  func testOriginalRustFillsRetainEditableControlsAtEveryDepth()throws {
    for bits in ["u8","u16","f32"] {
      let input=try file("fills-\(bits).pcraft"),doc=try PcraftImport.read(input)
      XCTAssertEqual(doc.layers.count,8);XCTAssertEqual(doc.patterns?.count,1);XCTAssertEqual(doc.layers[0].style?.fillOpacity,0.75)
      guard case .fill(let solid)=doc.layers[0].content else{return XCTFail("Editable solid")}
      XCTAssertEqual(solid,Pixel(0.2,0.4,0.8,0.65))
      for (i,style)in GradientStyle.allCases.enumerated() {
        guard case .gradientFill(let fill)=doc.layers[i+1].content else{return XCTFail("Editable gradient")}
        XCTAssertEqual(fill.placement.style,style);XCTAssertEqual(fill.placement.angle,37);XCTAssertEqual(fill.placement.scale,1.3)
        XCTAssertTrue(fill.placement.reverse);XCTAssertFalse(fill.aligned);XCTAssertFalse(fill.dither)
        XCTAssertEqual(fill.gradient.method,.classic);XCTAssertEqual(fill.gradient.smoothness,0)
        XCTAssertEqual(fill.gradient.colors.map(\.position),[0,0.4,1]);XCTAssertEqual(fill.gradient.colors.map(\.midpoint),[0.5,0.3,0.7])
        XCTAssertEqual(fill.gradient.opacity.map(\.opacity),[0.25,0.9,0.45])
      }
      guard case .patternFill(let fill)=doc.layers[7].content else{return XCTFail("Editable pattern")}
      XCTAssertEqual(fill.patternID,"photato-owned-source-pattern300");XCTAssertEqual(fill.placement.scale,125)
      XCTAssertEqual(fill.placement.angle,15);XCTAssertEqual(fill.placement.phaseX,0.25);XCTAssertEqual(fill.placement.phaseY,-0.5);XCTAssertFalse(fill.linked)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
      var session=EditorSession(document:doc)
      guard case .gradientFill(var changed)=doc.layers[1].content else{return XCTFail("Gradient")}
      changed.placement.angle=123;try session.execute(.setGradientFill(doc.layers[1].id,changed))
      try session.undo();XCTAssertEqual(session.document,doc);try session.redo()
      XCTAssertEqual(session.document.layers[1].content,.gradientFill(changed))
    }
  }
  func testImportedGradientRampsMatchOriginalRustFloatBits()throws {
    for bits in ["u8","u16","f32"] {
      let doc=try PcraftImport.read(file("fills-\(bits).pcraft")),reference=try expected(bits)
      for (layer,item)in zip(doc.layers,reference) {
        guard case .gradientFill(let fill)=layer.content else{continue}
        let ramp=try GradientRamp(fill.gradient),words=try XCTUnwrap(item["ramp_bits"]as?[NSNumber]).map(\.uint32Value)
        let actual=(0...256).flatMap{i->[UInt32]in let p=ramp.sample(Float(i)/256);return[p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}
        XCTAssertEqual(packed(actual),packed(words),"\(bits) \(layer.name)")
      }
    }
  }
  func testImportedFillContentMatchesIndependentRustRGBA8()throws {
    for bits in ["u8","u16","f32"] {
      let doc=try PcraftImport.read(file("fills-\(bits).pcraft")),reference=try expected(bits)
      for (layer,item)in zip(doc.layers,reference) {
        let surface=try Renderer.layerSurface(layer,in:doc)
        var actual=Data()
        for y in 0..<doc.height{for x in 0..<doc.width{
          let p=surface.pixel(x:x,y:y);actual.append(contentsOf:[p.r,p.g,p.b,p.a].map{UInt8((unit($0)*255).rounded())})
        }}
        let expected=Data(try XCTUnwrap(item["rgba8"]as?[NSNumber]).map(\.uint8Value))
        XCTAssertEqual(actual,expected,"\(bits) \(layer.name)")
      }
    }
  }
  func testPatternSampleBitsIncludingHiddenColorsAreRetained()throws {
    for bits in ["u8","u16","f32"] {
      let bytes=try file("fills-\(bits).pcraft"),project=try PcraftProject.read(bytes),doc=try PcraftImport.read(bytes)
      let pattern=try XCTUnwrap(doc.patterns?.first),source=try XCTUnwrap(project.surfaces["/document/patterns/0/surface"])
      XCTAssertEqual(pattern.surface.width,4);XCTAssertEqual(pattern.surface.height,3)
      for y in 0..<3{for x in 0..<4{
        let data=source.pixel(x:Int64(x),y:Int64(y)),depth=try PcraftSamples.depth(source.sample)
        let expected=try data.withUnsafeBytes{try PcraftSamples.pixel($0,at:0,depth:depth,gray:false,alpha:true)}
        XCTAssertTrue(pattern.surface.pixel(x:x,y:y).hasSameBits(as:expected),"\(bits) \(x),\(y)")
      }}
      XCTAssertEqual(pattern.surface.pixel(x:3,y:2).a,0);XCTAssertEqual(pattern.surface.pixel(x:3,y:2).r,bits=="u8" ? Float(191)/255:bits=="u16" ? Float(49151)/65535:0.75)
    }
  }
  func testGrayColorsDefaultsAndSourcePatternNameFallback()throws {
    let input=try file("fills-u8.pcraft")
    let project=try PcraftImportTests().source(input){doc in
      var layers=doc["layers"]as![[String:Any]]
      layers[0]["content"]=["kind":"fill","fill":["Solid":["mode":"Grayscale","c":[0.4,0,0,0],"alpha":0.5]]]
      layers[7]["content"]=["kind":"fill","fill":["Pattern":["name":"source TILE","scale":1.0]]]
      doc["layers"]=layers
    }
    let doc=try PcraftImportTests().convert(project)
    XCTAssertEqual(doc.layers[0].content,.fill(Pixel(0.4,0.4,0.4,0.5)))
    guard case .patternFill(let fill)=doc.layers[7].content else{return XCTFail("Pattern")}
    XCTAssertTrue(fill.linked);XCTAssertEqual(fill.placement.scale,100);XCTAssertEqual(fill.placement.phaseX,0)
  }
  func testExistingRasterProjectsAlsoRetainNondefaultFillOpacity()throws {
    let input=try PcraftImportTests().fixture()
    let project=try PcraftImportTests().source(input){doc in
      var layers=doc["layers"]as![[String:Any]];layers[0]["fill_opacity"]=0.5;doc["layers"]=layers
    }
    let model=try PcraftImportTests().convert(project)
    XCTAssertEqual(model.layers[0].style?.fillOpacity,0.5)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(model)),model)
  }
  func testUnknownUnrepresentableControlsAndMissingPatternsRejectWholeImport()throws {
    let input=try file("fills-u8.pcraft")
    let mutations:[([String:Any])->[String:Any]]=[
      {_ in ["Unknown":[:]]},
      {_ in ["Solid":["mode":"Cmyk","c":[0,1,0,0],"alpha":1]]},
      {_ in ["Solid":["mode":"Rgb","c":[0,1,0,1],"alpha":1]]},
      {_ in ["Pattern":["name":"missing","id":"missing","scale":1]]},
      {_ in ["Pattern":["name":"Source tile","scale":0]]},
      {fill in var result=fill;var gradient=result["Gradient"]as![String:Any];gradient["extra"]=1;result["Gradient"]=gradient;return result},
      {fill in var result=fill;var gradient=result["Gradient"]as![String:Any];var stops=gradient["stops"]as![[Any]];var color=stops[0][1]as![String:Any];color["alpha"]=0.5;stops[0][1]=color;gradient["stops"]=stops;result["Gradient"]=gradient;return result}
    ]
    for mutate in mutations {
      let project=try PcraftImportTests().source(input){doc in
        var layers=doc["layers"]as![[String:Any]],content=layers[1]["content"]as![String:Any]
        content["fill"]=mutate(content["fill"]as![String:Any]);layers[1]["content"]=content;doc["layers"]=layers
      }
      XCTAssertThrowsError(try PcraftImportTests().convert(project))
    }
    let duplicate=try PcraftImportTests().source(input){doc in let patterns=doc["patterns"]as![[String:Any]];doc["patterns"]=patterns+patterns}
    XCTAssertThrowsError(try PcraftImportTests().convert(duplicate))
  }
  func testOffFramePatternSamplesBudgetsAndCancellationAreNotDiscarded()async throws {
    let input=try file("fills-u8.pcraft"),project=try PcraftProject.read(input),path="/document/patterns/0/surface"
    var surfaces=project.surfaces;let original=try XCTUnwrap(surfaces[path]);var tiles=original.tiles
    let coordinate=PcraftProject.Coordinate(x:0,y:0);var data=try XCTUnwrap(tiles[coordinate]);data[255*4]=255;tiles[coordinate]=data
    surfaces[path] = .init(mode:original.mode,sample:original.sample,alpha:original.alpha,bytesPerPixel:original.bytesPerPixel,defaultPixel:original.defaultPixel,tiles:tiles)
    let changed=PcraftProject(rawManifest:project.rawManifest,manifest:project.manifest,surfaces:surfaces,blobs:project.blobs,layerIDs:project.layerIDs,accountedBytes:project.accountedBytes)
    XCTAssertThrowsError(try PcraftImportTests().convert(changed))
    XCTAssertThrowsError(try PcraftImport.read(input,rasterByteLimit:1))
    let task=Task{while !Task.isCancelled{await Task.yield()};return try PcraftImport.read(input)};task.cancel()
    do{_ = try await task.value;XCTFail("Cancelled import committed")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try file("fills-u8.pcraft"),input)
  }
}
