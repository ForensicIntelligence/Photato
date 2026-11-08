import Foundation
import XCTest
@testable import PhotoCraftCore

final class LegacyChannelFilterCaptureTests:XCTestCase {
  enum Target:String,CaseIterable {case alpha,quickMask,spot}
  static let kinds:[RasterFilter.Kind] = [.gaussianBlur,.boxBlur,.motionBlur,.highPass,.unsharpMask,.addNoise,.average,.mosaic]
  func filter(_ kind:RasterFilter.Kind)->RasterFilter {
    var f=RasterFilter(kind)
    if [.gaussianBlur,.boxBlur,.highPass,.unsharpMask].contains(kind){f.radius=1}
    if kind == .motionBlur{f.distance=3}
    if kind == .mosaic{f.cellSize=2}
    if kind == .addNoise{f.seed=42;f.amount=13}
    return f
  }
  func fixture(_ depth:PixelDepth,target:Target,selected:Bool=false,indicates:ChannelDisplayOptions.Indicates = .maskedAreas)throws->(CraftDocument,ChannelPlaneTarget) {
    var d=try CraftDocument(width:12,height:8,depth:depth)
    var pixels=try Surface(width:12,height:8,depth:depth)
    for y in 0..<8 {for x in 0..<12 {
      let v=Float((x+2*y)%7)/6
      pixels.setPixel(x:x,y:y,Pixel(v,0.92,0.14,x%2==0 ? 0:0.7))
    }}
    var options=ChannelDisplayOptions();options.indicates=indicates;options.color=Pixel(0.2,0.5,0.8);options.opacity=0.37
    var value=AlphaChannel(name:"Owned \(target.rawValue)",pixels:pixels,options:options,spot:target == .spot ? SpotInk(color:Pixel(0.8,0.2,0.6),solidity:0.43):nil)
    value.psdIdentifier=42
    if target == .spot && depth == .f32 {value.psdSpotGray=try pixels.mappedStoredSamples {p in let v=1-unit(p.r);return Pixel(v,v,v)}}
    let plane:ChannelPlaneTarget
    if target == .quickMask {d.quickMask=value;plane = .quickMask}
    else {d.alphaChannels=[value];plane = .alpha(value.id)}
    if selected {
      var bytes=[UInt8](repeating:0,count:12*8)
      for y in 2..<6 {for x in 2..<8 {bytes[y*12+x]=UInt8(((x+3*y)%3+1)*85)}}
      d.setCoverageSelection(try SelectionMask(width:12,height:8,bytes:bytes))
    }
    return(d,plane)
  }
  func append(_ pixel:Pixel,to data:inout Data) {
    for v in [pixel.r,pixel.g,pixel.b,pixel.a] {var bits=v.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}}
  }
  func testCaptureSmallChannelFiltersAcrossDepthTargetsSelectionsAndDisplayOptions() throws {
    var data=Data(),cases=[[String:Any]]()
    for depth in PixelDepth.allCases {for target in Target.allCases {for kind in Self.kinds {for selected in [false,true] {for indicates in ChannelDisplayOptions.Indicates.allCases {
      let (original,plane)=try fixture(depth,target:target,selected:selected,indicates:indicates)
      var session=EditorSession(document:original)
      let command=Command.channel(.filter(plane,filter(kind)))
      try session.execute(command)
      let result=session.document,output=try result.channel(plane),source=try original.channel(plane)
      var expected=source;expected.pixels=output.pixels
      XCTAssertEqual(output,expected);XCTAssertEqual(result.layers,original.layers);XCTAssertEqual(result.selection,original.selection);XCTAssertEqual(result.selectionMask,original.selectionMask)
      let changed=result != original;XCTAssertEqual(session.undoStack.count,changed ? 1:0)
      if changed {try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,result)}
      let offset=data.count
      for y in 0..<8 {for x in 0..<12 {append(output.pixels.pixel(x:x,y:y),to:&data)}}
      cases.append(["depth":String(describing:depth),"target":target.rawValue,"kind":kind.rawValue,"selected":selected,"indicates":indicates.rawValue,"offset":offset,"bytes":data.count-offset])
    }}}}}
    XCTAssertEqual(cases.count,288);XCTAssertEqual(data.count,442368)
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let root=URL(fileURLWithPath:folder)
      try data.write(to:root.appendingPathComponent("channel-filter-small.f32"))
      try JSONSerialization.data(withJSONObject:cases,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("channel-filter-small-cases.json"))
    }
  }
  func testAverageIsNumericCoverageWithOpaqueRedundantChannelsAtEveryDepthAndTarget() throws {
    var captured=Data()
    for depth in PixelDepth.allCases {for target in Target.allCases {
      var (d,plane)=try fixture(depth,target:target)
      var pixels=try Surface(width:12,height:8,depth:depth,fill:Pixel(0.5,0.1,0.9,0))
      for y in 0..<8 {for x in 0..<12 {let v:Float=x%2==0 ? 0:1;pixels.setPixel(x:x,y:y,Pixel(v,0.7,0.2,x%3==0 ? 0:1))}}
      if target == .quickMask {d.quickMask?.pixels=pixels}else{d.alphaChannels?[0].pixels=pixels}
      let before=d;try Command.channel(.filter(plane,filter(.average))).apply(to:&d)
      let output=try d.channel(plane).pixels,expected=Pixel(0.5,0.5,0.5).quantized(depth)
      for y in 0..<8 {for x in 0..<12 {XCTAssertEqual(output.pixel(x:x,y:y),expected)}}
      for x in 0..<4 {append(output.pixel(x:x,y:0),to:&captured)}
      XCTAssertEqual(d.layers,before.layers)
    }}
    XCTAssertEqual(captured.count,576)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try captured.write(to:URL(fileURLWithPath:path).appendingPathComponent("channel-filter-average.f32"))}
  }
}
