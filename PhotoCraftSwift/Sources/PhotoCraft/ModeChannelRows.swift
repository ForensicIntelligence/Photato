import AppKit
import PhotoCraftCore
import SwiftUI

struct ModeChannelRows: View {
  @Bindable var store: EditorStore
  let images: [CGImage]
  let size: ChannelThumbnailSize
  private var all: Set<Int> { Set(0..<store.document.colorMode.componentCount) }
  var body: some View {
    if store.document.colorMode != .grayscale {
      row(nil, title: store.document.colorMode == .lab ? "Lab" : store.document.colorMode.rawValue.uppercased())
    }
    ForEach(Array(store.document.colorMode.componentNames.enumerated()), id: \.offset) { item in
      row(item.offset, title: item.element)
    }
  }
  private func row(_ component: Int?, title: String) -> some View {
    let targets = component.map { Set([$0]) } ?? all
    let visible = targets.isSubset(of: store.modeVisibleComponents)
    let selected = store.editingChannel == nil && (store.modeComponentTargets.isEmpty || component.map { store.modeComponentTargets.contains($0) } == true)
    let imageIndex = component.map { $0 + 1 } ?? 0
    return HStack(spacing: 0) {
      Button {
        let next = visible ? store.modeVisibleComponents.subtracting(targets) : store.modeVisibleComponents.union(targets)
        if !next.isEmpty { do { try store.setModeComponentVisibility(next) } catch { store.error = error.localizedDescription } }
      } label: {
        Image(systemName: "eye").font(.system(size: 11)).opacity(visible ? 1 : 0)
          .frame(width: 26, height: size.rowHeight).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(!store.canChangeChannelVisibility)
        .accessibilityLabel("Visibility of \(title) channel")
        .accessibilityValue(visible ? "Visible" : "Hidden")
        .accessibilityIdentifier("channels.mode.visibility.\(imageIndex)")
      Rectangle().fill(StudioTheme.line).frame(width: 1)
      Button {
        var selection = component.map { Set([$0]) } ?? []
        if let component, NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
          selection = store.modeComponentTargets
          if selection.contains(component) { selection.remove(component) } else { selection.insert(component) }
        }
        do { try store.selectModeComponents(selection) } catch { store.error = error.localizedDescription }
      } label: {
        HStack(spacing: 0) {
          if size != .none {
            ZStack {
              Checkerboard()
              if images.indices.contains(imageIndex) { Image(decorative: images[imageIndex], scale: 1).resizable().scaledToFit() }
            }.frame(width: size.edge, height: size.edge).border(Color.black.opacity(0.7))
              .padding(.leading, 4).padding(.trailing, 5).accessibilityHidden(true)
          }
          Text(title).font(.system(size: 11)).padding(.leading, size == .none ? 7 : 0)
          Spacer(minLength: 5)
        }.frame(maxWidth: .infinity).frame(height: size.rowHeight).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(!store.canSelectComponentTarget)
        .help("Select \(title) editing target; Shift-click to select multiple components")
        .accessibilityLabel("Select \(title) channel")
        .accessibilityValue(selected ? "Selected editing target" : "")
        .accessibilityIdentifier("channels.mode.target.\(imageIndex)")
    }.background(selected ? StudioTheme.selected : StudioTheme.chrome)
      .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
      .contextMenu {
        if let component {
          Button("Invert") {
            do {
              try store.selectModeComponents([component])
              if let layer = store.activeLayer { store.performGeometry(.applyAdjustment(layer.id, .invert)) }
            } catch { store.error = error.localizedDescription }
          }.disabled(!store.canEditModeComponents)
        }
      }
  }
}
