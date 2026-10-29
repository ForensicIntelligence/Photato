import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class ProofWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  var settings: ProofSettings
  var preview = true
  var error: String?
  let workingSettings: ColorSettings
  init(_ store: EditorStore) throws {
    source = store.document; workingSettings = store.workingColorSettings
    settings = try workingSettings.resolvingProof(store.proofSettings, refresh: true); settings.enabled = true
  }
}
extension EditorStore {
  var effectiveProof: ProofSettings {
    guard let draft = proofWorkspace, draft.source == document else { return proofSettings }
    return draft.preview && draft.error == nil ? draft.settings : proofSettings
  }
  var canBeginProof: Bool { canBeginDocumentMode && proofWorkspace == nil }
  func setProof(_ settings: ProofSettings) throws {
    let settings = try workingColorSettings.resolvingProof(settings)
    try SoftProof.validate(settings, in: document)
    guard proofSettings != settings else { return }
    proofSettings = settings; render()
  }
  func beginProof() {
    guard canBeginProof else { return }
    do { proofWorkspace = try ProofWorkspace(self); render() } catch { self.error = error.localizedDescription }
  }
  func previewProof() {
    guard let draft = proofWorkspace else { return }
    do { try SoftProof.validate(draft.settings, in: document); draft.error = nil }
    catch { draft.error = error.localizedDescription }
    render()
  }
  func cancelProof() { proofWorkspace = nil; render() }
  func commitProof() {
    guard let draft = proofWorkspace, draft.source == document else { return }
    do { try setProof(draft.settings); proofWorkspace = nil; render() }
    catch { draft.error = error.localizedDescription }
  }
}
extension AppDelegate {
  static let proofMenus: [String: ProofSettings.Plate] = [
    "Working CMYK": .composite, "Working Cyan Plate": .cyan, "Working Magenta Plate": .magenta,
    "Working Yellow Plate": .yellow, "Working Black Plate": .black, "Working CMY Plates": .cmy]
  @objc func proofCommand(_ item: NSMenuItem) {
    guard let store else { return }
    if item.title == "Custom…" { store.beginProof(); return }
    var settings = store.proofSettings
    switch item.title {
    case "Proof Colors": settings.enabled.toggle()
    case "Gamut Warning": settings.gamutWarning.toggle()
    case "Internet Standard RGB (sRGB)":
      settings.device = .sRGB; settings.profile = nil; settings.profileName = "sRGB"; settings.plate = .composite; settings.preserveNumbers = true; settings.enabled = true
    case "Monitor RGB":
      guard let profile = NSApp.keyWindow?.screen?.colorSpace?.cgColorSpace?.copyICCData() as Data? else { return }
      settings.device = .custom; settings.profile = profile; settings.profileName = "Monitor RGB"; settings.plate = .composite
      settings.preserveNumbers = store.document.colorMode == .rgb; settings.enabled = true
    default:
      guard let plate = Self.proofMenus[item.title] else { return }
      settings.device = .workingCMYK; settings.profile = nil; settings.profileName = "Generic CMYK"; settings.plate = plate
      settings.preserveNumbers = false; settings.enabled = true
    }
    do { try store.setProof(settings) } catch { store.error = error.localizedDescription }
  }
  func validateProofMenu(_ item: NSMenuItem) -> Bool {
    guard let store else { return false }; let settings = store.proofSettings
    let checked: Bool
    switch item.title {
    case "Proof Colors": checked = settings.enabled
    case "Gamut Warning": checked = settings.gamutWarning
    case "Internet Standard RGB (sRGB)": checked = settings.device == .sRGB
    case "Monitor RGB": checked = settings.device == .custom && settings.profileName == "Monitor RGB"
    default: checked = Self.proofMenus[item.title].map { settings.device == .workingCMYK && settings.plate == $0 } ?? false
    }
    item.state = checked ? .on : .off
    if ["Internet Standard RGB (sRGB)", "Monitor RGB"].contains(item.title), store.document.colorMode != .rgb { return false }
    return store.canBeginProof && (item.title != "Monitor RGB" || NSApp.keyWindow?.screen?.colorSpace != nil)
  }
}

struct ProofSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: ProofWorkspace
  private func setting<T>(_ key: WritableKeyPath<ProofSettings,T>) -> Binding<T> {
    Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0; store.previewProof() })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Customize Proof Condition").font(.title2)
      GroupBox("Proof Conditions") {
        VStack(alignment: .leading, spacing: 10) {
          Picker("Device to Simulate", selection: Binding(get: { model.settings.device }, set: { device in
            model.settings.device = device; model.settings.plate = .composite; model.settings.preserveNumbers = false
            if device != .custom { model.settings.profile = nil; model.settings.profileName = device == .sRGB ? "sRGB" : "Generic CMYK" }
            do { model.settings = try model.workingSettings.resolvingProof(model.settings) }
            catch { model.error = error.localizedDescription }
            store.previewProof()
          })) { Text("Working CMYK").tag(ProofSettings.Device.workingCMYK); Text("sRGB").tag(ProofSettings.Device.sRGB)
            if model.settings.device == .custom, model.settings.profile != nil { Text(model.settings.profileName).tag(ProofSettings.Device.custom) }
          }
          Button("Choose ICC Profile…", action: chooseProfile)
          Toggle("Preserve Numbers", isOn: setting(\.preserveNumbers))
            .disabled(!SoftProof.canPreserveNumbers(store.document, settings: model.settings))
          Picker("Rendering Intent", selection: setting(\.intent)) {
            Text("Perceptual").tag(ModeRenderingIntent.perceptual)
            Text("Relative Colorimetric").tag(ModeRenderingIntent.relativeColorimetric)
            Text("Saturation").tag(ModeRenderingIntent.saturation)
            Text("Absolute Colorimetric").tag(ModeRenderingIntent.absoluteColorimetric)
          }.disabled(model.settings.preserveNumbers)
          Toggle("Black Point Compensation", isOn: setting(\.blackPointCompensation)).disabled(model.settings.preserveNumbers)
        }.padding(8)
      }
      GroupBox("Display Options (On-Screen)") {
        VStack(alignment: .leading) {
          Toggle("Simulate Paper Color", isOn: Binding(get: { model.settings.simulatePaper }, set: { value in
            model.settings.simulatePaper = value; if value { model.settings.simulateBlack = true }; store.previewProof()
          }))
          Toggle("Simulate Black Ink", isOn: setting(\.simulateBlack)).disabled(model.settings.simulatePaper)
          Toggle("Gamut Warning", isOn: setting(\.gamutWarning))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      if let error = model.error ?? store.proofDisplayError { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Toggle("Preview", isOn: Binding(get: { model.preview }, set: { model.preview = $0; store.render() }))
        Spacer(); Button("Load…", action: load); Button("Save…", action: save)
      }
      HStack { Spacer(); Button("Cancel") { store.cancelProof() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitProof() }.keyboardShortcut(.defaultAction).disabled(model.error != nil || store.proofDisplayError != nil || store.rendering) }
    }.padding(20).frame(width: 470)
      .onDisappear { if store.proofWorkspace === model { store.cancelProof() } }
  }
  private func chooseProfile() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= ICCProfile.maximumBytes else { throw CraftError.invalid("Proof profile is too large.") }
      let data = try Data(contentsOf: url); _ = try ProofSettings.mode(of: data)
      model.settings.device = .custom; model.settings.profile = data; model.settings.profileName = url.deletingPathExtension().lastPathComponent
      model.settings.plate = .composite; model.settings.preserveNumbers = false; store.previewProof()
    } catch { model.error = error.localizedDescription }
  }
  private func load() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= ICCProfile.maximumBytes * 2 else { throw CraftError.invalid("Proof preset is too large.") }
      let settings = try JSONDecoder().decode(ProofSettings.self, from: Data(contentsOf: url)); try SoftProof.validate(settings, in: store.document)
      model.settings = settings; model.settings.enabled = true; store.previewProof()
    } catch { model.error = error.localizedDescription }
  }
  private func save() {
    let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Proof Condition.photato.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    do { try model.settings.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(model.settings).write(to: url, options: .atomic) }
    catch { model.error = error.localizedDescription }
  }
}
