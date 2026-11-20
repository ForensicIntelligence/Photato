import AppKit
import Observation
import SwiftUI

struct ArtworkPlacementSettings: Equatable, Sendable {
  var resizeImageDuringPlace = true
  var skipTransformWhenPlacing = false
  var alwaysCreateSmartObjectsWhenPlacing = true
}

@MainActor @Observable final class ArtworkPlacementPreferences {
  private static let key = "Photato.ArtworkPlacement.v1"
  private let defaults: UserDefaults?
  private(set) var revision = UUID()
  var settings: ArtworkPlacementSettings {
    didSet {
      guard settings != oldValue else { return }
      defaults?.set([
        "resizeImageDuringPlace": settings.resizeImageDuringPlace,
        "skipTransformWhenPlacing": settings.skipTransformWhenPlacing,
        "alwaysCreateSmartObjectsWhenPlacing": settings.alwaysCreateSmartObjectsWhenPlacing,
      ], forKey: Self.key)
      revision = UUID()
    }
  }

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    let saved = defaults?.dictionary(forKey: Self.key)
    settings = ArtworkPlacementSettings(
      resizeImageDuringPlace: saved?["resizeImageDuringPlace"] as? Bool ?? true,
      skipTransformWhenPlacing: saved?["skipTransformWhenPlacing"] as? Bool ?? false,
      alwaysCreateSmartObjectsWhenPlacing: saved?["alwaysCreateSmartObjectsWhenPlacing"] as? Bool ?? true)
  }
}

struct GeneralPlacementPreferencesView: View {
  @Bindable var preferences: ArtworkPlacementPreferences

  var body: some View {
    Form {
      Section("Placing Artwork") {
        Toggle("Resize Image During Place", isOn: $preferences.settings.resizeImageDuringPlace)
          .help("Scale oversized artwork down to fit the document when placing it.")
        Toggle("Skip Transform when Placing", isOn: $preferences.settings.skipTransformWhenPlacing)
          .help("Commit the new layer after any PDF or Camera Raw choices.")
        Toggle("Always Create Smart Objects when Placing", isOn: $preferences.settings.alwaysCreateSmartObjectsWhenPlacing)
          .help("Keep embedded artwork editable as a Smart Object. Place Linked and frame artwork keep their Smart Objects.")
      }
      .toggleStyle(.checkbox)
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 168)
  }
}

@MainActor extension AppDelegate {
  @objc func generalPlacementPreferences() {
    if generalPlacementPreferencesWindow == nil {
      let window = PhotatoWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 168),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "Settings — General"
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: GeneralPlacementPreferencesView(
        preferences: controller.artworkPlacementPreferences))
      window.center()
      generalPlacementPreferencesWindow = NSWindowController(window: window)
    }
    generalPlacementPreferencesWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
