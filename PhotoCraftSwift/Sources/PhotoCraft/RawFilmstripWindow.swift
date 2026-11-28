import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension CraftDocumentController {
  @discardableResult func presentRawFilmstrip(_ urls: [URL], format: DocumentOpenFormat) -> Bool {
    let eligible = format == .automatic || format == .raw
    guard eligible, urls.count > 1, documentOpening.canStart,
      urls.allSatisfy({ DocumentOpenFormat.detect($0) == .raw && document(for: $0) == nil }) else { return false }
    let workspace = RawFilmstripWorkspace(controller: self) { [weak self] in
      self?.rawFilmstripWindow?.close()
      self?.rawFilmstripWindow = nil
    }
    let window = RawFilmstripWindow(workspace: workspace)
    rawFilmstripWindow = window
    window.showWindow(nil)
    workspace.start(urls)
    return true
  }
}

@MainActor final class RawFilmstripWindow: NSWindowController, NSWindowDelegate {
  let workspace: RawFilmstripWorkspace
  private var keyMonitor: Any?

  init(workspace: RawFilmstripWorkspace) {
    self.workspace = workspace
    let area = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 900)
    let window = PhotatoWindow(contentRect: NSRect(x: 0, y: 0, width: min(1260, area.width - 48),
      height: min(850, area.height - 48)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Camera Raw"
    window.isReleasedWhenClosed = false
    window.contentMinSize = CGSize(width: min(820, area.width - 48), height: min(540, area.height - 48))
    window.contentView = NSHostingView(rootView: RawFilmstripView(workspace: workspace))
    super.init(window: window)
    window.delegate = self
    window.center()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window, weak workspace] event in
      guard let window, window.isKeyWindow, event.window === window,
        workspace?.handleMarkingKey(event) == true else { return event }
      return nil
    }
  }

  required init?(coder: NSCoder) { nil }
  func windowShouldClose(_ sender: NSWindow) -> Bool { !workspace.finishing }
  func windowWillClose(_ notification: Notification) {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    Task { workspace.close() }
  }
}

private struct RawFilmstripView: View {
  let workspace: RawFilmstripWorkspace
  @State private var visible = true
  @State private var showingSync = false
  @State private var showingFilters = false
  @State private var showingInformation = false
  @State private var groups = Set(RawSettingsGroup.allCases)

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button(visible ? "Hide Photos" : "Show Photos", systemImage: "film") { visible.toggle() }
          .keyboardShortcut("/", modifiers: [])
        Button("Previous Photo", systemImage: "chevron.left") { workspace.navigate(-1) }.labelStyle(.iconOnly)
        Button("Next Photo", systemImage: "chevron.right") { workspace.navigate(1) }.labelStyle(.iconOnly)
        Menu("Sort") {
          Picker("Sort by", selection: Bindable(workspace).order) {
            ForEach(RawFilmstripOrder.allCases, id: \.self) { order in Text(order.rawValue).tag(order) }
          }
          Toggle("Reverse Order", isOn: Bindable(workspace).reverseOrder)
        }
        Button("Filter", systemImage: "line.3.horizontal.decrease.circle") { showingFilters = true }
          .popover(isPresented: $showingFilters) { filters }
        Menu("Photo") {
          markingCommands()
          Divider()
          Button("Select Rated") { workspace.selectRated() }
        }
        Button("Photo Info", systemImage: "info.circle") { showingInformation.toggle() }
          .labelStyle(.iconOnly)
          .help("Read the active RAW photo’s file and capture metadata.")
          .disabled(workspace.activeInformation == nil)
          .popover(isPresented: $showingInformation) {
            if let information = workspace.activeInformation { RawPhotoInformationView(information: information) }
          }
        Spacer()
        Text("\(workspace.selection.count) of \(workspace.displayedPhotos.count) selected").monospacedDigit()
        Button("Select All") { workspace.selectAll() }.keyboardShortcut("a", modifiers: .command)
        Button("Deselect Others") { workspace.selectActive() }.keyboardShortcut("d", modifiers: .command)
        Button("Synchronize…") { showingSync = true }
          .keyboardShortcut("s", modifiers: .option)
          .disabled(workspace.selection.count < 2)
          .popover(isPresented: $showingSync) { synchronization }
      }
      .controlSize(.small)
      .disabled(workspace.busy)
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      if visible {
        Divider()
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
              ForEach(workspace.displayedPhotos) { photo in
                Button {
                  let flags = NSApp.currentEvent?.modifierFlags ?? []
                  workspace.select(photo.id, extending: flags.contains(.shift), toggling: flags.contains(.command))
                } label: {
                  thumbnail(photo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(photo.name)
                .accessibilityValue(accessibilityMarking(photo))
                .accessibilityAddTraits(workspace.selection.contains(photo.id) ? .isSelected : [])
                .contextMenu { markingCommands(for: photo.id) }
                .id(photo.id)
              }
            }
            .padding(8)
          }
          .frame(height: 120)
          .onChange(of: workspace.activeID) { _, id in
            if let id { proxy.scrollTo(id, anchor: .center) }
          }
        }
        .disabled(workspace.busy)
      }
      Divider()
      if let editor = workspace.editor {
        CameraRawSheet(store: editor.store, filmstrip: workspace, filmstripPhoto: editor.id)
          .id(editor.id)
          .disabled(workspace.busy)
      } else {
        VStack(spacing: 14) {
          if workspace.busy || workspace.loadingPreview {
            ProgressView(workspace.progress ?? "Preparing photo preview…")
          } else {
            if workspace.error != nil {
              Text("The preview could not be opened.")
            } else if workspace.displayedPhotos.isEmpty, !workspace.photos.isEmpty {
              Text("No photos match the filters.")
              Button("Clear Filters") { workspace.clearFilters() }
            } else { Text("Select a photo") }
          }
          Button("Cancel") { workspace.close() }.keyboardShortcut(.cancelAction)
            .disabled(workspace.finishing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let progress = workspace.progress, workspace.editor != nil {
        ProgressView(progress).controlSize(.small).padding(.bottom, 8)
      }
      if let error = workspace.error {
        Text(error).font(.caption).foregroundStyle(.red).lineLimit(4)
          .textSelection(.enabled).padding(8)
      } else if let status = workspace.exportStatus {
        Text(status).font(.caption).foregroundStyle(.secondary).padding(8)
      }
    }
  }

  private func thumbnail(_ photo: RawFilmstripWorkspace.Photo) -> some View {
    let selected = workspace.selection.contains(photo.id)
    let active = workspace.activeID == photo.id
    return VStack(spacing: 3) {
      ZStack(alignment: .bottomTrailing) {
        Color(nsColor: .windowBackgroundColor)
        if let image = photo.thumbnail {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          Image(systemName: "photo").foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if active { Image(systemName: "circle.inset.filled").padding(4).accessibilityHidden(true) }
      }
      .frame(height: 57)
      Text(photo.name).font(.caption).lineLimit(1).truncationMode(.middle)
      HStack(spacing: 4) {
        if let rating = photo.marking.rating, rating > 0 {
          Image(systemName: "star.fill")
          Text(String(rating))
        } else if photo.marking.rating == -1 {
          Text("Rejected")
        }
        if let label = photo.marking.label, !label.isEmpty {
          let color = RawFilmstripLabel(marking: photo.marking)
          Circle().fill(labelColor(color)).frame(width: 8, height: 8)
          Text(label).lineLimit(1)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .frame(height: 14)
      .accessibilityHidden(true)
    }
    .frame(width: 111)
    .padding(5)
    .background(selected ? Color.accentColor.opacity(0.19) : .clear, in: RoundedRectangle(cornerRadius: 5))
    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? Color.accentColor : .clear, lineWidth: 2))
  }

  private func accessibilityMarking(_ photo: RawFilmstripWorkspace.Photo) -> String {
    var parts = [String]()
    if workspace.activeID == photo.id { parts.append("Active") }
    if let rating = photo.marking.rating {
      parts.append(rating < 0 ? "Rejected" : (rating == 1 ? "1 star" : "\(rating) stars"))
    }
    if let label = photo.marking.label, !label.isEmpty { parts.append(label) }
    return parts.joined(separator: ", ")
  }

  private func labelColor(_ label: RawFilmstripLabel) -> Color {
    switch label {
    case .red: .red
    case .yellow: .yellow
    case .green: .green
    case .blue: .blue
    case .purple: .purple
    case .none, .other: .secondary
    }
  }

  @ViewBuilder private func markingCommands(for photo: UUID? = nil) -> some View {
    Menu("Rating") {
      Button("Unrated") { mark(photo) { workspace.setRating(0) } }
      ForEach(1...5, id: \.self) { rating in
        Button(rating == 1 ? "1 Star" : "\(rating) Stars") { mark(photo) { workspace.setRating(rating) } }
      }
    }
    .disabled(workspace.selection.isEmpty && photo == nil)
    Menu("Color Label") {
      ForEach(RawFilmstripLabel.allCases.dropLast(), id: \.self) { label in
        Button(label.rawValue) { mark(photo) { workspace.setLabel(label) } }
      }
    }
    .disabled(workspace.selection.isEmpty && photo == nil)
  }

  private func mark(_ photo: UUID?, _ change: () -> Void) {
    if let photo, !workspace.selection.contains(photo) { workspace.select(photo) }
    change()
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Rating", selection: Binding(get: { workspace.ratingFilter }, set: workspace.setRatingFilter)) {
        ForEach(RawFilmstripRatingFilter.allCases, id: \.self) { filter in Text(filter.rawValue).tag(filter) }
      }
      Text("Color Labels").font(.subheadline).fontWeight(.medium)
      ForEach(RawFilmstripLabel.allCases, id: \.self) { label in
        Toggle(label.rawValue, isOn: Binding(get: { workspace.labelFilters.contains(label) },
          set: { enabled in if enabled != workspace.labelFilters.contains(label) { workspace.toggleLabelFilter(label) } }))
      }
      Button("Clear Filters") { workspace.clearFilters() }
        .disabled(workspace.ratingFilter == .all && workspace.labelFilters.isEmpty)
    }
    .padding(14)
    .frame(width: 225)
  }

  private var synchronization: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("Synchronize Settings").font(.headline)
      ForEach(RawSettingsGroup.allCases, id: \.self) { group in
        Toggle(group.rawValue, isOn: Binding(get: { groups.contains(group) }, set: { selected in
          if selected { groups.insert(group) } else { groups.remove(group) }
        }))
      }
      HStack {
        Button("Cancel") { showingSync = false }.keyboardShortcut(.cancelAction)
        Button("Synchronize") {
          workspace.synchronize(groups)
          showingSync = false
        }
        .keyboardShortcut(.defaultAction)
        .disabled(groups.isEmpty)
      }
    }
    .padding(15)
  }
}
