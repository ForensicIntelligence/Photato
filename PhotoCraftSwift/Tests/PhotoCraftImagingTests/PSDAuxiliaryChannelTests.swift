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

  func testWriteRGBWithoutPreviewKeepsEditableSamplesAndIndependentSavedPlanes() throws {
    let directory = try PSDFileOutputTests().directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let controls = try rows().filter { $0["mode"] as? Int == 3 && $0["compression"] as? Int == 0 }
    XCTAssertEqual(controls.count, 6)
    for row in controls {
      let name = try XCTUnwrap(row["file"] as? String)
      let format: PSDFileFormat = row["version"] as? Int == 2 ? .psb : .psd
      let document = try PSDCodec.read(data(name))
      let expectedPreview = try Renderer.composite(document)
      let encoded = try PSDCodec.writeRasterLayers(document, format: format, maximizeCompatibility: false)
      var section = PSDReader(data: encoded)
      _ = try section.bytes(12)
      XCTAssertEqual(try section.u16(), 6)
      _ = try section.bytes(12)
      _ = try section.section()
      XCTAssertEqual(PSDImageResources.hasRealMergedData(try PSDImageResources.blocks(section.section().data)), false)
      let url = directory.appendingPathComponent(name)
      try PSDCodec.writeRasterLayers(document, to: url, format: format, maximizeCompatibility: false)
      XCTAssertEqual(try Data(contentsOf: url), encoded)
      let reopened = try PSDCodec.read(url)
      try compare(reopened, row: row)
      XCTAssertEqual(try Renderer.composite(reopened), expectedPreview)
      XCTAssertEqual(reopened.alphaChannels?.map(\.psdIdentifier), [41, 73])
      XCTAssertEqual(reopened.quickMask?.psdIdentifier, 99)
      XCTAssertThrowsError(try PSDCodec.read(encoded.dropLast()))
      if let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let folder = URL(fileURLWithPath: capture).appendingPathComponent("compatibility-off")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoded.write(to: folder.appendingPathComponent(name))
      }
    }
  }

  func testWideFloatSavedChannelUsesRawPlaceholderWhenPSDRowLengthCouldOverflow() throws {
    let width = 17_000
    var document = try CraftDocument(width: width, height: 2, depth: .f32)
    var gray = try Surface(width: width, height: 2, depth: .f32, fill: .black)
    gray.setPixel(x: width - 1, y: 1, Pixel(0.375, 0.375, 0.375))
    document.alphaChannels = [AlphaChannel(name: "Painted selection", pixels: gray)]
    let encoded = try PSDCodec.writeRasterLayers(document, maximizeCompatibility: false)
    var file = PSDReader(data: encoded)
    _ = try file.bytes(26)
    for _ in 0..<3 { _ = try file.section() }
    XCTAssertEqual(try file.u16(), 0)
    XCTAssertEqual(try PSDCodec.read(encoded).alphaChannels?.first?.pixels, gray)
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

  func testLargeSavedChannelsRetainImplicitGrayAndExactChangedWords() throws {
    let width = 1201, height = 30_001
    for depth in PixelDepth.allCases {
      let bits = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      let methods: [PSDCompression] = depth == .u8 ? [.raw, .rle, .zip, .zipPrediction] : [.rle, .zipPrediction]
      for compression in methods {
        var document = try CraftDocument(width: width, height: height, depth: depth)
        let empty = try Surface(width: width, height: height, depth: depth, fill: .black)
        var selected = ChannelDisplayOptions()
        selected.indicates = .selectedAreas
        document.alphaChannels = [
          AlphaChannel(name: "Selected gray", pixels: empty, options: selected),
          AlphaChannel(name: "Ink", pixels: empty, spot: SpotInk(color: Pixel(1, 0, 0), solidity: 0.5)),
        ]
        document.quickMask = AlphaChannel(name: "Quick Mask", pixels: empty)
        let blocks = try PSDImageResources.blocks(PSDAuxiliaryChannels.resources(document, first: 3))
        document.alphaChannels = nil
        document.quickMask = nil

        let explicitFirst: Float = depth == .f32 ? -0.0 : 0.25
        let explicitLast: Float = depth == .f32 ? 1.5 : 0.75
        let output = PSDOutput()
        try PSDChannelWriter.write(width: width, height: height, depth: bits, compression: compression,
          channels: 3, format: .psb, to: output, repeatedRows: { index in
            index % height == 1 ? height - 2 : 1
          }) { index in
            let y = index % height
            var bytes = [UInt8](repeating: 0, count: width * (bits / 8))
            if y == 0 || y == height - 1 {
              var word: [UInt8] = []
              try PSDChannelCodec.append(y == 0 ? explicitFirst : explicitLast, depth: bits, to: &word)
              let at = (y == 0 ? 3 : width - 1) * (bits / 8)
              bytes.replaceSubrange(at..<at + word.count, with: word)
            }
            return bytes
          }

        let context = try PSDRasterPaging.Context(scratchByteLimit: 12 * 65_536)
        let reader = try PSDChannelReader(PSDReader(data: output.data), width: width, height: height,
          depth: bits, channels: 3, format: .psb)
        try PSDAuxiliaryChannels.read(reader, first: 3, count: 3, blocks: blocks, document: &document, paging: context)
        XCTAssertEqual(reader.remainingRows, 0)
        let channels = PSDAuxiliaryChannels.all(document)
        XCTAssertEqual(channels.map(\.name), ["Selected gray", "Ink", "Quick Mask"])
        for (index, channel) in channels.enumerated() {
          XCTAssertEqual(channel.pixels.defaultPixel.r, index == 2 ? 0 : 1)
          XCTAssertEqual(channel.pixels.tileCount, depth == .f32 && index != 2 ? 1 : 2)
          if depth == .f32, index != 2 {
            let original = try XCTUnwrap(channel.psdSpotGray ?? channel.psdSelectedGray)
            XCTAssertEqual(original.tileCount, 2)
            XCTAssertEqual(original.pixel(x: 3, y: 0).r.bitPattern, Float(-0.0).bitPattern)
          }
          for (x, y, expected) in [(3, 0, explicitFirst), (width - 1, height - 1, explicitLast)] {
            let row = try PSDAuxiliaryChannels.row(channel, y: y, depth: bits)
            var expectedBytes: [UInt8] = []
            try PSDChannelCodec.append(expected, depth: bits, to: &expectedBytes)
            let at = x * (bits / 8)
            XCTAssertEqual(Array(row[at..<at + expectedBytes.count]), expectedBytes)
          }
        }
      }
    }
  }

  func testSparseFloatWriterKeepsOriginalOnlyWordsAcrossTheMaximumCanvas() throws {
    let width = 300_000, height = 300_000
    let tiny = Float(sign: .plus, exponent: -26, significand: 1)
    let smaller = Float(sign: .plus, exponent: -30, significand: 1)
    func gray(_ value: Float) -> Pixel { Pixel(value, value, value) }
    var coverage = try Surface(width: width, height: height, depth: .f32, fill: .white)
    var original = try Surface(width: width, height: height, depth: .f32, fill: gray(tiny))
    original.setPixel(x: 0, y: 0, gray(-0.0))
    original.setPixel(x: width - 1, y: 65, gray(smaller))
    coverage.setPixel(x: 2, y: 0, gray(1.5))
    coverage.setPixel(x: width - 1, y: height - 1, gray(0.25))
    var selected = ChannelDisplayOptions()
    selected.indicates = .selectedAreas
    var alpha = AlphaChannel(name: "Selected coverage", pixels: coverage, options: selected)
    alpha.psdSelectedGray = original
    var spot = AlphaChannel(name: "Spot", pixels: coverage, spot: SpotInk(color: Pixel(1, 0, 0), solidity: 0.5))
    spot.psdSpotGray = original
    for channel in [alpha, spot] {
      let rows = try XCTUnwrap(PSDAuxiliaryChannels.storedRows(channel))
      XCTAssertEqual(rows.repeatedRows(from: 65), 1)
      XCTAssertEqual(rows.repeatedRows(from: 128), 299_968 - 128)
      XCTAssertEqual(rows.repeatedRows(from: height - 1), 1)
      for (y, edits) in [(0, [0: Float(-0.0), 2: Float(-0.5)]), (65, [width - 1: smaller]),
        (128, [:]), (height - 1, [width - 1: Float(0.75)])] {
        let stored = try rows.row(y, channel: 0, depth: 32)
        var expected = Data(count: width * 4)
        expected.withUnsafeMutableBytes { buffer in
          for x in 0..<width {
            buffer.storeBytes(of: (edits[x] ?? tiny).bitPattern.bigEndian, toByteOffset: x * 4, as: UInt32.self)
          }
        }
        XCTAssertEqual(Data(stored), expected)
      }
    }
  }

  func testPagedSavedChannelsRoundTripThroughFileAndDataWriters() throws {
    let width = 1_201, height = 30_001
    var document = try CraftDocument(width: width, height: height)
    document.layers[0].content = .fill(.white)
    var pixels = try Surface(width: width, height: height, fill: Pixel(0.25, 0.25, 0.25))
    pixels.setPixel(x: width - 1, y: height - 1, Pixel(0.75, 0.75, 0.75))
    var options = ChannelDisplayOptions()
    options.indicates = .selectedAreas
    document.alphaChannels = [AlphaChannel(name: "Saved alpha", pixels: pixels, options: options),
      AlphaChannel(name: "Spot", pixels: pixels, spot: SpotInk(color: Pixel(1, 0, 0), solidity: 0.5))]
    document.quickMask = AlphaChannel(name: "Quick Mask", pixels: pixels)
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".psb")
    defer { try? FileManager.default.removeItem(at: target) }
    let data = try PSDCodec.writeRasterLayers(document, compression: .rle, format: .psb, compositeCompression: .rle)
    try PSDCodec.writeRasterLayers(document, to: target, compression: .rle, format: .psb, compositeCompression: .rle)
    XCTAssertEqual(try Data(contentsOf: target), data)
    let imported = try PSDCodec.read(target)
    let channels = PSDAuxiliaryChannels.all(imported)
    XCTAssertEqual(channels.map(\.name), ["Saved alpha", "Spot", "Quick Mask"])
    for (index, channel) in channels.enumerated() {
      let background: UInt8 = index == 2 ? 64 : 191
      let changed: UInt8 = index == 2 ? 191 : 64
      XCTAssertEqual(channel.pixels.tileCount, 1)
      XCTAssertEqual(try PSDAuxiliaryChannels.row(channel, y: 0, depth: 8), Array(repeating: background, count: width))
      XCTAssertEqual(try PSDAuxiliaryChannels.row(channel, y: height - 1, depth: 8),
        Array(repeating: background, count: width - 1) + [changed])
    }
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
