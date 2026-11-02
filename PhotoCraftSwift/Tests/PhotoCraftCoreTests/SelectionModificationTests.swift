import XCTest
import PhotoCraftCore

final class SelectionModificationTests:XCTestCase {
  func reference(_ bytes:[UInt8],_ w:Int,_ h:Int,_ request:SelectionModification)->[UInt8] {
    func filtered(_ radius:Int,_ kind:SelectionModification.Kind)->[Double] {
      if radius==0{return bytes.map{Double($0)}}
      return (0..<(w*h)).map {i in
        let x=i%w,y=i/w;var values:[UInt8]=[]
        for dy in -radius...radius {for dx in -radius...radius where dx*dx+dy*dy<=radius*radius {
          let xx=x+dx,yy=y+dy
          if request.atCanvasBounds && (xx<0 || yy<0 || xx>=w || yy>=h) {values.append(0)}
          else {values.append(bytes[min(h-1,max(0,yy))*w+min(w-1,max(0,xx))])}
        }}
        values.sort();return Double(kind == .expand ? values.last!:kind == .contract ? values.first!:values[values.count/2])
      }
    }
    if request.operation != .border {return filtered(request.amount,request.operation).map{UInt8($0)}}
    let lower=request.amount/2,upper=(request.amount+1)/2,a=filtered(lower,.expand),b=filtered(upper,.expand),c=filtered(lower,.contract),d=filtered(upper,.contract)
    return a.indices.map{UInt8(max(0,((a[$0]+b[$0]-c[$0]-d[$0])/2).rounded()))}
  }
  func testAllOperationsGrayRanksAndBoundsAgainstIndependentDiscReference()throws {
    let w=11,h=9,bytes=(0..<(w*h)).map{UInt8(($0*73+$0/7*29)%256)},mask=try SelectionMask(width:w,height:h,bytes:bytes)
    for kind in SelectionModification.Kind.allCases {for amount in 1...3 {for bounds in [false,true] {
      let request=SelectionModification(kind,amount:amount,atCanvasBounds:bounds)
      XCTAssertEqual(try request.applied(to:mask).bytes,reference(bytes,w,h,request),"\(kind)/\(amount)/\(bounds)")
    }}}
  }
  func testExpandContractBoundsAndLayerIndependentGeometry()throws {
    let mask=try SelectionMask.make(.rectangle(.init(x:8,y:8,width:12,height:10)),width:32,height:28,antiAlias:false)
    XCTAssertEqual(try SelectionModification(.expand,amount:3).applied(to:mask).bounds,.init(x:5,y:5,width:18,height:16))
    XCTAssertEqual(try SelectionModification(.contract,amount:3).applied(to:mask).bounds,.init(x:11,y:11,width:6,height:4))
    XCTAssertNil(try SelectionModification(.contract,amount:20).applied(to:mask).bounds)
  }
  func testSmoothRemovesStrayPixelsAndFillsSmallHoles()throws {
    var bytes=[UInt8](repeating:0,count:144);for y in 3..<9{for x in 3..<9{bytes[y*12+x]=255}};bytes[5*12+5]=0;bytes[1*12+1]=255
    let mask=try SelectionMask(width:12,height:12,bytes:bytes),out=try SelectionModification(.smooth,amount:1).applied(to:mask)
    XCTAssertEqual(out.coverage(x:1,y:1),0);XCTAssertEqual(out.coverage(x:5,y:5),1);XCTAssertEqual(out.coverage(x:6,y:6),1)
  }
  func testCenteredOddEvenBordersAndCapturedAnalyticalOutputs()throws {
    let w=24,h=20,mask=try SelectionMask.make(.rectangle(.init(x:6,y:5,width:12,height:10)),width:w,height:h,antiAlias:false);var rows:[[String:Any]]=[]
    for amount in [1,2,3,4] {
      let request=SelectionModification(.border,amount:amount),output=try request.applied(to:mask)
      XCTAssertEqual(try output.bytes,reference(try mask.bytes,w,h,request));XCTAssertEqual(output.coverage(x:12,y:10),0)
      rows.append(["amount":amount,"bytes":try output.bytes.map{Int($0)}])
    }
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":w,"height":h,"rectangle":[6,5,12,10],"rows":rows],options:.sortedKeys).write(to:url.appendingPathComponent("selection-modify-analytical.json"))}
  }
  func testTileSeamsMatchDenseReference()throws {
    let w=140,h=90,bytes=(0..<(w*h)).map{i->UInt8 in let x=i%w,y=i/w;return (x>=61 && x<68 && y>=61 && y<70) || (x==100 && y==20) ? 255:0},mask=try SelectionMask(width:w,height:h,bytes:bytes)
    for kind in SelectionModification.Kind.allCases {let request=SelectionModification(kind,amount:2);XCTAssertEqual(try request.applied(to:mask).bytes,reference(bytes,w,h,request))}
  }
  func testSparseMaximumCanvasAndConstantPlaneAdmission()throws {
    let mask=try SelectionMask.make(.rectangle(.init(x:64,y:64,width:12,height:12)),width:300_000,height:300_000,antiAlias:false)
    let expanded=try SelectionModification(.expand,amount:2).applied(to:mask);XCTAssertTrue(expanded.isPaged);XCTAssertEqual(expanded.bounds,.init(x:62,y:62,width:16,height:16));XCTAssertLessThan(expanded.allocatedBytes,1_048_576)
    let full=try SelectionMask.make(.rectangle(.init(x:0,y:0,width:300_000,height:300_000)),width:300_000,height:300_000,antiAlias:false)
    for kind in [SelectionModification.Kind.expand,.contract,.smooth] {XCTAssertEqual(try SelectionModification(kind,amount:100).applied(to:full),full)}
  }
  func testCanvasBoundsOptionIsExplicit()throws {
    let full=try SelectionMask.make(.rectangle(.init(x:0,y:0,width:9,height:9)),width:9,height:9,antiAlias:false)
    XCTAssertEqual(try SelectionModification(.contract,amount:2).applied(to:full),full)
    let clipped=try SelectionModification(.contract,amount:2,atCanvasBounds:true).applied(to:full);XCTAssertEqual(clipped.bounds,.init(x:2,y:2,width:5,height:5))
    XCTAssertNil(try SelectionModification(.border,amount:2).applied(to:full).bounds)
    XCTAssertNotNil(try SelectionModification(.border,amount:2,atCanvasBounds:true).applied(to:full).bounds)
  }
  func testValidationCancellationHistoryActionsAndArchives()async throws {
    var original=try CraftDocument(width:24,height:20);original.selection = .init(x:6,y:5,width:12,height:10)
    for kind in SelectionModification.Kind.allCases {
      XCTAssertThrowsError(try SelectionModification(kind,amount:0).validate());XCTAssertThrowsError(try SelectionModification(kind,amount:kind.maximum+1).validate())
      var session=EditorSession(document:original);try session.startActionRecording(name:"Modify");try session.execute(SelectionModification(kind,amount:2).command(in:original));XCTAssertEqual(session.undoStack.last?.label,kind.title+" Selection");XCTAssertEqual(session.document.layers,original.layers)
      var replay=original;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==session.document);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(session.document))==session.document)
      try session.undo();XCTAssertTrue(session.document==original)
    }
    let source=original,task=Task {while !Task.isCancelled{await Task.yield()};return try SelectionModification(.expand).command(in:source)};task.cancel();do{_=try await task.value;XCTFail("Cancelled modification completed")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertThrowsError(try SelectionModification(.expand).command(in:CraftDocument(width:2,height:2)))
  }
}
