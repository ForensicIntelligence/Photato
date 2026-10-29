import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RecoverySalvageView: View {
  @Bindable var salvage: RecoverySalvage
  let export: (UUID, UUID, String) -> Void
  @State private var selection: UUID?
  @State private var resetRevision: UUID?
  @State private var confirmsReset = false
  @State private var error: String?
  private var selected: RecoverySalvageItem? { salvage.items.first { $0.id == selection } }
  private var ready: Bool { salvage.canScan && !salvage.isStale }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Find Recovery Copies").font(.title2)
        Spacer()
        if salvage.manager.isBusy { ProgressView().controlSize(.small) }
        Button("Scan") {
          let revision = salvage.revision
          run { try await salvage.scan(revision: revision) }
        }.disabled(!salvage.canScan)
      }
      Text("Search Photato’s private backup folder, even when its recovery index cannot be read. Nothing is restored automatically.")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if salvage.isStale { Text("Scan to refresh this list.").font(.caption) }
      List(selection: $selection) {
        ForEach(salvage.items) { item in
          VStack(alignment: .leading, spacing: 3) {
            Text(item.name).lineLimit(1)
            Text("\(item.registration.capitalized) · \(item.contextKind.capitalized) recovery metadata · "
              + ByteCountFormatter.string(fromByteCount: item.stamp.size, countStyle: .file))
              .font(.caption).foregroundStyle(.secondary)
          }.tag(item.id).padding(.vertical, 3)
        }
      }.frame(minHeight: 180)
      Text("\(salvage.examined) folder entries examined. Opening or saving a copy checks the complete document and leaves its original association behind.")
        .font(.caption).foregroundStyle(.secondary)
      if let message = error ?? salvage.lastError ?? salvage.manager.index.loadError {
        Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("Open Copy") {
          guard let selected else { return }
          let revision = salvage.revision
          run { _ = try await salvage.openCopy(selected.id, revision: revision, display: true) }
        }.disabled(!ready || selected == nil)
        Button("Save Copy…") {
          guard let selected else { return }
          export(selected.id, salvage.revision, selected.name)
        }.disabled(!ready || selected == nil)
        Spacer()
        Button("Reset Damaged Index…") {
          resetRevision = salvage.revision; confirmsReset = true
        }.disabled(!salvage.canResetIndex)
      }
      Text("Reset requires a fresh scan, an unreadable index and all documents closed. It preserves the old index and every backup file, then starts an empty index for future recovery. Existing backups stay available here as copies.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(20).frame(minWidth: 720, minHeight: 430)
    .alert("Reset the damaged recovery index?", isPresented: $confirmsReset) {
      Button("Cancel", role: .cancel) {}
      Button("Preserve and Reset", role: .destructive) {
        guard let revision = resetRevision else { return }
        run { try await salvage.resetIndex(revision: revision) }
      }
    } message: {
      Text("The old index is kept as a separate file. No backups or originals are deleted. Existing backup registrations will not be restored automatically.")
    }
  }
  private func run<T>(_ operation: @escaping @MainActor () async throws -> T) {
    error = nil
    Task { @MainActor in
      await Task.yield()
      do { _ = try await operation() }
      catch { self.error = "The operation did not finish. Scan again and review the current files." }
    }
  }
}

@MainActor final class RecoverySalvageWindowController: NSWindowController {
  let salvage: RecoverySalvage
  private var panel: NSSavePanel?
  init(controller: CraftDocumentController) {
    salvage = controller.recoveryMaintenance.salvage
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Photato — Find Recovery Copies"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(rootView: RecoverySalvageView(salvage: salvage) {
      [weak self] id, revision, name in self?.save(id, revision: revision, name: name)
    })
    window.center()
  }
  required init?(coder: NSCoder) { nil }
  private func save(_ id: UUID, revision: UUID, name: String) {
    guard panel == nil, let window else { return }
    let chooser = NSSavePanel()
    chooser.title = "Save Recovery Copy"
    chooser.allowedContentTypes = [UTType("local.photocraft.swift.document") ?? .data]
    chooser.nameFieldStringValue = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + "-recovered.photato"
    panel = chooser
    chooser.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      self.panel = nil
      guard response == .OK, let url = chooser.url else { return }
      Task { @MainActor in
        await Task.yield()
        do { try await self.salvage.saveCopy(id, revision: revision, to: url) }
        catch { NSApp.presentError(error) }
      }
    }
  }
}

@MainActor extension CraftDocumentController {
  func showRecoverySalvage() {
    if recoverySalvageWindow?.window?.isVisible != true { recoverySalvageWindow = .init(controller: self) }
    recoverySalvageWindow?.showWindow(nil)
    recoverySalvageWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
