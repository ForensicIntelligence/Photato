import PhotoCraftCore
import SwiftUI

struct LayerFilterControls: View {
  @Bindable var store: EditorStore
  @FocusState private var nameFocused: Bool
  func binding<T>(_ key: WritableKeyPath<LayerPanelFilter, T>) -> Binding<T> {
    Binding(get: { store.displayedLayerFilter[keyPath: key] }, set: { value in
      store.editLayerFilter { $0[keyPath: key] = value; $0.enabled = true }
    })
  }
  var body: some View {
    HStack(spacing: 5) {
      Picker("Filter type", selection: binding(\.mode)) {
        ForEach(LayerFilterMode.allCases, id: \.self) { Text($0.title).tag($0) }
      }.labelsHidden().frame(width: 87).accessibilityIdentifier("layerFilter.mode")
      if store.layerContentFilter.phase == .running {
        ProgressView().controlSize(.mini).accessibilityLabel("Checking layer content")
        Button { store.layerContentFilter.cancel() } label: { Image(systemName: "xmark.circle") }
          .buttonStyle(.plain).help("Cancel layer content filtering")
          .accessibilityIdentifier("layerFilter.cancel")
      }
      criteria.frame(maxWidth: .infinity, alignment: .leading)
      Button {
        store.editLayerFilter { $0.enabled.toggle() }
      } label: {
        Image(systemName: store.displayedLayerFilter.enabled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
          .foregroundStyle(store.displayedLayerFilter.enabled && store.displayedLayerFilter.isFiltering ? StudioTheme.accent : .secondary)
          .frame(width: 19, height: 20)
      }.buttonStyle(.plain)
        .accessibilityLabel("Turn layer filtering on or off")
        .accessibilityValue(store.displayedLayerFilter.enabled ? "On" : "Off")
        .accessibilityIdentifier("layerFilter.enabled")
        .help(store.displayedLayerFilter.enabled ? "Turn layer filtering off" : "Turn layer filtering on")
    }.controlSize(.small).disabled(!store.canChangeLayerFilter)
      .help(store.layerContentFilter.message ?? "Filter layers")
      .onAppear { nameFocused = store.layerFilterFocusRequest > 0 && store.displayedLayerFilter.mode == .name }
      .onChange(of: store.layerFilterFocusRequest) { _, request in if request > 0 { nameFocused = true } }
  }
  @ViewBuilder var criteria: some View {
    switch store.displayedLayerFilter.mode {
    case .kind:
      HStack(spacing: 1) {
        ForEach(LayerFilterKind.allCases, id: \.self) { kind in
          filterButton(kind.symbol, title: kind.title, selected: store.displayedLayerFilter.kinds.contains(kind)) {
            store.editLayerFilter { value in
              if !value.kinds.insert(kind).inserted { value.kinds.remove(kind) }
              value.enabled = true
            }
          }
        }
      }
    case .name:
      TextField("Name", text: binding(\.name)).textFieldStyle(.plain).focused($nameFocused)
        .padding(4).background(StudioTheme.field)
        .accessibilityIdentifier("layerFilter.name")
    case .effect:
      Picker("Filter effect", selection: binding(\.effect)) {
        ForEach(LayerEffect.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
      }.labelsHidden()
    case .mode:
      Picker("Filter blending mode", selection: binding(\.blend)) {
        Text("Pass Through").tag("Pass Through")
        ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
      }.labelsHidden()
    case .attribute:
      Picker("Filter attribute", selection: binding(\.attribute)) {
        ForEach(LayerFilterAttribute.allCases, id: \.self) { Text($0.title).tag($0) }
      }.labelsHidden()
    case .color:
      Picker("Filter color label", selection: binding(\.color)) {
        ForEach(LayerColorLabel.allCases, id: \.self) { Text($0.title).tag($0) }
      }.labelsHidden()
    case .smartObject:
      HStack(spacing: 1) {
        ForEach(LayerFilterSmartKind.allCases, id: \.self) { kind in
          filterButton(kind.symbol, title: kind.title, selected: store.displayedLayerFilter.smartKinds.contains(kind)) {
            store.editLayerFilter { value in
              if !value.smartKinds.insert(kind).inserted { value.smartKinds.remove(kind) }
              value.enabled = true
            }
          }.disabled(kind == .library)
        }
      }
    case .selected:
      Text("Selected layers").font(.system(size: 10)).foregroundStyle(.secondary)
    case .artboard:
      Picker("Filter artboard", selection: binding(\.artboardID)) {
        Text("All Artboards").tag("")
        ForEach(store.document.layers.filter { $0.group?.artboard != nil }) { layer in
          Text(layer.name).tag(layer.id.uuidString)
        }
        if !store.displayedLayerFilter.artboardID.isEmpty,
          !store.document.layers.contains(where: { $0.id.uuidString == store.displayedLayerFilter.artboardID }) {
          Text("Missing Artboard").tag(store.displayedLayerFilter.artboardID)
        }
      }.labelsHidden()
    }
  }
  func filterButton(_ symbol: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 10)).frame(width: 20, height: 20)
        .background(selected ? StudioTheme.selected : .clear)
    }.buttonStyle(.plain).help("Filter layers: \(title)")
      .accessibilityLabel("Filter layers: \(title)").accessibilityValue(selected ? "Selected" : "Not selected")
  }
}
