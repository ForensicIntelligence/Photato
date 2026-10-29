import XCTest
@testable import PhotoCraftCore

final class WideAngleTests:XCTestCase {
  func testCameraModelsAndIndependentCylindricalCoordinates() throws {
    for model in WideAngleSettings.Model.allCases {
      var s=WideAngleSettings();s.model=model;s.focalLength=24
      let camera=WideAngleCamera(s,width:600,height:400)
      for p in [PathPoint(10,20),.init(300,200),.init(590,350)] {
        let actual=try XCTUnwrap(camera.pixel(camera.ray(p)));XCTAssertEqual(actual.x,p.x,accuracy:1e-9);XCTAssertEqual(actual.y,p.y,accuracy:1e-9)
      }
    }
    var s=WideAngleSettings();s.model = .panorama;s.focalLength=24
    let camera=WideAngleCamera(s,width:600,height:400),ray=camera.ray(.init(300+400 * .pi/4,200))
    XCTAssertEqual(ray.x,sqrt(0.5),accuracy:1e-12);XCTAssertEqual(ray.z,sqrt(0.5),accuracy:1e-12);XCTAssertEqual(ray.y,0)
    s.model = .fisheye;s.focalLength=8;let fish=WideAngleCamera(s,width:600,height:400)
    XCTAssertLessThan(try fish.arc(.init(50,60),.init(550,60),samples:10)[5].y,50)
    XCTAssertEqual(WideAngleCamera(.init(),width:800,height:400).model,.fullSpherical)
  }
  func testOriginalSourceConstraintStraightnessAndLocality() throws {
    var s=WideAngleSettings();s.model = .fisheye;s.focalLength=8
    var line=WideAngleSettings.Constraint(points:[.init(60.0/480,70.0/320),.init(420.0/480,70.0/320)]);line.setOrientation(.horizontal,at:0)
    s.constraints=[line,.init(points:[.init(80.0/480,60.0/320),.init(80.0/480,260.0/320)])]
    let camera=WideAngleCamera(s,width:480,height:320),curve=try camera.arc(.init(60,70),.init(420,70))
    XCTAssertGreaterThan(curve.map{abs($0.y-70)}.max()!,10)
    let mesh=try WideAngleSolver.solve(s,width:480,height:320)
    XCTAssertLessThan(mesh.residual,2)
    let ys=mesh.curves[0].map{mesh.point($0).y};XCTAssertLessThan(ys.max()!-ys.min()!,2)
    let far=mesh.point(.init(300,250));XCTAssertLessThan(abs(far.x-300),80);XCTAssertLessThan(abs(far.y-250),40)
  }
  func testIdentityScaleAndTransparentBorders() throws {
    let source=try Surface(width:64,height:48,fill:Pixel(0.2,0.4,0.6))
    XCTAssertEqual(try WideAngleEngine.render(source,settings:.init()),source)
    var s=WideAngleSettings();s.scale=80;s.interpolation = .bilinear
    let result=try WideAngleEngine.render(source,settings:s);XCTAssertGreaterThan(result.pixel(x:32,y:24).a,0.99);XCTAssertLessThan(result.pixel(x:1,y:1).a,0.01)
    for y in 8..<40 { for x in 8..<56 { XCTAssertGreaterThan(result.pixel(x:x,y:y).a,0.99) } }
  }
  func testStrictPolygonParametersAndInvalidCurves() throws {
    var s=WideAngleSettings();var c=WideAngleSettings.Constraint(points:[.init(0.1,0.1),.init(0.8,0.2),.init(0.8,0.8)],closed:true);c.setOrientation(.angle,angle:20,at:0);s.constraints=[c]
    XCTAssertEqual(try WideAngleSettings.decodeJSON(JSONEncoder().encode(s)),s)
    for raw in ["{\"focalLength\":true}","{\"unknown\":1}","{\"constraints\":[{\"points\":[{\"x\":0,\"y\":0},{\"x\":0,\"y\":0}]}]}","{\"constraints\":[{\"points\":[{\"x\":0,\"y\":0},{\"x\":1,\"y\":1}],\"closed\":true}]}"] { XCTAssertThrowsError(try WideAngleSettings.decodeJSON(Data(raw.utf8))) }
    let camera=WideAngleCamera(.init(),width:800,height:400);XCTAssertThrowsError(try camera.arc(.init(0,200),.init(400,200)))
  }
}
