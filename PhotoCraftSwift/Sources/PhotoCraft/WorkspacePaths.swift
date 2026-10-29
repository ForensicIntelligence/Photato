import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct PathsPanel: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(spacing: 1) {
          ForEach(store.document.paths ?? []) { saved in
            row(saved.name, path: saved.path, target: .saved(saved.id))
              .contextMenu {
                Button("Fill Path") {store.selectPath(.saved(saved.id));store.paintSelectedPath(stroke:false)}
                Button("Stroke Path…") {store.selectPath(.saved(saved.id));store.showStrokePath()}
                Button("Make Selection") {store.selectPath(.saved(saved.id));store.pathToSelection()}
                Divider()
                Button("Save / Rename Path…") {
                  store.selectPath(.saved(saved.id))
                  store.renamePath()
                }
                Button("Duplicate Path") {
                  var copy = saved
                  copy.id = UUID()
                  copy.isWorkPath = false
                  copy.name += " copy"
                  store.perform(.savePath(copy))
                  store.selectPath(.saved(copy.id))
                }
                Button("Delete Path") {
                  store.selectPath(.saved(saved.id))
                  store.deleteSelectedPath()
                }
              }
          }
          if let layer = store.activeLayer, let mask = layer.vectorMask {
            row("\(layer.name) Vector Mask", path: mask.path, target: .vectorMask(layer.id))
          }
        }.padding(.vertical, 3)
      }
      if let path = store.selectedVectorPath {
        HStack {
          Picker(
            "Fill rule",
            selection: Binding(
              get: { path.fillRule },
              set: { rule in
                var updated = path
                updated.fillRule = rule
                store.commitPath(updated)
              })
          ) {
            ForEach(PathFillRule.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.labelsHidden()
          Toggle(
            "Invert",
            isOn: Binding(
              get: { path.inverted },
              set: { value in
                var updated = path
                updated.inverted = value
                store.commitPath(updated)
              })
          ).toggleStyle(.checkbox)
          Spacer(minLength: 0)
        }.padding(.horizontal, 8).padding(.bottom, 6).controlSize(.mini)
          .disabled(!store.pathIsEditable)
      } else if (store.document.paths ?? []).isEmpty && store.activeLayer?.vectorMask == nil {
        Text("Draw a path with the Pen tool, then save it or use it as a vector mask.")
          .foregroundStyle(.secondary).padding(12)
      }
      Divider()
      HStack {
        Button("Fill Path") {store.paintSelectedPath(stroke:false)}.disabled(store.selectedVectorPath == nil || store.activeLayer == nil)
        Button("Stroke Path…") {store.showStrokePath()}.disabled(store.selectedVectorPath == nil || store.activeLayer == nil)
        Button("Make Work Path…") {store.showMakeWorkPath()}.disabled(store.document.selection == nil && store.document.selectionMask == nil)
      }.controlSize(.mini).padding(6)
      HStack(spacing: 16) {
        action("circle.dashed", "Load path as selection", enabled: store.selectedVectorPath != nil)
        {
          store.pathToSelection()
        }
        action(
          "rectangle.on.rectangle", "Make vector mask",
          enabled: store.selectedVectorPath != nil && store.activeLayer != nil
        ) {
          store.makeVectorMask()
        }
        action(
          "square.and.arrow.down", "Save or rename path", enabled: store.selectedVectorPath != nil
        ) {
          store.renamePath()
        }
        Spacer(minLength: 0)
        action("plus.square", "New path") { store.newPath() }
        action(
          "trash", "Delete path", enabled: store.selectedVectorPath != nil && store.pathIsEditable
        ) {
          store.deleteSelectedPath()
        }
      }.padding(8)
    }.font(.system(size: 11))
  }
  func row(_ name: String, path: VectorPath, target: PathTarget) -> some View {
    Button {
      store.selectPath(target)
      if !store.usesPathTool { store.tool = .directSelection }
    } label: {
      HStack(spacing: 8) {
        PathThumbnail(path: path, width: store.document.width, height: store.document.height)
          .frame(width: 40, height: 34).border(.gray)
        Text(name).lineLimit(1)
        Spacer(minLength: 0)
      }.padding(.horizontal, 8).padding(.vertical, 5)
        .background(store.pathTarget == target ? StudioTheme.selected : .clear)
        .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(name)
  }
  func action(
    _ symbol: String, _ label: String, enabled: Bool = true, perform: @escaping () -> Void
  ) -> some View {
    Button(action: perform) { Image(systemName: symbol) }.buttonStyle(.plain)
      .disabled(!enabled).help(label).accessibilityLabel(label)
  }
}
struct PathThumbnail: View {
  let path: VectorPath
  let width: Int
  let height: Int
  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
      guard let outline = try? VectorRasterizer.outline(path) else { return }
      let scale = min((size.width - 4) / Double(width), (size.height - 4) / Double(height))
      context.translateBy(
        x: (size.width - Double(width) * scale) / 2,
        y: (size.height - Double(height) * scale) / 2)
      context.scaleBy(x: scale, y: scale)
      context.stroke(Path(outline), with: .color(.black), lineWidth: 1 / scale)
    }
  }
}

struct VectorMaskControls: View {
  @Bindable var store: EditorStore
  var body: some View {
    if case .vectorMask(let id) = store.pathTarget,
      let mask = store.document.layers.first(where: { $0.id == id })?.vectorMask
    {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Toggle(
            "Enabled",
            isOn: Binding(
              get: { mask.enabled },
              set: { value in
                store.updateVectorMask(id) { $0.enabled = value }
              }))
          Toggle(
            "Linked",
            isOn: Binding(
              get: { mask.linked },
              set: { value in
                store.updateVectorMask(id) { $0.linked = value }
              }))
        }.toggleStyle(.checkbox)
        HStack {
          Text("Density")
          Slider(
            value: Binding(
              get: { Double(mask.density) },
              set: { value in
                store.updateVectorMask(id) { $0.density = Float(value) }
              }), in: 0...1, onEditingChanged: store.coalesce)
          Text("\(Int(mask.density * 100))%").frame(width: 30)
        }
        HStack {
          Text("Feather")
          TextField(
            "Vector mask feather",
            value: Binding(
              get: { mask.feather },
              set: { value in
                if value.isFinite {
                  store.updateVectorMask(id) { $0.feather = min(100, max(0, value)) }
                }
              }), format: .number.precision(.fractionLength(1)))
          Text("px")
        }
      }.padding(9).controlSize(.mini).disabled(!store.pathIsEditable)
    }
  }
}
