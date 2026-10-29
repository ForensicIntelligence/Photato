import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

typealias ColorPolicyReviewer = @MainActor (ColorPolicyAssessment, DocumentColorMode, PixelDepth) async throws -> ColorPolicyChoice

@MainActor @Observable final class ColorPolicyDialog: NSObject, NSWindowDelegate {
  let assessment: ColorPolicyAssessment
  let mode: DocumentColorMode
  let depth: PixelDepth
  var action: ColorPolicyChoice.Action
  var profile: Data?
  var error: String?
  @ObservationIgnored private var continuation: CheckedContinuation<ColorPolicyChoice, Error>?
  @ObservationIgnored private var controller: NSWindowController?
  init(_ assessment: ColorPolicyAssessment, mode: DocumentColorMode, depth: PixelDepth) {
    self.assessment = assessment; self.mode = mode; self.depth = depth
    action = assessment.choices.first ?? .preserveEmbedded
  }
  static func present(_ assessment: ColorPolicyAssessment, _ mode: DocumentColorMode, _ depth: PixelDepth) async throws -> ColorPolicyChoice {
    try Task.checkCancellation()
    let dialog = ColorPolicyDialog(assessment, mode: mode, depth: depth)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        dialog.continuation = continuation
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 550, height: 330),
          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = assessment.kind == .missing ? "Missing Profile"
          : assessment.kind == .pasteMismatch ? "Paste Profile Mismatch" : "Embedded Profile Mismatch"
        window.isReleasedWhenClosed = false; window.delegate = dialog
        window.contentView = NSHostingView(rootView: ColorPolicyDialogView(model: dialog))
        dialog.controller = NSWindowController(window: window)
        window.center(); dialog.controller?.showWindow(nil); window.makeKeyAndOrderFront(nil)
      }
    } onCancel: { Task { @MainActor in dialog.finish(nil) } }
  }
  func finish(_ choice: ColorPolicyChoice?) {
    guard let continuation else { return }
    self.continuation = nil; controller?.close(); controller = nil
    if let choice { continuation.resume(returning: choice) } else { continuation.resume(throwing: CancellationError()) }
  }
  func windowWillClose(_ notification: Notification) { finish(nil) }
  func loadProfile() {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "icc"), UTType(filenameExtension: "icm")].compactMap { $0 }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, count <= ICCProfile.maximumBytes else {
        throw CraftError.invalid("ICC profiles are limited to 4 MiB.")
      }
      profile = try NativeModeProfile.atDepth(Data(contentsOf: url), mode: mode, depth: depth); error = nil
    } catch { self.error = error.localizedDescription }
  }
}
struct ColorPolicyDialogView: View {
  @Bindable var model: ColorPolicyDialog
  private func title(_ action: ColorPolicyChoice.Action) -> String {
    switch action {
    case .preserveEmbedded: "Use the embedded profile"
    case .convertToWorking: "Convert document’s colors to the working space"
    case .discard: "Discard the embedded profile (don’t color manage)"
    case .leaveUntagged: "Leave as is (don’t color manage)"
    case .assignWorking: "Assign the working profile"
    case .assignProfile: "Assign a different profile"
    case .convertAppearance: "Convert colors to preserve appearance"
    case .preserveNumbers: "Preserve color numbers"
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Source: \(model.assessment.source)").fixedSize(horizontal: false, vertical: true)
      Text("\(model.assessment.kind == .pasteMismatch ? "Destination" : "Working space"): \(model.assessment.destination)")
        .fixedSize(horizontal: false, vertical: true)
      Picker("How would you like to proceed?", selection: $model.action) {
        ForEach(model.assessment.choices, id: \.self) { Text(title($0)).tag($0) }
      }.pickerStyle(.radioGroup)
      if model.action == .assignProfile {
        HStack {
          Menu(model.profile.map(ColorPolicyInput.name) ?? "Choose Profile") {
            ForEach(ColorProfileChoice.available(mode: model.mode, depth: model.depth)) { choice in
              Button(choice.name) { model.profile = choice.data }
            }
          }
          Button("Load…") { model.loadProfile() }
        }
      }
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button("Cancel") { model.finish(nil) }.keyboardShortcut(.cancelAction)
        Button("OK") { model.finish(.init(model.action, profile: model.action == .assignProfile ? model.profile : nil)) }
          .keyboardShortcut(.defaultAction).disabled(model.action == .assignProfile && model.profile == nil)
      }
    }.padding(20).frame(width: 520)
  }
}
