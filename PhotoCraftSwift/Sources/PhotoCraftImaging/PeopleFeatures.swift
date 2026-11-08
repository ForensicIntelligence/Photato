import Foundation
import CoreML
import PhotoCraftCore

public enum PeopleFeature: String, Codable, CaseIterable, Sendable {
  case wholePerson, hair, bodySkin, faceSkin, clothes, accessories
  public var label: String {
    switch self { case .wholePerson:"Whole Person";case .hair:"Hair";case .bodySkin:"Body Skin";case .faceSkin:"Face Skin";case .clothes:"Clothing";case .accessories:"Accessories" }
  }
  var channel: Int { Self.allCases.firstIndex(of:self)! }
}

public protocol PeopleFeaturesDetecting: Sendable {
  func features(in image: Surface) async throws -> PeopleFeatureMap
}

/// Small, source-aligned semantic probability grid. Instance identity still comes from Vision.
public struct PeopleFeatureMap: Sendable {
  public let width: Int, height: Int
  public let probabilities: [Float]
  public init(width: Int, height: Int, probabilities: [Float]) throws {
    guard width>0,height>0,width<=512,height<=512,probabilities.count==width*height*6 else { throw CraftError.invalid("Invalid person feature grid.") }
    for i in stride(from:0,to:probabilities.count,by:6) {
      let values=probabilities[i..<i+6]
      guard values.allSatisfy({$0.isFinite && $0>=0 && $0<=1}),abs(values.reduce(0,+)-1)<0.001 else { throw CraftError.invalid("Invalid person feature probabilities.") }
    }
    self.width=width;self.height=height;self.probabilities=probabilities
  }
  public static func fromLogits(_ logits: [Float], width: Int = 256, height: Int = 256) throws -> Self {
    guard width>0,height>0,width<=512,height<=512,logits.count==width*height*6 else { throw CraftError.invalid("Invalid person model output.") }
    var values=logits
    for i in stride(from:0,to:values.count,by:6) {
      if i%(width*6)==0 { try Task.checkCancellation() }
      let row=logits[i..<i+6];guard row.allSatisfy(\.isFinite),let peak=row.max() else { throw CraftError.invalid("Nonfinite person model output.") }
      var sum:Float=0
      for c in 0..<6 { let value=exp(logits[i+c]-peak);values[i+c]=value;sum+=value }
      for c in 0..<6 { values[i+c]/=sum }
    }
    return try .init(width:width,height:height,probabilities:values)
  }
  public func restricting(_ mask: SelectionMask, to features: [PeopleFeature]) throws -> SelectionMask {
    guard !features.isEmpty,Set(features).count==features.count else { throw CraftError.invalid("Choose unique person features.") }
    if features.contains(.wholePerson) { return mask }
    let channels=features.map(\.channel)
    var bytes=(try mask.bytes)
    for y in 0..<mask.height {
      try Task.checkCancellation()
      let sy=max(0,min(Double(height-1),(Double(y)+0.5)*Double(height)/Double(mask.height)-0.5)),y0=Int(sy),y1=min(height-1,y0+1),fy=Float(sy-Double(y0))
      for x in 0..<mask.width where bytes[y*mask.width+x]>0 {
        let sx=max(0,min(Double(width-1),(Double(x)+0.5)*Double(width)/Double(mask.width)-0.5)),x0=Int(sx),x1=min(width-1,x0+1),fx=Float(sx-Double(x0))
        var probability:Float=0
        for c in channels {
          let top=probabilities[(y0*width+x0)*6+c]*(1-fx)+probabilities[(y0*width+x1)*6+c]*fx
          let bottom=probabilities[(y1*width+x0)*6+c]*(1-fx)+probabilities[(y1*width+x1)*6+c]*fx
          probability+=top*(1-fy)+bottom*fy
        }
        let i=y*mask.width+x;bytes[i]=UInt8((Float(mask.byte(at:i))*min(1,max(0,probability))).rounded())
      }
    }
    return try .init(width:mask.width,height:mask.height,bytes:bytes)
  }
}

/// All weak-reference and resource-identity access is protected by the lock. The pool does not
/// own a model: documents and pending inference jobs retain their actor only while needed.
final class BundledPeopleFeaturePool: @unchecked Sendable {
  private let lock = NSLock()
  private weak var cached: CoreMLPeopleFeaturesDetector?
  private var cachedURL: URL?

  func provider(for modelURL: URL) -> CoreMLPeopleFeaturesDetector {
    lock.lock()
    defer { lock.unlock() }
    if cachedURL == modelURL, let cached { return cached }
    // Construction does no model loading or inference while the pool lock is held.
    let value = CoreMLPeopleFeaturesDetector(modelURL: modelURL)
    cachedURL = modelURL
    cached = value
    return value
  }
}

/// The app runs only Apple's Core ML framework. Python/TensorFlow are build-time conversion tools.
public actor CoreMLPeopleFeaturesDetector: PeopleFeaturesDetecting {
  public static let sourceSHA256="c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0"
  private static let bundledProviders = BundledPeopleFeaturePool()
  public static var bundled: CoreMLPeopleFeaturesDetector? {
    Bundle.main.url(forResource:"PeopleParts",withExtension:"mlmodelc").map { bundledProviders.provider(for: $0) }
  }
  private let modelURL: URL
  private var model: MLModel?
  public init(modelURL: URL) { self.modelURL=modelURL }
  public func features(in image: Surface) async throws -> PeopleFeatureMap {
    try predict(image)
  }
  private func predict(_ image: Surface) throws -> PeopleFeatureMap {
    try ForegroundSelection.checkSize(image.width,image.height);try Task.checkCancellation()
    let model=try loadedModel(),input=try MLMultiArray(shape:[1,256,256,3],dataType:.float32)
    let tensor=try Self.inputTensor(image)
    guard input.strides.map(\.intValue)==[196608,768,3,1] else { throw CraftError.unavailable("Unsupported person model input layout.") }
    tensor.withUnsafeBufferPointer { input.dataPointer.assumingMemoryBound(to:Float.self).update(from:$0.baseAddress!,count:$0.count) }
    let output=try model.prediction(from:MLDictionaryFeatureProvider(dictionary:["image":input]))
    try Task.checkCancellation()
    guard let array=output.featureValue(for:"logits")?.multiArrayValue,array.dataType == .float32,array.shape.map(\.intValue)==[1,256,256,6] else { throw CraftError.unavailable("Unsupported person model output.") }
    let strides=array.strides.map(\.intValue),pointer=array.dataPointer.assumingMemoryBound(to:Float.self)
    var logits=[Float]();logits.reserveCapacity(256*256*6)
    for y in 0..<256 { try Task.checkCancellation();for x in 0..<256 {for c in 0..<6 {logits.append(pointer[y*strides[1]+x*strides[2]+c*strides[3]])}} }
    return try PeopleFeatureMap.fromLogits(logits)
  }
  private func loadedModel() throws -> MLModel {
    if let model { return model }
    let configuration=MLModelConfiguration();configuration.computeUnits = .all
    let value=try MLModel(contentsOf:modelURL,configuration:configuration),description=value.modelDescription
    let metadata=description.metadata[.creatorDefinedKey] as? [String:String]
    guard metadata?["photato.model"] == "people-parts-v1",metadata?["photato.source.sha256"] == Self.sourceSHA256,
      metadata?["photato.classes"] == "background,hair,bodySkin,faceSkin,clothes,accessories",
      metadata?["photato.input.mean"] == "127.5",metadata?["photato.input.std"] == "127.5",
      description.inputDescriptionsByName["image"]?.multiArrayConstraint?.shape.map(\.intValue)==[1,256,256,3],
      description.outputDescriptionsByName["logits"]?.multiArrayConstraint?.shape.map(\.intValue)==[1,256,256,6]
    else { throw CraftError.unsupported("This person feature model has an unsupported identity or tensor format.") }
    model=value;return value
  }
  public static func inputTensor(_ image: Surface) throws -> [Float] {
    try ForegroundSelection.checkSize(image.width,image.height)
    var values=[Float]();values.reserveCapacity(256*256*3)
    for y in 0..<256 {
      try Task.checkCancellation()
      let sy=max(0,min(Double(image.height-1),(Double(y)+0.5)*Double(image.height)/256-0.5)),y0=Int(sy),y1=min(image.height-1,y0+1),fy=Float(sy-Double(y0))
      for x in 0..<256 {
        let sx=max(0,min(Double(image.width-1),(Double(x)+0.5)*Double(image.width)/256-0.5)),x0=Int(sx),x1=min(image.width-1,x0+1),fx=Float(sx-Double(x0))
        let pixels=[image.pixel(x:x0,y:y0),image.pixel(x:x1,y:y0),image.pixel(x:x0,y:y1),image.pixel(x:x1,y:y1)],weights=[(1-fx)*(1-fy),fx*(1-fy),(1-fx)*fy,fx*fy]
        var rgb=[Float](repeating:0,count:3)
        for i in 0..<4 {let p=pixels[i],w=weights[i]*p.a;rgb[0]+=p.r*w;rgb[1]+=p.g*w;rgb[2]+=p.b*w}
        values.append(contentsOf:rgb.map{min(1,max(0,$0))*2-1})
      }
    }
    return values
  }
}
