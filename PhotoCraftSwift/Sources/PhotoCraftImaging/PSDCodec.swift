import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore

// Bounded native PSD v1 RGB/8/16/32 raster/group interchange, based on Adobe's public
// file-format specification and PhotoCraft's Rust psd/header, layer and compression modules.
// Unrepresented rich layers fail explicitly. They are never flattened on import.
struct PSDReader {
  let data: Data
  var offset = 0
  var remaining: Int { data.count - offset }
  mutating func bytes(_ count: Int) throws -> Data {
    guard count >= 0, count <= remaining else {
      throw CraftError.invalid("Truncated PSD section at byte \(offset).")
    }
    defer { offset += count }
    return data.subdata(in: offset..<offset + count)
  }
  mutating func number(_ count: Int) throws -> UInt64 {
    var value: UInt64 = 0
    for byte in try bytes(count) { value = (value << 8) | UInt64(byte) }
    return value
  }
  mutating func u8() throws -> UInt8 { UInt8(try number(1)) }
  mutating func u16() throws -> Int { Int(try number(2)) }
  mutating func i16() throws -> Int { Int(Int16(bitPattern: UInt16(try number(2)))) }
  mutating func u32() throws -> Int { Int(try number(4)) }
  mutating func i32() throws -> Int { Int(Int32(bitPattern: UInt32(try number(4)))) }
  mutating func string(_ count: Int) throws -> String {
    String(decoding: try bytes(count), as: UTF8.self)
  }
  mutating func section() throws -> PSDReader { PSDReader(data: try bytes(u32())) }
}
struct PSDWriter {
  var data = Data()
  mutating func n(_ value: Int, _ count: Int) {
    let bits = UInt64(truncatingIfNeeded: value)
    for i in (0..<count).reversed() { data.append(UInt8(truncatingIfNeeded: bits >> (i * 8))) }
  }
  mutating func text(_ s: String) { data.append(contentsOf: s.utf8) }
  mutating func section(_ d: Data) {
    n(d.count, 4)
    data.append(d)
  }
}
public enum PSDCodec {
  private static func storageBytes(width: Int, height: Int) -> Int {
    let side = Surface.tileSide
    return ((width + side - 1) / side) * ((height + side - 1) / side) * side * side * 16
  }
  static let keys = [
    "norm", "diss", "dark", "mul ", "idiv", "lbrn", "dkCl", "lite", "scrn", "div ", "lddg", "lgCl",
    "over", "sLit", "hLit", "vLit", "lLit", "pLit", "hMix", "diff", "smud", "fsub", "fdiv", "hue ",
    "sat ", "colr", "lum ",
  ]
  struct Record {
    var name: String
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var channels: [(Int, Int)]
    var blend: BlendMode
    var opacity: Float
    var visible: Bool
    var locked: Bool
    var mask: PSDMaskRecord?
    var tags: [String: Data]
    var section: Int
    var passThrough: Bool
    var clipped: Bool
  }
  public static func decodePackBits(_ data: Data, expected: Int) throws -> [UInt8] {
    guard expected >= 0, expected <= Surface.maxDimension * 4 else {
      throw CraftError.invalid("PSD row exceeds the size limit.")
    }
    var r = PSDReader(data: data)
    var out: [UInt8] = []
    out.reserveCapacity(expected)
    while out.count < expected {
      let code = Int(Int8(bitPattern: try r.u8()))
      if code >= 0 {
        let count = code + 1
        guard count <= expected - out.count else {
          throw CraftError.invalid("PackBits literal exceeds the row.")
        }
        out.append(contentsOf: try r.bytes(count))
      } else if code != -128 {
        let count = 1 - code
        guard count <= expected - out.count else {
          throw CraftError.invalid("PackBits repeat exceeds the row.")
        }
        out.append(contentsOf: repeatElement(try r.u8(), count: count))
      }
    }
    if r.remaining > 0 {
      guard try r.bytes(r.remaining).allSatisfy({ $0 == 128 }) else {
        throw CraftError.invalid("Unexpected trailing PackBits bytes.")
      }
    }
    return out
  }
  public static func read(_ data: Data, name: String = "Imported PSD") throws -> CraftDocument {
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("PSD exceeds the 512 MiB input limit.")
    }
    var r = PSDReader(data: data)
    guard try r.string(4) == "8BPS" else { throw CraftError.invalid("This is not a PSD file.") }
    guard try r.u16() == 1 else { throw CraftError.unsupported("PSB import is not ported yet.") }
    guard try r.bytes(6).allSatisfy({ $0 == 0 }) else {
      throw CraftError.invalid("Invalid PSD reserved header.")
    }
    let channels = try r.u16()
    let height = try r.u32()
    let width = try r.u32()
    let depth = try r.u16()
    let mode = try r.u16()
    guard [8, 16, 32].contains(depth), mode == 3, (3...4).contains(channels) else {
      throw CraftError.unsupported(
        "PSD import supports RGB at 8, 16 or 32 bits. Other color modes and extra alpha/spot channels are not ported yet."
      )
    }
    let pixelDepth: PixelDepth = depth == 8 ? .u8 : depth == 16 ? .u16 : .f32
    var doc = try CraftDocument(width: width, height: height, depth: pixelDepth, name: name)
    let colorData = try r.section()
    guard
      colorData.remaining == 0 || (depth == 32 && colorData.data.starts(with: Data("hdrt".utf8)))
    else {
      throw CraftError.unsupported("Unexpected color-mode data in RGB PSD.")
    }
    var resources = try r.section()
    _ = try PSDImageResources.blocks(resources.data)
    var profile: Data?
    while resources.remaining > 0 {
      guard try resources.string(4) == "8BIM" else {
        throw CraftError.invalid("Invalid image resource signature.")
      }
      let id = try resources.u16()
      let length = Int(try resources.u8())
      let resourceName = String(data: try resources.bytes(length), encoding: .macOSRoman) ?? "Path"
      if (length + 1) % 2 != 0 { _ = try resources.bytes(1) }
      let count = try resources.u32()
      let content = try resources.bytes(count)
      if count % 2 != 0 { _ = try resources.bytes(1) }
      if id == 1039 { profile = content }
      if id == 1025 || (2000...2997).contains(id) {
        var paths = doc.paths ?? []
        paths.append(
          NamedPath(
            name: id == 1025 ? "Work Path" : (resourceName.isEmpty ? "Path" : resourceName),
            path: try PSDPaths.read(content, width: width, height: height), isWorkPath: id == 1025))
        doc.paths = paths
      }
      if id == 1005 {
        var resolution = PSDReader(data: content)
        let horizontal = Double(try resolution.u32()) / 65536
        let horizontalUnit = try resolution.u16()
        _ = try resolution.u16()
        let vertical = Double(try resolution.u32()) / 65536
        let verticalUnit = try resolution.u16()
        _ = try resolution.u16()
        // Resolution values are stored in pixels/inch; units select how the UI displays them.
        guard (1...2).contains(horizontalUnit), (1...2).contains(verticalUnit),
          horizontal >= 1, vertical >= 1, abs(horizontal - vertical) < 0.01
        else {
          throw CraftError.unsupported(
            "Unequal horizontal/vertical PSD resolutions are not supported yet.")
        }
        doc.resolution = horizontal
      }
    }
    // Preserve all image resource blocks in the development archive, including unknown metadata.
    doc.sourceMetadata = ["psdResources": resources.data, "psdColorModeData": colorData.data]
    doc.sourceICC = profile
    var layerSection = try r.section()
    var info = layerSection.remaining > 0 ? try layerSection.section() : PSDReader(data: Data())
    var mergedTransparency = false
    if layerSection.remaining > 0 {
      let global = try layerSection.section()
      guard global.remaining == 0 || global.remaining >= 13 else {
        throw CraftError.invalid("Invalid global mask info.")
      }
      doc.sourceMetadata?["psdGlobalMask"] = global.data
      var tags = Set<String>()
      while layerSection.remaining >= 12 {
        guard try layerSection.string(4) == "8BIM" else {
          throw CraftError.invalid("Invalid global PSD tag.")
        }
        let tag = try layerSection.string(4)
        let length = try layerSection.u32()
        let content = try layerSection.bytes(length)
        _ = try layerSection.bytes((4 - length % 4) % 4)
        guard tags.insert(tag).inserted else {
          throw CraftError.invalid("Duplicate global PSD block.")
        }
        if ["Lr16", "Lr32", "Layr"].contains(tag) {
          let expectedTag = depth == 16 ? "Lr16" : depth == 32 ? "Lr32" : "Layr"
          guard tag == expectedTag, info.remaining == 0 else {
            throw CraftError.unsupported("Conflicting PSD layer-depth sections.")
          }
          info = PSDReader(data: content)
        } else if ["Mt16", "Mt32", "Mtrn"].contains(tag) {
          mergedTransparency = true
          doc.sourceMetadata?["psdGlobal_" + tag] = content
        } else if tag == "pths" {
          let names = try PSDPaths.readNames(content)
          let indices = (doc.paths ?? []).indices.filter { doc.paths?[$0].isWorkPath == false }
          guard names.count == indices.count else {
            throw CraftError.invalid("PSD path names and resources disagree.")
          }
          for (i, name) in zip(indices, names) { doc.paths?[i].name = name }
        } else if tag == "LMsk" {
          // User-mask overlay color/opacity; not a layer coverage channel.
          guard (13...16).contains(content.count), content[12] == 128 else {
            throw CraftError.unsupported("Unrecognized PSD user-mask display metadata.")
          }
          doc.sourceMetadata?["psdGlobal_LMsk"] = content
        } else {
          if tag == "OCIO", try !PSDColorMetadata.usesICC(content) {
            throw CraftError.unsupported("OpenColorIO-managed PSD documents are not ported yet.")
          }
          guard ["Patt", "Pat2", "Pat3", "FMsk", "cinf", "CAI ", "OCIO", "GenI"].contains(tag)
          else {
            throw CraftError.unsupported("Global PSD block '\(tag)' is not ported yet.")
          }
          doc.sourceMetadata?["psdGlobal_" + tag] = content
        }
      }
      guard try layerSection.bytes(layerSection.remaining).allSatisfy({ $0 == 0 }) else {
        throw CraftError.invalid("Invalid global PSD padding.")
      }
    }
    var patternBytes = 0
    for key in PSDPatterns.keys {
      guard let block = doc.sourceMetadata?["psdGlobal_" + key] else { continue }
      let patterns = try PSDPatterns.read(block, tileBudget: 536_870_912 - patternBytes)
      for pattern in patterns {
        if let previous = doc.pattern(pattern.id) {
          guard try PSDPatterns.exact([previous], [pattern]) else {
            throw CraftError.invalid("Conflicting embedded PSD pattern identifiers.")
          }
        } else {
          doc.patterns = (doc.patterns ?? []) + [pattern]
          patternBytes += pattern.surface.allocatedBytes
        }
      }
      try PatternArchive.validate(doc.patterns ?? [])
    }
    let signedCount = info.remaining == 0 ? 0 : try info.i16()
    mergedTransparency = mergedTransparency || signedCount < 0
    let count = abs(signedCount)
    guard count <= 1024 else {
      throw CraftError.invalid("PSD exceeds the layer/group record limit.")
    }
    guard channels == 3 || mergedTransparency else {
      throw CraftError.unsupported("PSD saved alpha channels are not ported yet.")
    }
    var records: [Record] = []
    var decodedBudget = patternBytes
    for _ in 0..<count {
      let top = try info.i32()
      let left = try info.i32()
      let bottom = try info.i32()
      let right = try info.i32()
      let w = right - left
      let h = bottom - top
      guard w >= 0, h >= 0, (w == 0) == (h == 0) else {
        throw CraftError.invalid("Invalid PSD layer bounds.")
      }
      _ = try Surface(width: max(1, w), height: max(1, h))
      decodedBudget += storageBytes(width: max(1, w), height: max(1, h))
      guard decodedBudget <= 512 * 1024 * 1024, abs(Double(left)) <= 1_000_000,
        abs(Double(top)) <= 1_000_000
      else { throw CraftError.invalid("PSD layers exceed the memory or coordinate budget.") }
      let channelCount = try info.u16()
      guard (0...6).contains(channelCount) else {
        throw CraftError.unsupported("Unsupported PSD layer channel count.")
      }
      var channelInfo: [(Int, Int)] = []
      var ids = Set<Int>()
      for _ in 0..<channelCount {
        let id = try info.i16()
        let length = try info.u32()
        guard [-3, -2, -1, 0, 1, 2].contains(id), ids.insert(id).inserted else {
          throw CraftError.unsupported("Unsupported or duplicate PSD layer channel.")
        }
        channelInfo.append((id, length))
      }
      guard try info.string(4) == "8BIM" else {
        throw CraftError.invalid("Invalid PSD layer channels or blend signature.")
      }
      let key = try info.string(4)
      guard keys.contains(key) || key == "pass" else {
        throw CraftError.unsupported("PSD blend mode \(key) is not supported.")
      }
      let opacity = Float(try info.u8()) / 255
      let clipping = try info.u8()
      let flags = try info.u8()
      _ = try info.u8()
      guard clipping <= 1 else { throw CraftError.invalid("Invalid PSD clipping flag.") }
      var extra = try info.section()
      let mask = try PSDMaskRecord.read(extra.section().data)
      guard mask != nil || (!ids.contains(-2) && !ids.contains(-3)) else {
        throw CraftError.invalid("PSD mask record and channels disagree.")
      }
      let ranges = try extra.section()
      guard
        ranges.remaining == 0
          || (ranges.data.count % 8 == 0
            && ranges.data.enumerated().allSatisfy({ $0.element == ($0.offset % 4 < 2 ? 0 : 255) }))
      else { throw CraftError.unsupported("PSD Blend If ranges are not ported yet.") }
      let length = Int(try extra.u8())
      var layerName = String(data: try extra.bytes(length), encoding: .macOSRoman) ?? "Layer"
      let padding = (4 - (length + 1) % 4) % 4
      _ = try extra.bytes(padding)
      var locked = flags & 1 != 0
      var tags: [String: Data] = [:]
      var section = 0
      var sectionBlend = key
      while extra.remaining >= 12 {
        guard try extra.string(4) == "8BIM" else {
          throw CraftError.unsupported("Unknown PSD tagged-block signature.")
        }
        let tag = try extra.string(4)
        let size = try extra.u32()
        let content = try extra.bytes(size)
        if size % 2 != 0 { _ = try extra.bytes(1) }
        guard tags[tag] == nil else { throw CraftError.invalid("Duplicate PSD layer block.") }
        tags[tag] = content
        switch tag {
        case "levl", "curv", "hue2", "blnc", "thrs", "post", "grdm", "PtFl", "GdFl":
          if tag == "grdm" {
            _ = try PSDGradientMap.read(content)
          } else if tag == "GdFl" {
            _ = try PSDGradientFill.read(content)
          } else if tag == "PtFl" {
            _ = try PSDPatternFill.read(content)
          } else if tag == "levl" {
            _ = try PSDLevels.read(content)
          } else if tag == "curv" {
            _ = try PSDCurves.read(content)
          } else if tag == "hue2" {
            _ = try PSDHueSaturation.read(content)
          } else if tag == "thrs" || tag == "post" {
            _ = try PSDTonalSteps.read(content, kind: tag == "thrs" ? .threshold : .posterize)
          } else {
            _ = try PSDColorBalance.read(content)
          }
          if let profile {
            let source = CGColorSpace(iccData: profile as CFData)
            guard
              source == (try RasterIO.colorSpace())
                || (depth == 32 && source == CGColorSpace(name: CGColorSpace.linearSRGB))
            else {
              throw CraftError.unsupported(
                "Editable PSD fill and tone layers require an sRGB document profile.")
            }
          }
        case "SoCo":
          _ = try PSDSolidColor.read(content)
        case "vmsk", "vsms":
          _ = try PSDPaths.readMask(content, width: doc.width, height: doc.height)
        case "lsct", "lsdk":
          guard section == 0, [4, 12, 16].contains(content.count) else {
            throw CraftError.invalid("Invalid PSD group divider.")
          }
          var divider = PSDReader(data: content)
          section = try divider.u32()
          guard (0...3).contains(section) else {
            throw CraftError.invalid("Invalid PSD group kind.")
          }
          if divider.remaining >= 8 {
            guard try divider.string(4) == "8BIM" else {
              throw CraftError.invalid("Invalid group blend signature.")
            }
            sectionBlend = try divider.string(4)
            guard keys.contains(sectionBlend) || sectionBlend == "pass" else {
              throw CraftError.unsupported("Unsupported PSD group blend mode.")
            }
          }
          if divider.remaining == 4, try divider.u32() != 0 {
            throw CraftError.unsupported("PSD scene groups are not ported yet.")
          }
        case "luni":
          var unicode = PSDReader(data: content)
          let n = try unicode.u32()
          guard n <= 100_000 else { throw CraftError.invalid("PSD layer name is too long.") }
          var units: [UInt16] = []
          for _ in 0..<n { units.append(UInt16(try unicode.u16())) }
          layerName = String(decoding: units, as: UTF16.self)
        case "lspf":
          var lock = PSDReader(data: content)
          let value = try lock.u32()
          locked = locked || value != 0
        case "lyid", "lnsr", "lclr", "shmd", "fxrp", "lyvr": break
        case "clbl", "infx", "lmgm", "vmgm":
          guard content.count == 4, content.dropFirst().allSatisfy({ $0 == 0 }), content[0] <= 1
          else {
            throw CraftError.invalid("Invalid PSD blending flag.")
          }
        // Effect/group flags have no rendering effect on these plain raster layers.
        case "knko":
          guard content.count == 4, content.allSatisfy({ $0 == 0 }) else {
            throw CraftError.unsupported("PSD knockout blending is not ported yet.")
          }
        case "iOpa":
          guard content.first == 255 else {
            throw CraftError.unsupported("PSD fill opacity is not ported yet.")
          }
        default:
          throw CraftError.unsupported(
            "PSD layer '\(layerName)' contains unported data '\(tag)' (for example type, effects, groups or smart objects). Import cancelled to preserve its contents."
          )
        }
      }
      if extra.remaining > 0 {
        guard try extra.bytes(extra.remaining).allSatisfy({ $0 == 0 }) else {
          throw CraftError.invalid("Invalid layer padding.")
        }
      }
      guard
        section != 0
          || (key != "pass"
            && (tags["SoCo"] != nil || tags["PtFl"] != nil || tags["GdFl"] != nil
              || tags["levl"] != nil
              || tags["curv"] != nil
              || tags["hue2"] != nil || tags["blnc"] != nil || tags["thrs"] != nil
              || tags["post"] != nil || tags["grdm"] != nil
              || (flags & 16 == 0 && ids.isSuperset(of: [0, 1, 2]))))
      else {
        throw CraftError.unsupported("Unsupported non-raster PSD layer.")
      }
      let contentBlocks = [
        "SoCo", "PtFl", "GdFl", "levl", "curv", "hue2", "blnc", "thrs", "post", "grdm",
      ]
      .filter {
        tags[$0] != nil
      }
      guard section == 0 || contentBlocks.isEmpty, contentBlocks.count <= 1
      else {
        throw CraftError.invalid("Conflicting PSD layer content blocks.")
      }
      guard !(tags["vmsk"] != nil && tags["vsms"] != nil) else {
        throw CraftError.invalid("Duplicate PSD vector masks.")
      }
      if mask != nil && !ids.contains(-2) && !ids.contains(-3)
        && tags["vmsk"] == nil && tags["vsms"] == nil
      {
        throw CraftError.invalid("PSD mask metadata without a mask.")
      }
      records.append(
        Record(
          name: layerName, x: left, y: top, w: w, h: h, channels: channelInfo,
          blend: BlendMode.allCases[keys.firstIndex(of: sectionBlend) ?? 0], opacity: opacity,
          visible: flags & 2 == 0,
          locked: locked, mask: mask, tags: tags, section: section,
          passThrough: sectionBlend == "pass", clipped: clipping == 1))
    }
    var layers: [Layer] = []
    var groupStack: [UUID] = []
    for record in records {
      var planes: [Int: [UInt8]] = [:]
      for (id, length) in record.channels {
        if id == -2 || id == -3 {
          guard let metadata = record.mask else {
            throw CraftError.invalid("Missing PSD mask record.")
          }
          let (b, _) = try metadata.selected(id)
          decodedBudget += storageBytes(width: max(1, b.width), height: max(1, b.height))
          guard decodedBudget <= 512 * 1024 * 1024 else {
            throw CraftError.invalid("PSD masks exceed the memory budget.")
          }
          let bytes = try info.bytes(length)
          if b.empty {
            guard bytes == Data([0, 0]) || bytes == Data([0, 1]) else {
              throw CraftError.invalid("Invalid empty mask channel.")
            }
            planes[id] = []
          } else {
            planes[id] = try PSDChannelCodec.decode(
              bytes, width: b.width, height: b.height, depth: depth)
          }
        } else if record.w == 0 {
          let bytes = try info.bytes(length)
          guard bytes == Data([0, 0]) || bytes == Data([0, 1]) else {
            throw CraftError.invalid("Invalid empty PSD layer channel.")
          }
          planes[id] = []
        } else {
          planes[id] = try PSDChannelCodec.decode(
            info.bytes(length), width: record.w, height: record.h, depth: depth)
        }
      }
      if record.section == 3 {
        guard groupStack.count < 32, record.mask == nil else {
          throw CraftError.invalid("Invalid or excessive PSD group nesting.")
        }
        groupStack.append(UUID())
        continue
      }
      let red = planes[0] ?? []
      let green = planes[1] ?? []
      let blue = planes[2] ?? []
      guard
        record.section != 0 || record.tags["SoCo"] != nil || record.tags["PtFl"] != nil
          || record.tags["GdFl"] != nil
          || record.tags["levl"] != nil
          || record.tags["curv"] != nil || record.tags["hue2"] != nil || record.tags["blnc"] != nil
          || record.tags["thrs"] != nil || record.tags["post"] != nil || record.tags["grdm"] != nil
          || [0, 1, 2].allSatisfy({ planes[$0] != nil })
      else {
        throw CraftError.invalid("Missing RGB plane.")
      }
      var surface = try Surface(
        width: max(1, record.w), height: max(1, record.h), depth: pixelDepth,
        colorEncoding: depth == 32 ? .linearRGB : .sRGB)
      for y
        in 0..<(record.section == 0 && record.tags["SoCo"] == nil && record.tags["PtFl"] == nil
        && record.tags["GdFl"] == nil
        && record.tags["levl"] == nil
        && record.tags["curv"] == nil && record.tags["hue2"] == nil && record.tags["blnc"] == nil
        && record.tags["thrs"] == nil && record.tags["post"] == nil && record.tags["grdm"] == nil
        ? record.h : 0)
      {
        for x in 0..<record.w {
          let i = y * record.w + x
          let sample = try Pixel(
            PSDChannelCodec.sample(red, i, depth: depth),
            PSDChannelCodec.sample(green, i, depth: depth),
            PSDChannelCodec.sample(blue, i, depth: depth),
            planes[-1].map { try PSDChannelCodec.sample($0, i, depth: depth) } ?? 1)
          if depth == 32 {
            surface.setLinearPixel(x: x, y: y, sample)
          } else {
            surface.setPixel(x: x, y: y, sample)
          }
        }
      }
      surface = try convertProfile(surface, profile: profile, linear: depth == 32)
      var layer = Layer(name: record.name, content: .raster(surface))
      if let data = record.tags["GdFl"] {
        layer.content = .gradientFill(try PSDGradientFill.read(data))
      }
      if let data = record.tags["PtFl"] {
        layer.content = .patternFill(try PSDPatternFill.read(data).fill)
      }
      if let levels = record.tags["levl"] {
        layer.content = .adjustment(.levels(try PSDLevels.read(levels)))
      }
      if let curves = record.tags["curv"] {
        layer.content = .adjustment(.curves(try PSDCurves.read(curves)))
      }
      if let settings = record.tags["hue2"] {
        layer.content = .adjustment(.hueSaturation(try PSDHueSaturation.read(settings)))
      }
      for kind in TonalStepsAdjustment.Kind.allCases {
        if let settings = record.tags[PSDTonalSteps.key(kind)] {
          layer.content = .adjustment(.tonalSteps(try PSDTonalSteps.read(settings, kind: kind)))
        }
      }
      if let settings = record.tags["grdm"] {
        layer.content = .adjustment(.gradientMap(try PSDGradientMap.read(settings)))
      }
      if let settings = record.tags["blnc"] {
        layer.content = .adjustment(.colorBalance(try PSDColorBalance.read(settings)))
      }
      if let fill = record.tags["SoCo"] {
        // RGB fill components use the document profile; RGB/32 uses linear light.
        let sample = try Surface(width: 1, height: 1, depth: .f32, fill: PSDSolidColor.read(fill))
        layer.content = .fill(
          try convertProfile(sample, profile: profile, linear: depth == 32).pixel(x: 0, y: 0))
      }
      if record.section == 1 || record.section == 2 {
        guard let id = groupStack.popLast() else {
          throw CraftError.invalid("Unbalanced PSD group divider.")
        }
        layer.id = id
        layer.content = .group(
          GroupContent(passThrough: record.passThrough, expanded: record.section == 1))
      }
      layer.parentID = groupStack.last
      layer.clipped = record.clipped
      layer.blendClippedAsGroup = record.tags["clbl"].map { $0[0] != 0 }
      layer.x = record.x
      layer.y = record.y
      layer.blendMode = record.blend
      layer.opacity = record.opacity
      layer.visible = record.visible
      layer.locked = record.locked
      layer.sourceTags = record.tags
      if let block = record.tags["vmsk"] ?? record.tags["vsms"] {
        layer.vectorMask = try PSDPaths.readMask(block, width: doc.width, height: doc.height)
        layer.vectorMask?.density = Float(record.mask?.vectorDensity ?? 255) / 255
        layer.vectorMask?.feather = record.mask?.vectorFeather ?? 0
      }
      if let metadata = record.mask, layer.vectorMask == nil {
        // Photoshop may save an empty, all-white generated mask even without a path.
        // Only this identity mask is safe to omit; nontrivial rasterized vectors still reject.
        let emptyOpaque =
          metadata.bounds.empty && metadata.background == 255
          && metadata.flags == 8 && metadata.real == nil
        guard metadata.vectorDensity == 255, metadata.vectorFeather == 0,
          metadata.flags & 8 == 0 || emptyOpaque
        else {
          throw CraftError.unsupported(
            "Rasterized vector-mask parameters are not yet editable in Photato.")
        }
      }
      if let metadata = record.mask,
        planes[-3] != nil || (planes[-2] != nil && metadata.flags & 8 == 0)
      {
        let id = planes[-3] != nil ? -3 : -2
        let (b, properties) = try metadata.selected(id)
        var mask = try Surface(
          width: max(1, b.width), height: max(1, b.height), depth: pixelDepth,
          fill: Pixel(properties.outside, properties.outside, properties.outside))
        if !b.empty, let values = planes[id] {
          for y in 0..<b.height {
            for x in 0..<b.width {
              let value = unit(try PSDChannelCodec.sample(values, y * b.width + x, depth: depth))
              mask.setPixel(x: x, y: y, Pixel(value, value, value))
            }
          }
        }
        layer.mask = mask
        layer.maskProperties = properties
        layer.maskProperties?.transform = .translation(Double(b.x - layer.x), Double(b.y - layer.y))
      }
      try PSDPatternFill.importPlacement(&layer, width: doc.width, height: doc.height)
      layers.append(layer)
    }
    guard groupStack.isEmpty else { throw CraftError.invalid("Unclosed PSD layer group.") }
    // Photoshop records and the engine both store layers bottom-to-top.
    doc.layers = layers
    doc.activeLayerID = doc.layers.last?.id
    if info.remaining > 0 {
      guard try info.bytes(info.remaining).allSatisfy({ $0 == 0 }) else {
        throw CraftError.invalid("Unexpected layer channel tail.")
      }
    }
    // Validate all merged compression streams even when editable layers supply the image.
    let merged = try PSDChannelCodec.decode(
      r.bytes(r.remaining), width: width, height: height, depth: depth, channels: channels)
    if count == 0 {
      guard storageBytes(width: width, height: height) <= 512 * 1024 * 1024 else {
        throw CraftError.invalid("PSD pixels exceed the memory budget.")
      }
      let n = width * height
      var surface = try Surface(
        width: width, height: height, depth: pixelDepth,
        colorEncoding: depth == 32 ? .linearRGB : .sRGB)
      for y in 0..<height {
        for x in 0..<width {
          let i = y * width + x
          let stored = try Pixel(
            PSDChannelCodec.sample(merged, i, depth: depth),
            PSDChannelCodec.sample(merged, n + i, depth: depth),
            PSDChannelCodec.sample(merged, 2 * n + i, depth: depth),
            channels == 4 ? PSDChannelCodec.sample(merged, 3 * n + i, depth: depth) : 1)
          let sample = mergedTransparency && channels == 4 ? PSDMergedSample.decode(stored) : stored
          if depth == 32 {
            surface.setLinearPixel(x: x, y: y, sample)
          } else {
            surface.setPixel(x: x, y: y, sample)
          }
        }
      }
      surface = try convertProfile(surface, profile: profile, linear: depth == 32)
      let layer = Layer(name: "Background", content: .raster(surface))
      doc.layers = [layer]
      doc.activeLayerID = layer.id
    }
    try doc.validate()
    return doc
  }
  private static func convertProfile(_ surface: Surface, profile: Data?, linear: Bool) throws
    -> Surface
  {
    let target = try RasterIO.colorSpace()
    let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    let source =
      profile.flatMap { CGColorSpace(iccData: $0 as CFData) } ?? (linear ? linearSpace : target)
    guard source.model == .rgb, profile == nil || CGColorSpace(iccData: profile! as CFData) != nil
    else {
      throw CraftError.invalid("Invalid embedded RGB PSD ICC profile.")
    }
    if !linear && source == target { return surface }
    if linear && (source == linearSpace || source == target) {
      // Photoshop coerces RGB/32 sRGB profiles to gamma 1. Unprofiled RGB/32 is
      // interpreted as linear sRGB. Alpha and mask channels never use the transfer.
      return try surface.interpretingSamples(as: .linearRGB)
    }
    // Convert opaque colors, then restore alpha, preserving hidden RGB samples.
    var opaque = surface
    opaque.mapPixels { _, _, p in Pixel(p.r, p.g, p.b) }
    var result = try RasterIO.surface(
      RasterIO.cgImage(opaque, space: source, colorEncoding: surface.colorEncoding),
      depth: surface.depth)
    result.mapPixels { x, y, p in Pixel(p.r, p.g, p.b, surface.pixel(x: x, y: y).a) }
    return result
  }

  public static func writeRasterLayers(
    _ doc: CraftDocument, compression: PSDCompression = .zipPrediction
  ) throws -> Data {
    try doc.validate()
    guard !doc.layers.isEmpty, doc.width <= 30000, doc.height <= 30000 else {
      throw CraftError.unsupported(
        "PSD export requires at least one pixel layer and dimensions no larger than 30,000 pixels."
      )
    }
    let depth = doc.depth == .u8 ? 8 : doc.depth == .u16 ? 16 : 32
    var records = PSDWriter()
    var pixels = Data()
    var entries: [(Layer, Int)] = []
    func collect(_ parent: UUID?) {
      for layer in doc.children(of: parent) {
        if let group = layer.group {
          var marker = Layer(name: "</Layer group>", content: .group(GroupContent()))
          marker.visible = false
          entries.append((marker, 3))
          collect(layer.id)
          entries.append((layer, group.expanded ? 1 : 2))
        } else {
          entries.append((layer, 0))
        }
      }
    }
    collect(nil)
    records.n(-entries.count, 2)  // Negative count declares merged transparency.
    for (layer, section) in entries {
      let surface: Surface?
      let isFill: Bool
      isFill = layer.isCanvasFill
      if case .raster(let pixels) = layer.content, layer.affine == nil {
        surface = pixels
      } else if case .fill(let color) = layer.content {
        _ = try PSDSolidColor.write(color)
        surface = try Renderer.layerSurface(layer, in: doc)
      } else if case .gradientFill(let fill) = layer.content {
        _ = try PSDGradientFill.write(fill)
        surface = try Renderer.layerSurface(layer, in: doc)
      } else if case .patternFill(let fill) = layer.content {
        guard let pattern = doc.pattern(fill.patternID) else {
          throw CraftError.invalid("Missing embedded pattern.")
        }
        _ = try PSDPatternFill.write(fill, pattern: pattern)
        surface = try Renderer.layerSurface(layer, in: doc)
      } else if layer.isGroup {
        surface = nil
      } else if case .adjustment(.levels(let levels)) = layer.content {
        _ = try PSDLevels.write(levels)
        surface = nil
      } else if case .adjustment(.curves(let curves)) = layer.content {
        _ = try PSDCurves.write(curves)
        surface = nil
      } else if case .adjustment(.hueSaturation(let settings)) = layer.content {
        _ = try PSDHueSaturation.write(settings)
        surface = nil
      } else if case .adjustment(.gradientMap(let settings)) = layer.content {
        guard depth != 32 else {
          throw CraftError.unsupported(
            "Photoshop does not support editable Gradient Map layers in 32-bit documents. Export a flattened image or use an 8- or 16-bit document."
          )
        }
        _ = try PSDGradientMap.write(settings)
        surface = nil
      } else if case .adjustment(.tonalSteps(let settings)) = layer.content {
        _ = try PSDTonalSteps.write(settings)
        surface = nil
      } else if case .adjustment(.colorBalance(let settings)) = layer.content {
        _ = try PSDColorBalance.write(settings)
        surface = nil
      } else {
        throw CraftError.unsupported(
          "PSD export currently preserves pixel layers, solid-color, gradient and pattern fills, Levels, Curves, Hue/Saturation, Color Balance, Threshold, Posterize, Gradient Map, groups and masks. Keep the .photato original; other live layers are not yet supported."
        )
      }
      let originX = isFill ? 0 : layer.x
      let originY = isFill ? 0 : layer.y
      records.n(surface == nil ? 0 : originY, 4)
      records.n(surface == nil ? 0 : originX, 4)
      records.n(surface == nil ? 0 : originY + surface!.height, 4)
      records.n(surface == nil ? 0 : originX + surface!.width, 4)
      records.n(layer.mask == nil ? 4 : 5, 2)
      var channelData: [(Int, Data)] = []
      for channel in 0..<4 {
        guard let surface else {
          channelData.append((channel == 3 ? -1 : channel, Data([0, 0])))
          continue
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(surface.width * surface.height * (depth / 8))
        for y in 0..<surface.height {
          for x in 0..<surface.width {
            let p = depth == 32 ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
            let value = [p.r, p.g, p.b, p.a][channel]
            try PSDChannelCodec.append(
              value, depth: depth,
              to: &bytes)
          }
        }
        channelData.append(
          (
            channel == 3 ? -1 : channel,
            try PSDChannelCodec.encode(
              bytes,
              width: surface.width, height: surface.height, depth: depth, compression: compression)
          ))
      }
      if let mask = layer.mask {
        var bytes: [UInt8] = []
        for y in 0..<mask.height {
          for x in 0..<mask.width {
            try PSDChannelCodec.append(unit(mask.pixel(x: x, y: y).r), depth: depth, to: &bytes)
          }
        }
        channelData.append(
          (
            -2,
            try PSDChannelCodec.encode(
              bytes, width: mask.width, height: mask.height,
              depth: depth, compression: compression)
          ))
      }
      for (id, data) in channelData {
        records.n(id, 2)
        records.n(data.count, 4)
      }
      records.text("8BIM")
      let blendKey =
        section != 3 && layer.group?.passThrough == true
        ? "pass" : keys[BlendMode.allCases.firstIndex(of: layer.blendMode) ?? 0]
      records.text(blendKey)
      records.n(Int((unit(layer.opacity) * 255).rounded()), 1)
      records.n(layer.isClipped ? 1 : 0, 1)
      let adjustmentFlags: Int
      if case .adjustment = layer.content { adjustmentFlags = 24 } else { adjustmentFlags = 0 }
      records.n((layer.visible ? 0 : 2) | (layer.locked ? 1 : 0) | adjustmentFlags, 1)
      records.n(0, 1)
      var extra = PSDWriter()
      if layer.mask != nil || layer.vectorMask != nil {
        let mask = layer.mask
        let p = layer.effectiveMaskProperties
        let t = layer.maskCoordinateTransform
        guard t.a == 1, t.b == 0, t.c == 0, t.d == 1, t.tx == t.tx.rounded(),
          t.ty == t.ty.rounded(), p.outside == 0 || p.outside == 1
        else {
          throw CraftError.unsupported(
            "PSD export of resampled or transformed mask bounds is not ported yet. Save the editable .photato original."
          )
        }
        var m = PSDWriter()
        m.n(Int(t.ty), 4)
        m.n(Int(t.tx), 4)
        m.n(Int(t.ty) + (mask?.height ?? 0), 4)
        m.n(Int(t.tx) + (mask?.width ?? 0), 4)
        m.n(p.outside == 0 ? 0 : 255, 1)
        let parameters = p.density != 1 || p.feather != 0 || layer.vectorMask != nil
        m.n(
          (p.linked ? 0 : 1) | (p.enabled ? 0 : 2) | (p.inverted ? 4 : 0) | (parameters ? 16 : 0), 1
        )
        if parameters {
          m.n(layer.vectorMask == nil ? 3 : 15, 1)
          m.n(Int((p.density * 255).rounded()), 1)
          m.n(Int(truncatingIfNeeded: p.feather.bitPattern), 8)
          if let vector = layer.vectorMask {
            m.n(Int((vector.density * 255).rounded()), 1)
            m.n(Int(truncatingIfNeeded: vector.feather.bitPattern), 8)
          }
        } else {
          m.n(0, 2)
        }
        extra.section(m.data)
      } else {
        extra.n(0, 4)
      }
      extra.n(0, 4)
      let name = Data(layer.name.utf8.prefix(255))
      extra.n(name.count, 1)
      extra.data.append(name)
      for _ in 0..<((4 - (name.count + 1) % 4) % 4) { extra.n(0, 1) }
      let unicode = Array(layer.name.utf16)
      var text = PSDWriter()
      text.n(unicode.count, 4)
      for unit in unicode { text.n(Int(unit), 2) }
      extra.text("8BIM")
      extra.text("luni")
      extra.section(text.data)
      if section != 0 {
        var divider = PSDWriter()
        divider.n(section, 4)
        divider.text("8BIM")
        divider.text(blendKey)
        extra.text("8BIM")
        extra.text("lsct")
        extra.section(divider.data)
      }
      extra.text("8BIM")
      extra.text("clbl")
      extra.section(Data([layer.clipsBlendAsGroup ? 1 : 0, 0, 0, 0]))
      if let mask = layer.vectorMask {
        extra.text("8BIM")
        extra.text("vmsk")
        extra.section(try PSDPaths.writeMask(mask, width: doc.width, height: doc.height))
      }
      if case .gradientFill(let fill) = layer.content {
        let data = try PSDGradientFill.write(fill, original: layer.sourceTags?["GdFl"])
        extra.text("8BIM")
        extra.text("GdFl")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .patternFill(let fill) = layer.content, let pattern = doc.pattern(fill.patternID) {
        let placement = try PSDPatternFill.exportPlacement(
          layer, width: doc.width, height: doc.height)
        let data = try PSDPatternFill.write(
          placement, pattern: pattern, original: layer.sourceTags?["PtFl"])
        extra.text("8BIM")
        extra.text("PtFl")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .fill(let color) = layer.content {
        let fill = try PSDSolidColor.write(
          depth == 32 ? SRGBTransfer.linear(color) : color,
          original: layer.sourceTags?["SoCo"])
        extra.text("8BIM")
        extra.text("SoCo")
        extra.section(fill)
        if fill.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .adjustment(.levels(let levels)) = layer.content {
        extra.text("8BIM")
        extra.text("levl")
        extra.section(try PSDLevels.write(levels, original: layer.sourceTags?["levl"]))
      }
      if case .adjustment(.curves(let curves)) = layer.content {
        let data = try PSDCurves.write(curves, original: layer.sourceTags?["curv"])
        extra.text("8BIM")
        extra.text("curv")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .adjustment(.hueSaturation(let settings)) = layer.content {
        extra.text("8BIM")
        extra.text("hue2")
        extra.section(
          try PSDHueSaturation.write(
            settings, original: layer.sourceTags?["hue2"], includeRangeColors: true))
      }
      if case .adjustment(.gradientMap(let settings)) = layer.content {
        extra.text("8BIMgrdm")
        extra.section(try PSDGradientMap.write(settings, original: layer.sourceTags?["grdm"]))
      }
      if case .adjustment(.tonalSteps(let settings)) = layer.content {
        let key = PSDTonalSteps.key(settings.kind)
        extra.text("8BIM")
        extra.text(key)
        extra.section(try PSDTonalSteps.write(settings, original: layer.sourceTags?[key]))
      }
      if case .adjustment(.colorBalance(let settings)) = layer.content {
        let data = try PSDColorBalance.write(settings, original: layer.sourceTags?["blnc"])
        extra.text("8BIM")
        extra.text("blnc")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      for (tag, content) in (layer.sourceTags ?? [:]).sorted(by: { $0.key < $1.key })
      where ![
        "luni", "lspf", "lyid", "lsct", "lsdk", "clbl", "vmsk", "vsms", "SoCo", "levl", "curv",
        "hue2", "blnc", "thrs", "post", "grdm", "PtFl", "GdFl",
      ]
      .contains(tag) {
        extra.text("8BIM")
        extra.text(tag)
        extra.section(content)
        if content.count % 2 != 0 { extra.n(0, 1) }
      }
      var lock = PSDWriter()
      lock.n(layer.locked ? 7 : 0, 4)
      extra.text("8BIM")
      extra.text("lspf")
      extra.section(lock.data)
      records.section(extra.data)
      for (_, data) in channelData { pixels.append(data) }
      guard pixels.count + records.data.count <= 512 * 1024 * 1024 else {
        throw CraftError.invalid("PSD export exceeds the file size budget.")
      }
    }
    // Mask samples retain their own rectangle and editable property parameters.
    records.data.append(pixels)
    while records.data.count % 4 != 0 { records.n(0, 1) }
    var layerMask = PSDWriter()
    if depth == 8 { layerMask.section(records.data) } else { layerMask.n(0, 4) }
    layerMask.n(0, 4)
    if depth != 8 {
      layerMask.text("8BIM")
      layerMask.text(depth == 16 ? "Lr16" : "Lr32")
      layerMask.section(records.data)
    }
    let savedNames = (doc.paths ?? []).filter { !$0.isWorkPath }.map(\.name)
    for (key, data) in try PSDPatterns.exportBlocks(doc) {
      layerMask.text("8BIM")
      layerMask.text(key)
      layerMask.section(data)
      for _ in 0..<((4 - data.count % 4) % 4) { layerMask.n(0, 1) }
    }
    if !savedNames.isEmpty {
      let names = PSDPaths.writeNames(savedNames)
      layerMask.text("8BIM")
      layerMask.text("pths")
      layerMask.section(names)
      for _ in 0..<((4 - names.count % 4) % 4) { layerMask.n(0, 1) }
    }
    var output = PSDWriter()
    output.text("8BPS")
    output.n(1, 2)
    output.data.append(contentsOf: repeatElement(0, count: 6))
    output.n(4, 2)
    output.n(doc.height, 4)
    output.n(doc.width, 4)
    output.n(depth, 2)
    output.n(3, 2)
    output.section(
      depth == 32
        ? (doc.sourceMetadata?["psdColorModeData"].flatMap { $0.isEmpty ? nil : $0 }
          ?? PSDColorMetadata.defaultHDRToning()) : Data())
    // Export samples are sRGB; never attach the original import profile after conversion.
    var resources = PSDWriter()
    resources.data = try PSDImageResources.preserved(doc.sourceMetadata?["psdResources"] ?? Data())
    if let metadata = try RasterMetadata.metadata(
      doc.sourceMetadata, width: doc.width, height: doc.height, resolution: doc.pixelsPerInch,
      linear: doc.depth == .f32),
      let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data?
    {
      resources.data.append(PSDImageResources.block(1060, data: xmp))
    }
    guard doc.pixelsPerInch < 65536 else {
      throw CraftError.unsupported("PSD resolution exceeds its 16.16 fixed-point range.")
    }
    var resolution = PSDWriter()
    for _ in 0..<2 {
      resolution.n(Int((doc.pixelsPerInch * 65536).rounded()), 4)
      resolution.n(1, 2)
      resolution.n(1, 2)
    }
    resources.text("8BIM")
    resources.n(1005, 2)
    resources.n(0, 2)
    resources.section(resolution.data)
    let exportSpace =
      depth == 32 ? CGColorSpace(name: CGColorSpace.linearSRGB)! : try RasterIO.colorSpace()
    if let profile = exportSpace.copyICCData() {
      resources.text("8BIM")
      resources.n(1039, 2)
      resources.n(0, 2)
      let data = profile as Data
      resources.section(data)
      if data.count % 2 != 0 { resources.n(0, 1) }
    }
    var pathID = 2000
    for saved in doc.paths ?? [] {
      let name = Data(
        (saved.name.data(using: .macOSRoman, allowLossyConversion: true) ?? Data("Path".utf8))
          .prefix(255))
      resources.text("8BIM")
      resources.n(saved.isWorkPath ? 1025 : pathID, 2)
      let bytes = saved.isWorkPath ? Data() : name
      resources.n(bytes.count, 1)
      resources.data.append(bytes)
      if (bytes.count + 1) % 2 != 0 { resources.n(0, 1) }
      let data = try PSDPaths.write(saved.path, width: doc.width, height: doc.height)
      resources.section(data)
      if data.count % 2 != 0 { resources.n(0, 1) }
      if !saved.isWorkPath { pathID += 1 }
    }
    output.section(resources.data)
    output.section(layerMask.data)
    output.n(0, 2)
    let composite = try Renderer.composite(doc)
    for channel in 0..<4 {
      for y in 0..<doc.height {
        for x in 0..<doc.width {
          let p =
            depth == 32
            ? PSDMergedSample.encodeLinear(composite.linearPixel(x: x, y: y))
            : PSDMergedSample.encode(composite.pixel(x: x, y: y), depth: depth)
          var bytes: [UInt8] = []
          let value = [p.r, p.g, p.b, p.a][channel]
          try PSDChannelCodec.append(
            value, depth: depth,
            to: &bytes)
          output.data.append(contentsOf: bytes)
        }
      }
    }
    guard output.data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("PSD export exceeds the file size budget.")
    }
    return output.data
  }
}
