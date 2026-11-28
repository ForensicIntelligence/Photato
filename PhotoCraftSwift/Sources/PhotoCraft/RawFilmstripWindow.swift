import AppKit
import PhotoCraftCore
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
  }

  required init?(coder: NSCoder) { nil }
  func windowShouldClose(_ sender: NSWindow) -> Bool { !workspace.finishing }
  func windowWillClose(_ notification: Notification) { Task { workspace.close() } }
}

private struct RawFilmstripView: View {
  let workspace: RawFilmstripWorkspace
  @State private var visible = true
  @State private var showingSync = false
  @State private var groups = Set(RawSettingsGroup.allCases)

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button(visible ? "Hide Photos" : "Show Photos", systemImage: "film") { visible.toggle() }
          .keyboardShortcut("/", modifiers: [])
        Button("Previous Photo", systemImage: "chevron.left") { workspace.navigate(-1) }.labelStyle(.iconOnly)
        Button("Next Photo", systemImage: "chevron.right") { workspace.navigate(1) }.labelStyle(.iconOnly)
        Spacer()
        Text("\(workspace.selection.count) of \(workspace.photos.count) selected").monospacedDigit()
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
              ForEach(workspace.photos) { photo in
                Button {
                  let flags = NSApp.currentEvent?.modifierFlags ?? []
                  workspace.select(photo.id, extending: flags.contains(.shift), toggling: flags.contains(.command))
                } label: {
                  thumbnail(photo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(photo.name)
                .accessibilityValue(workspace.activeID == photo.id ? "Active" : "")
                .accessibilityAddTraits(workspace.selection.contains(photo.id) ? .isSelected : [])
                .id(photo.id)
              }
            }
            .padding(8)
          }
          .frame(height: 105)
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
            Text(workspace.error == nil ? "Select a photo" : "The preview could not be opened.")
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
    }
    .frame(width: 111)
    .padding(5)
    .background(selected ? Color.accentColor.opacity(0.19) : .clear, in: RoundedRectangle(cornerRadius: 5))
    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? Color.accentColor : .clear, lineWidth: 2))
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
