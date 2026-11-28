import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class CameraRawPreferences {
  private static let storageKey = "Photato.CameraRaw.DNGStorage"
  private static let objectKey = "Photato.CameraRaw.OpenAsSmartObject"
  private static let outputKey = "Photato.CameraRaw.WorkflowOutput"
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

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
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

  var body: some View {
    Form {
      Section("Opening Images") {
        Toggle("Open as Smart Object by default", isOn: $preferences.openAsSmartObject)
          .help("Hold Shift in Camera Raw to use the other opening mode. Hold Option to open a copy.")
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
    .frame(width: 460, height: 244)
  }
}

@MainActor extension AppDelegate {
  @objc func cameraRawPreferences() {
    if cameraRawPreferencesWindow == nil {
      let window = PhotatoWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 244),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "Settings — Camera Raw"
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
