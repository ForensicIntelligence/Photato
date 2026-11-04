import AppKit
import SwiftUI
import PhotoCraftCore

struct InkChannelRows: View {
  @Bindable var store: EditorStore
  let images: [CGImage]
  let size: ChannelThumbnailSize
  let eyeTracking:ChannelEyeTracking
  var body: some View {
    ForEach(Array(store.document.inkChannelTargets.enumerated()), id: \.element) { index, target in
      let name = store.inkChannelName(target), selected = store.editingChannel == nil && store.effectiveInkTargets.contains(target)
      HStack(spacing: 0) {
        ChannelEyeControl(store:store,channel:.ink(target),tracking:eyeTracking,label:"Visibility of \(name) ink channel",identifier:"channels.ink.visibility.\(target.key)",height:size.rowHeight).frame(width:26,height:size.rowHeight)
        Rectangle().fill(StudioTheme.line).frame(width: 1)
        Button {
          let modifiers = NSApp.currentEvent?.modifierFlags ?? []
          if modifiers.contains(.command) {
            let mode: SelectionMode = modifiers.contains(.shift) ? (modifiers.contains(.option) ? .intersect : .add) : (modifiers.contains(.option) ? .subtract : .replace)
            store.performInkChannel(.loadSelection(target, mode, false))
          } else {
            var targets: Set<InkChannelTarget> = [target]
            if modifiers.contains(.shift) {
              targets = Set(store.effectiveInkTargets)
              if targets.contains(target) { targets.remove(target) } else { targets.insert(target) }
            }
            do { try store.selectInkChannels(targets) } catch { store.error = error.localizedDescription }
          }
        } label: {
          HStack(spacing: 7) {
            if size != .none {
              Group { if images.indices.contains(index) { Image(decorative: images[index], scale: 1).resizable().scaledToFit() } else { Color.gray } }
                .frame(width: size.edge, height: size.edge).border(.black).accessibilityHidden(true)
            }
            Text(name).font(.system(size: 11)); Spacer(minLength: 4)
          }.padding(.horizontal, 5).frame(maxWidth: .infinity).frame(height: size.rowHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!store.canSelectComponentTarget)
          .accessibilityLabel("Select \(name) ink channel").accessibilityIdentifier("channels.ink.\(target.key)")
          .accessibilityValue(selected ? "Selected" : "")
      }.background(selected ? StudioTheme.selected : StudioTheme.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
        .contextMenu {
          Button("Select All Channels") { try? store.selectInkChannels([]) }
          Button("Load Selection") { store.performInkChannel(.loadSelection(target, .replace, false)) }
          Button("Invert") { store.performInkChannel(.edit([target], .invert)) }
          Menu("Fill") {
            Button("Black") { store.performInkChannel(.edit([target], .fill(0, 1))) }
            Button("White") { store.performInkChannel(.edit([target], .fill(1, 1))) }
            Button("50% Gray") { store.performInkChannel(.edit([target], .fill(0.5, 1))) }
          }
          Menu("Filter") { ForEach(InkChannelCommand.filters.sorted(by: { $0.title < $1.title }), id: \.self) { kind in
            Button(kind.title) { do { try store.selectInkChannels([target]); store.beginFilter(kind) } catch { store.error = error.localizedDescription } }
          } }
          if case .plate(let id) = target {
            Divider()
            Button("Spot Channel Options…") { store.beginInkChannelOptions(id) }
            Button("Duplicate Channel") { store.performInkChannel(.duplicate(id, UUID(), nil)) }
            Button("Move Up") { store.performInkChannel(.move(id, index - 1)) }.disabled(index == 0)
            Button("Move Down") { store.performInkChannel(.move(id, index + 1)) }.disabled(index == store.document.inkChannelTargets.count - 1)
            Button("Delete Channel") { store.performInkChannel(.delete(id)) }.disabled(store.document.inkChannelTargets.count == 1)
          }
        }
    }
  }
}

struct InkChannelOptionsSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: InkChannelOptionsDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(draft.creating ? "New Spot Channel" : "Spot Channel Options").font(.headline)
      TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
      ColorPicker("Color", selection: Binding(get: { Color(.sRGB, red: Double(draft.color.r), green: Double(draft.color.g), blue: Double(draft.color.b)) }, set: { color in
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .black
        draft.color = Pixel(Float(value.redComponent), Float(value.greenComponent), Float(value.blueComponent))
      }), supportsOpacity: false)
      HStack { Text("Solidity"); Slider(value: $draft.solidity, in: 0...1); Text("\(Int((draft.solidity * 100).rounded()))%") }
      Text("Solidity affects the combined ink preview; stored ink coverage stays unchanged.").font(.caption).foregroundStyle(.secondary)
      if draft.creating {
        HStack { Text("Initial ink"); Slider(value: $draft.density, in: 0...1); Text("\(Int((draft.density * 100).rounded()))%") }
      }
      HStack { Spacer(); Button("Cancel") { store.inkChannelOptions = nil }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitInkChannelOptions() }.keyboardShortcut(.defaultAction).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.utf8.count > 1024)
      }
    }.padding(20).frame(width: 400)
  }
}
