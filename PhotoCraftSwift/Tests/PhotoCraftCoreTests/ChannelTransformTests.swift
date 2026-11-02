import XCTest
@testable import PhotoCraftCore

final class ChannelTransformTests:XCTestCase{
  func fixture(_ depth:PixelDepth = .u8,kind:Int=0,selected:Bool=false)throws->(CraftDocument,ChannelPlaneTarget){
    var d=try CraftDocument(width:16,height:12,depth:depth),plane=try Surface(width:16,height:12,depth:depth,fill:.black)
    for y in 0..<12{for x in 0..<16{let v=Float(10+x*7+y*5)/255;plane.setPixel(x:x,y:y,Pixel(v,v,v))}}
    var channel=AlphaChannel(name:"Target",pixels:plane);channel.options.opacity=0.3;channel.options.color=Pixel(0,1,0);channel.psdIdentifier=17
    if kind==1{channel.spot=SpotInk(color:Pixel(0.4,0.2,0.6),solidity:0.7);if depth == .f32{channel.psdSpotGray=try plane.mappedStoredSamples{p in let v=1-p.r;return Pixel(v,v,v)}}}
    let target:ChannelPlaneTarget;if kind==2{d.quickMask=channel;target = .quickMask}else{d.alphaChannels=[AlphaChannel(name:"Untouched",pixels:try Surface(width:16,height:12,depth:depth,fill:.white)),channel];target = .alpha(channel.id)}
    if selected{d.selection = .init(x:3,y:2,width:6,height:5)};return(d,target)
  }
  func testWholeAndSelectedThreeDepthAlphaSpotQuickMaskPreserveOtherData()throws{
    for depth in PixelDepth.allCases{for kind in 0..<3{for selected in [false,true]{let(source,target)=try fixture(depth,kind:kind,selected:selected);var d=source;let old=try source.channel(target);try Command.transformChannel(.init(target:target,matrix:.init(.translation(3,2)),interpolation:.nearest,backgroundValue:0.4)).apply(to:&d);let changed=try d.channel(target);XCTAssertEqual(changed.pixels.pixel(x:7,y:5).r,old.pixels.pixel(x:4,y:3).r);XCTAssertEqual(d.layers,source.layers);XCTAssertEqual(d.workingICC,source.workingICC);XCTAssertEqual(changed.name,old.name);XCTAssertEqual(changed.options,old.options);XCTAssertEqual(changed.spot,old.spot);XCTAssertEqual(changed.psdIdentifier,17)
      if selected{XCTAssertEqual(d.selection?.x,6);XCTAssertEqual(d.selection?.y,4)}else{XCTAssertNil(d.selection)};if case .alpha=target{XCTAssertEqual(d.alphaChannels?.first,source.alphaChannels?.first)};try d.validate()
    }}}
  }
  func testEditingGrayAndSelectedAreasSpotInversionApplyOnce()throws{
    for kind in 0..<3{for selected in [false,true]{for invert in [false,true]{var(source,target)=try fixture(.f32,kind:kind,selected:selected);if invert{switch target{case .alpha(let id):let i=try XCTUnwrap(source.alphaChannels?.firstIndex{$0.id==id});source.alphaChannels?[i].options.indicates = .selectedAreas;case .quickMask:source.quickMask?.options.indicates = .selectedAreas}};let before=try source.channel(target);var d=source;try Command.transformChannel(.init(target:target,matrix:.init(.translation(9,5)),interpolation:.nearest,backgroundValue:0.25)).apply(to:&d);let output=try d.channel(target),x=selected ? 3:0,y=selected ? 2:0;XCTAssertEqual(output.pixels.pixel(x:x,y:y).r,before.display(0.25),accuracy:1e-6);XCTAssertEqual(output.options,before.options)}}}
  }
  func testSoftSelectionCopiesAndRawNumericGrayIgnoreRedundantAlphaRGB()throws{
    var(d,target)=try fixture(.f32,selected:true),plane=try d.channel(target).pixels;plane.setPixel(x:4,y:3,Pixel(0.8,0.1,0.2,0));if case .alpha(let id)=target{let i=try XCTUnwrap(d.alphaChannels?.firstIndex{$0.id==id});d.alphaChannels?[i].pixels=plane};var bytes=[UInt8](repeating:0,count:192);bytes[3*16+4]=128;d.setCoverageSelection(try SelectionMask(width:16,height:12,bytes:bytes));let source=d,old=try d.channel(target).pixels.pixel(x:9,y:6).r,k:Float=128/255
    try Command.transformChannel(.init(target:target,matrix:.init(.translation(5,3)),interpolation:.nearest,backgroundValue:1,copy:true)).apply(to:&d);let p=try d.channel(target).pixels;XCTAssertEqual(p.pixel(x:9,y:6).r,0.8*k+old*(1-k),accuracy:1e-6);XCTAssertEqual(p.pixel(x:4,y:3).r,try source.channel(target).pixels.pixel(x:4,y:3).r);XCTAssertEqual(p.pixel(x:9,y:6).a,1)
  }
  func testProjectiveMethodsAndFloatSpotGrayAreRetainedAtMovedSamples()throws{
    let(source,target)=try fixture(.f32,kind:1);for method in Resampling.allCases{var d=source;try Command.transformChannel(.init(target:target,matrix:try .init([1,0.1,1,0,1,1,0.003,0.002,1]),interpolation:method)).apply(to:&d);XCTAssertNotNil(try d.channel(target).psdSpotGray);try d.validate()}
    var translated=source;try Command.transformChannel(.init(target:target,matrix:.init(.translation(3,2)),interpolation:.nearest)).apply(to:&translated);XCTAssertEqual(try translated.channel(target).psdSpotGray?.pixel(x:7,y:5).r.bitPattern,try source.channel(target).psdSpotGray?.pixel(x:4,y:3).r.bitPattern)
  }
  func testPortableActionsResolveDuplicateNamesWithoutOriginalUUIDAndUndo()throws{
    let(source,target)=try fixture(.u16,selected:true);var session=EditorSession(document:source);try session.startActionRecording(name:"Channel");try session.execute(.transformChannel(.init(target:target,matrix:.init(.translation(3,2)),interpolation:.nearest,backgroundValue:0.5)));let result=session.document;XCTAssertEqual(session.undoStack.last?.label,"Free Transform");var replay=source;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,result);try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,result)
    var portable=source;portable.alphaChannels?[1].id=UUID();try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&portable);XCTAssertEqual(portable.alphaChannels?[1].pixels,result.alphaChannels?[1].pixels);XCTAssertEqual(portable.layers,result.layers)
    var duplicate=source;var second=try source.channel(target);second.id=UUID();duplicate.alphaChannels?.append(second);let ref=ActionChannelTarget(.alpha(second.id),in:duplicate);XCTAssertEqual(try ref.resolve(in:duplicate),.alpha(second.id))
  }
  func testInvalidStaleIdentityAndCancellationAreAtomic()async throws{
    let(source,target)=try fixture();for value in [Float.nan,.infinity,-0.1,1.1]{var d=source;XCTAssertThrowsError(try Command.transformChannel(.init(target:target,matrix:.identity,backgroundValue:value)).apply(to:&d));XCTAssertEqual(d,source)}
    var d=source;XCTAssertThrowsError(try Command.transformChannel(.init(target:.alpha(UUID()),matrix:.identity)).apply(to:&d));XCTAssertEqual(d,source);var session=EditorSession(document:source);try session.execute(.transformChannel(.init(target:target,matrix:.identity)));XCTAssertTrue(session.undoStack.isEmpty)
    let edit=try PreparedEdit(command:.transformChannel(.init(target:target,matrix:.init(.translation(1,0)))),document:source);try session.execute(.renameLayer(source.layers[0].id,"Changed"));let before=session.document;XCTAssertThrowsError(try session.executePrepared(edit));XCTAssertEqual(session.document,before)
    let task=Task{while !Task.isCancelled{await Task.yield()};var d=source;try Command.transformChannel(.init(target:target,matrix:.init(.translation(1,0)))).apply(to:&d)};task.cancel();do{try await task.value;XCTFail("Canceled channel transform committed")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testSparseMaximumWholeAndSelectedPlanesStayBounded()throws{
    for selected in [false,true]{var d=try CraftDocument(width:300000,height:300000),plane=try Surface(width:300000,height:300000,fill:.black);plane.setPixel(x:65,y:65,.white);let channel=AlphaChannel(name:"Large",pixels:plane);d.alphaChannels=[channel];if selected{d.selection = .init(x:64,y:64,width:10,height:10)};try Command.transformChannel(.init(target:.alpha(channel.id),matrix:.init(.translation(32,16)),interpolation:.nearest,backgroundValue:0)).apply(to:&d);XCTAssertEqual(d.alphaChannels?[0].pixels.pixel(x:97,y:81),.white);XCTAssertLessThan(try XCTUnwrap(d.alphaChannels?.first).pixels.allocatedBytes,2_097_152);XCTAssertEqual(d.alphaChannels?.first?.pixels.width,300000)}
  }
  func testAnalyticalWholeSelectedAndCopyOutputsCapturedForIndependentReader()throws{
    var rows:[[String:Any]]=[]
    for(selected,copy,matrix) in [(false,false,ProjectiveTransform(.translation(3,2))),(true,false,ProjectiveTransform(.translation(-5,-2))),(true,true,ProjectiveTransform(.translation(2,1))),(false,false,try ProjectiveTransform([1,0,1,0,1,-1,0.037,0.013,1]))]{var(d,target)=try fixture(selected:selected);try Command.transformChannel(.init(target:target,matrix:matrix,interpolation:.nearest,backgroundValue:40/255,copy:copy)).apply(to:&d);let plane=try d.channel(target).pixels;var values:[Int]=[];for y in 0..<12{for x in 0..<16{values.append(Int((plane.pixel(x:x,y:y).r*255).rounded()))}};rows.append(["selected":selected,"copy":copy,"matrix":matrix.values,"values":values])}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":16,"height":12,"background":40,"selection":[3,2,6,5],"rows":rows],options:.sortedKeys).write(to:dir.appendingPathComponent("channel-transform-analytical.json"))}
  }
}
