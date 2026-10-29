import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class BrushLibrary {
  static let shared = BrushLibrary(persistenceURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Photato/Brushes.photatobrushes"))
  private(set) var file = BrushPresetFile(presets: BrushPresets.builtins())
  private(set) var revision = 0
  private(set) var loadError: String?
  @ObservationIgnored let persistenceURL: URL?
  init(persistenceURL: URL? = nil) {
    self.persistenceURL = persistenceURL
    if let url=persistenceURL, FileManager.default.fileExists(atPath:url.path) {
      do { file = try .decode(Self.read(url)) }
      catch { loadError = "Saved brushes could not be read; the file is preserved. \(error.localizedDescription)" }
    }
  }
  static func read(_ url:URL) throws -> Data {
    guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=BrushPresetFile.maximumBytes else { throw CraftError.invalid("Brush file exceeds 64 MiB.") }
    return try Data(contentsOf:url)
  }
  func update(_ edit:(inout BrushPresetFile)throws->Void) throws {
    guard loadError == nil else { throw CraftError.invalid(loadError!) }
    var next=file;try edit(&next);let data=try next.encoded()
    if let url=persistenceURL { try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url,options:.atomic) }
    file=next;revision += 1
  }
  func preset(_ id:UUID)throws->BrushPreset {
    guard let preset=file.presets.first(where:{$0.id==id}) else { throw CraftError.invalid("Brush preset no longer exists.") };return preset
  }
  func save(_ preset:BrushPreset)throws {
    try update { if let i=$0.presets.firstIndex(where:{$0.id==preset.id}) { $0.presets[i]=preset } else { $0.presets.append(preset) } }
  }
  func remove(_ id:UUID)throws { _ = try preset(id);try update{$0.presets.removeAll{$0.id==id}} }
  func move(_ id:UUID,to index:Int)throws {
    _ = try preset(id);guard file.presets.indices.contains(index) else { throw CraftError.invalid("Invalid brush destination.") }
    try update { file in let i=file.presets.firstIndex{$0.id==id}!;file.presets.insert(file.presets.remove(at:i),at:index) }
  }
  @discardableResult func importData(_ data:Data,abr:Bool)throws->[String] {
    let presets:[BrushPreset],warnings:[String]
    if abr { let result=try ABRCodec.read(data);presets=result.presets;warnings=result.warnings }
    else { presets=try BrushPresetFile.decode(data).presets;warnings=[] }
    try update { file in for var preset in presets { preset.id=UUID();file.presets.append(preset) } };return warnings
  }
  func exportData(_ id:UUID?=nil,abr:Bool=false)throws->Data {
    let presets=try id.map{[try preset($0)]} ?? file.presets
    return try abr ? ABRCodec.write(presets):BrushPresetFile(presets:presets).encoded()
  }
}

@MainActor extension EditorStore {
  var brushOptions:BrushSettings {
    get { brush.settings ?? .init() }
    set { brush.settings=newValue }
  }
  var canUseBrush:Bool { !geometryBusy && !hasToneDraft && transformDraft == nil && (isCompositeColorTarget || (!modeComponentTargets.isEmpty && canEditModeComponents && [.brush, .eraser].contains(tool))) && (activeLayer != nil || document.inkMode != nil) && (document.colorMode != .multichannel || [.brush, .eraser].contains(tool)) }
  func selectBrush(_ id:UUID)throws {
    guard canUseBrush else { throw CraftError.invalid("Finish the current edit before choosing a brush.") }
    brush=try brushes.preset(id).applying(to:brush);selectedBrushID=id
  }
  @discardableResult func saveBrush(name:String,group:String,includeSize:Bool=true,includeToolSettings:Bool=true,includeColor:Bool=false)throws->BrushPreset {
    guard canUseBrush else { throw CraftError.invalid("Finish the current edit before saving a brush.") }
    var preset=BrushPreset(name:name,group:group,brush:brush);preset.brush.backgroundColor=backgroundColor;preset.includeSize=includeSize;preset.includeToolSettings=includeToolSettings;preset.includeColor=includeColor
    try brushes.save(preset);selectedBrushID=preset.id;return preset
  }
  @discardableResult func defineBrush(name:String,group:String="My Brushes",validateCommit:@MainActor ()throws->Void = {})async throws->BrushPreset {
    guard canUseBrush else { throw CraftError.invalid("Finish the current edit before defining a brush.") }
    let original=document,generation=layerPanelGeneration
    let bounds=original.selection ?? IntRect(x:0,y:0,width:original.width,height:original.height)
    guard bounds.width<=2500,bounds.height<=2500 else { throw CraftError.invalid("Select an area no larger than 2500 × 2500 pixels.") }
    geometryBusy=true;defer { if layerPanelGeneration==generation {geometryBusy=false;geometryTask=nil} };status="Define Brush Preset"
    let worker=Task.detached { try BrushPresets.define(from:Renderer.composite(original),bounds:bounds,selection:original.selectionMask) }
    geometryTask=Task { await withTaskCancellationHandler(operation:{_ = try? await worker.value},onCancel:{worker.cancel()}) }
    let tip=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    try Task.checkCancellation();if geometryTask?.isCancelled == true { throw CancellationError() }
    guard document==original,layerPanelGeneration==generation else { throw CraftError.invalid("Document changed while defining the brush.") }
    try validateCommit()
    var value=Brush();value.color=brush.color;value.size=Double(min(2048,max(tip.width,tip.height)));value.hardness=1;value.settings = .init();value.settings!.tip=tip
    var preset=BrushPreset(name:name,group:group,brush:value);preset.includeToolSettings=false
    try brushes.save(preset);brush=preset.applying(to:brush);selectedBrushID=preset.id;return preset
  }
}
