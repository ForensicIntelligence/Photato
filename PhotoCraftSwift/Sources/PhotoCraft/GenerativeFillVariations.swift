import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum GenerativeFillVariations {
  static let key = PSDCodec.fillVariationTag
  static let maximumStoredVariations = 64

  struct Entry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let seed: UInt32
    let prompt: String?
    let referenceVariationID: UUID?
  }

  struct Metadata: Codable, Equatable, Sendable {
    let version: Int
    let prompt: String
    let model: String
    let sourceSHA256: String
    let entries: [Entry]
    let lastDocumentStateID: UUID?
    var guideUse: LocalGenerationGuide.Kind? = nil

    var isBackground: Bool { version == PSDCodec.fillBackgroundVariationVersion }
    var isGeneratedImage: Bool { version == PSDCodec.generatedImageVariationVersion }
    var isPromptEdit: Bool { version == PSDCodec.promptEditVariationVersion }
    var hasSavedContext: Bool { version == 2 || version == 3 || isBackground || isGeneratedImage || isPromptEdit }

    func selectedID(_ explicit: UUID?) -> UUID? {
      explicit ?? lastDocumentStateID ?? entries.first?.id
    }

    func prompt(for id: UUID?) -> String {
      let selected = selectedID(id)
      return entries.first(where: { $0.id == selected })?.prompt ?? prompt
    }
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
    let (recipe, coverage) = try LocalGenerativeFill.capture(document)
    let patches = try recipe.patches(in: document) { image, mask in
      try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt, seeds: seeds, image: image, mask: mask)
    }
    let layers = patches.map { pixels in
      var layer = Layer(name: "Generative Fill", content: .raster(pixels))
      layer.x = recipe.selection.x; layer.y = recipe.selection.y; layer.mask = coverage
      return layer
    }
    return .generativeFill(try pack(layers, in: document, prompt: prompt, seeds: seeds, context: recipe.encoded()))
  }

  static func pack(_ layers: [Layer], in document: CraftDocument, prompt: String, seeds: [UInt32], context: Data? = nil,
    savedSource: [Layer] = [], forBackground: Bool = false) throws -> Layer {
    guard ((context == nil ? 2 : 1)...LocalGenerativeFill.maximumVariations).contains(layers.count), seeds.count == layers.count,
      Set(seeds).count == seeds.count, let first = layers.first,
      forBackground ? (context != nil && savedSource.isEmpty && first.mask == nil) : first.mask != nil,
      case .raster(let image) = first.content else {
      throw CraftError.invalid("The local fill variation set is incomplete.")
    }
    var source = try CraftDocument(width: image.width, height: image.height, depth: document.depth,
      name: forBackground ? "Background Variations" : "Fill Variations")
    source.colorSpace = document.colorSpace
    source.workingICC = document.workingICC
    source.profileIsUntagged = document.profileIsUntagged
    source.resolution = document.resolution
    source.layers = try layers.enumerated().map { index, layer in
      guard layer.mask == first.mask, layer.x == first.x, layer.y == first.y,
        case .raster(let patch) = layer.content, patch.width == image.width, patch.height == image.height else {
        throw CraftError.invalid("Local fill variations must share the same selection and placement.")
      }
      return Layer(name: "Variation \(index + 1)", content: .raster(patch))
    }
    if let context { source.layers[0].sourceTags = [PSDCodec.fillContextTag: context] }
    source.layers += savedSource
    let entries = seeds.map { Entry(id: UUID(), seed: $0, prompt: nil, referenceVariationID: nil) }
    let version = forBackground ? PSDCodec.fillBackgroundVariationVersion : savedSource.isEmpty ? (context == nil ? 1 : 2) : 3
    return try packaged(source, in: document, previous: first, entries: entries,
      prompt: prompt, version: version, selected: 0)
  }

  private static func packaged(
    _ inner: CraftDocument, in document: CraftDocument, previous: Layer, entries: [Entry], prompt: String, version: Int, selected: Int,
    guideUse: LocalGenerationGuide.Kind? = nil
  ) throws -> Layer {
    var source = inner
    var comps = LayerComps()
    for index in entries.indices {
      try Task.checkCancellation()
      for i in source.layers.indices { source.layers[i].visible = i == index }
      comps.comps.append(LayerComp(id: entries[index].id, name: source.layers[index].name,
        options: .init(visibility: true, position: false, appearance: false), document: source))
    }
    for i in source.layers.indices { source.layers[i].visible = i == selected }
    source.activeLayerID = source.layers[selected].id
    comps.appliedID = comps.comps[selected].id
    source.layerComps = comps
    let bytes: EmbeddedSourceBytes
    let fileName: String
    if version == 3 {
      bytes = .file(try PSDCodec.writeFileBackedEmbeddedSmartObject(source))
      fileName = "Fill Variations.psb"
    } else {
      bytes = .memory(try PSDCodec.writeRasterLayers(source, maximumBytes: SmartObject.maximumDocumentSourceBytes))
      switch version {
      case PSDCodec.fillBackgroundVariationVersion: fileName = "Background Variations.psd"
      case PSDCodec.generatedImageVariationVersion: fileName = "Image Variations.psd"
      case PSDCodec.promptEditVariationVersion: fileName = "Prompt Edit Variations.psd"
      default: fileName = "Fill Variations.psd"
      }
    }
    let decoded = try SmartObjectIO.decode(bytes, fileName: fileName)
    var (object, initial) = try SmartObjectIO.embedded(
      document: decoded, in: document, original: bytes, fileName: fileName)
    guard let choices = object.layerComps, choices.entries.count == entries.count else {
      throw CraftError.invalid("Could not preserve the variations in the embedded Photoshop document.")
    }
    object.layerComps?.selectedID = choices.entries[selected].id
    let model = version == PSDCodec.promptEditVariationVersion ? LocalGenerativeFill.instructionModelIdentifier
      : LocalGenerativeFill.promptModelIdentifier
    let record = Metadata(version: version, prompt: prompt, model: model,
      sourceSHA256: object.dataFingerprint,
      entries: zip(choices.entries, entries).map { choice, entry in
        Entry(id: choice.id, seed: entry.seed, prompt: entry.prompt, referenceVariationID: entry.referenceVariationID)
      },
      lastDocumentStateID: version == 1 ? nil : choices.entries[selected].id, guideUse: guideUse)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let metadata = try encoder.encode(record)
    guard metadata.count <= PSDCodec.fillVariationTagLimit else { throw CraftError.invalid("The variation record is too large.") }
    var layer = previous
    layer.smartObject = object
    layer.content = .raster(initial)
    layer.sourceTags = (layer.sourceTags ?? [:]).merging([key: metadata]) { _, new in new }
    for tag in ["SoLd", "SoLE", "PlLd"] { layer.sourceTags?.removeValue(forKey: tag) }
    return layer
  }

  static func packModelImages(_ choices: [Layer], in document: CraftDocument, prompt: String,
    seeds: [UInt32], instructionContext: Data? = nil, guide: LocalGenerationGuide? = nil) throws -> Layer {
    guard let first = choices.first, case .raster(let pixels) = first.content else {
      throw CraftError.invalid("The generated image has no variations.")
    }
    var source = try CraftDocument(width: pixels.width, height: pixels.height, depth: document.depth,
      name: instructionContext == nil ? "Image Variations" : "Prompt Edit Variations")
    source.colorSpace = document.colorSpace
    source.workingICC = document.workingICC
    source.profileIsUntagged = document.profileIsUntagged
    source.resolution = document.resolution
    source.layers = choices.enumerated().map { index, choice in
      Layer(name: "Variation \(index + 1)", content: choice.content)
    }
    if let instructionContext { source.layers[0].sourceTags = [PSDCodec.fillContextTag: instructionContext] }
    if let guide {
      guard instructionContext == nil else { throw CraftError.invalid("A separate image reference requires Generate Image.") }
      try guide.validate()
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      source.layers[0].sourceTags = [PSDCodec.fillContextTag: try encoder.encode(guide)]
    }
    let entries = seeds.map { Entry(id: UUID(), seed: $0, prompt: nil, referenceVariationID: nil) }
    return try packaged(source, in: document, previous: first, entries: entries,
      prompt: prompt, version: instructionContext == nil ? PSDCodec.generatedImageVariationVersion : PSDCodec.promptEditVariationVersion,
      selected: 0, guideUse: guide?.kind)
  }

  static func canAppend(_ layer: Layer, in document: CraftDocument) -> Bool {
    guard document.colorMode == .rgb, document.inkMode == nil, document.restrictedMode == nil,
      !document.isChannelOnly, !document.isImageLocked(layer.id),
      let record = read(layer), record.hasSavedContext, record.entries.count < maximumStoredVariations else { return false }
    return true
  }

  static func append(
    to id: UUID, in document: CraftDocument, model: URL, bookmark: Data?, prompt: String?, seed: UInt32?, count: Int,
    referenceVariationID: UUID? = nil, guideBookmark: Data? = nil
  ) throws -> Command {
    let layer = document.layers.first { $0.id == id }
    let record = layer.flatMap(read)
    let instructions = record?.isPromptEdit == true
    let guide: LocalGenerationGuide? = try record?.guideUse.map { use in
      guard let object = layer?.smartObject else { throw CraftError.invalid("The saved reference layer is unavailable.") }
      return try LocalGeneratedImage.savedGuide(from: SmartObjectIO.sourceDocument(object), use: use)
    }
    return try GenerativeFillWorker.withSession(model: model, bookmark: bookmark, instructions: instructions,
      guide: guide, guideBookmark: guide == nil ? nil : guideBookmark) { worker in
      try append(to: id, in: document, prompt: prompt, seed: seed, count: count,
        referenceVariationID: referenceVariationID) { prompt, seeds, image, mask in
        try worker.predict(prompt: prompt, seeds: seeds, image: image, mask: mask,
          mode: referenceVariationID == nil ? .fill : .similar)
      }
    }
  }

  static func append(
    to id: UUID, in parent: CraftDocument, prompt override: String?, seed: UInt32?, count: Int,
    referenceVariationID: UUID? = nil,
    predict: (String, [UInt32], [Float], [Float]) throws -> [Surface]
  ) throws -> Command {
    try Task.checkCancellation()
    guard let position = parent.layers.firstIndex(where: { $0.id == id }),
      canAppend(parent.layers[position], in: parent), (1...LocalGenerativeFill.maximumVariations).contains(count) else {
      throw CraftError.invalid("Select an unlocked generative layer with saved context and room for more variations.")
    }
    let layer = parent.layers[position]
    guard let record = read(layer), let object = layer.smartObject,
      record.entries.count + count <= maximumStoredVariations else {
      throw CraftError.invalid("The Generative Fill layer is at its variation limit.")
    }
    if let referenceVariationID, !record.entries.contains(where: { $0.id == referenceVariationID }) {
      throw CraftError.invalid("Choose an existing variation from this Generative Fill layer.")
    }
    var source = try SmartObjectIO.sourceDocument(object)
    let stored = source.layers.first?.sourceTags?[PSDCodec.fillContextTag]
    guard let comps = source.layerComps, comps.comps.map(\.id) == record.entries.map(\.id),
      (record.isGeneratedImage && record.guideUse == nil) || stored != nil else {
      throw CraftError.invalid("The original Generative Fill context is unavailable.")
    }
    let prompt = try LocalGenerativeFill.validatePrompt(override ?? record.prompt(for: referenceVariationID ?? object.layerComps?.selectedID))
    guard !prompt.isEmpty else { throw CraftError.invalid("Enter a text prompt for the new variations.") }
    let used = Set(record.entries.map(\.seed))
    var firstSeed = seed ?? (record.entries[record.entries.count - 1].seed &+ 1)
    var seeds = (0..<count).map { firstSeed &+ UInt32($0) }
    while !used.isDisjoint(with: seeds) {
      guard seed == nil else { throw CraftError.invalid("Choose a starting seed that is new to this layer.") }
      firstSeed &+= 1
      seeds = (0..<count).map { firstSeed &+ UInt32($0) }
    }
    let patches: [Surface]
    if record.isGeneratedImage {
      guard source.layers.count == record.entries.count else {
        throw CraftError.invalid("The generated image variations are unavailable.")
      }
      let reference = try referenceVariationID.map { id in
        try SmartObjectLayerCompIO.pixels(source, compID: id, stackMode: nil, in: source)
      }
      patches = try LocalGeneratedImage.pixels(in: source, reference: reference, prompt: prompt, seeds: seeds, predict: predict)
    } else if record.isPromptEdit, let stored {
      guard source.layers.count == record.entries.count else {
        throw CraftError.invalid("The prompt edit variations are unavailable.")
      }
      let context = try LocalPromptEdit.Context.decode(stored, matching: source)
      let reference = try referenceVariationID.map { id in
        try SmartObjectLayerCompIO.pixels(source, compID: id, stackMode: nil, in: source)
      }
      patches = try context.pixels(in: source, reference: reference, prompt: prompt, seeds: seeds, predict: predict)
    } else if record.isBackground, let stored {
      guard source.layers.count == record.entries.count else {
        throw CraftError.invalid("The original Generative Background context is unavailable.")
      }
      let context = try LocalGeneratedBackground.Context.decode(stored, matching: source)
      let conditioning = try referenceVariationID.map { id in
        try SmartObjectLayerCompIO.pixels(source, compID: id, stackMode: nil, in: source)
      }
      patches = try context.patches(in: source, reference: conditioning) { image, mask in
        try predict(prompt, seeds, image, mask)
      }
    } else if record.version == 3, let stored {
      let reference = referenceVariationID.flatMap { id in record.entries.firstIndex { $0.id == id } }
      patches = try expandPatches(source: source, count: record.entries.count, stored: stored, reference: reference,
        prompt: prompt, seeds: seeds, predict: predict)
    } else if let stored {
      guard source.layers.count == record.entries.count else {
        throw CraftError.invalid("The original Generative Fill context is unavailable.")
      }
      let recipe = try LocalGenerativeFill.Recipe.decode(stored)
      guard recipe.selection.width == source.width, recipe.selection.height == source.height else {
        throw CraftError.invalid("The saved Generative Fill context no longer matches its layer.")
      }
      let conditioning = try referenceVariationID.map { id in
        try SmartObjectLayerCompIO.pixels(source, compID: id, stackMode: nil, in: source)
      }
      patches = try recipe.patches(in: source, conditioning: conditioning) { image, mask in
        try predict(prompt, seeds, image, mask)
      }
    } else {
      throw CraftError.invalid("The original generation context is unavailable.")
    }
    guard patches.count == count else { throw CraftError.invalid("Local inference returned an incomplete batch.") }
    let variationLayers = patches.enumerated().map { index, pixels in
      Layer(name: "Variation \(record.entries.count + index + 1)", content: .raster(pixels))
    }
    source.layers.insert(contentsOf: variationLayers, at: record.entries.count)
    let newEntries = seeds.map {
      Entry(id: UUID(), seed: $0, prompt: prompt == record.prompt ? nil : prompt, referenceVariationID: referenceVariationID)
    }
    let resultLayer = try packaged(source, in: parent, previous: layer, entries: record.entries + newEntries,
      prompt: record.prompt, version: record.version, selected: record.entries.count, guideUse: record.guideUse)
    guard read(resultLayer)?.entries.prefix(record.entries.count).map(\.id) == record.entries.map(\.id) else {
      throw CraftError.invalid("The saved identifiers for earlier variations changed.")
    }
    var result = parent
    result.layers[position] = resultLayer
    return .linkedSmartObject(try .init(source: parent, result: result,
      title: referenceVariationID == nil ? "Generate More Variations" : "Generate Similar"))
  }

  private static func expandPatches(
    source: CraftDocument, count: Int, stored: Data, reference: Int?, prompt: String, seeds: [UInt32],
    predict: (String, [UInt32], [Float], [Float]) throws -> [Surface]
  ) throws -> [Surface] {
    guard stored.count <= 4_096, source.layers.count > count else {
      throw CraftError.invalid("The original Generative Expand context is unavailable.")
    }
    let geometry = try PropertyListDecoder().decode(GenerativeExpandWindows.Geometry.self, from: stored)
    let windows = try geometry.windows(depth: source.depth)
    guard windows.border.width == source.width, windows.border.height == source.height else {
      throw CraftError.invalid("The saved Generative Expand context no longer matches its layer.")
    }
    let referencePixels = try reference.map { index in
      guard source.layers.indices.contains(index), case .raster(let pixels) = source.layers[index].content,
        source.layers[index].x == 0, source.layers[index].y == 0,
        pixels.width == source.width, pixels.height == source.height else {
        throw CraftError.invalid("The saved Generative Expand reference no longer matches its layer.")
      }
      return pixels
    }
    let sampler = try windows.sourceSampler(source.layers.dropFirst(count))
    return try windows.render(original: source, includeMask: false, reference: referencePixels,
      count: seeds.count, sourceSampler: sampler) { index, image, mask in
      let generated = try predict(prompt, [seeds[index]], image, mask)
      guard generated.count == 1, let pixels = generated.first else {
        throw CraftError.invalid("Local inference returned an incomplete Generative Expand window.")
      }
      return pixels
    }.map { layer in
      guard case .raster(let pixels) = layer.content else { throw CraftError.invalid("Invalid rendered expansion.") }
      return pixels
    }
  }

  static func read(_ layer: Layer) -> Metadata? {
    guard let data = layer.sourceTags?[key], data.count <= PSDCodec.fillVariationTagLimit,
      let object = layer.smartObject, object.linkedSource == nil, object.stackMode == nil,
      ["image/vnd.adobe.photoshop", "application/x-photoshop"].contains(object.mediaType),
      let record = try? JSONDecoder().decode(Metadata.self, from: data),
      (record.version == 1 || record.hasSavedContext),
      record.model == (record.isPromptEdit ? LocalGenerativeFill.instructionModelIdentifier : LocalGenerativeFill.promptModelIdentifier),
      record.sourceSHA256 == object.dataFingerprint, (record.guideUse == nil || record.isGeneratedImage),
      ((record.version == 1 ? 2 : 1)...(record.version == 1 ? LocalGenerativeFill.maximumVariations : maximumStoredVariations))
        .contains(record.entries.count),
      !record.prompt.isEmpty, (try? LocalGenerativeFill.validatePrompt(record.prompt)) == record.prompt,
      record.entries.map(\.id) == object.layerComps?.entries.map(\.id),
      record.lastDocumentStateID.map({ id in record.entries.contains { $0.id == id } }) ?? true,
      Set(record.entries.map(\.seed)).count == record.entries.count,
      record.entries.allSatisfy({ entry in
        guard let prompt = entry.prompt else { return true }
        return !prompt.isEmpty && (try? LocalGenerativeFill.validatePrompt(prompt)) == prompt
      }) else { return nil }
    var priorIDs = Set<UUID>()
    for entry in record.entries {
      if let reference = entry.referenceVariationID, !priorIDs.contains(reference) { return nil }
      priorIDs.insert(entry.id)
    }
    return record
  }
}

struct GenerativeFillVariationControls: View {
  @Bindable var store: EditorStore
  let layer: Layer
  let metadata: GenerativeFillVariations.Metadata

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(metadata.prompt(for: layer.smartObject?.layerComps?.selectedID))
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if let use = metadata.guideUse {
        Text("\(use.title) reference").font(.caption).foregroundStyle(.secondary)
      }
      Group {
        if metadata.entries.count <= LocalGenerativeFill.maximumVariations { picker.pickerStyle(.segmented) }
        else { picker.pickerStyle(.menu) }
      }
      .disabled(!store.canChooseSmartObjectComp)
      .accessibilityIdentifier("generativeFill.variations")
      if metadata.hasSavedContext {
        HStack {
          Button("Generate More…") { store.beginGenerativeFillBatch(layer.id) }
            .accessibilityIdentifier("generativeFill.generateMore")
          if let selected = metadata.selectedID(layer.smartObject?.layerComps?.selectedID) {
            Menu {
              Button(metadata.isPromptEdit ? "Edit This Variation…" : "Generate Similar…") {
                store.beginGenerativeFillBatch(layer.id, referenceVariationID: selected)
              }
                .accessibilityIdentifier("generativeFill.generateSimilar")
            } label: {
              Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Variation actions")
            .help("Actions for the selected variation")
          }
        }
        .disabled(!store.canBeginGenerativeFillBatch(layer.id))
      }
    }
  }

  private var picker: some View {
    Picker("Variation", selection: Binding(get: {
      metadata.selectedID(layer.smartObject?.layerComps?.selectedID)
    }, set: { store.chooseSmartObjectComp($0) })) {
      ForEach(Array(metadata.entries.enumerated()), id: \.element.id) { index, entry in
        Text("\(index + 1)").tag(Optional(entry.id))
          .accessibilityLabel("Variation \(index + 1)")
          .help("Seed \(entry.seed)")
      }
    }
  }
}
