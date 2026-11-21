import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum GenerativeFillVariations {
  static let key = PSDCodec.fillVariationTag

  struct Entry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let seed: UInt32
  }

  struct Metadata: Codable, Equatable, Sendable {
    let version: Int
    let prompt: String
    let model: String
    let sourceSHA256: String
    let entries: [Entry]
  }

  static func prepare(
    _ document: CraftDocument, model: URL, bookmark: Data? = nil, prompt raw: String, seed: UInt32, count: Int
  ) throws -> Command {
    let prompt = try LocalGenerativeFill.validatePrompt(raw)
    guard (1...LocalGenerativeFill.maximumVariations).contains(count), !prompt.isEmpty || count == 1 else {
      throw CraftError.invalid("Multiple variations require a text prompt.")
    }
    if prompt.isEmpty { return try LocalGenerativeFill.prepare(document, model: model) }
    let seeds = (0..<count).map { seed &+ UInt32($0) }
    let layers = try LocalGenerativeFill.prepareVariations(document) { image, mask in
      try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt, seeds: seeds, image: image, mask: mask)
    }
    if layers.count == 1 { return .generativeFill(layers[0]) }
    return .generativeFill(try pack(layers, in: document, prompt: prompt, seeds: seeds))
  }

  static func pack(_ layers: [Layer], in document: CraftDocument, prompt: String, seeds: [UInt32]) throws -> Layer {
    guard (2...LocalGenerativeFill.maximumVariations).contains(layers.count), seeds.count == layers.count,
      Set(seeds).count == seeds.count, var first = layers.first,
      let mask = first.mask, case .raster(let image) = first.content else {
      throw CraftError.invalid("The local fill variation set is incomplete.")
    }
    var source = try CraftDocument(width: image.width, height: image.height, depth: document.depth, name: "Fill Variations")
    source.colorSpace = document.colorSpace
    source.workingICC = document.workingICC
    source.profileIsUntagged = document.profileIsUntagged
    source.resolution = document.resolution
    source.layers = try layers.enumerated().map { index, layer in
      guard layer.mask == mask, layer.x == first.x, layer.y == first.y,
        case .raster(let patch) = layer.content, patch.width == image.width, patch.height == image.height else {
        throw CraftError.invalid("Local fill variations must share the same selection and placement.")
      }
      return Layer(name: "Variation \(index + 1)", content: .raster(patch))
    }
    var comps = LayerComps()
    for index in source.layers.indices {
      try Task.checkCancellation()
      for i in source.layers.indices { source.layers[i].visible = i == index }
      comps.comps.append(LayerComp(name: source.layers[index].name,
        options: .init(visibility: true, position: false, appearance: false), document: source))
    }
    for i in source.layers.indices { source.layers[i].visible = i == 0 }
    source.activeLayerID = source.layers[0].id
    comps.appliedID = comps.comps[0].id
    source.layerComps = comps
    let bytes = try PSDCodec.writeRasterLayers(source, maximumBytes: SmartObject.maximumDocumentSourceBytes)
    let decoded = try PSDCodec.read(bytes)
    var (object, initial) = try SmartObjectIO.embedded(
      document: decoded, in: document, originalData: bytes, fileName: "Fill Variations.psd")
    guard let choices = object.layerComps, choices.entries.count == layers.count else {
      throw CraftError.invalid("Could not preserve the variations in the embedded Photoshop document.")
    }
    object.layerComps?.selectedID = choices.entries[0].id
    let record = Metadata(version: 1, prompt: prompt, model: LocalGenerativeFill.promptModelIdentifier,
      sourceSHA256: object.dataFingerprint, entries: zip(choices.entries, seeds).map { Entry(id: $0.0.id, seed: $0.1) })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let metadata = try encoder.encode(record)
    guard metadata.count <= PSDCodec.fillVariationTagLimit else { throw CraftError.invalid("The variation record is too large.") }
    first.smartObject = object
    first.content = .raster(initial)
    first.sourceTags = (first.sourceTags ?? [:]).merging([key: metadata]) { _, new in new }
    return first
  }

  static func read(_ layer: Layer) -> Metadata? {
    guard let data = layer.sourceTags?[key], data.count <= PSDCodec.fillVariationTagLimit,
      let object = layer.smartObject, object.linkedSource == nil, object.stackMode == nil,
      object.mediaType == "image/vnd.adobe.photoshop",
      let record = try? JSONDecoder().decode(Metadata.self, from: data),
      record.version == 1, record.model == LocalGenerativeFill.promptModelIdentifier,
      record.sourceSHA256 == object.dataFingerprint,
      (2...LocalGenerativeFill.maximumVariations).contains(record.entries.count),
      !record.prompt.isEmpty, (try? LocalGenerativeFill.validatePrompt(record.prompt)) == record.prompt,
      record.entries.map(\.id) == object.layerComps?.entries.map(\.id),
      Set(record.entries.map(\.seed)).count == record.entries.count else { return nil }
    return record
  }
}

struct GenerativeFillVariationControls: View {
  @Bindable var store: EditorStore
  let layer: Layer
  let metadata: GenerativeFillVariations.Metadata

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(metadata.prompt)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Picker("Variation", selection: Binding(get: {
        layer.smartObject?.layerComps?.selectedID ?? metadata.entries.first?.id
      }, set: { store.chooseSmartObjectComp($0) })) {
        ForEach(Array(metadata.entries.enumerated()), id: \.element.id) { index, entry in
          Text("\(index + 1)").tag(Optional(entry.id))
            .accessibilityLabel("Variation \(index + 1)")
            .help("Seed \(entry.seed)")
        }
      }
      .pickerStyle(.segmented)
      .disabled(!store.canChooseSmartObjectComp)
      .accessibilityIdentifier("generativeFill.variations")
    }
  }
}
