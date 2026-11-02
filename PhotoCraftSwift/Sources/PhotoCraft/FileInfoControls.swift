import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class FileInfoDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let initial: FileInformation
  let packetPreview: String
  var info: FileInformation
  var keywords: String
  var error: String?
  init(_ document: CraftDocument) throws {
    original = document; initial = try FileInfoMetadata.read(document); info = initial
    keywords = initial.keywords.joined(separator: "; ")
    let packet = try FileInfoMetadata.packet(document) ?? Data()
    packetPreview = String(decoding: packet.prefix(65_536), as: UTF8.self) + (packet.count > 65_536 ? "\n… Preview limited to 64 KB." : "")
  }
  func editedInfo() throws -> FileInformation {
    var result = info
    if keywords != initial.keywords.joined(separator: "; ") {
      result.keywords = keywords.split(whereSeparator: { $0 == ";" || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    try result.validate(); return result
  }
}

extension EditorStore {
  var canEditFileInfo: Bool { !geometryBusy && !aiBusy && !hasToneDraft && transformDraft == nil && historyOperation == nil }
  func beginFileInfo() {
    guard canEditFileInfo else { return }
    finishNumericField(); finishLayerName()
    do { fileInfoDraft = try FileInfoDraft(document) } catch { self.error = error.localizedDescription }
  }
  func commitFileInfo(_ draft: FileInfoDraft) {
    guard fileInfoDraft === draft, document == draft.original, !geometryBusy, !aiBusy else {
      draft.error = "The document changed. Reopen File Info."; return
    }
    do {
      let info = try draft.editedInfo()
      let updated = try FileInfoMetadata.applying(info, fields: info.changedFields(from: draft.initial), to: document)
      fileInfoDraft = nil
      try executeEditorCommand(.documentMetadata(updated.sourceMetadata))
    } catch { draft.error = error.localizedDescription; fileInfoDraft = draft }
  }
}

struct FileInfoSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: FileInfoDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("File Info — \(draft.original.name)").font(.title2)
      TabView {
        Form {
          TextField("Document Title", text: $draft.info.title)
          TextField("Author", text: $draft.info.author)
          TextField("Author Title", text: $draft.info.authorTitle)
          LabeledContent("Description") { TextEditor(text: $draft.info.description).frame(height: 95).border(.quaternary) }
          TextField("Keywords", text: $draft.keywords)
          Text("Separate authors and keywords with semicolons.").font(.caption).foregroundStyle(.secondary)
          Picker("Copyright Status", selection: $draft.info.copyrightStatus) {
            Text("Unknown").tag(FileInformation.CopyrightStatus.unknown)
            Text("Copyrighted").tag(FileInformation.CopyrightStatus.copyrighted)
            Text("Public Domain").tag(FileInformation.CopyrightStatus.publicDomain)
          }
          TextField("Copyright Notice", text: $draft.info.copyright)
          TextField("Copyright Info URL", text: $draft.info.copyrightUrl)
        }.padding(16).tabItem { Text("Description") }
        ScrollView { Text(draft.packetPreview.isEmpty ? "No XMP packet." : draft.packetPreview).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
          .tabItem { Text("Raw Data") }
      }
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Spacer()
        Button("Cancel") { store.fileInfoDraft = nil }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitFileInfo(draft) }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width: 640, height: 525)
  }
}

@MainActor extension AppDelegate {
  @objc func fileInfoDialog() { store?.beginFileInfo() }
}
