import CoreML
import Foundation
import PhotoCraftCore

/// The optional local provider has its own output semantics. It is not Firefly.
public struct LearnedUpscaleContract: Sendable, Equatable {
  public let inputSide: Int, interiorSide: Int
  public static let realESRGAN = Self(inputSide: 522, interiorSide: 384)
  public init(inputSide: Int, interiorSide: Int) {
    self.inputSide = inputSide; self.interiorSide = interiorSide
  }
  public var padding: Int { (inputSide - interiorSide) / 2 }
  public func validate() throws {
    guard inputSide > interiorSide, inputSide <= 1024, interiorSide > 0,
      interiorSide % 32 == 0, (inputSide - interiorSide) % 2 == 0 else {
      throw CraftError.invalid("Invalid super-resolution tile contract.")
    }
  }
}
public protocol LearnedUpscalePredicting: Sendable {
  var contract: LearnedUpscaleContract { get }
  /// CHW, RGB, encoded sRGB, finite floats. The provider returns four times each side.
  func prediction(_ input: [Float]) async throws -> [Float]
}

/// Core ML owns execution. No Python, subprocess, cloud request or runtime download.
public actor CoreMLUpscaleModel: LearnedUpscalePredicting {
  public nonisolated let contract = LearnedUpscaleContract.realESRGAN
  private let model: MLModel
  public init(url: URL, cpuOnly: Bool = false) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = cpuOnly ? .cpuOnly : .all
    model = try MLModel(contentsOf: url, configuration: configuration)
    let description = model.modelDescription
    guard Set(description.inputDescriptionsByName.keys) == ["input"],
      Set(description.outputDescriptionsByName.keys) == ["var_584"],
      let input = description.inputDescriptionsByName["input"]?.multiArrayConstraint,
      let output = description.outputDescriptionsByName["var_584"]?.multiArrayConstraint,
      input.shape.map(\.intValue) == [1,3,522,522], input.dataType == .float16,
      output.shape.map(\.intValue) == [1,3,2088,2088], output.dataType == .float16 else {
      throw CraftError.invalid("The installed super-resolution model has an unexpected tensor contract.")
    }
  }
  public func prediction(_ input: [Float]) throws -> [Float] {
    try Task.checkCancellation()
    let side = contract.inputSide
    guard input.count == 3 * side * side, input.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw CraftError.invalid("Invalid super-resolution input samples.")
    }
    let array = try MLMultiArray(shape:[1,3,NSNumber(value:side),NSNumber(value:side)], dataType:.float16)
    let strides = array.strides.map(\.intValue), target = array.dataPointer.assumingMemoryBound(to:UInt16.self)
    for c in 0..<3 { for y in 0..<side {
      try Task.checkCancellation()
      for x in 0..<side { target[c*strides[1]+y*strides[2]+x*strides[3]] = try OpenEXR.halfBits(input[(c*side+y)*side+x]) }
    } }
    let provider = try MLDictionaryFeatureProvider(dictionary:["input":MLFeatureValue(multiArray:array)])
    let options = MLPredictionOptions()
    // A single Core ML prediction is not interruptible; cancellation is checked
    // immediately before and after it, and between tiles and output rows.
    let features = try model.prediction(from:provider, options:options)
    try Task.checkCancellation()
    guard let output = features.featureValue(for:"var_584")?.multiArrayValue,
      output.shape.map(\.intValue) == [1,3,2088,2088], output.dataType == .float16 else {
      throw CraftError.invalid("The super-resolution provider returned an unexpected tensor.")
    }
    let s = output.strides.map(\.intValue), p = output.dataPointer.assumingMemoryBound(to:UInt16.self)
    let edge = side * 4
    var result = [Float](repeating:0, count:3*edge*edge)
    for c in 0..<3 { for y in 0..<edge {
      try Task.checkCancellation()
      for x in 0..<edge { result[(c*edge+y)*edge+x] = OpenEXR.halfValue(p[c*s[1]+y*s[2]+x*s[3]]) }
    } }
    return result
  }
}

public enum LearnedUpscale {
  public struct Progress: Sendable {
    public let completedTiles: Int, totalTiles: Int
    public init(completedTiles:Int, totalTiles:Int) { self.completedTiles=completedTiles;self.totalTiles=totalTiles }
  }
  public static func outputSize(width:Int,height:Int,scale:Int) throws -> (width:Int,height:Int) {
    guard [2,4].contains(scale), width > 0, height > 0,
      width <= Surface.maxDimension / scale, height <= Surface.maxDimension / scale,
      width <= Surface.maxPixels / (height * scale * scale) else {
      throw CraftError.invalid("Choose 2× or 4× within the 300,000-pixel document dimensions.")
    }
    return (width*scale,height*scale)
  }
  /// Streams one model row to scratch before ordered, bounded output assembly.
  /// 2× is area reduction of learned 4× RGB; alpha is independently bilinear.
  public static func render(_ source:Surface,scale:Int,depth:PixelDepth,
    model:any LearnedUpscalePredicting,progress:@Sendable(Progress)->Void = {_ in}) async throws -> Surface {
    try Task.checkCancellation();try source.validated();try model.contract.validate()
    let size = try outputSize(width:source.width,height:source.height,scale:scale)
    guard try source.allStoredSamplesSatisfy({p in p.isFinite && (0...1).contains(p.r) && (0...1).contains(p.g) && (0...1).contains(p.b)}) else {
      throw CraftError.unsupported("Local super-resolution requires SDR RGB samples. Convert HDR content before upscaling.")
    }
    let contract=model.contract,side=contract.inputSide,interior=contract.interiorSide,pad=contract.padding,edge=side*4
    let columns=(source.width+interior-1)/interior,rows=(source.height+interior-1)/interior,total=columns*rows
    let encoding:SurfaceColorEncoding = depth == .f32 ? .linearRGB:.sRGB
    let builder=try Surface.PagedBuilder(width:size.width,height:size.height,depth:depth,colorEncoding:encoding)
    let scratch=try RasterTileStore()
    var completed=0
    progress(.init(completedTiles:0,totalTiles:total))
    for row in 0..<rows {
      let top=row*interior,h=min(interior,source.height-top)
      var chunks=[Surface]()
      for column in 0..<columns {
        try Task.checkCancellation()
        let left=column*interior,w=min(interior,source.width-left)
        var input=[Float](repeating:0,count:3*side*side)
        for y in 0..<side {
          try Task.checkCancellation()
          for x in 0..<side {
            let p=source.pixel(x:min(source.width-1,max(0,left+x-pad)),y:min(source.height-1,max(0,top+y-pad)))
            let index=y*side+x
            input[index]=p.r;input[side*side+index]=p.g;input[2*side*side+index]=p.b
          }
        }
        let prediction=try await model.prediction(input)
        try Task.checkCancellation()
        guard prediction.count == 3*edge*edge else {throw CraftError.invalid("Super-resolution output has the wrong size.")}
        var chunk=try Surface(width:w*scale,height:h*scale,depth:depth,colorEncoding:encoding)
        let reduction=4/scale
        for y in 0..<chunk.height {
          try Task.checkCancellation()
          for x in 0..<chunk.width {
            var rgb=SIMD3<Double>(repeating:0)
            for dy in 0..<reduction {for dx in 0..<reduction {
              let index=(pad*4+y*reduction+dy)*edge+pad*4+x*reduction+dx
              let value=SIMD3(prediction[index],prediction[edge*edge+index],prediction[2*edge*edge+index])
              guard value.x.isFinite && value.y.isFinite && value.z.isFinite else {throw CraftError.invalid("Super-resolution returned nonfinite samples.")}
              rgb += SIMD3(Double(value.x),Double(value.y),Double(value.z))
            }}
            rgb /= Double(reduction*reduction)
            let a=alpha(source,x:Double(left)+Double(x+1)/Double(scale)-0.5-0.5/Double(scale),y:Double(top)+Double(y+1)/Double(scale)-0.5-0.5/Double(scale))
            let p=Pixel(Float(min(1,max(0,rgb.x))),Float(min(1,max(0,rgb.y))),Float(min(1,max(0,rgb.z))),a)
            if depth == .f32 {chunk.setLinearPixel(x:x,y:y,SRGBTransfer.linear(p))}else{chunk.setPixel(x:x,y:y,p)}
          }
        }
        chunks.append(try chunk.spillingTiles(to:scratch))
        completed+=1;progress(.init(completedTiles:completed,totalTiles:total))
      }
      for y in stride(from:0,to:h*scale,by:Surface.tileSide) {
        for (column,chunk) in chunks.enumerated() {
          try Task.checkCancellation()
          let patch=try chunk.cropped(to:.init(x:0,y:y,width:chunk.width,height:min(64,chunk.height-y)))
          try builder.append(patch,atX:column*interior*scale,atY:top*scale+y)
        }
      }
    }
    return try builder.finish()
  }
  private static func alpha(_ source:Surface,x:Double,y:Double)->Float {
    let fx=min(Double(source.width-1),max(0,x)),fy=min(Double(source.height-1),max(0,y)),x0=Int(fx),y0=Int(fy)
    let x1=min(source.width-1,x0+1),y1=min(source.height-1,y0+1),u=Float(fx-Double(x0)),v=Float(fy-Double(y0))
    let a=source.pixel(x:x0,y:y0).a*(1-u)+source.pixel(x:x1,y:y0).a*u
    let b=source.pixel(x:x0,y:y1).a*(1-u)+source.pixel(x:x1,y:y1).a*u
    return a*(1-v)+b*v
  }
}
