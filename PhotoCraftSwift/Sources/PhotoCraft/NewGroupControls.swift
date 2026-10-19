import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class NewGroupDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let children: Set<UUID>
  let below: Bool
  var options: NewLayerGroupOptions
  var opacityText = "100"
  var error: String?
  init(document: CraftDocument, children: Set<UUID>, below: Bool) {
    original = document
    self.children = children
    self.below = below
    options = .init(name: document.suggestedGroupName)
  }
  var validatedOptions: NewLayerGroupOptions? {
    guard let percent = Float(opacityText), percent.isFinite, (0...100).contains(percent),
      !options.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      options.name.utf16.count <= 65_535
    else { return nil }
    var result = options
    result.opacity = percent / 100
    return result
  }
}

extension EditorStore {
  var groupSelectionIDs: Set<UUID> {
    selectedLayerIDs.isEmpty ? Set(document.activeLayerID.map { [$0] } ?? []) : selectedLayerIDs
  }
  func canCreateGroup(fromSelection: Bool = false, below: Bool = false) -> Bool {
    guard canBeginLayerCreation, !fromSelection || !groupSelectionIDs.isEmpty else { return false }
    var candidate = document
    return
      (try? Command.newGroup(
        .init(name: "Group"),
        children: fromSelection ? Array(groupSelectionIDs) : [], below: below
      ).apply(to: &candidate)) != nil
  }
  func beginNewGroup(fromSelection: Bool = false, below: Bool = false) {
    finishLayerName()
    guard canCreateGroup(fromSelection: fromSelection, below: below) else { return }
    newGroupDraft = NewGroupDraft(
      document: document,
      children: fromSelection ? groupSelectionIDs : [], below: below)
  }
  func cancelNewGroup() { newGroupDraft = nil }
  func commitNewGroup(_ draft: NewGroupDraft) {
    guard newGroupDraft === draft, let options = draft.validatedOptions else { return }
    guard document == draft.original,
      draft.children.isEmpty || draft.children == groupSelectionIDs,
      !geometryBusy, transformDraft == nil
    else {
      draft.error = "The document or layer selection changed. Cancel and reopen New Group."
      return
    }
    newGroupDraft = nil
    guard canCreateGroup(fromSelection: !draft.children.isEmpty, below: draft.below) else {
      draft.error = "Finish the current edit before creating a group."
      newGroupDraft = draft
      return
    }
    error = nil
    perform(.newGroup(options, children: Array(draft.children), below: draft.below))
    if let error {
      draft.error = error
      self.error = nil
      newGroupDraft = draft
    } else {
      finishGroupCreation()
    }
  }
  func finishGroupCreation() {
    maskEditingLayerID = nil
    selectPath(nil)
  }
  func createGroupFromFooter(modifiers: NSEvent.ModifierFlags) {
    let fromSelection = modifiers.contains(.shift)
    // Shift requests grouping, whose position follows its selected roots.
    let below = !fromSelection && modifiers.contains(.command)
    if modifiers.contains(.option) {
      beginNewGroup(fromSelection: fromSelection, below: below)
    } else if fromSelection {
      groupSelection()
    } else {
      newGroup(below: below)
    }
  }
}

struct NewGroupSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: NewGroupDraft
  @FocusState private var nameFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(draft.children.isEmpty ? "New Group" : "New Group from Layers").font(.headline)
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text("Name:").frame(width: 48, alignment: .trailing)
            TextField("Name", text: $draft.options.name).labelsHidden()
              .focused($nameFocused).accessibilityIdentifier("newGroup.name")
          }
          HStack {
            Text("Color:").frame(width: 48, alignment: .trailing)
            Picker("Color", selection: $draft.options.color) {
              ForEach(LayerColorLabel.allCases, id: \.self) { color in
                HStack {
                  Image(systemName: "square.fill").foregroundStyle(color.swatch)
                  Text(color.title)
                }.tag(color)
              }
            }.labelsHidden().frame(width: 158).accessibilityIdentifier("newGroup.color")
            Spacer(minLength: 0)
          }
          HStack {
            Text("Mode:").frame(width: 48, alignment: .trailing)
            Picker("Mode", selection: $draft.options.mode) {
              Text("Pass Through").tag(Optional<PhotoCraftCore.BlendMode>.none)
              ForEach(BlendMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(Optional(mode))
              }
            }.labelsHidden().frame(width: 158).accessibilityIdentifier("newGroup.mode")
            Text("Opacity:")
            TextField("Opacity", text: $draft.opacityText).labelsHidden().frame(width: 48)
              .multilineTextAlignment(.trailing).accessibilityIdentifier("newGroup.opacity")
            Text("%")
          }
        }
        VStack(spacing: 10) {
          Button("OK") { store.commitNewGroup(draft) }.keyboardShortcut(.defaultAction)
            .disabled(draft.validatedOptions == nil).frame(width: 76)
          Button("Cancel") { store.cancelNewGroup() }.keyboardShortcut(.cancelAction).frame(
            width: 76)
        }
      }
      if let error = draft.error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(20).frame(width: 560).font(.system(size: 12)).controlSize(.small)
      .onAppear { nameFocused = true }
  }
}

extension AppDelegate {
  /// Offscreen native content for layout review; this is not a live UI check.
  func newGroupSnapshot() {
    do {
      let store = EditorStore(document: try CraftDocument(width: 3, height: 2))
      store.renderTask?.cancel()
      let fromSelection = CommandLine.arguments.contains("--snapshot-group-from-layers")
      store.beginNewGroup(fromSelection: fromSelection)
      guard let draft = store.newGroupDraft else { return }
      if fromSelection {
        draft.options.name = "Color Grade"
        draft.options.mode = .normal
        draft.options.color = .orange
        draft.opacityText = "65"
      }
      let host = NSHostingView(
        rootView: NewGroupSheet(store: store, draft: draft)
          .background(StudioTheme.panel).preferredColorScheme(.dark))
      host.frame = .init(x: 0, y: 0, width: 560, height: 200)
      let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = host
      window.appearance = NSAppearance(named: .darkAqua)
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [window, host] in
        do {
          window.layoutIfNeeded()
          host.layoutSubtreeIfNeeded()
          guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CraftError.invalid("New Group snapshot allocation failed.")
          }
          host.cacheDisplay(in: host.bounds, to: rep)
          guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CraftError.invalid("New Group snapshot encoding failed.")
          }
          let path = CommandLine.arguments.last ?? "/private/tmp/photato-new-group.png"
          try data.write(to: URL(fileURLWithPath: path))
          print("Offscreen New Group snapshot: \(path)")
        } catch { print("New Group snapshot failed: \(error)") }
        NSApp.terminate(nil)
      }
    } catch {
      print("New Group snapshot setup failed: \(error)")
      NSApp.terminate(nil)
    }
  }
}
