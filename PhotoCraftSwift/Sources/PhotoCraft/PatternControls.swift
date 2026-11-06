import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct PatternNameDraft: Identifiable {
  enum Purpose {
    case define
    case rename(String)
    case renameNode(UUID)
    case group(UUID?)
  }
  let id = UUID()
  let purpose: Purpose
  var name: String
  var source: PatternDialogSource? = nil
}

extension EditorStore {
  func beginDefinePattern() {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil, !patterns.busy else { return }
    patternNameDraft = .init(purpose: .define, name: document.name, source: PatternDialogSource(self))
  }
  func definePattern(name: String) {
    guard !geometryBusy,!hasToneDraft,transformDraft==nil,!patterns.busy else{return}
    let original=document,source=PatternDialogSource(self),library=patterns
    geometryBusy=true;status="Define Pattern"
    geometryTask=Task{[weak self]in
      do {
        _=try await library.define(in:original,name:name,authorize:{[weak self]in self.map{source.matches($0)} ?? false})
        self?.bucketUsesPattern=true;self?.colorTab = .patterns;self?.status="Pattern saved: \(name)"
      }catch is CancellationError{self?.status="Pattern creation cancelled"}catch{self?.error=error.localizedDescription}
      self?.geometryBusy=false
    }
  }
  @discardableResult func patternAction(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void,Never> {
    Task { [weak self] in
      do { try await operation() } catch { self?.error = error.localizedDescription }
    }
  }
  func importPatterns() {
    guard !patterns.busy,!geometryBusy else{return}
    let source=PatternDialogSource(self),parent=selectedPatternGroup
    let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"pat") ?? .data]
    panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
    guard panel.runModal() == .OK,let url=panel.url else{return}
    patternAction{[weak self]in
      guard let self,source.matches(self)else{throw CraftError.invalid("The pattern import source changed. Try again.")}
      let data=try await Task.detached(priority:.userInitiated){try PatternLibrary.readFile(url)}.value
      try Task.checkCancellation()
      let count=try await self.patterns.importData(data,into:parent,authorize:{[weak self]in self.map{source.matches($0)} ?? false})
      self.colorTab = .patterns;self.status="Imported \(count) patterns with folder order retained"
    }
  }
  func exportPatterns(all:Bool) {
    guard !patterns.busy,!patterns.state.nodes.isEmpty else{return}
    let captured=patterns.state,source=PatternDialogSource(self)
    let selection=all ? nil:captured.selectedNodes
    guard all || !captured.selectedNodes.isEmpty else{return}
    let panel=NSSavePanel();panel.allowedContentTypes=[UTType(filenameExtension:"pat") ?? .data]
    panel.nameFieldStringValue=all ? "Photato Patterns.pat":"Selected Patterns.pat"
    guard panel.runModal() == .OK,let url=panel.url else{return}
    guard source.matches(self)else{error="The pattern export source changed. Try again.";return}
    patternAction {
      try await Task.detached(priority:.userInitiated) {
        let data=try PATCodec.writeLibrary(captured,selected:selection)
        try Task.checkCancellation();try data.write(to:url,options:.atomic)
      }.value
    }
  }
}

struct PatternNameSheet: View {
  @Bindable var store: EditorStore
  let draft: PatternNameDraft
  @State private var name: String
  init(store: EditorStore, draft: PatternNameDraft) {
    self.store = store
    self.draft = draft
    _name = State(initialValue: draft.name)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text({ if case .group = draft.purpose { return "Group Name" }; return "Pattern Name" }()).font(.headline)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder)
      if case .define = draft.purpose {
        Text(
          "Uses the visible image within the selection bounds, or the full canvas when no selection is active."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel") { store.patternNameDraft = nil }.keyboardShortcut(.cancelAction)
        Button("OK") {
          _ = store.commitPatternName(draft,name:name)
        }.keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width: 350)
  }
}

struct PatternSwatch: View {
  let pattern: RasterPattern
  @State private var image: CGImage?
  var body: some View {
    ZStack {
      Color(white: 0.65)
      Canvas { context, size in
        for y in 0..<8 {
          for x in 0..<8 where (x + y) % 2 == 0 {
            context.fill(
              Path(
                CGRect(
                  x: CGFloat(x) * size.width / 8, y: CGFloat(y) * size.height / 8,
                  width: size.width / 8, height: size.height / 8)),
              with: .color(.white.opacity(0.5)))
          }
        }
      }
      if let image { Image(decorative: image, scale: 1).resizable().interpolation(.none) }
    }.task(id: pattern) {
      let worker = Task.detached(priority: .utility) {
        let sampler = try PatternSampler(pattern)
        let step = max(1, Double(max(pattern.surface.width, pattern.surface.height)) / 64)
        var pixels = try Surface(width: 64, height: 64)
        for y in 0..<64 {
          try Task.checkCancellation()
          for x in 0..<64 {
            pixels.setPixel(
              x: x, y: y, sampler.tile(u: Double(x) * step + 0.5, v: Double(y) * step + 0.5))
          }
        }
        return try RasterIO.displayImage(pixels)
      }
      do {
        let result = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        image = result
      } catch {}
    }
  }
}

struct PatternsPanel: View {
  @Bindable var store: EditorStore
  var body: some View { PatternLibraryPanel(store:store) }
}

extension WorkspaceView {
  var bucketPatternPicker: some View {
    HStack(spacing: 4) {
      if let pattern = store.patterns.selected {
        PatternSwatch(pattern: pattern).frame(width: 24, height: 24)
      }
      Menu {
        ForEach(store.patterns.items) { pattern in
          Button(pattern.displayName) { store.patterns.selectedID = pattern.id }
        }
        Divider()
        Button("Open Patterns Panel") { store.colorTab = .patterns }
        Button("Import Patterns…") { store.importPatterns() }
      } label: {
        Text(store.patterns.selected?.displayName ?? "Choose Pattern").lineLimit(1).frame(
          maxWidth: 120)
      }.menuStyle(.borderlessButton)
    }.frame(width: 150).disabled(store.patterns.busy)
  }
}
