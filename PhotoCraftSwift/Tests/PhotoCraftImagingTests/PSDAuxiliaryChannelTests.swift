import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDAuxiliaryChannelTests:XCTestCase {
  func folder()throws->URL {try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("PSDAuxiliary")}
  func data(_ name:String)throws->Data {try Data(contentsOf:folder().appendingPathComponent(name))}
  func rows()throws->[[String:Any]] {try XCTUnwrap(JSONSerialization.jsonObject(with:data("cases.json"))as?[[String:Any]])}
  func compare(_ document:CraftDocument,row:[String:Any],file:StaticString = #filePath,line:UInt = #line)throws {
    let channels=PSDAuxiliaryChannels.all(document),expected=row["planes"]as![String]
    XCTAssertEqual(channels.count,3,file:file,line:line);XCTAssertEqual(channels.map(\.name),row["names"]as![String],file:file,line:line)
    for(index,channel)in channels.enumerated(){
      var actual=Data();for y in 0..<document.height{actual.append(contentsOf:try PSDAuxiliaryChannels.row(channel,y:y,depth:document.bitsPerChannel))}
      XCTAssertEqual(actual,try data(expected[index]),"Unchanged gray words \(row["file"]!) channel\(index)",file:file,line:line)
    }
  }
  func testAllIndependentCompressedPlanesAndNative77PreserveEveryWord()throws {
    let cases=try rows();XCTAssertEqual(cases.count,81)
    for row in cases {
      let input=try data(row["file"]as!String),d=try PSDCodec.read(input)
      // These synthetic Float32 fixtures include selected-area gray; native91 retains its exact source words.
      let expectedArchive = (row["depth"]as!Int)==32 && row["independentCorpus"]as?Bool != true ? 91:77
      try compare(d,row:row);XCTAssertEqual(d.minimumArchiveVersion,expectedArchive)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      if row["independentCorpus"]as?Bool != true {
        XCTAssertEqual(d.alphaChannels?.map(\.psdIdentifier),[41,73]);XCTAssertEqual(d.quickMask?.psdIdentifier,99)
        XCTAssertEqual(d.quickMask?.psdQuickMaskInitiallyEmpty,true)
      }else{XCTAssertNil(d.quickMask);XCTAssertTrue(d.alphaChannels?.allSatisfy{$0.spot != nil}==true)}
      XCTAssertEqual(try data(row["file"]as!String),input)
    }
  }
  func testLayeredPSDPSBOutputsKeepPlanesAndAreCapturedForIndependentReader()throws {
    for row in try rows() {
      let d=try PSDCodec.read(data(row["file"]as!String)),format:PSDFileFormat=(row["version"]as!Int)==2 ? .psb:.psd
      let compression=try XCTUnwrap(PSDCompression(rawValue:row["compression"]as!Int))
      let bytes=try PSDCodec.writeRasterLayers(d,compression:compression,format:format,compositeCompression:compression)
      let restored=try PSDCodec.read(bytes);try compare(restored,row:row)
      if let base=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let folder=URL(fileURLWithPath:base).appendingPathComponent("psd-auxiliary");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try bytes.write(to:folder.appendingPathComponent(row["file"]as!String),options:.atomic)
      }
    }
  }
  func testAbsentMergedPreviewRetainsIndependentAuxiliaryPlanesAtEveryDepth() throws {
    let directory = try PSDFileOutputTests().directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // A public Version Info record with one-character writer/reader names.
    let noPreview = Data([0x38, 0x42, 0x49, 0x4D, 0x04, 0x21, 0, 0, 0, 0, 0, 21,
      0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 84, 0, 0, 0, 1, 0, 84, 0, 0, 0, 1, 0])
    func layout(_ bytes: Data, _ format: PSDFileFormat) throws
      -> (resourceLength: Int, layerStart: Int, previewStart: Int) {
      var reader = PSDReader(data: bytes)
      _ = try reader.bytes(26)
      _ = try reader.section()
      let resourceLength = reader.offset
      _ = try reader.section()
      let layerStart = reader.offset
      _ = try reader.section(lengthBytes: format.sectionLengthBytes)
      return (resourceLength, layerStart, reader.offset)
    }
    func withoutPreview(_ bytes: Data, format: PSDFileFormat, planes: Data) throws -> Data {
      let sections = try layout(bytes, format)
      let resourceStart = sections.resourceLength + 4
      var output = PSDWriter()
      output.data = Data(bytes.prefix(sections.resourceLength))
      output.n(sections.layerStart - resourceStart + noPreview.count, 4)
      output.data.append(bytes[resourceStart..<sections.layerStart])
      output.data.append(noPreview)
      output.data.append(bytes[sections.layerStart..<sections.previewStart])
      output.data.append(planes)
      return output.data
    }
    let controls = try rows().filter { $0["mode"] as? Int == 3 && $0["independentCorpus"] as? Bool != true }
    XCTAssertEqual(controls.count, 24)
    for row in controls {
      let name = try XCTUnwrap(row["file"] as? String)
      let format: PSDFileFormat = row["version"] as? Int == 2 ? .psb : .psd
      let input = try data(name)
      let original = try layout(input, format)
      var document = try PSDCodec.read(input)
      // Change an editable pixel without regenerating the independent plane stream.
      let id = try XCTUnwrap(document.layers.first?.id)
      try Command.fill(id, Pixel(0.5, 0.25, 0.75)).apply(to: &document)
      document.layers[0].background = true
      let layerBytes = try PSDCodec.writeRasterLayers(document, format: format)
      XCTAssertEqual(layerBytes[12..<14], input[12..<14])
      let planes = Data(input[original.previewStart...])
      let layerOnly = try withoutPreview(layerBytes, format: format, planes: planes)
      let opened = try PSDCodec.read(layerOnly)
      try compare(opened, row: row)
      XCTAssertEqual(try Renderer.composite(opened), try Renderer.composite(PSDCodec.read(layerBytes)))
      XCTAssertEqual(opened.layers.count, 1)
      XCTAssertThrowsError(try PSDCodec.read(layerOnly.dropLast()), name)
      XCTAssertThrowsError(try PSDCodec.read(layerOnly + Data([7])), name)
      XCTAssertThrowsError(try PSDCodec.read(withoutPreview(input, format: format, planes: planes)), name)
      let target = directory.appendingPathComponent(name)
      try layerOnly.write(to: target)
      let paged = try PSDCodec.read(target)
      try compare(paged, row: row)
      XCTAssertEqual(try Renderer.composite(paged), try Renderer.composite(opened))

      // A signed layer count also declares an obsolete merged transparency plane.
      // Leave alpha/spot/Quick Mask samples at their original channel positions.
      if row["compression"] as? Int == 0 {
        document.layers[0].background = false
        let transparent = try PSDCodec.writeRasterLayers(document, format: format)
        let offset = try layout(transparent, format).previewStart
        var marked = Data(transparent[offset...])
        let processAndTransparency = document.width * document.height * (document.bitsPerChannel / 8) * 4
        marked.replaceSubrange(2..<(2 + processAndTransparency), with: repeatElement(0, count: processAndTransparency))
        let restored = try PSDCodec.read(withoutPreview(transparent, format: format, planes: marked))
        try compare(restored, row: row)
        XCTAssertEqual(try Renderer.composite(restored), try Renderer.composite(PSDCodec.read(transparent)))
      }
    }
  }

  func testUnusedRawPreviewPlanesSkipFilePagesAndValidateTheirBounds() throws {
    let directory = try PSDFileOutputTests().directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let width = 300_000, height = 2, retained = [UInt8](repeating: 17, count: 300_000)
    var bytes = Data(count: 2 + width * height * 3)
    bytes.append(contentsOf: retained)
    bytes.append(contentsOf: retained)
    let path = directory.appendingPathComponent("Uncompressed planes.psb")
    try bytes.write(to: path)
    let source = try PSDFileSource(path)
    let reader = try PSDChannelReader(PSDReader(file: source), width: width, height: height,
      depth: 8, channels: 4, format: .psb)
    let callsBeforeDiscard = source.metrics.readCalls
    try reader.discardRows(height * 3)
    XCTAssertEqual(source.metrics.readCalls, callsBeforeDiscard)
    for _ in 0..<height { XCTAssertEqual(try reader.nextRow(), retained) }
    XCTAssertEqual(reader.remainingRows, 0)
    try source.validateUnchanged()

    let short = try PSDChannelReader(PSDReader(data: Data(bytes.prefix(100))), width: width,
      height: height, depth: 8, channels: 4, format: .psb)
    XCTAssertThrowsError(try short.discardRows(height * 3))
    let long = try PSDChannelReader(PSDReader(data: bytes + Data([0])), width: width,
      height: height, depth: 8, channels: 4, format: .psb)
    XCTAssertThrowsError(try long.discardRemaining())
  }

  func testFloatSpotGrayUsesOriginalOnlyUntilTheSampleChanges()throws {
    var d=try PSDCodec.read(data("m3-d32-v1-c0.psd"));let channel=try XCTUnwrap(d.alphaChannels?.last),original=try XCTUnwrap(channel.psdSpotGray)
    var before=Data();for y in 0..<d.height{before.append(contentsOf:try PSDAuxiliaryChannels.row(channel,y:y,depth:32))}
    XCTAssertEqual(before,try data("m3-d32-channel1.bin"))
    d.selection = .init(x:1,y:1,width:1,height:1)
    try Command.channel(.fill(.alpha(channel.id),0.25,1)).apply(to:&d)
    let edited=try d.channel(.alpha(channel.id));XCTAssertEqual(edited.psdSpotGray,original)
    let row=try PSDAuxiliaryChannels.row(edited,y:1,depth:32);XCTAssertEqual(try PSDChannelCodec.sample(row,1,depth:32),0.25)
    for y in 0..<d.height {for x in 0..<d.width where x != 1 || y != 1 {
      let actual=try PSDAuxiliaryChannels.row(edited,y:y,depth:32);XCTAssertEqual(try PSDChannelCodec.sample(actual,x,depth:32).bitPattern,original.pixel(x:x,y:y).r.bitPattern)
    }}
  }
  func testMetadataValidationNamesAndUnknownBookColorsAreExplicit()throws {
    let d=try PSDCodec.read(data("m3-d8-v1-c0.psd")),channels=PSDAuxiliaryChannels.all(d)
    XCTAssertEqual(channels.map(\.name),["Mask α","Ink Ω","Quick Mask"])
    var raw=Data(repeating:0,count:13);raw[0]=0x23;raw[1]=0x31
    XCTAssertThrowsError(try PSDInkChannels.display(raw))
    let duplicated=[PSDImageResources.Block(id:1053,data:Data(),raw:Data()),PSDImageResources.Block(id:1053,data:Data(),raw:Data())]
    var document=try CraftDocument(width:1,height:1)
    let stream=try PSDChannelReader(PSDReader(data:Data([0,0,0])),width:1,height:1,depth:8)
    XCTAssertThrowsError(try PSDAuxiliaryChannels.read(stream,first:3,count:1,blocks:duplicated,document:&document,paging:nil))
    var invalid=PSDWriter();invalid.n(2,2);invalid.n(0,1)
    XCTAssertThrowsError(try PSDAuxiliaryChannels.read(stream,first:3,count:1,blocks:[.init(id:1022,data:invalid.data,raw:Data())],document:&document,paging:nil))
    let long=String(repeating:"A",count:1024);var channel=channels[0];channel.name=long;document.alphaChannels=[channel]
    document.width=d.width;document.height=d.height
    let blocks=try PSDImageResources.blocks(PSDAuxiliaryChannels.resources(document,first:4));XCTAssertEqual(try PSDAuxiliaryChannels.names(blocks,count:1),[long])
  }
  func testFiftySixChannelBoundaryNeverDropsPlanesAndCancellationIsAtomic()async throws {
    var d=try CraftDocument(width:2,height:1);d.layers[0].content = .fill(.white)
    d.alphaChannels=try (0..<52).map{AlphaChannel(name:"A\($0)",pixels:try Surface(width:2,height:1,fill:.white))}
    d.quickMask=AlphaChannel(name:"Quick Mask",pixels:try Surface(width:2,height:1,fill:.black))
    let bytes=try PSDCodec.writeRasterLayers(d),restored=try PSDCodec.read(bytes)
    XCTAssertEqual(Int(bytes[12])<<8|Int(bytes[13]),56);XCTAssertEqual(restored.alphaChannels?.count,52);XCTAssertNotNil(restored.quickMask)
    d.layers[0].content = .fill(Pixel(1,1,1,0.5));XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    let input=try data("m3-d32-v2-c3.psb")
    let task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try PSDCodec.read(input)}
    do{_ = try await task.value;XCTFail("Cancellation expected")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try data("m3-d32-v2-c3.psb"),input)
  }
}
