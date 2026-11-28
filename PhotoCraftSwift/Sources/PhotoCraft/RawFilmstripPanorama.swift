import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct RawFilmstripPanoramaRequest: Identifiable, Sendable {
  let id = UUID()
  let photos: [RawFilmstripWorkspace.Photo]
  let skipPreview: Bool
  let hdr: Bool
  let settings: RawPanoramaSettings

  var name: String {
    let source = photos[0].original.url.deletingPathExtension().lastPathComponent
    return ImageProcessor.safeBase(source) + (hdr ? "-HDR-Pano" : "-Pano")
  }
}

struct RawFilmstripPanoramaView: View {
  let workspace: RawFilmstripWorkspace
  let request: RawFilmstripPanoramaRequest
  @State private var settings: RawPanoramaSettings
  @State private var sources: [CraftDocument]?
  @State private var bracketSize: Int?
  @State private var registration: RawPanorama.Registration?
  @State private var registeredProjection: RawPanoramaSettings.Projection?
  @State private var result: RawPanorama.Result?
  @State private var readySettings: RawPanoramaSettings?
  @State private var preparing = true
  @State private var saving = false
  @State private var offeredShortcut = false
  @State private var savePanel: NSSavePanel?
  @State private var error: String?

  init(workspace: RawFilmstripWorkspace, request: RawFilmstripPanoramaRequest) {
    self.workspace = workspace
    self.request = request
    var settings = request.settings
    if settings.fillEdges { settings.autoCrop = false }
    _settings = State(initialValue: settings)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(request.hdr ? "HDR Panorama Merge Preview" : "Panorama Merge Preview").font(.headline)
      HStack(alignment: .top, spacing: 16) {
        ZStack {
          Color(nsColor: .underPageBackgroundColor)
          if let image = result?.preview {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
              .accessibilityLabel("Stitched panorama preview")
          }
          if preparing {
            ProgressView(sources == nil ? (request.hdr ? "Fusing exposure brackets…" : "Developing RAW photos…")
              : "Preparing panorama…")
              .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          }
        }
        .frame(minWidth: 390, minHeight: 300)
        .clipped()
        VStack(alignment: .leading, spacing: 10) {
          Picker("Projection", selection: $settings.projection) {
            ForEach(RawPanoramaSettings.Projection.allCases, id: \.self) { value in
              Text(value.title).tag(value)
            }
          }
          Slider(value: $settings.boundaryWarp, in: 0...100, step: 1) {
            Text("Boundary Warp")
          } minimumValueLabel: {
            Text("0").accessibilityHidden(true)
          } maximumValueLabel: {
            Text("100").accessibilityHidden(true)
          }
          .accessibilityValue(settings.boundaryWarp.formatted(.number.precision(.fractionLength(0))))
          Toggle("Fill Edges", isOn: Binding(
            get: { settings.fillEdges },
            set: { enabled in
              var updated = settings
              updated.fillEdges = enabled
              if enabled { updated.autoCrop = false }
              settings = updated
            }))
          Toggle("Auto Crop", isOn: $settings.autoCrop)
            .keyboardShortcut("c", modifiers: [])
            .disabled(settings.fillEdges)
          Toggle("Apply Auto Settings", isOn: $settings.autoSettings)
          if let bracketSize, let sources {
            Text("\(sources.count) brackets · \(bracketSize) exposures each")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let result, readySettings == settings {
            Text("\(result.document.width) × \(result.document.height) pixels")
              .font(.caption).foregroundStyle(.secondary)
          }
          ForEach(Array(RawPanoramaSettings.Projection.allCases.enumerated()), id: \.element) { index, projection in
            Button(projection.title) { settings.projection = projection }
              .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
              .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
          }
        }
        .frame(width: 215)
        .disabled(saving || savePanel != nil)
      }
      if let error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if saving { ProgressView("Saving panorama DNG…").controlSize(.small) }
        Spacer()
        Button("Cancel") { workspace.panoramaRequest = nil }
          .keyboardShortcut(.cancelAction).disabled(saving || savePanel != nil)
        Button("Merge…") { Task { await chooseDestination() } }
          .keyboardShortcut(.defaultAction)
          .disabled(preparing || saving || savePanel != nil || readySettings != settings || result == nil)
      }
    }
    .padding(18)
    .frame(idealWidth: 790, idealHeight: 510)
    .interactiveDismissDisabled(saving || savePanel != nil)
    .task { await loadSources() }
    .task(id: settings) { await render(settings) }
    .onDisappear { savePanel?.cancel(nil) }
  }

  private func loadSources() async {
    let inputs = request.photos.map { $0.original.hdrMergeSource(settings: $0.settings) }
    let hdr = request.hdr
    let worker = Task.detached(priority: .userInitiated) { () throws -> ([CraftDocument], Int?) in
      if hdr {
        let prepared = try RawPanorama.prepareHDRSources(inputs)
        return (prepared.photos, prepared.bracketSize)
      }
      return (try RawPanorama.prepareSources(inputs), nil)
    }
    do {
      let (photos, bracketSize) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      self.bracketSize = bracketSize
      sources = photos
      await render(settings)
    } catch is CancellationError {
    } catch {
      preparing = false
      self.error = error.localizedDescription
    }
  }

  private func render(_ options: RawPanoramaSettings) async {
    guard let sources else { return }
    preparing = true
    error = nil
    do {
      if result != nil { try await Task.sleep(for: .milliseconds(160)) }
      guard options == settings else { return }
      let name = request.name
      let existing = registeredProjection == options.projection ? registration : nil
      let worker = Task.detached(priority: .userInitiated) {
        let prepared = try existing ?? RawPanorama.register(sources, projection: options.projection, name: name)
        return (prepared, try RawPanorama.finish(prepared, options: options))
      }
      let (prepared, finished) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      guard options == settings else { return }
      registration = prepared
      registeredProjection = options.projection
      result = finished
      readySettings = options
      preparing = false
      if request.skipPreview && !offeredShortcut {
        offeredShortcut = true
        await chooseDestination()
      }
    } catch is CancellationError {
    } catch {
      guard options == settings, !Task.isCancelled else { return }
      preparing = false
      self.error = error.localizedDescription
    }
  }

  private func chooseDestination() async {
    guard !preparing, !saving, savePanel == nil, let result, readySettings == settings else { return }
    let options = settings
    let panel = NSSavePanel()
    panel.title = "Merge Result"
    panel.prompt = "Save"
    panel.allowedContentTypes = [UTType("com.adobe.raw-image") ?? .data]
    panel.nameFieldStringValue = request.name + ".dng"
    panel.directoryURL = request.photos.first?.original.url.deletingLastPathComponent()
    panel.canCreateDirectories = true
    savePanel = panel
    let response = if let parent = NSApp.keyWindow { await panel.beginSheetModal(for: parent) }
      else { await panel.begin() }
    savePanel = nil
    guard response == .OK, let destination = panel.url else {
      if request.skipPreview { workspace.panoramaRequest = nil }
      return
    }
    saving = true
    error = nil
    do {
      let photo = try await workspace.savePanorama(result, to: destination, requestID: request.id)
      try Task.checkCancellation()
      workspace.acceptPanorama(photo, requestID: request.id, settings: options)
    } catch is CancellationError {
    } catch {
      self.error = error.localizedDescription
    }
    saving = false
  }
}
