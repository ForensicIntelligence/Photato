import XCTest
import PhotoCraftCore
import PhotoCraftImaging

final class PeopleFeatureTests: XCTestCase {
  func testProbabilitiesSoftmaxProjectionAndFeatureUnion() throws {
    let map=try PeopleFeatureMap(width:2,height:1,probabilities:[0,1,0,0,0,0,0,0,0,1,0,0])
    let mask=try SelectionMask(width:4,height:1,bytes:[255,255,255,255])
    XCTAssertEqual(try map.restricting(mask,to:[.hair]).bytes,[255,191,64,0])
    XCTAssertEqual(try map.restricting(mask,to:[.hair,.faceSkin]).bytes,[255,255,255,255])
    XCTAssertEqual(try map.restricting(mask,to:[.wholePerson]),mask)
    let soft=try PeopleFeatureMap.fromLogits([1000,999,-1000,-1000,-1000,-1000],width:1,height:1)
    XCTAssertEqual(soft.probabilities[0],Float(1/(1+exp(-1.0))),accuracy:0.00001)
    XCTAssertEqual(soft.probabilities.reduce(0,+),1,accuracy:0.000001)
    for p:[Float] in [[.nan,0,0,0,0,0],[2,0,0,0,0,0],[0,0,0,0,0,0]] {XCTAssertThrowsError(try PeopleFeatureMap(width:1,height:1,probabilities:p))}
    XCTAssertThrowsError(try PeopleFeatureMap.fromLogits([.infinity,0,0,0,0,0],width:1,height:1))
    XCTAssertThrowsError(try map.restricting(mask,to:[]));XCTAssertThrowsError(try map.restricting(mask,to:[.hair,.hair]))
  }
  func testSemanticMasksKeepPersonIdentityHistoryAndUnavailableFeaturesHonest() throws {
    let document=try CraftDocument(width:2,height:1),source=ObjectFinderSource(document,layerID:document.activeLayerID,sampleAllLayers:false)
    let masks=try [DetectedObjectMask(instanceID:1,mask:SelectionMask(width:2,height:1,bytes:[255,0])),DetectedObjectMask(instanceID:2,mask:SelectionMask(width:2,height:1,bytes:[0,128]))]
    let features=try PeopleFeatureMap(width:2,height:1,probabilities:[0,0.8,0,0.2,0,0,0,0.1,0,0.9,0,0])
    let input=try Surface(width:2,height:1),scene=try PeopleScene(source:source,input:input,masks:masks,featureMap:features)
    XCTAssertEqual(try scene.coverage(instanceIDs:[1],hardEdge:false,features:[.hair]).bytes,[204,0])
    XCTAssertEqual(try scene.coverage(instanceIDs:[2],hardEdge:false,features:[.hair]).bytes,[0,13])
    XCTAssertEqual(try scene.coverage(instanceIDs:[1,2],hardEdge:false,features:[.hair,.faceSkin]).bytes,[255,128])
    XCTAssertEqual(try scene.coverage(instanceIDs:[1,2],hardEdge:true,features:[.hair]).bytes,[255,0])
    var session=EditorSession(document:document);try session.execute(scene.command(instanceIDs:[1],mode:.replace,hardEdge:false,features:[.hair]));let selected=session.document
    XCTAssertEqual(try selected.selectionMask?.bytes,[204,0]);XCTAssertEqual(selected.layers,document.layers);try session.undo();XCTAssertEqual(session.document,document);try session.redo();XCTAssertEqual(session.document,selected)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(selected)),selected)
    let unavailable=try PeopleScene(source:source,input:input,masks:masks,featureError:"Missing model")
    XCTAssertEqual(unavailable.availableFeatures,[.wholePerson]);XCTAssertThrowsError(try unavailable.coverage(instanceIDs:[1],hardEdge:false,features:[.hair]))
  }
  func testNativeRGBNormalizationOrientationAndTransparency() throws {
    var image=try Surface(width:2,height:1);image.setPixel(x:0,y:0,Pixel(1,0,0));image.setPixel(x:1,y:0,Pixel(0,0,1))
    let input=try CoreMLPeopleFeaturesDetector.inputTensor(image)
    XCTAssertEqual(input.count,256*256*3);XCTAssertEqual(Array(input.prefix(3)),[1,-1,-1]);XCTAssertEqual(Array(input.suffix(3)),[-1,-1,1])
    XCTAssertEqual(input[127*3],0.0078125,accuracy:0.00001);XCTAssertEqual(input[127*3+2],-0.0078125,accuracy:0.00001)
    let clear=try CoreMLPeopleFeaturesDetector.inputTensor(Surface(width:1,height:1));XCTAssertTrue(clear.allSatisfy{$0 == -1})
  }
}
