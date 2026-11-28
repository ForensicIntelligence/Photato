import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct RawFilmstripHDRRequest: Identifiable, Sendable {
  let id = UUID()
  let photos: [RawFilmstripWorkspace.Photo]
  let skipPreview: Bool
  let settings: RawHDRMergeSettings

  var name: String {
    let original = photos[0].original.url.deletingPathExtension().lastPathComponent
    return ImageProcessor.safeBase(original) + "-HDR"
  }
}

struct RawFilmstripHDRMergeView: View {
  private struct PreviewKey: Equatable {
    let options: RawHDRMergeSettings
    let hasSources: Bool
  }

  let workspace: RawFilmstripWorkspace
  let request: RawFilmstripHDRRequest
  @State private var settings: RawHDRMergeSettings
  @State private var sources: [CraftDocument]?
  @State private var result: RawHDRMerge.Result?
  @State private var renderedSettings: RawHDRMergeSettings?
  @State private var preparing = true
  @State private var showingOverlay = false
  @State private var error: String?
  @State private var saving = false
  @State private var savePanel: NSSavePanel?
  @State private var didOfferShortcut = false

  init(workspace: RawFilmstripWorkspace, request: RawFilmstripHDRRequest) {
    self.workspace = workspace
    self.request = request
    _settings = State(initialValue: request.settings)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("HDR Merge Preview").font(.headline)
      HStack(alignment: .top, spacing: 16) {
        ZStack {
          Color(nsColor: .underPageBackgroundColor)
          if let result, let preview = showingOverlay ? result.overlayPreview ?? result.preview : result.preview {
            Image(decorative: preview, scale: 1)
              .resizable()
              .scaledToFit()
              .accessibilityLabel("HDR merge preview")
          }
          if preparing {
            ProgressView(sources == nil ? "Developing exposure brackets…" : "Merging exposures…")
              .padding(12)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          }
        }
        .frame(minWidth: 390, minHeight: 300)
        .clipped()
        VStack(alignment: .leading, spacing: 10) {
          Toggle("Align Images", isOn: $settings.align)
            .keyboardShortcut("a", modifiers: [])
          Toggle("Apply Auto Settings", isOn: $settings.autoSettings)
            .keyboardShortcut("t", modifiers: [])
          Picker("Deghost", selection: $settings.deghost) {
            ForEach(RawHDRMergeSettings.Deghost.allCases, id: \.self) {
              Text($0.title).tag($0)
            }
          }
          Toggle("Show Overlay", isOn: $showingOverlay)
            .keyboardShortcut("y", modifiers: [])
            .disabled(result?.overlayPreview == nil || settings.deghost == .off)
        }
        .frame(width: 170)
        .disabled(saving || savePanel != nil)
      }
      if let error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if saving { ProgressView("Saving HDR DNG…").controlSize(.small) }
        Spacer()
        Button("Cancel") { workspace.dismissHDRMerge() }
          .keyboardShortcut(.cancelAction)
          .disabled(saving || savePanel != nil)
        Button("Merge…") { Task { await chooseDestination() } }
          .keyboardShortcut(.defaultAction)
          .disabled(preparing || saving || savePanel != nil || renderedSettings != settings || result == nil)
      }
    }
    .padding(18)
    .frame(idealWidth: 740, idealHeight: 490)
    .interactiveDismissDisabled(saving || savePanel != nil)
    .task { await loadSources() }
    .task(id: PreviewKey(options: settings, hasSources: sources != nil)) { await render() }
    .onDisappear { savePanel?.cancel(nil) }
  }

  private func loadSources() async {
    let inputs = request.photos.map { $0.original.hdrMergeSource(settings: $0.settings) }
    let worker = Task.detached(priority: .userInitiated) { try RawHDRMerge.prepareSources(inputs) }
    do {
      let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      sources = prepared
    } catch is CancellationError {
    } catch {
      preparing = false
      self.error = error.localizedDescription
    }
  }

  private func render() async {
    guard let sources else { return }
    let options = settings, name = request.name
    preparing = true
    error = nil
    let worker = Task.detached(priority: .userInitiated) {
      try RawHDRMerge.prepare(sources, options: options, name: name)
    }
    do {
      let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      guard options == settings else { return }
      result = prepared
      renderedSettings = options
      preparing = false
      if request.skipPreview && !didOfferShortcut {
        didOfferShortcut = true
        await chooseDestination()
      }
    } catch is CancellationError {
    } catch {
      guard options == settings, !Task.isCancelled else { return }
      result = nil
      preparing = false
      self.error = error.localizedDescription
    }
  }

  private func chooseDestination() async {
    guard !preparing, !saving, savePanel == nil, let result, renderedSettings == settings else { return }
    let panel = NSSavePanel()
    panel.title = "Merge Result"
    panel.prompt = "Save"
    panel.allowedContentTypes = [UTType("com.adobe.raw-image") ?? .data]
    panel.nameFieldStringValue = request.name + ".dng"
    panel.directoryURL = request.photos.first?.original.url.deletingLastPathComponent()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    savePanel = panel
    let response = if let parent = NSApp.keyWindow {
      await panel.beginSheetModal(for: parent)
    } else { await panel.begin() }
    savePanel = nil
    guard response == .OK, let destination = panel.url else {
      if request.skipPreview { workspace.dismissHDRMerge() }
      return
    }
    saving = true
    error = nil
    do {
      let result = try await workspace.saveHDRMerge(result, to: destination, requestID: request.id)
      try Task.checkCancellation()
      workspace.acceptHDRMerge(result, requestID: request.id, settings: settings)
    } catch is CancellationError {
    } catch {
      self.error = error.localizedDescription
    }
    saving = false
  }
}
