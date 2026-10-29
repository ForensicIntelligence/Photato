import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

struct ColorSettingsView: View {
  @Bindable var draft: ColorSettingsDraft
  let dismiss: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Working Spaces") {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(ColorSettings.workingModes, id: \.self) { mode in
            HStack {
              Text(mode.title).frame(width: 75, alignment: .leading)
              Menu {
                Button("Photato Default") { set(nil, mode) }
                Divider()
                ForEach(ColorProfileChoice.available(mode: mode, depth: .u16)) { choice in
                  Button(choice.name) { set(choice.data, mode) }
                }
              } label: { Text(profileName(mode)).lineLimit(1) }
              Button("Load…") { load(mode) }
            }
          }
        }.padding(10)
      }
      GroupBox("Color Management Policies") {
        VStack(alignment: .leading, spacing: 8) {
          policy("RGB", $draft.value.rgbPolicy)
          policy("CMYK", $draft.value.cmykPolicy)
          policy("Gray", $draft.value.grayPolicy)
          Toggle("Profile Mismatches: Ask When Opening", isOn: $draft.value.askMismatchOpening)
          Toggle("Profile Mismatches: Ask When Pasting", isOn: $draft.value.askMismatchPasting)
          Toggle("Missing Profiles: Ask When Opening", isOn: $draft.value.askMissingOpening)
        }.padding(10)
      }
      GroupBox("Conversion Options") {
        VStack(alignment: .leading, spacing: 10) {
          Text("Engine: Apple ColorSync")
          Picker("Intent", selection: $draft.value.intent) {
            Text("Perceptual").tag(ModeRenderingIntent.perceptual)
            Text("Relative Colorimetric").tag(ModeRenderingIntent.relativeColorimetric)
            Text("Saturation").tag(ModeRenderingIntent.saturation)
            Text("Absolute Colorimetric").tag(ModeRenderingIntent.absoluteColorimetric)
          }
          Toggle("Use Black Point Compensation", isOn: $draft.value.blackPointCompensation)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
      }
      Text("Working spaces apply to new documents and color mode changes. Conversion options supply defaults for Convert to Profile. Opening and pasting follow the selected policies. Existing open documents retain their profiles.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Button("Reset to Photato Defaults") { draft.value = ColorSettings() }
        Spacer()
        Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
        Button("OK") { if draft.apply() { dismiss() } }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 580)
  }
  private func policy(_ title: String, _ binding: Binding<ColorSettings.Policy>) -> some View {
    Picker(title, selection: binding) {
      Text("Preserve Embedded Profiles").tag(ColorSettings.Policy.preserveEmbedded)
      Text("Convert to Working Space").tag(ColorSettings.Policy.convertToWorking)
      Text("Off").tag(ColorSettings.Policy.off)
    }
  }
  private func profileName(_ mode: DocumentColorMode) -> String {
    guard let data = try? draft.value.profile(mode, depth: .u16),
      let space = CGColorSpace(iccData: data as CFData) else { return "Unavailable profile" }
    return NSColorSpace(cgColorSpace: space)?.localizedName ?? "Custom ICC profile"
  }
  private func set(_ data: Data?, _ mode: DocumentColorMode) {
    do { try draft.value.setProfile(data, for: mode); draft.error = nil }
    catch { draft.error = error.localizedDescription }
  }
  private func load(_ mode: DocumentColorMode) {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "icc"), UTType(filenameExtension: "icm")].compactMap { $0 }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0, size <= ICCProfile.maximumBytes else { throw CraftError.invalid("ICC profiles are limited to 4 MiB.") }
      set(try Data(contentsOf: url), mode)
    } catch { draft.error = error.localizedDescription }
  }
}

@MainActor final class ColorSettingsWindowController: NSWindowController {
  init(store: ColorSettingsStore) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Color Settings"; window.isReleasedWhenClosed = false
    super.init(window: window)
    let content = NSHostingView(rootView: ColorSettingsView(draft: .init(store: store)) { [weak self] in self?.close() })
    window.contentView = content
    content.layoutSubtreeIfNeeded()
    window.setContentSize(content.fittingSize)
    window.center()
  }
  required init?(coder: NSCoder) { nil }
}
extension AppDelegate {
  @objc func colorSettingsDialog() {
    if colorSettingsWindow?.window?.isVisible != true {
      colorSettingsWindow = ColorSettingsWindowController(store: controller.colorSettings)
    }
    colorSettingsWindow?.showWindow(nil); colorSettingsWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
