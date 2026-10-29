import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RecoveryMaintenanceView: View {
  struct Confirmation: Identifiable {
    let id: UUID
    let revision: UUID
    let name: String
    let trash: Bool
  }
  @Bindable var manager: RecoveryMaintenance
  let export: (UUID, UUID, String) -> Void
  @State private var selection: UUID?
  @State private var confirmation: Confirmation?
  @State private var error: String?
  private var item: RecoveryBackupItem? { manager.items.first { $0.id == selection } }
  private var ready: Bool { manager.canStart && !manager.isStale }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Recovery Backups").font(.title2)
        Spacer()
        if manager.isBusy { ProgressView().controlSize(.small) }
        Button("Refresh") { run { try await manager.refresh() } }.disabled(!manager.canStart)
      }
      Text("\(manager.index.entries.count) of \(RecoveryIndexStore.maximumEntries) recovery records used")
        .font(.caption).foregroundStyle(.secondary)
      if manager.isStale {
        Text("Refresh to inspect the current backups.").foregroundStyle(.secondary)
      }
      List(selection: $selection) {
        ForEach(manager.items) { row in
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(row.name).lineLimit(1)
              Spacer()
              Text(row.status.rawValue.capitalized).font(.caption)
            }
            HStack {
              Text(row.registration == .retired ? "Retired" : "Recovery snapshot")
              if manager.isOpen(row.id) { Text("· In use by an open document") }
              if let bytes = row.bytes {
                Text("· " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
              }
              if let date = row.modified { Text(date, style: .date) }
            }.font(.caption).foregroundStyle(.secondary)
          }.tag(row.id).padding(.vertical, 3)
        }
      }.frame(minHeight: 190)
      Text("Available means the backup metadata matches. Open Copy and Save Copy also check the complete document. Original files stay separate.")
        .font(.caption).foregroundStyle(.secondary)
      if let message = error ?? manager.lastError ?? manager.index.loadError {
        Text(message).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("Open Copy") {
          guard let item else { return }
          let revision = manager.index.revision
          run { _ = try await manager.openCopy(item.id, revision: revision, display: true) }
        }.disabled(!ready || item?.status != .available)
        Button("Save Copy…") {
          guard let item else { return }
          export(item.id, manager.index.revision, item.name)
        }.disabled(!ready || item?.status != .available)
        Spacer()
        Button("Move to Trash…") { confirm(trash: true) }
          .disabled(!ready || item?.status != .available || item.map { manager.isOpen($0.id) } != false)
        Button("Forget Record…") { confirm(trash: false) }
          .disabled(!ready || item == nil || item.map { manager.isOpen($0.id) } != false)
      }
      Button("Remove Missing Records") {
        let revision = manager.index.revision
        run { try await manager.removeMissing(revision: revision) }
      }.disabled(!ready || !manager.items.contains { $0.status == .missing && !manager.isOpen($0.id) })
    }
    .padding(20).frame(minWidth: 720, minHeight: 400)
    .alert(item: $confirmation) { value in
      Alert(title: Text(value.trash ? "Move this backup to Trash?" : "Forget this recovery record?"),
        message: Text(value.trash
          ? "\(value.name) will stop recovering automatically. Its backup can be restored from Trash. The original file is unaffected."
          : "\(value.name) will stop recovering automatically through Photato's index. Its backup file stays on disk, but this list cannot undo removal of the record."),
        primaryButton: .destructive(Text(value.trash ? "Move to Trash" : "Forget Record")) {
          run {
            if value.trash { _ = try await manager.trash(value.id, revision: value.revision) }
            else { try await manager.forget(value.id, revision: value.revision) }
          }
        }, secondaryButton: .cancel())
    }
  }
  private func confirm(trash: Bool) {
    guard let item else { return }
    confirmation = .init(id: item.id, revision: manager.index.revision, name: item.name, trash: trash)
  }
  private func run<T>(_ operation: @escaping @MainActor () async throws -> T) {
    error = nil
    Task { @MainActor in
      await Task.yield()
      do { _ = try await operation() }
      catch {
        self.error = (error as? RecoveryIndexFailure)?.localizedDescription
          ?? "The backup operation did not finish. Refresh the list and try again."
      }
    }
  }
}

@MainActor final class RecoveryMaintenanceWindowController: NSWindowController {
  let manager: RecoveryMaintenance
  private var savePanel: NSSavePanel?
  init(controller: CraftDocumentController) {
    manager = controller.recoveryMaintenance
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 470),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Photato — Recovery Backups"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(rootView: RecoveryMaintenanceView(manager: manager) { [weak self] id, revision, name in
      self?.saveCopy(id, revision: revision, name: name)
    })
    window.center()
  }
  required init?(coder: NSCoder) { nil }
  private func saveCopy(_ id: UUID, revision: UUID, name: String) {
    guard savePanel == nil, let window else { return }
    let panel = NSSavePanel()
    panel.title = "Save Recovery Copy"
    panel.allowedContentTypes = [UTType("local.photocraft.swift.document") ?? .data]
    panel.nameFieldStringValue = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + "-recovered.photato"
    savePanel = panel
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      self.savePanel = nil
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        await Task.yield()
        do { try await self.manager.saveCopy(id, revision: revision, to: url) }
        catch { NSApp.presentError(error) }
      }
    }
  }
}

@MainActor extension CraftDocumentController {
  func showRecoveryMaintenance() {
    if recoveryMaintenanceWindow?.window?.isVisible != true {
      recoveryMaintenanceWindow = .init(controller: self)
    }
    recoveryMaintenanceWindow?.showWindow(nil)
    recoveryMaintenanceWindow?.window?.makeKeyAndOrderFront(nil)
    if recoveryMaintenance.canStart {
      Task { try? await recoveryMaintenance.refresh() }
    }
  }
}
