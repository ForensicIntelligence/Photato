import Foundation
import PhotoCraftCore

/// Independent Swift mapping of Adobe resource1065 and shmd/cmls envelopes.
/// Public format evidence and limits are recorded in PSD_LAYER_COMP_REFERENCES.json.
enum PSDLayerComps {
  static let namespace = "50484F54-4154-5000-8000-"
  static func uuid(_ id: Int32) -> UUID {
    UUID(uuidString: namespace + String(format: "%012llX", UInt64(UInt32(bitPattern: id))))!
  }
  static func originalID(_ id: UUID) -> Int32? {
    let text = id.uuidString
    guard text.hasPrefix(namespace), let value = UInt32(text.suffix(12), radix: 16) else { return nil }
    return Int32(bitPattern: value)
  }
  static func identifiers(_ ids: [UUID]) throws -> [UUID: Int32] {
    var result: [UUID: Int32] = [:], used = Set<Int32>([0, -1])
    for id in ids {
      if let value = originalID(id), !used.contains(value) { result[id] = value; used.insert(value) }
    }
    for id in ids where result[id] == nil {
      // Stable within the document, independent of Swift's randomized Hasher.
      var hash: UInt32 = 2_166_136_261
      for byte in id.uuidString.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
      var value = Int32(hash & 0x7fff_ffff); if value == 0 { value = 1 }
      while used.contains(value) { value = value == Int32.max ? 1 : value + 1 }
      result[id] = value; used.insert(value)
    }
    return result
  }
  static func integer(_ value: PSDValue?) throws -> Int32 {
    guard case .integer(let n) = value else { throw CraftError.invalid("Invalid Layer Comp integer.") }; return n
  }
  static func text(_ value: PSDValue?, fallback: String? = nil) throws -> String {
    if value == nil, let fallback { return fallback }
    guard case .text(let units) = value else { throw CraftError.invalid("Invalid Layer Comp text.") }
    return String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
  }
  static func point(_ value: PSDValue?) throws -> PathPoint? {
    guard let value else { return nil }
    guard case .object(let d) = value, let x = d["Hrzn"]?.number, let y = d["Vrtc"]?.number,
      x.isFinite, y.isFinite, abs(x) <= 1_000_000, abs(y) <= 1_000_000 else { throw CraftError.invalid("Invalid Layer Comp offset.") }
    try PSDGradient.supported(d, keys: ["Hrzn", "Vrtc"]); return PathPoint(x, y)
  }
  struct Metadata {
    let signature: Data
    let key: String
    let flags: Data
    let data: Data
    var encoded: Data {
      var w = PSDWriter(); w.data.append(signature); w.text(key); w.data.append(flags); w.section(data); return w.data
    }
  }
  static func metadata(_ data: Data?) throws -> [Metadata] {
    guard let data else { return [] }
    var r = PSDReader(data: data); let count = try r.u32()
    guard count <= 4096, count <= r.remaining / 16 else { throw CraftError.invalid("Oversized layer metadata list.") }
    var result: [Metadata] = []
    for _ in 0..<count {
      let signature = try r.bytes(4), key = try r.string(4), flags = try r.bytes(4)
      guard [Data("8BIM".utf8), Data("8ELE".utf8)].contains(signature) else { throw CraftError.invalid("Invalid layer metadata signature.") }
      result.append(.init(signature: signature, key: key, flags: flags, data: try r.bytes(r.u32())))
    }
    guard r.remaining <= 3, try r.consumePadding(0) else { throw CraftError.invalid("Invalid layer metadata tail.") }
    return result
  }
  static func descriptor(_ layer: Layer) throws -> PSDDescriptor? {
    let entries = try metadata(layer.sourceTags?["shmd"]).filter { $0.key == "cmls" }
    guard entries.count <= 1 else { throw CraftError.invalid("Duplicate layer comp metadata.") }
    guard let entry = entries.first else { return nil }
    let d = try PSDDescriptor.read(entry.data, padding: true)
    try PSDGradient.supported(d, keys: ["LyrI", "origFXRefPoint", "layerSettings"])
    if let raw = layer.sourceTags?["lyid"] {
      var r = PSDReader(data: raw); guard try Int32(r.i32()) == integer(d["LyrI"]), r.remaining == 0 else { throw CraftError.invalid("Layer Comp layer ID disagrees with its layer.") }
    }
    _ = try point(d["origFXRefPoint"]); return d
  }
  static func read(into document: inout CraftDocument) throws {
    let blocks = try PSDImageResources.blocks(document.sourceMetadata?["psdResources"] ?? Data()).filter { $0.id == 1065 }
    guard blocks.count <= 1 else { throw CraftError.invalid("Duplicate Layer Comp resources.") }
    guard let block = blocks.first else { return }
    let root = try PSDDescriptor.read(block.data)
    try PSDGradient.supported(root, keys: ["list", "lastAppliedComp"])
    guard case .list(let values) = root["list"], values.count <= LayerComps.maximumComps else { throw CraftError.invalid("Invalid Layer Comp catalogue.") }
    var library = LayerComps(), numbers = Set<Int32>()
    for value in values {
      guard case .object(let d) = value else { throw CraftError.invalid("Invalid Layer Comp record.") }
      try PSDGradient.supported(d, keys: ["Nm  ", "comment", "compID", "capturedInfo"])
      let id = try integer(d["compID"]), flags = try integer(d["capturedInfo"])
      guard id != 0, id != -1, numbers.insert(id).inserted else { throw CraftError.invalid("Invalid or duplicate Layer Comp ID.") }
      guard flags >= 0, flags & ~7 == 0 else { throw CraftError.unsupported("PSD parent Smart Object comp records or additional properties require further mapping.") }
      let options = LayerCompOptions(visibility: flags & 1 != 0, position: flags & 2 != 0, appearance: flags & 4 != 0)
      var comp = LayerComp(id: uuid(id), name: try text(d["Nm  "]), comment: try text(d["comment"], fallback: ""), options: options, document: document)
      comp.layers = []; library.comps.append(comp)
    }
    let indices = Dictionary(uniqueKeysWithValues: library.comps.indices.map { (library.comps[$0].id, $0) })
    var last: [LayerCompLayerState] = [], sawLast = false
    for layer in document.layers {
      try Task.checkCancellation()
      guard let d = try descriptor(layer) else { continue }
      guard case .list(let entries) = d["layerSettings"], entries.count <= LayerComps.maximumComps + 1 else { throw CraftError.invalid("Invalid per-layer comp settings.") }
      var enabled = true, offset = PathPoint(0, 0), seen = Set<Int32>()
      for value in entries {
        guard case .object(let entry) = value else { throw CraftError.invalid("Invalid layer comp state.") }
        try PSDGradient.supported(entry, keys: ["compList", "enab", "Ofst", "FXRefPoint"])
        if let flag = entry["enab"] {
          guard case .boolean(let flag) = flag else { throw CraftError.invalid("Invalid comp visibility.") }; enabled = flag
        }
        if let position = try point(entry["Ofst"]) { offset = position }
        _ = try point(entry["FXRefPoint"])
        guard offset.x.rounded() == offset.x, offset.y.rounded() == offset.y,
          case .list(let comps) = entry["compList"], comps.count <= LayerComps.maximumComps + 1 else { throw CraftError.unsupported("Fractional PSD comp offsets are not qualified.") }
        for value in comps {
          let id = try integer(value); guard seen.insert(id).inserted else { throw CraftError.invalid("Duplicate per-layer comp ID.") }
          let index = indices[uuid(id)]
          guard id == 0 || index != nil else { continue } // Deleted source comps retain no active library entry.
          let options = index.map { library.comps[$0].options } ?? LayerCompOptions()
          var state = LayerCompLayerState(layer, options: options)
          if options.visibility { state.visible = enabled }
          if options.position { state.x = layer.x + Int(offset.x); state.y = layer.y + Int(offset.y) }
          if let index { library.comps[index].layers.append(state) }
          else { last.append(state); sawLast = true }
        }
      }
    }
    if let value = root["lastAppliedComp"] {
      let id = try integer(value)
      if id != 0 && id != -1 {
        guard indices[uuid(id)] != nil else { throw CraftError.invalid("Unknown applied Layer Comp.") }; library.appliedID = uuid(id)
      }
    }
    if sawLast { library.lastDocumentState = last }
    try library.validate(); document.layerComps = library
  }
  struct Export {
    var resource: Data?
    var layerIDs: [UUID: Int32] = [:]
    var tags: [UUID: Data] = [:]
  }
  static func prepare(_ document: CraftDocument) throws -> Export {
    let old = try PSDImageResources.blocks(document.sourceMetadata?["psdResources"] ?? Data())
    let active = document.layerComps != nil || old.contains { $0.id == 1065 }
    guard active else {var result=Export();for layer in document.layers where layer.isBackground{result.layerIDs[layer.id]=0};return result}
    var output = Export(), usedLayers = Set<Int32>([0, -1])
    let retainedOpaque=document.layerComps==nil && !document.clearedSourceLayerComps
    for layer in document.layers {
      // Retained opaque cmls records reference their original LyrI. Renumbering
      // only the Background's lyid would make those preserved records invalid.
      if layer.isBackground && (!retainedOpaque || layer.sourceTags?["lyid"]?.count != 4){output.layerIDs[layer.id]=0;continue}
      if let raw = layer.sourceTags?["lyid"], raw.count == 4 {
        var r = PSDReader(data: raw); let id = Int32(try r.i32())
        guard (id==0 && layer.isBackground) || usedLayers.insert(id).inserted else { throw CraftError.invalid("Conflicting Photoshop layer IDs.") }; output.layerIDs[layer.id] = id
      }
    }
    var next: Int32 = 1
    for layer in document.layers where output.layerIDs[layer.id] == nil {
      while usedLayers.contains(next) { next += 1 }; output.layerIDs[layer.id] = next; usedLayers.insert(next)
    }
    // Older native documents retained PSD comp resources before typed import existed.
    // A nil library alone is not evidence that the user deleted those saved comps.
    if document.layerComps == nil, !document.clearedSourceLayerComps {
      let compBlocks = old.filter { $0.id == 1065 }
      guard compBlocks.count <= 1 else { throw CraftError.invalid("Duplicate retained Layer Comp resources.") }
      output.resource = compBlocks.first?.raw
      for layer in document.layers { output.tags[layer.id] = layer.sourceTags?["shmd"] }
      return output
    }
    let library = document.layerComps, ids = try identifiers(library?.comps.map(\.id) ?? [])
    if let library {
      guard library.comps.allSatisfy({ !$0.options.recordsSmartObjects && $0.missingLayers(in: document).isEmpty }) else { throw CraftError.unsupported("Review missing layers or save parent Smart Object comp records as Photato. Their PSD mapping remains open.") }
      let list = library.comps.map { comp in
        PSDValue.object(PSDDescriptor("Comp", items: [.init("Nm  ", .text(Array(comp.name.utf16))), .init("comment", .text(Array(comp.comment.utf16))),
          .init("compID", .integer(ids[comp.id]!)), .init("capturedInfo", .integer((comp.options.visibility ? 1 : 0) | (comp.options.position ? 2 : 0) | (comp.options.appearance ? 4 : 0)))]))
      }
      var root = PSDDescriptor("CompList", items: [.init("list", .list(list))])
      if let applied = library.appliedID { root.items.append(.init("lastAppliedComp", .integer(ids[applied]!))) }
      output.resource = PSDImageResources.block(1065, data: try root.encoded())
    }
    for layer in document.layers {
      let original = try descriptor(layer)
      var originalEffects: [Int32: PSDValue] = [:], effectPoint: PSDValue?
      if case .list(let settings) = original?["layerSettings"] {
        for value in settings {
          guard case .object(let entry) = value else { continue }
          if let point = entry["FXRefPoint"] { effectPoint = point }
          if case .list(let ids) = entry["compList"], let effectPoint {
            for value in ids { originalEffects[try integer(value)] = effectPoint }
          }
        }
      }
      var records: [PSDValue] = []
      func record(_ state: LayerCompLayerState, id: Int32) throws -> PSDValue {
        guard state.smartObjectSelection == nil else { throw CraftError.unsupported("PSD prior Smart Object comp choices require further mapping. Save as Photato.") }
        let current = LayerCompLayerState(layer, options: .init())
        guard state.appearance == nil || state.appearance == current.appearance else { throw CraftError.unsupported("Changing comp appearance requires Photato until PSD appearance records are mapped.") }
        var d = PSDDescriptor("null", items: [.init("compList", .list([.integer(id)]))])
        if let visible = state.visible { d.items.append(.init("enab", .boolean(visible))) }
        if let x = state.x, let y = state.y, let t = state.translation {
          let dx = Double(x - layer.x) + t.x - (layer.affine?.tx ?? 0), dy = Double(y - layer.y) + t.y - (layer.affine?.ty ?? 0)
          guard dx.rounded() == dx, dy.rounded() == dy, abs(dx) <= 1_000_000, abs(dy) <= 1_000_000 else { throw CraftError.unsupported("Fractional comp translations require Photato until PSD mapping is qualified.") }
          d.items.append(.init("Ofst", .object(PSDDescriptor("null", items: [.init("Hrzn", .integer(Int32(dx))), .init("Vrtc", .integer(Int32(dy)))]))))
        }
        if let point = originalEffects[id] { d.items.append(.init("FXRefPoint", point)) }
        return .object(d)
      }
      for comp in library?.comps ?? [] {
        if let state = comp.layers.first(where: { $0.layerID == layer.id }) { records.append(try record(state, id: ids[comp.id]!)) }
      }
      if let state = library?.lastDocumentState?.first(where: { $0.layerID == layer.id }) { records.append(try record(state, id: 0)) }
      var entries = try metadata(layer.sourceTags?["shmd"]).filter { $0.key != "cmls" }
      if library != nil {
        var d = PSDDescriptor("null", items: [.init("LyrI", .integer(output.layerIDs[layer.id]!)), .init("layerSettings", .list(records))])
        if let point = original?["origFXRefPoint"] { d.items.append(.init("origFXRefPoint", point)) }
        entries.append(.init(signature: Data("8BIM".utf8), key: "cmls", flags: Data(repeating: 0, count: 4), data: try d.encoded()))
      }
      if !entries.isEmpty { var w = PSDWriter(); w.n(entries.count, 4); for entry in entries { w.data.append(entry.encoded) }; output.tags[layer.id] = w.data }
    }
    return output
  }
}
