import CoreGraphics
import Foundation
import PhotoCraftCore

/// Public PSD resources1006/1045/1077. Modern DisplayInfo records are13 bytes;
/// obsolete1007 records add one padding byte. See pinned psd-tools1.26.0 evidence.
enum PSDInkChannels {
  struct Display {
    var color: Pixel
    var opacity: Float
    var kind: Int
    var raw: Data
  }
  static let resourceIDs: Set<Int> = [1006, 1007, 1022, 1045, 1053, 1066, 1067, 1077]
  static func key(_ id: UUID) -> String { "psdInkDisplay." + id.uuidString }
  static func identifierKey(_ id:UUID)->String {"psdInkIdentifier."+id.uuidString}

  static func names(_ blocks: [PSDImageResources.Block], count: Int) throws -> [String] {
    var names: [String] = []
    if let unicode = blocks.first(where: { $0.id == 1045 }) {
      var reader = PSDReader(data: unicode.data)
      while reader.remaining > 0 {
        let n = try reader.u32()
        guard names.count < count, n <= 1025, n <= reader.remaining / 2 else { throw CraftError.invalid("Invalid Photoshop channel name length.") }
        let bytes = try reader.bytes(n * 2)
        guard let name = String(data: bytes, encoding: .utf16BigEndian) else { throw CraftError.invalid("Invalid Unicode channel name.") }
        names.append(String(name.reversed().drop(while: { $0 == "\0" }).reversed()))
      }
    } else if let pascal = blocks.first(where: { $0.id == 1006 }) {
      var reader = PSDReader(data: pascal.data)
      while reader.remaining > 0 {
        guard names.count < count else { throw CraftError.invalid("Too many Photoshop channel names.") }
        names.append(String(data: try reader.bytes(Int(reader.u8())), encoding: .macOSRoman) ?? "")
      }
    }
    guard names.isEmpty || names.count == count else { throw CraftError.unsupported("Incomplete Multichannel names cannot be assigned to ink plates reliably.") }
    if names.isEmpty { names = (1...count).map { "Channel \($0)" } }
    guard names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1024 }) else {
      throw CraftError.invalid("Photoshop channel names exceed the supported name limit or are empty.")
    }
    return names
  }

  static func displays(_ blocks: [PSDImageResources.Block], count: Int) throws -> [Display] {
    guard let block = blocks.first(where: { $0.id == 1077 }) ?? blocks.first(where: { $0.id == 1007 }) else {
      return (0..<count).map { _ in Display(color: .black, opacity: 0, kind: 2, raw: Data()) }
    }
    var reader = PSDReader(data: block.data)
    if block.id == 1077, try reader.u32() != 1 { throw CraftError.unsupported("Unsupported Photoshop channel-display version.") }
    let stride = block.id == 1077 ? 13 : 14
    guard reader.remaining == count * stride else { throw CraftError.invalid("Photoshop channel-display records do not match the channel count.") }
    return try (0..<count).map { _ in
      let raw = try reader.bytes(13)
      if stride == 14 { guard try reader.u8() == 0 else { throw CraftError.invalid("Invalid obsolete channel-display padding.") } }
      return try display(raw)
    }
  }

  static func display(_ raw: Data) throws -> Display {
    guard raw.count == 13 else { throw CraftError.invalid("Invalid channel-display record.") }
    var reader = PSDReader(data: raw)
    let space = try reader.u16(), c = try (0..<4).map { _ in try reader.u16() }
    let opacity = try reader.u16(), kind = Int(try reader.u8())
    guard opacity <= 100, (0...2).contains(kind) else { throw CraftError.unsupported("Unknown Photoshop channel kind or opacity.") }
    let color: Pixel
    switch space {
    case 0: color = Pixel(Float(c[0]) / 65535, Float(c[1]) / 65535, Float(c[2]) / 65535)
    case 1:
      let h = Double(c[0]) / 65535 * 6, s = Float(c[1]) / 65535, v = Float(c[2]) / 65535
      let x = v * (1 - s), y = v * (1 - s * Float(h - floor(h))), z = v * (1 - s * (1 - Float(h - floor(h))))
      color = [Pixel(v,z,x),Pixel(y,v,x),Pixel(x,v,z),Pixel(x,y,v),Pixel(z,x,v),Pixel(v,x,y)][Int(floor(h)) % 6]
    case 2, 7:
      let colorSpace: CGColorSpace?
      let components: [CGFloat]
      if space == 2 {
        colorSpace = CGColorSpace(name: CGColorSpace.genericCMYK)
        components = c.map { CGFloat(65535 - $0) / 65535 } + [1]
      } else {
        guard c[0] <= 10000 else { throw CraftError.invalid("Invalid Lab channel display lightness.") }
        colorSpace = CGColorSpace(name: CGColorSpace.genericLab)
        components = [CGFloat(c[0]) / 100, CGFloat(Int16(bitPattern: UInt16(c[1]))) / 100,
          CGFloat(Int16(bitPattern: UInt16(c[2]))) / 100, 1]
      }
      guard let colorSpace, let source = CGColor(colorSpace: colorSpace, components: components),
        let destination = CGColorSpace(name: CGColorSpace.sRGB),
        let rgb = source.converted(to: destination, intent: .relativeColorimetric, options: nil)?.components, rgb.count >= 3 else {
        throw CraftError.unsupported("Cannot display this Photoshop ink color space.")
      }
      color = Pixel(unit(Float(rgb[0])), unit(Float(rgb[1])), unit(Float(rgb[2])))
    case 8:
      guard c[0] <= 10000 else { throw CraftError.invalid("Invalid gray channel display color.") }
      let v = Float(c[0]) / 10000; color = Pixel(v,v,v)
    default: throw CraftError.unsupported("This Photoshop ink color-book space is not implemented. No color was substituted.")
    }
    return Display(color: color, opacity: Float(opacity) / 100, kind: kind, raw: raw)
  }

  static func record(id: UUID, color: Pixel, opacity: Float, kind: Int, document: CraftDocument) throws -> Data {
    if let raw = document.sourceMetadata?[key(id)], let old = try? display(raw),
      old.color == color, old.opacity == opacity, old.kind == kind { return raw }
    var result = PSDWriter(); result.n(0, 2)
    for v in [color.r,color.g,color.b,Float(0)] { result.n(Int((v * 65535).rounded()), 2) }
    result.n(Int((opacity * 100).rounded()), 2); result.n(kind, 1); return result.data
  }

  static func resources(_ document: CraftDocument, plates: [InkPlate]) throws -> Data {
    if document.isChannelOnly {
      let base = try PSDRestrictedStorage.resources(document)
      let retained = try PSDImageResources.blocks(base).filter { !resourceIDs.contains($0.id) }
        .reduce(into: Data()) { $0 += $1.raw }
      let resources = retained + (try PSDAuxiliaryChannels.resources(document, first: 0))
      guard resources.count <= PSDImageResources.maximumBytes else { throw CraftError.invalid("Channel resources exceed the metadata limit.") }
      return resources
    }
    let alphas = PSDAuxiliaryChannels.all(document)
    let names = plates.map(\.name) + alphas.map(\.name)
    var unicode = PSDWriter(), pascal = PSDWriter(), displayInfo = PSDWriter(); displayInfo.n(1, 4)
    for name in names {
      let chars = Array(name.utf16); unicode.n(chars.count, 4)
      for c in chars { unicode.n(Int(c), 2) }
      let legacy = Data((name.data(using: .macOSRoman, allowLossyConversion: true) ?? Data("Channel".utf8)).prefix(255))
      pascal.n(legacy.count, 1); pascal.data += legacy
    }
    for plate in plates {
      displayInfo.data += try record(id: plate.id, color: plate.color, opacity: plate.solidity, kind: 2, document: document)
    }
    for alpha in alphas {
      displayInfo.data += try record(id: alpha.id, color: alpha.options.color, opacity: alpha.options.opacity,
        kind: alpha.options.indicates == .selectedAreas ? 0 : 1, document: document)
    }
    var identifiers=PSDWriter(),used=Set(alphas.compactMap(\.psdIdentifier)),next:UInt32=1
    let plateIDs=try plates.map {plate->UInt32? in
      guard let data=document.sourceMetadata?[identifierKey(plate.id)] else{return nil}
      guard data.count==4 else{throw CraftError.invalid("Invalid retained printing-channel identifier.")}
      var input=PSDReader(data:data);return UInt32(try input.u32())
    }
    for id in plateIDs.compactMap({$0}) {guard used.insert(id).inserted else{throw CraftError.invalid("Duplicate Photoshop channel identifier.")}}
    for id in plateIDs+alphas.map(\.psdIdentifier) {
      if let id {identifiers.n(Int(id),4)}
      else {while used.contains(next){next+=1};identifiers.n(Int(next),4);used.insert(next)}
    }
    let base = try PSDRestrictedStorage.resources(document)
    var resources = try PSDImageResources.blocks(base).filter { !resourceIDs.contains($0.id) }.reduce(into: Data()) { $0 += $1.raw }
    resources += PSDImageResources.block(1006, data: pascal.data)
    resources += PSDImageResources.block(1045, data: unicode.data)
    resources += PSDImageResources.block(1077, data: displayInfo.data)
    resources += PSDImageResources.block(1053,data:identifiers.data)
    if let quick=document.quickMask {
      var info=PSDWriter();info.n(plates.count+alphas.count-1,2);info.n(quick.psdQuickMaskInitiallyEmpty==true ? 1:0,1)
      resources += PSDImageResources.block(1022,data:info.data)
    }
    guard resources.count <= PSDImageResources.maximumBytes else { throw CraftError.invalid("Ink resources exceed the metadata limit.") }
    return resources
  }
}
