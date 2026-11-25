import Foundation
import UniformTypeIdentifiers
import PhotoCraftCore

/// Native files for the Vanishing Point scene and its rectified plane textures.
/// The 3DS command includes the companion VPE, as in Photoshop.
public enum VanishingSceneExport {
  public enum Format: String, CaseIterable, Sendable { case studio = "3ds", afterEffects = "vpe" }
  public static let maximumBytes = 128 * 1024 * 1024
  public static let maximumTextureSide = 4096
  public static let maximumTexturePixels = 16_777_216
  public struct Output: Sendable {
    public let name: String
    public let files: [StoredZIP.File]
    public func zip() throws -> Data { try StoredZIP.encode(files,maximumBytes:VanishingSceneExport.maximumBytes) }
  }

  public static func render(_ document: CraftDocument, format: Format) throws -> Output {
    try Task.checkCancellation()
    guard let settings = document.vanishingPoint, !settings.planes.isEmpty else {
      throw CraftError.invalid("Create a perspective plane before exporting a scene.")
    }
    let scene = try VanishingScene(settings,width:document.width,height:document.height)
    let geometry = try scene.exportGeometry(settings:settings,canvasWidth:document.width)
    let sample = try Renderer.composite(document)
    let name = basename(document.name)
    // Photoshop emits related planes before their parent, within each family.
    func ordered(_ parent: Int?) -> [Int] {
      settings.planes.indices.filter { settings.planes[$0].parent == parent }
        .flatMap { ordered($0) + [$0] }
    }
    let order = ordered(nil)
    let textureNames = order.indices.map { "\(name.prefix(5))\($0).png" }
    let textureSizes = try order.map { index in
      let metric = scene.measurementMetric(for:index)
      guard metric.x.isFinite, metric.y.isFinite, min(metric.x,metric.y) > 0 else {
        throw CraftError.invalid("Vanishing Point has an invalid texture metric.")
      }
      let resize = min(1,Double(maximumTextureSide)/max(metric.x,metric.y))
      return (width:max(1,Int((metric.x*resize).rounded())),height:max(1,Int((metric.y*resize).rounded())))
    }
    let textureArea = textureSizes.reduce(0) { $0+$1.width*$1.height }
    let shrink = min(1,sqrt(Double(maximumTexturePixels)/Double(textureArea)))
    var files: [StoredZIP.File] = []
    var bytes = 0
    for (index,dimensions) in textureSizes.enumerated() {
      try Task.checkCancellation()
      let width = max(1,Int(Double(dimensions.width)*shrink))
      let height = max(1,Int(Double(dimensions.height)*shrink))
      let frame = scene.frames[order[index]]
      var texture = try Surface(width:width,height:height,depth:.f32,colorEncoding:sample.colorEncoding)
      for y in 0..<height {
        try Task.checkCancellation()
        let v = (Double(y)+0.5)/Double(height)
        for x in 0..<width {
          let uv = PathPoint((Double(x)+0.5)/Double(width),v)
          let pixel = WarpRaster.sample(sample,frame.point(uv),method:.bilinear,clampEdges:false,
            encoding:sample.colorEncoding)
          if sample.colorEncoding == .linearRGB { texture.setLinearPixel(x:x,y:y,pixel) }
          else { texture.setPixel(x:x,y:y,pixel) }
        }
      }
      let data = try RasterIO.encoded(texture,type:.png,outputDepth:.u8,workingDocument:document)
      guard bytes+data.count <= maximumBytes else { throw CraftError.invalid("Vanishing Point textures exceed 128 MiB.") }
      bytes += data.count
      files.append(.init(name:textureNames[index],data:data))
    }
    let firstRoot = order.firstIndex(of:0) ?? 0
    let exchange = vpe(geometry,width:document.width,height:document.height,order:order,names:textureNames,cameraIndex:firstRoot)
    files.insert(.init(name:name+".vpe",data:exchange),at:0)
    if format == .studio {
      files.insert(.init(name:name+".3ds",data:studio(geometry,order:order,names:textureNames)),at:0)
    }
    guard files.reduce(0,{$0+$1.data.count}) <= maximumBytes else {
      throw CraftError.invalid("Vanishing Point export exceeds 128 MiB.")
    }
    return Output(name:name,files:files)
  }

  private static func basename(_ input: String) -> String {
    let withoutExtension = (input as NSString).deletingPathExtension
    let normalized = withoutExtension.utf8.prefix(48).map { value in
      switch value {
      case 45,48...57,65...90,95,97...122: value
      default: UInt8(95)
      }
    }
    let name = String(decoding:normalized,as:UTF8.self)
    return name.trimmingCharacters(in:CharacterSet(charactersIn:"-_")).isEmpty ? "scene" : name
  }

  private static func vpe(_ scene: VanishingSceneGeometry,width: Int,height: Int,order: [Int],names: [String],
    cameraIndex: Int) -> Data
  {
    let locale = Locale(identifier:"en_US_POSIX")
    func scalar(_ number: Double) -> String { String(format:"%.12g",locale:locale,abs(number) < 1e-12 ? 0 : number) }
    func point(_ value: SIMD3<Double>) -> String { [value.x,value.y,value.z].map(scalar).joined(separator:",") }
    var xml = ["<vp>","<canvas>\(width),\(height)</canvas>"]
    for (index,name) in names.enumerated() {
      if index == cameraIndex {
        xml += ["<camera>","<location>\(point(scene.camera))</location>",
          "<pointOfInterest>\(point(scene.target))</pointOfInterest>","<roll>\(scalar(scene.rollDegrees))</roll>",
          "<angleOfView>\(scalar(scene.horizontalAngleOfView))</angleOfView>","</camera>"]
      }
      let corners = scene.planes[order[index]]
      xml.append("<surface>")
      for (key,corner) in zip(["topLeft","topRight","bottomRight","bottomLeft"],corners) {
        xml.append("<\(key)>\(point(corner))</\(key)>")
      }
      xml += ["<texture>\(name)</texture>","</surface>"]
    }
    xml.append("</vp>")
    return Data((xml.joined(separator:"\n")+"\n").utf8)
  }

  private struct StudioChunk {
    var data = Data()
    mutating func integer<T: FixedWidthInteger>(_ value: T) {
      var value = value.littleEndian
      withUnsafeBytes(of:&value) { data.append(contentsOf:$0) }
    }
    mutating func short(_ value: Int) { integer(UInt16(value)) }
    mutating func float(_ value: Double) { integer(Float(value).bitPattern) }
    mutating func point(_ p: SIMD3<Double>) { float(p.x);float(p.y);float(p.z) }
    mutating func string(_ value: String) { data.append(contentsOf:value.utf8);data.append(0) }
    mutating func chunk(_ tag: UInt16, _ write: (inout StudioChunk) -> Void) {
      var child = StudioChunk()
      write(&child)
      integer(tag)
      integer(UInt32(child.data.count+6))
      data.append(child.data)
    }
  }

  private static func studio(_ scene: VanishingSceneGeometry,order: [Int],names: [String]) -> Data {
    var result = StudioChunk()
    result.chunk(0x4D4D) { file in
      file.chunk(0x0002) { $0.integer(UInt32(3)) }
      file.chunk(0x3D3D) { editor in
        editor.chunk(0x3D3E) { $0.integer(UInt32(3)) }
        editor.chunk(0x0100) { $0.float(0.3937) }
        for (index,name) in names.enumerated() {
          editor.chunk(0xAFFF) { material in
            material.chunk(0xA000) { $0.string(name) }
            for (tag,level) in [(UInt16(0xA010),UInt8(150)),(0xA020,150),(0xA030,229)] {
              material.chunk(tag) { color in
                color.chunk(0x0011) { $0.data.append(contentsOf:[level,level,level]) }
                color.chunk(0x0012) { $0.data.append(contentsOf:[level,level,level]) }
              }
            }
            material.chunk(0xA200) { map in
              map.chunk(0xA300) { $0.string(name) }
            }
          }
          editor.chunk(0x4000) { object in
            object.string((name as NSString).deletingPathExtension)
            object.chunk(0x4100) { mesh in
              // Match the observed bottom-right, bottom-left, top-right, top-left
              // vertex order and matching U,V coordinates in 3DS.
              mesh.chunk(0x4110) { vertices in
                vertices.short(4)
                for corner in [2,3,1,0] { vertices.point(scene.planes[order[index]][corner]) }
              }
              mesh.chunk(0x4140) { uv in
                uv.short(4)
                for word in [1.0,0,0,0,1,1,0,1] { uv.float(word) }
              }
              mesh.chunk(0x4120) { faces in
                faces.short(2)
                for word in [2,1,0,5,1,2,3,5] { faces.short(word) }
                faces.chunk(0x4130) { group in
                  group.string(name);group.short(2);group.short(0);group.short(1)
                }
              }
            }
          }
        }
        editor.chunk(0x4000) { object in
          object.string("Camera")
          object.chunk(0x4700) { camera in
            camera.point(scene.camera);camera.point(scene.target)
            camera.float(scene.rollDegrees);camera.float(2400/scene.horizontalAngleOfView)
            let radius = scene.planes.flatMap { $0 }.map { point -> Double in
              let d = point-scene.camera
              return sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
            }
            camera.chunk(0x4720) { clip in
              clip.float(max(0.01,(radius.min() ?? 1)/100))
              clip.float(max(1000,(radius.max() ?? 1000)*2))
            }
          }
        }
      }
    }
    return result.data
  }
}
