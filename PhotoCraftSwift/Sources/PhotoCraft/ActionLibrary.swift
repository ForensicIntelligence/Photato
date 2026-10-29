import Foundation
import Observation
import PhotoCraftCore

struct ActionLibraryFile: Codable {
  var version = 1
  var actions: [RecordedAction] = []
  static let maximumBytes = 16 * 1024 * 1024
  var requiredVersion:Int {
    if actions.contains(where: { $0.steps.contains { if case .inkMode = $0.operation { return true }; return false } }) { return 20 }
    if actions.contains(where: { $0.steps.contains { switch $0.operation { case .documentMode, .restrictedMode, .clipboardCopy, .clipboardCut, .clipboardPaste: true; default: false } } }) { return 19 }
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .toneAdjustment:return true;case .filter(_,let f):return f.kind == .shadowsHighlights;case .filters(_,let s):return s?.filters.contains{$0.filter.kind == .shadowsHighlights} == true;default:return false}}}){return 18}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind.isClassicDetail;case .filters(_,let s):return s?.filters.contains{$0.filter.kind.isClassicDetail} == true;default:return false}}}){return 17}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind.isOtherVideo;case .filters(_,let s):return s?.filters.contains{$0.filter.kind.isOtherVideo} == true;default:return false}}}){return 16}
    if actions.contains(where:{$0.steps.contains{if case .proceduralRender=$0.operation{return true};return false}}){return 15}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind.isRender;case .filters(_,let s):return s?.filters.contains{$0.filter.kind.isRender} == true;default:return false}}}){return 14}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind.isStylize;case .filters(_,let s):return s?.filters.contains{$0.filter.kind.isStylize} == true;default:return false}}}){return 13}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind.isPixelate;case .filters(_,let s):return s?.filters.contains{$0.filter.kind.isPixelate} == true;default:return false}}}){return 12}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind.isDistortion;case .filters(_,let s):return s?.filters.contains{$0.filter.kind.isDistortion} == true;default:return false}}}){return 11}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind == .lensBlur;case .filters(_,let s):return s?.filters.contains{$0.filter.kind == .lensBlur} == true;default:return false}}}){return 10}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind == .smartSharpen || f.kind == .reduceNoise;case .filters(_,let s):return s?.filters.contains{$0.filter.kind == .smartSharpen || $0.filter.kind == .reduceNoise} == true;default:return false}}}){return 9}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .filter(_,let f):return f.kind == .filterGallery;case .filters(_,let s):return s?.filters.contains{$0.filter.kind == .filterGallery} == true;default:return false}}}){return 8}
    if actions.contains(where:{$0.steps.contains{if case .addContent(_,let content)=$0.operation,case .text(let text)=content{return text.typography?.requiresShapedText==true};return false}}){return 7}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .addContent(_,let content):if case .text(let text)=content{return text.typography?.requiresAdvancedTypography==true};return false;default:return false}}}){return 6}
    if actions.contains(where:{$0.steps.contains{switch $0.operation{case .createShape,.setShape,.appendShape:return true;default:return false}}}){return 5}
    if actions.contains(where:{$0.steps.contains{if case .selectionCoverage=$0.operation{return true};return false}}){return 4}
    if actions.contains(where:{a in a.steps.contains{step in switch step.operation {case .adjustmentBrush,.replaceAdjustment:return true;default:return false}}}) {return 3}
    return actions.contains { action in action.steps.contains { step in
      if case .stroke(_,let points,let brush,_) = step.operation { return brush.settings != nil || points.contains{$0.tiltX != nil || $0.tiltY != nil || $0.rotation != nil || $0.wheel != nil || $0.time != nil} };return false
    } } ? 2:1
  }
  func encoded() throws -> Data {
    guard (1...20).contains(version), actions.count <= 128, Set(actions.map(\.id)).count == actions.count else {
      throw CraftError.invalid("Invalid action library (versions 1–20, maximum 128 actions).")
    }
    for action in actions { try action.validate() }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    var value=self;value.version=max(version,requiredVersion)
    let data = try encoder.encode(value)
    guard data.count <= Self.maximumBytes else { throw CraftError.invalid("Action library exceeds 16 MiB.") }
    return data
  }
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumBytes else { throw CraftError.invalid("Action library exceeds 16 MiB.") }
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version>=value.requiredVersion else { throw CraftError.invalid("Action library version is older than its recorded operations require.") }
    _ = try value.encoded()
    return value
  }
}

@MainActor @Observable final class ActionLibrary {
  static let shared = ActionLibrary(persistenceURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Photato/Actions.photatoactions"))
  private(set) var file = ActionLibraryFile()
  private(set) var revision = 0
  private(set) var loadError: String?
  @ObservationIgnored let persistenceURL: URL?
  init(persistenceURL: URL? = nil) {
    self.persistenceURL = persistenceURL
    if let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) {
      do { file = try .decode(Self.read(url)) }
      catch { loadError = "Saved actions could not be read; the file is preserved. \(error.localizedDescription)" }
    }
  }
  static func read(_ url: URL) throws -> Data {
    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= ActionLibraryFile.maximumBytes else { throw CraftError.invalid("Action file exceeds 16 MiB.") }
    return try Data(contentsOf: url)
  }
  func update(_ edit: (inout ActionLibraryFile) throws -> Void) throws {
    guard loadError == nil else { throw CraftError.invalid(loadError!) }
    var next = file; try edit(&next); let data = try next.encoded()
    if let url = persistenceURL {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    }
    file = try .decode(data); revision += 1
  }
  func save(_ action: RecordedAction) throws {
    try update { file in
      if let i = file.actions.firstIndex(where: { $0.id == action.id }) { file.actions[i] = action }
      else { file.actions.append(action) }
    }
  }
  func action(_ id: UUID) throws -> RecordedAction {
    guard let action = file.actions.first(where: { $0.id == id }) else { throw CraftError.invalid("Action no longer exists.") }; return action
  }
  func remove(_ id: UUID) throws { _ = try action(id); try update { $0.actions.removeAll { $0.id == id } } }
  func importFile(_ data: Data) throws {
    let imported = try ActionLibraryFile.decode(data)
    try update { file in
      // Import makes independent copies, never overwrites an existing user's action.
      for var action in imported.actions { action.id = UUID(); file.actions.append(action) }
    }
  }
  func exportFile(_ id: UUID? = nil) throws -> Data {
    try ActionLibraryFile(version:file.version,actions: id.map { [try action($0)] } ?? file.actions).encoded()
  }
}

@MainActor extension EditorStore {
  var canUseActions: Bool { !geometryBusy && !hasToneDraft && transformDraft == nil && !coalescingChanges && numericEditor == nil && layerNameDraft == nil && clipboardTargetAvailable }
  func startRecordingAction(name: String, set: String) throws {
    guard canUseActions else { throw CraftError.invalid("Finish the current edit and choose the composite image before recording.") }
    guard actions.loadError == nil else { throw CraftError.invalid(actions.loadError!) }
    try session.startActionRecording(name: name, set: set); actionRevision += 1
  }
  @discardableResult func stopRecordingAction(save: Bool = true) throws -> RecordedAction {
    guard canUseActions, let action = session.actionRecording?.snapshot else { throw CraftError.invalid("There is no finished recording to stop.") }
    if save { try actions.save(action) }
    session.stopActionRecording(); actionRevision += 1; return action
  }
  func playAction(_ action: RecordedAction) {
    guard canUseActions, session.actionRecording == nil else { error = "Stop recording and finish the current edit before playback."; return }
    playPreparedAction(action)
  }
  var actionState: [String: Any] {
    ["format": "photatoactions", "version": actions.file.version, "supportedVersions": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20], "libraryRevision": actions.revision,
     "playback": ["semanticColorModes": true, "semanticClipboard": true, "resultSchema": ActionPlaybackAPI.resultSchema, "masterSources": "Desktop uses eligible open documents; API uses explicit shared sources; Batch uses its source snapshots.", "clipboard": "Desktop reads an initial image only when required and publishes Copy/Cut after successful playback. API and Batch use a private clipboard; API returns copied data up to2MiB. Action files contain commands, not clipboard images.", "previousPalette": "Explicit palette saved with the conversion settings.", "adobeATN": false],
     "canRecord": canUseActions && session.actionRecording == nil && actions.loadError == nil,
     "canPlay": canUseActions && session.actionRecording == nil,
     "recording": session.actionRecording.map { Self.actionInfo($0.snapshot) } as Any? ?? NSNull(),
     "library": actions.file.actions.map(Self.actionInfo),
     "loadError": actions.loadError as Any? ?? NSNull()]
  }
  static func actionInfo(_ action: RecordedAction) -> [String: Any] {
    ["id": action.id.uuidString, "name": action.name, "set": action.set,
     "steps": action.steps.map { ["id": $0.id.uuidString, "name": $0.name, "enabled": $0.enabled, "unsupportedReason": $0.operation.unsupportedReason as Any? ?? NSNull()] }]
  }
}
