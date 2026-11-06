import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct GradientNameDraft: Identifiable {
  enum Purpose {
    case save(GradientDefinition, UUID?)
    case group(UUID?)
    case rename(UUID)
  }
  let id = UUID()
  let purpose: Purpose
  var name: String
  var title: String {
    switch purpose {
    case .save: "New Gradient Preset"
    case .group: "New Gradient Group"
    case .rename: "Rename Gradient Entry"
    }
  }
}

extension EditorStore {
  var gradientPresetDestination: UUID? {
    guard gradients.state.selected.count == 1, let id = gradients.state.selected.first else {
      return nil
    }
    if gradients.state.node(id)?.children != nil { return id }
    return gradientParent(of: id)
  }
  func gradientParent(of id: UUID) -> UUID? {
    func find(_ nodes: [GradientLibraryNode], parent: UUID?) -> UUID? {
      for node in nodes {
        if node.id == id { return parent }
        if let found = find(node.children ?? [], parent: node.id) { return found }
      }
      return nil
    }
    return find(gradients.state.nodes, parent: nil)
  }
  var gradientForPreset: GradientDefinition {
    if let draft = gradientMapDraft { return draft.adjustment.gradient }
    if case .adjustment(.gradientMap(let settings)) = activeLayer?.content {
      return settings.gradient
    }
    if let draft = gradientFillDraft { return draft.fill.gradient }
    if case .gradientFill(let fill) = activeLayer?.content { return fill.gradient }
    return gradientOptions.gradient
  }
  func beginSaveGradientPreset() {
    guard !geometryBusy, !gradients.busy else { return }
    let gradient = gradientForPreset
    gradientNameDraft = .init(
      purpose: .save(gradient, gradientPresetDestination), name: gradient.name)
  }
  func gradientLibraryAction(_ operation: @escaping @MainActor () async throws -> Void) {
    gradientLibraryTask = Task { [weak self] in
      do { try await operation() } catch is CancellationError {
        self?.status = "Gradient library operation cancelled"
      } catch { self?.error = error.localizedDescription }
    }
  }
  func chooseGradientPreset(_ id: UUID, modifiers: NSEvent.ModifierFlags = [], creationOnly: Bool = false) {
    guard !gradients.busy, let node = gradients.state.node(id) else { return }
    var ids = Set([id])
    if modifiers.contains(.shift), let anchor = gradientSelectionAnchor {
      func flatten(_ nodes: [GradientLibraryNode]) -> [UUID] {
        nodes.flatMap { [$0.id] + flatten($0.children ?? []) }
      }
      let order = flatten(gradients.state.nodes)
      if let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
        ids = Set(order[min(a, b)...max(a, b)])
      }
    } else if modifiers.contains(.command) {
      ids = gradients.state.selected
      if !ids.insert(id).inserted { ids.remove(id) }
    } else {
      gradientSelectionAnchor = id
    }
    let preset = gradients.state.presets[id]
    let activeID = activeLayer?.id
    let fillDraftID = gradientFillDraft?.sessionID
    let mapDraftID = gradientMapDraft?.sessionID
    let optionRevision = gradientOptionsRevision
    let ownerSession = sessionGeneration
    let ownerTool = tool
    let colors = (brush.color, backgroundColor)
    let selected = ids
    let active = node.children == nil && ids.contains(id) ? id : nil
    gradientLibraryAction { [weak self] in
      guard let self else { return }
      try await self.gradients.select(selected, active: active)
      guard active != nil, let preset else { return }
      guard let gradient = preset.gradient else {
        self.status =
          preset.unavailableReason ?? "This gradient is preserved but cannot yet be rendered."
        return
      }
      if creationOnly {
        guard self.sessionGeneration==ownerSession,self.tool==ownerTool,self.gradientOptionsRevision==optionRevision,
          self.canConfigureGradientCreation else{return}
        var options=self.gradientOptions;options.gradient=gradient
        try self.setGradientCreationOptions(options)
        return
      }
      // A delayed disk write must not apply a preset to a different layer or a later draft.
      if let mapDraftID, self.gradientMapDraft?.sessionID == mapDraftID {
        self.gradientMapDraft?.adjustment.gradient = try gradient.resolved(
          foreground: colors.0, background: colors.1)
        self.render()
      } else if let fillDraftID, self.gradientFillDraft?.sessionID == fillDraftID {
        self.chooseGradient(try gradient.resolved(foreground: colors.0, background: colors.1))
      } else if fillDraftID == nil, mapDraftID == nil, self.activeLayer?.id == activeID,
        self.gradientFillDraft == nil, !self.hasToneDraft
      {
        self.gradientOptions.gradient = gradient
        if let layer = self.activeLayer, case .gradientFill(var fill) = layer.content {
          fill.gradient = try gradient.resolved(foreground: colors.0, background: colors.1)
          self.performGeometry(.setGradientFill(layer.id, fill))
        } else if let layer = self.activeLayer,
          case .adjustment(.gradientMap(var value)) = layer.content
        {
          value.gradient = try gradient.resolved(foreground: colors.0, background: colors.1)
          self.setGradientMap(layer.id, value)
        }
      } else {
        self.gradientOptions.gradient = gradient
      }
    }
  }
  func activateGradientPreset(_ id: UUID) {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil, !gradients.busy,
      let preset = gradients.state.presets[id]
    else { return }
    guard let gradient = preset.gradient else {
      status = preset.unavailableReason ?? "This gradient cannot yet be rendered."
      return
    }
    do {
      let fill = GradientFill(
        gradient: try gradient.resolved(foreground: brush.color, background: backgroundColor))
      performGeometry(
        .addGradientFill(
          Layer(name: "Gradient Fill", content: .gradientFill(fill)), document.selection != nil))
      gradientOptions.gradient = gradient
      gradientLibraryAction { [weak self] in try await self?.gradients.select([id], active: id) }
    } catch { self.error = error.localizedDescription }
  }
  func gradientCanvasDrop(_ value: String) -> UUID? {
    guard canBeginGradientFill, !gradients.busy, value.hasPrefix("photato-gradients:") else {
      return nil
    }
    let items = value.dropFirst("photato-gradients:".count).split(separator: ",")
    guard items.count == 1, let id = UUID(uuidString: String(items[0])),
      gradients.state.presets[id]?.gradient != nil
    else { return nil }
    return id
  }
  func finishGradientName(_ draft: GradientNameDraft, name: String) {
    gradientNameDraft = nil
    gradientLibraryAction { [weak self] in
      guard let self else { return }
      try await self.gradients.edit { state in
        switch draft.purpose {
        case .save(var gradient, let parent):
          gradient.name = name
          try state.add(gradient, into: parent)
        case .group(let parent): try state.group(name, into: parent)
        case .rename(let id): try state.rename(id, to: name)
        }
      }
      self.colorTab = .gradients
      self.status = "Gradient library saved"
    }
  }
  func importGradients() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "grd") ?? .data]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let parent = gradientPresetDestination
    gradientLibraryAction { [weak self] in
      guard let self else { return }
      try await self.gradients.importFile(url, into: parent)
      self.colorTab = .gradients
      self.status = "Imported \(url.lastPathComponent)"
    }
  }
  func exportGradients(selected: Bool) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "grd") ?? .data]
    let name =
      selected && gradients.state.selected.count == 1
      ? gradients.state.selected.first.flatMap { gradients.state.name($0) } : nil
    panel.nameFieldStringValue = (name ?? "Photato Gradients") + ".grd"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    gradientLibraryAction { [weak self] in
      try await self?.gradients.exportFile(url, selected: selected)
    }
  }
  func removeGradientPresets() {
    let ids = gradients.state.selected
    gradientLibraryAction { [weak self] in try await self?.gradients.edit { try $0.remove(ids) } }
  }
  func moveGradientPresets(_ ids: Set<UUID>, into parent: UUID?, before: UUID? = nil) {
    gradientLibraryAction { [weak self] in
      try await self?.gradients.edit { try $0.move(ids, into: parent, before: before) }
    }
  }
}

struct GradientNameSheet: View {
  @Bindable var store: EditorStore
  let draft: GradientNameDraft
  @State private var name: String
  init(store: EditorStore, draft: GradientNameDraft) {
    self.store = store
    self.draft = draft
    _name = State(initialValue: draft.name)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(draft.title).font(.headline)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel") { store.gradientNameDraft = nil }.keyboardShortcut(.cancelAction)
        Button("OK") { store.finishGradientName(draft, name: name) }.keyboardShortcut(
          .defaultAction
        )
        .disabled(
          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.gradients.busy)
      }
    }.padding(24).frame(width: 350)
  }
}

struct GradientsPanel: View {
  @Bindable var store: EditorStore
  var compact = false
  var creationOnly = false
  @State private var search = ""
  @State private var collapsed: Set<UUID> = []
  private struct Row: Identifiable {
    var node: GradientLibraryNode
    var depth: Int
    var id: UUID { node.id }
  }
  private struct Destination: Identifiable {
    var id: UUID
    var path: String
  }
  private var destinations: [Destination] {
    func collect(_ nodes: [GradientLibraryNode], path: String) -> [Destination] {
      nodes.flatMap { node -> [Destination] in
        guard case .folder(let id, let name, let children) = node else { return [] }
        let next = path.isEmpty ? name : path + " / " + name
        return [Destination(id: id, path: next)] + collect(children, path: next)
      }
    }
    return collect(store.gradients.state.nodes, path: "")
  }
  private var rows: [Row] {
    let state = store.gradients.state
    let presets = state.presets
    func matches(_ node: GradientLibraryNode) -> Bool {
      let name: String
      switch node {
      case .preset(let id): name = presets[id]?.name ?? ""
      case .folder(_, let title, _): name = title
      }
      return search.isEmpty || name.localizedCaseInsensitiveContains(search)
        || node.children?.contains(where: matches) == true
    }
    func flatten(_ nodes: [GradientLibraryNode], depth: Int, includeAll: Bool = false) -> [Row] {
      nodes.flatMap { node -> [Row] in
        guard includeAll || matches(node) else { return [] }
        let ownMatch: Bool
        if case .folder(_, let name, _) = node {
          ownMatch = !search.isEmpty && name.localizedCaseInsensitiveContains(search)
        } else {
          ownMatch = false
        }
        let children = search.isEmpty && collapsed.contains(node.id) ? [] : (node.children ?? [])
        return [Row(node: node, depth: depth)]
          + flatten(
            children, depth: depth + 1,
            includeAll: includeAll || ownMatch)
      }
    }
    return flatten(state.nodes, depth: 0)
  }
  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 5) {
        TextField("Search gradients", text: $search).textFieldStyle(.roundedBorder)
        Menu {
          libraryMenu
        } label: {
          Image(systemName: "line.3.horizontal")
        }
        .menuStyle(.borderlessButton).frame(width: 22).accessibilityLabel("Gradient library menu")
      }
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(rows) { row in entry(row) }
          if rows.isEmpty {
            Text("Save or import a gradient to get started.").font(.caption).foregroundStyle(
              .secondary)
          }
        }
      }
      .dropDestination(for: String.self) { values, _ in receive(values, parent: nil, before: nil) }
      if let id = store.gradients.state.selected.first, store.gradients.state.selected.count == 1,
        let preset = store.gradients.state.presets[id], let reason = preset.unavailableReason
      {
        Text(reason).font(.caption).foregroundStyle(.orange).lineLimit(3)
      }
      if let error = store.gradients.error {
        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
      }
      HStack(spacing: 9) {
        Text("\(store.gradients.state.library.presets.count) gradients").font(.caption)
          .foregroundStyle(.secondary)
        if store.gradients.busy {
          ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12)
        }
        Spacer()
        Button {
          newGroup()
        } label: {
          Image(systemName: "folder.badge.plus")
        }.help("New Gradient Group")
        Button {
          store.beginSaveGradientPreset()
        } label: {
          Image(systemName: "plus.square")
        }.help("Save Gradient Preset")
        Button {
          store.removeGradientPresets()
        } label: {
          Image(systemName: "trash")
        }
        .disabled(store.gradients.state.selected.isEmpty).help(
          "Delete selected gradients or groups")
      }.buttonStyle(.plain)
    }.font(.system(size: 11)).padding(8)
      .disabled(store.gradients.busy)
  }
  private func entry(_ row: Row) -> some View {
    let node = row.node
    let preset = store.gradients.state.presets[node.id]
    return HStack(spacing: 7) {
      if node.children != nil {
        Button {
          if !collapsed.insert(node.id).inserted { collapsed.remove(node.id) }
        } label: {
          Image(systemName: collapsed.contains(node.id) ? "chevron.right" : "chevron.down").frame(
            width: 11)
        }
        .buttonStyle(.plain).accessibilityLabel("Expand or collapse gradient group")
        Image(systemName: "folder")
      } else if let gradient = preset?.gradient {
        GradientSwatch(
          gradient: (try? gradient.resolved(
            foreground: store.brush.color,
            background: store.backgroundColor)) ?? .blackToWhite
        )
        .frame(width: compact ? 65 : 46, height: 21)
      } else {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).frame(
          width: 46, height: 21)
      }
      Text(store.gradients.state.name(node.id) ?? "Gradient").lineLimit(1)
      Spacer(minLength: 0)
    }.padding(.leading, CGFloat(min(row.depth, 12) * 10)).padding(.horizontal, 5).padding(
      .vertical, 3
    )
    .background(store.gradients.state.selected.contains(node.id) ? StudioTheme.selected : .clear)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      if creationOnly {store.chooseGradientPreset(node.id,creationOnly:true)}else{store.activateGradientPreset(node.id)}
    }
    .onTapGesture { store.chooseGradientPreset(node.id, modifiers: NSEvent.modifierFlags, creationOnly: creationOnly) }
    .help(preset?.unavailableReason ?? store.gradients.state.name(node.id) ?? "Gradient group")
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { store.chooseGradientPreset(node.id) }
    .contextMenu { entryMenu(node) }
    .onDrag {
      let ids =
        store.gradients.state.selected.contains(node.id)
        ? store.gradients.state.selected : [node.id]
      return NSItemProvider(
        object: ("photato-gradients:" + ids.map(\.uuidString).sorted().joined(separator: ","))
          as NSString)
    }
    .dropDestination(for: String.self) { values, _ in
      receive(
        values, parent: node.children == nil ? store.gradientParent(of: node.id) : node.id,
        before: node.children == nil ? node.id : nil)
    }
  }
  private func receive(_ values: [String], parent: UUID?, before: UUID?) -> Bool {
    guard !store.gradients.busy, let value = values.first, value.hasPrefix("photato-gradients:")
    else { return false }
    let ids = Set(
      value.dropFirst("photato-gradients:".count).split(separator: ",").compactMap {
        UUID(uuidString: String($0))
      })
    guard !ids.isEmpty, ids.allSatisfy({ store.gradients.state.node($0) != nil }) else {
      return false
    }
    store.moveGradientPresets(ids, into: parent, before: before)
    return true
  }
  private func newGroup() {
    store.gradientNameDraft = .init(
      purpose: .group(store.gradientPresetDestination), name: "New Group")
  }
  @ViewBuilder private var libraryMenu: some View {
    Button("New Gradient Preset…") { store.beginSaveGradientPreset() }
    Button("New Gradient Group…") { newGroup() }
    Divider()
    Button("Import Gradients…") { store.importGradients() }
    Button("Export Selected Gradients…") { store.exportGradients(selected: true) }
      .disabled(store.gradients.state.selected.isEmpty)
    Button("Export All Gradients…") { store.exportGradients(selected: false) }
      .disabled(store.gradients.state.library.presets.isEmpty)
    Divider()
    Button("Append Default Gradients") {
      store.gradientLibraryAction {
        try await store.gradients.edit { state in
          let parent = try state.group("Basics", into: nil)
          for gradient in [
            GradientDefinition.foregroundToBackground, .foregroundToTransparent, .blackToWhite,
          ] {
            try state.add(gradient, into: parent)
          }
        }
      }
    }
  }
  @ViewBuilder private func entryMenu(_ node: GradientLibraryNode) -> some View {
    if node.children == nil {
      Button("Apply as Gradient Fill") { store.activateGradientPreset(node.id) }
        .disabled(
          store.gradients.state.presets[node.id]?.gradient == nil || store.hasToneDraft
            || store.geometryBusy)
    }
    Button("Rename…") {
      store.gradientNameDraft = .init(
        purpose: .rename(node.id), name: store.gradients.state.name(node.id) ?? "")
    }
    Button("Duplicate") {
      let parent = store.gradientParent(of: node.id)
      store.gradientLibraryAction {
        try await store.gradients.edit { try $0.duplicate([node.id], into: parent) }
      }
    }
    Menu("Move To") {
      Button("Top Level") { store.moveGradientPresets([node.id], into: nil) }
      ForEach(destinations.filter { !node.contains($0.id) }) { destination in
        Button(destination.path) {
          store.moveGradientPresets([node.id], into: destination.id)
        }
      }
    }
    Button("Delete") {
      store.gradientLibraryAction { try await store.gradients.edit { try $0.remove([node.id]) } }
    }
  }
}
