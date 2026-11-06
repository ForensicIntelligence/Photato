import AppKit
import SwiftUI

struct AutomationView: View {
  let service: AutomationService
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Label("Photato Automation API", systemImage: "network").font(.title2).fontWeight(.semibold)
        Text(
          "Connect a browser or local client to the native editor. Shared documents can be read and edited; edits use the same undo history as Photato."
        )
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Circle().fill(service.isRunning ? .green : .secondary).frame(width: 8, height: 8)
          Text(service.endpoint ?? (service.starting ? "Starting…" : "Off"))
            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            .accessibilityLabel("API endpoint")
            .accessibilityValue(service.endpoint ?? (service.starting ? "Starting" : "Off"))
            .id(service.endpoint ?? (service.starting ? "starting" : "off"))
          Spacer()
          if service.isRunning || service.starting {
            Button("Stop API") { service.stop() }
          } else {
            Button("Start API") { service.start() }
          }
        }
        HStack {
          Button("Copy Session Token") { service.copyToken() }.disabled(!service.isRunning)
          Button("Open Browser Client") {
            if let endpoint = service.endpoint, let url = URL(string: endpoint) {
              NSWorkspace.shared.open(url)
            }
          }.disabled(!service.isRunning)
        }
        Divider()
        Toggle(
          "Enable resource action jobs",
          isOn: Binding(
            get: { service.resourceJobsEnabled },
            set: { service.setResourceJobsEnabled($0) })
        )
        .disabled(!service.isRunning)
        Text(
          "Allows token holders to fetch input URLs and write requested output URLs from this Mac. Jobs use separate documents. Disabling revokes jobs and hosted outputs; completed remote uploads remain."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle(
          "Allow document transfers, Revert and opening cancellation",
          isOn: Binding(
            get: { service.documentTransfersEnabled },
            set: { service.setDocumentTransfersEnabled($0) })
        ).disabled(!service.isRunning)
        Text(
          "Uploads open new shared documents. Clients can cancel a native document-opening operation by its ID. Downloads copy shared documents as Photato, PSD, PNG, JPEG or TIFF. Revert restores a shared document’s saved file and can be undone. Transfers cannot choose local file paths or overwrite your files. Local saving has its own permission below."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        LinkedSourcePermissionsView(service:service)
        Divider()
        Toggle("Allow printing", isOn: Binding(get: { service.printingEnabled }, set: { service.setPrintingEnabled($0) })).disabled(!service.isRunning)
        Text("Allows clients to open print controls or submit jobs for shared documents. Turning this off cancels preparation; submitted jobs remain in the macOS print queue. PDF output does not require this permission.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle(
          "Allow local document saving",
          isOn: Binding(
            get: { service.documentSavesEnabled }, set: { service.setDocumentSavesEnabled($0) })
        ).disabled(!service.isRunning)
        Text(
          "Allows clients to overwrite associated files of shared documents. Save As writes only inside the folder you select; clients can explicitly request replacement there. Saving changes the document’s file association and clears its modified flag."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Choose Save As Folder…") { service.chooseSaveDirectory() }.disabled(
            !service.isRunning)
          Text(service.saveDirectoryURL?.lastPathComponent ?? "No folder selected").lineLimit(1)
          if service.saveDirectoryURL != nil { Button("Clear") { service.setSaveDirectory(nil) } }
        }
        Divider()
        Toggle("Allow recent-file access", isOn: Binding(
          get: { service.recentFilesEnabled }, set: { service.setRecentFilesEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows clients to see recent filenames, open files from that list, clear the list and change its size. Opening does not share a document. This permission turns off when the API stops.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle(
          "Allow recovery preference changes",
          isOn: Binding(
            get: { service.preferenceChangesEnabled },
            set: { service.setPreferenceChangesEnabled($0) })
        ).disabled(!service.isRunning)
        Text(
          "Allows clients to enable or disable automatic recovery and change its interval for all documents. This permission turns off when the API stops."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Allow workspace panel changes", isOn: Binding(
          get: { service.workspacePanelChangesEnabled }, set: { service.setWorkspacePanelChangesEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows clients to show, hide and arrange panels in the shared saved workspace. This affects all open documents and turns off when the API stops.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Allow Color Settings changes", isOn: Binding(
          get: { service.colorSettingsChangesEnabled }, set: { service.setColorSettingsChangesEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows clients to change working profiles and conversion defaults. This permission turns off when the API stops.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Allow Photoshop file preference changes", isOn: Binding(
          get: { service.photoshopPreferenceChangesEnabled },
          set: { service.setPhotoshopPreferenceChangesEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows clients to change the default compression of 16-bit and 32-bit PSD/PSB saves. Explicit output choices still apply. This permission turns off when the API stops.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Allow recovery management", isOn: Binding(
          get: { service.recoveryManagementEnabled },
          set: { service.setRecoveryManagementEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows retrying recovery and cancelling active recovery, including startup. Recovered documents remain unshared. Turning this off cancels this API session’s retry. This permission turns off when the API stops.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Allow recovery-backup access", isOn: Binding(
          get: { service.recoveryBackupsEnabled },
          set: { service.setRecoveryBackupsEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows backup names and contents, scanning for recovery copies, explicit backup cleanup and confirmed damaged-index reset. Copies remain unshared. This permission turns off when the API stops.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Allow document closing and Quit", isOn: Binding(
          get: { service.documentClosingEnabled },
          set: { service.setDocumentClosingEnabled($0) }
        )).disabled(!service.isRunning)
        Text("Allows clients to close documents, including unshared documents, discard unsaved changes, and quit Photato. Automatic saving also requires local-saving permission and shared source documents. Turning this off cancels remaining close work.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        HStack {
          Text("Shared documents").font(.headline)
          Spacer()
          Button("Share Current Document") {
            guard let document = service.controller.currentDocument as? CraftNSDocument else {
              service.message = "Select a Photato document first."
              return
            }
            do { try service.share(document) } catch let error as AutomationFailure {
              service.message = error.message
            } catch { service.message = error.localizedDescription }
          }.disabled(!service.isRunning)
        }
        if service.shares.isEmpty {
          Text("No documents shared").foregroundStyle(.secondary).frame(
            maxWidth: .infinity, minHeight: 48)
        } else {
          ScrollView {
            VStack(spacing: 8) {
              ForEach(service.shares) { share in
                HStack {
                  Image(systemName: "doc")
                  Text(share.document?.displayName ?? "Closed document").lineLimit(1)
                  Spacer()
                  Button("Revoke") { service.revoke(share.id) }
                }
              }
            }
          }.frame(maxHeight: 130)
        }
        Text(service.message).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true).accessibilityLabel(
            "API status: \(service.message)")
        Divider()
        Text(
          "Local access only • Off on every launch\nClosing this window keeps the API running. Stopping revokes all shares and tokens. Treat the copied token as a password. The document API supports \(AutomationCommand.definitions.count) commands and documents up to 4 megapixels, 8,000 layers and 128 MiB."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.padding(24).frame(width: 570)
    }.frame(width: 570, height: 700)
      .task {
        while !Task.isCancelled {
          service.prune()
          try? await Task.sleep(for: .seconds(1))
        }
      }
  }
}
