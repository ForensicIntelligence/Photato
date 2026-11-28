import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class CameraRawPreferences {
  private static let storageKey = "Photato.CameraRaw.DNGStorage"
  private static let objectKey = "Photato.CameraRaw.OpenAsSmartObject"
  private static let outputKey = "Photato.CameraRaw.WorkflowOutput"
  private static let defaultsKey = "Photato.CameraRaw.RawDefaults"
  private let defaults: UserDefaults?
  private(set) var revision = UUID()
  var dngStorage: RawDNGSettingsStorage {
    didSet {
      guard dngStorage != oldValue else { return }
      defaults?.set(dngStorage.rawValue, forKey: Self.storageKey)
      revision = UUID()
    }
  }

  var openAsSmartObject: Bool {
    didSet {
      guard openAsSmartObject != oldValue else { return }
      defaults?.set(openAsSmartObject, forKey: Self.objectKey)
      revision = UUID()
    }
  }

  var workflowOutput: RawWorkflowOutput {
    didSet {
      guard workflowOutput != oldValue else { return }
      if let data = try? JSONEncoder().encode(workflowOutput) {
        defaults?.set(data, forKey: Self.outputKey)
      }
      revision = UUID()
    }
  }

  private(set) var rawDefaults: RawDefaults

  func setRawDefaults(_ value: RawDefaults) throws {
    guard value != rawDefaults else { return }
    try value.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    defaults?.set(try encoder.encode(value), forKey: Self.defaultsKey)
    rawDefaults = value
    revision = UUID()
  }

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    if let data = defaults?.data(forKey: Self.defaultsKey), data.count <= RawDefaults.maximumEncodedBytes,
      let decoded = try? JSONDecoder().decode(RawDefaults.self, from: data), (try? decoded.validate()) != nil {
      rawDefaults = decoded
    } else {
      rawDefaults = .init()
    }
    openAsSmartObject = defaults?.bool(forKey: Self.objectKey) ?? false
    let stored = defaults?.data(forKey: Self.outputKey).flatMap { try? JSONDecoder().decode(RawWorkflowOutput.self, from: $0) }
    if let stored, (try? stored.validate()) != nil {
      workflowOutput = stored
    } else {
      workflowOutput = .init()
    }
    dngStorage = defaults?.string(forKey: Self.storageKey).flatMap(RawDNGSettingsStorage.init(rawValue:))
      ?? .embedXMP
  }
}

private extension RawDNGSettingsStorage {
  var label: String {
    switch self {
    case .embedXMP: "Embed XMP in DNG"
    case .sidecarXMP: "Always use XMP sidecars"
    case .ignoreSidecarXMP: "Ignore XMP sidecars"
    }
  }

  var detail: String {
    switch self {
    case .embedXMP: "Read an existing sidecar and save adjustments inside the DNG."
    case .sidecarXMP: "Save adjustments to an XMP file beside the DNG."
    case .ignoreSidecarXMP: "Read and save adjustments inside the DNG. Existing sidecars stay in place."
    }
  }
}

private struct CameraRawPreferencesView: View {
  @Bindable var preferences: CameraRawPreferences
  @State private var error: String?

  var body: some View {
    Form {
      Section("Opening Images") {
        Toggle("Open as Smart Object by default", isOn: $preferences.openAsSmartObject)
          .help("Hold Shift in Camera Raw to use the other opening mode. Hold Option to open a copy.")
      }
      Section("Raw Defaults") {
        LabeledContent("Master") {
          choiceMenu(preferences.rawDefaults.master, camera: nil)
        }
        Toggle("Override master settings for specific cameras", isOn: Binding(
          get: { preferences.rawDefaults.useOverrides },
          set: { enabled in update { $0.useOverrides = enabled } }))
        if preferences.rawDefaults.useOverrides {
          ForEach(preferences.rawDefaults.rules, id: \.camera) { rule in
            LabeledContent(rule.camera.title) {
              choiceMenu(rule.choice, camera: rule.camera)
            }
          }
          Menu("Add Camera…") {
            Button("Camera Model from RAW File…") { addCamera(matchSerial: false) }
            Button("Camera Body from RAW File…") { addCamera(matchSerial: true) }
          }
          .disabled(preferences.rawDefaults.rules.count >= RawDefaults.maximumRules)
        }
        if let error {
          Text(error).foregroundStyle(.red).accessibilityLabel("Camera Raw settings error: \(error)")
        }
      }
      Section("DNG File Handling") {
        Picker("Sidecars", selection: $preferences.dngStorage) {
          ForEach(RawDNGSettingsStorage.allCases, id: \.self) { choice in
            Text(choice.label).tag(choice)
          }
        }
        Text(preferences.dngStorage.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 480, minHeight: 365)
  }

  private func choiceMenu(_ current: RawDefaults.Choice, camera: RawDefaults.Camera?) -> some View {
    let label = current.name ?? (current.mode == .camera ? "Camera Settings" : "Photato Default")
    return Menu(label) {
      Button("Photato Default") { setChoice(.init(), camera: camera) }
      Button("Camera Settings") { setChoice(.init(mode: .camera), camera: camera) }
      Button("Choose XMP Preset…") { choosePreset(for: camera) }
      if let camera {
        Divider()
        Button("Remove Camera Override", role: .destructive) {
          update { $0.rules.removeAll { $0.camera == camera } }
        }
      }
    }
    .accessibilityLabel(camera.map { "RAW defaults for \($0.title)" } ?? "Master RAW defaults")
    .accessibilityValue(label)
  }

  private func setChoice(_ choice: RawDefaults.Choice, camera: RawDefaults.Camera?) {
    update { policy in
      if let camera {
        if let index = policy.rules.firstIndex(where: { $0.camera == camera }) {
          policy.rules[index].choice = choice
        }
      } else {
        policy.master = choice
      }
    }
  }

  private func update(_ change: (inout RawDefaults) -> Void) {
    var policy = preferences.rawDefaults
    change(&policy)
    do {
      try preferences.setRawDefaults(policy)
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func choosePreset(for camera: RawDefaults.Camera?) {
    let panel = NSOpenPanel()
    panel.prompt = "Use Preset"
    panel.allowedContentTypes = [UTType(filenameExtension: "xmp") ?? .xml]
    panel.begin { result in
      guard result == .OK, let url = panel.url else { return }
      do {
        let bytes = try RecoverySourceReader.snapshot(url, maximumBytes: { _ in CameraRawXMP.maximumBytes },
          fileBackedAbove: CameraRawXMP.maximumBytes).data
        setChoice(.init(mode: .preset, name: url.deletingPathExtension().lastPathComponent, xmp: bytes), camera: camera)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func addCamera(matchSerial: Bool) {
    let panel = NSOpenPanel()
    panel.prompt = "Add Camera"
    panel.allowedContentTypes = [RawSourceIO.contentType]
    panel.begin { result in
      guard result == .OK, let url = panel.url else { return }
      do {
        var camera = try RawSourceIO.cameraIdentity(at: url)
        if matchSerial {
          guard camera.serial != nil else { throw CraftError.invalid("This file does not record a camera body serial number.") }
        } else {
          camera = camera.withoutSerial
        }
        update { policy in
          let inherited = policy.choice(for: camera)
          policy.rules.append(.init(camera: camera, choice: inherited))
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

@MainActor extension AppDelegate {
  @objc func cameraRawPreferences() {
    if cameraRawPreferencesWindow == nil {
      let window = PhotatoWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 428),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.title = "Settings — Camera Raw"
      window.contentMinSize = NSSize(width: 480, height: 365)
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: CameraRawPreferencesView(
        preferences: controller.cameraRawPreferences))
      window.center()
      cameraRawPreferencesWindow = NSWindowController(window: window)
    }
    cameraRawPreferencesWindow?.window?.makeKeyAndOrderFront(nil)
  }
}


struct RawWorkflowControls: View {
  @State private var draft: RawWorkflowOutput
  let width: Int
  let height: Int
  var onApply: (RawWorkflowOutput) -> Void
  var onCancel: () -> Void

  init(output: RawWorkflowOutput, width: Int, height: Int,
    onApply: @escaping (RawWorkflowOutput) -> Void, onCancel: @escaping () -> Void) {
    _draft = State(initialValue: output)
    self.width = width
    self.height = height
    self.onApply = onApply
    self.onCancel = onCancel
  }

  var body: some View {
    Form {
      Picker("Color Space", selection: $draft.profile) {
        Text("Current profile").tag(nil as RawWorkflowOutput.Profile?)
        ForEach(RawWorkflowOutput.Profile.allCases, id: \.self) { profile in
          Text(profile.title).tag(Optional(profile))
        }
      }
      Picker("Bit Depth", selection: $draft.depth) {
        Text("Current depth").tag(nil as PixelDepth?)
        Text("8 bits/channel").tag(Optional(PixelDepth.u8))
        Text("16 bits/channel").tag(Optional(PixelDepth.u16))
      }
      TextField("Resolution (ppi)", value: $draft.pixelsPerInch, format: .number)
        .help("Leave empty to keep the source resolution.")
      Toggle("Resize to Fit", isOn: Binding(
        get: { draft.resize != nil },
        set: { draft.resize = $0 ? resizeDefaults(.widthHeight) : nil }))
      if let resize = draft.resize {
        Picker("Resize Mode", selection: Binding(
          get: { draft.resize?.mode ?? resize.mode },
          set: { draft.resize = resizeDefaults($0, dontEnlarge: resize.dontEnlarge) })) {
          ForEach(RawWorkflowOutput.Resize.Mode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
        TextField(resize.mode.usesSecondValue ? "Width or longer side (px)" : resize.mode.title,
          value: Binding(get: { draft.resize?.value ?? resize.value }, set: { draft.resize?.value = $0 }),
          format: .number)
        if let second = resize.secondValue {
          TextField("Height or shorter side (px)", value: Binding(
            get: { draft.resize?.secondValue ?? second }, set: { draft.resize?.secondValue = $0 }),
            format: .number)
        }
        Toggle("Don’t Enlarge", isOn: Binding(
          get: { draft.resize?.dontEnlarge ?? false },
          set: { draft.resize?.dontEnlarge = $0 }))
      }
      if let size = try? dimensions() {
        LabeledContent("Output Dimensions", value: "\(size.width) × \(size.height) px")
      } else {
        Text("Enter valid output dimensions and resolution.").foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
        Button("Apply") { onApply(draft) }.disabled((try? dimensions()) == nil)
      }
    }
    .padding(16).frame(width: 360)
  }

  private func dimensions() throws -> (width: Int, height: Int) {
    try draft.validate()
    return try draft.resize?.dimensions(width: width, height: height) ?? (width, height)
  }

  private func resizeDefaults(_ mode: RawWorkflowOutput.Resize.Mode,
    dontEnlarge: Bool = false) -> RawWorkflowOutput.Resize {
    let value: Double
    switch mode {
    case .widthHeight: value = Double(width)
    case .dimensions, .longSide: value = Double(max(width, height))
    case .shortSide: value = Double(min(width, height))
    case .megapixels: value = Double(width * height) / 1_000_000
    case .percentage: value = 100
    }
    let second = mode == .dimensions ? Double(min(width, height)) : Double(height)
    return .init(mode: mode, value: value, secondValue: mode.usesSecondValue ? second : nil, dontEnlarge: dontEnlarge)
  }
}
