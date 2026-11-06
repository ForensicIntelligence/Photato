import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ColorLookupFormatsTests: XCTestCase {
  func options(_ size:Int=3)->ColorLookupExportRequest {
    .init(size:size,title:"Owned étage # grade",copyright:"FI Test",formats:ColorLookupFileFormat.allCases,baseName:"Owned grade",created:Date(timeIntervalSince1970:1793923200))
  }
  func table()throws->ColorLUT {try .generated(title:options().title,size:3){p in .init(0.1+0.7*p.x,0.2+0.6*p.z,0.05+0.8*p.y)}}
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:6,depth:depth);d.layers[0].background=true;d.layers.append(Layer(name:"Invert",content:.adjustment(.invert)));return d
  }
  func testAllFourFormatsHaveIndependentAxesAndICCStructureAndRetainLegacyCubeBytes()throws {
    let lut=try table(),request=options()
    let files=try ColorLookupFileFormat.allCases.map {format in ColorLookupEncodedFile(format:format,name:request.baseName+"."+format.rawValue,data:try ColorLookupFormats.encode(lut,format:format,request:request))}
    XCTAssertEqual(files.map(\.name),["Owned grade.3dl","Owned grade.cube","Owned grade.csp","Owned grade.icc"])
    let three=try ColorLUTFile.read(files[0].data,name:files[0].name)
    XCTAssertEqual(three.size,3)
    XCTAssertEqual(three.values[0],Float(410)/4095)
    XCTAssertEqual(three.values[3],Float(1843)/4095)
    XCTAssertEqual(three.values[3*9+1],Float(2048)/4095)
    let csp=try XCTUnwrap(String(data:files[2].data,encoding:.utf8));XCTAssertTrue(csp.hasPrefix("CSPLUTV100\n3D\n"));XCTAssertTrue(csp.contains("3 3 3\n"));XCTAssertTrue(csp.contains("© Copyright 2026 FI Test"))
    let icc=files[3].data
    func u16(_ i:Int)->Int {Int(icc[i])<<8|Int(icc[i+1])}
    func u32(_ i:Int)->Int {icc[i..<i+4].reduce(0){$0<<8|Int($1)}}
    XCTAssertEqual(u32(0),icc.count);XCTAssertEqual(String(decoding:icc[12..<24],as:UTF8.self),"linkRGB RGB ")
    XCTAssertEqual(String(decoding:icc[36..<40],as:UTF8.self),"acsp");XCTAssertEqual(u16(24),2026)
    var tags:[String:(Int,Int)]=[:]
    for i in 0..<u32(128) {let at=132+i*12;tags[String(decoding:icc[at..<at+4],as:UTF8.self)]=(u32(at+4),u32(at+8))}
    XCTAssertEqual(Set(tags.keys),["desc","cprt","pseq","A2B0"])
    for value in tags.values {XCTAssertEqual(value.0%4,0);XCTAssertLessThanOrEqual(value.0+value.1,icc.count)}
    let start=try XCTUnwrap(tags["A2B0"]).0
    XCTAssertEqual(String(decoding:icc[start..<start+4],as:UTF8.self),"mft2");XCTAssertEqual(icc[start+10],3)
    let grid=start+52+12
    XCTAssertEqual([u16(grid),u16(grid+2),u16(grid+4)],[6554,13107,3277])
    XCTAssertEqual([u16(grid+2*6),u16(grid+2*6+2),u16(grid+2*6+4)],[6554,52428,3277])
    XCTAssertEqual([u16(grid+18*6),u16(grid+18*6+2),u16(grid+18*6+4)],[52428,13107,3277])
    var legacy=request;legacy.copyright=""
    XCTAssertEqual(try ColorLookupFormats.encode(lut,format:.cube,request:legacy),try ColorLUTFile.writeCube(lut))
    if let dir=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let path=URL(fileURLWithPath:dir).appendingPathComponent("format-reference");try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
      for file in files {try file.data.write(to:path.appendingPathComponent(file.name))}
      let expected:[String:Any]=["title":request.title,"copyright":request.copyrightLine,"size":3,"transform":"r=0.1+0.7r; g=0.2+0.6b; b=0.05+0.8g","source":"Owned analytical affine RGB transform; not Adobe output"]
      try JSONSerialization.data(withJSONObject:expected,options:[.prettyPrinted,.sortedKeys]).write(to:path.appendingPathComponent("expected.json"))
    }
  }
  func testAllBakedFormatsShareCanonicalSamplingAndPreserveDocumentAtEveryDepth()throws {
    for depth in PixelDepth.allCases {
      let original=try fixture(depth),before=try NativeArchive.encodeChunked(original,minimumVersion:86),request=options(),files=try ColorLookupExport.files(original,request:request)
      XCTAssertEqual(files.count,4)
      let cube=try XCTUnwrap(files.first{$0.format == .cube})
      let decoded=try ColorLUTFile.read(cube.data,name:cube.name),expected=try ColorLookupExport.bake(original,size:3,title:request.title)
      XCTAssertEqual(decoded.values,expected.values)
      XCTAssertEqual(try NativeArchive.encodeChunked(original,minimumVersion:86),before)
      let zip=try ColorLookupExport.archive(files);XCTAssertTrue(zip.starts(with:[0x50,0x4b,3,4]));XCTAssertLessThan(zip.count,20000)
    }
  }
  func testMetadataShapeExtendedRangeIntegerLimitsAndCancelledEncodingAreExplicit()async throws {
    let lut=try table()
    var bad=options();bad.formats=[];XCTAssertThrowsError(try ColorLookupFormats.encode(lut,format:.icc,request:bad))
    for change in [0,1,2,3,4] {
      var q=options()
      switch change {case 0:q.formats=[.cube,.cube];case 1:q.baseName="../escape";case 2:q.copyright="bad\nline";case 3:q.created=Date(timeIntervalSince1970:.infinity);default:q.size=130}
      XCTAssertThrowsError(try q.validate())
    }
    var hdr=lut;hdr.values[0] = -0.25;hdr.values[1]=2
    XCTAssertThrowsError(try ColorLookupFormats.encode(hdr,format:.icc,request:options()))
    XCTAssertThrowsError(try ColorLookupFormats.encode(hdr,format:.threeDL,request:options()))
    XCTAssertNoThrow(try ColorLookupFormats.encode(hdr,format:.csp,request:options()))
    let request=options();let task=Task {try Task.checkCancellation();return try ColorLookupFormats.encode(lut,format:.icc,request:request)};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled LUT delivered")}catch is CancellationError {}catch {XCTFail("Unexpected \(error)")}
  }
  func testDeclared3DLPrecisionPreservesDarkTablesAndSmallGrids()throws {
    for n in [2,3,5] {
      let lut=try ColorLUT.generated(title:"Dark",size:n){$0*0.1}
      let data=try ColorLookupFormats.encode(lut,format:.threeDL,request:options(n)),decoded=try ColorLUTFile.read(data,name:"Dark.3dl")
      XCTAssertEqual(decoded.size,n);XCTAssertEqual(decoded.values.last,Float(410)/4095)
    }
  }
}
