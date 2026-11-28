import AppKit
import Observation
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class CameraRawPreferences {
  private static let storageKey = "Photato.CameraRaw.DNGStorage"
  private static let objectKey = "Photato.CameraRaw.OpenAsSmartObject"
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

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    openAsSmartObject = defaults?.bool(forKey: Self.objectKey) ?? false
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
