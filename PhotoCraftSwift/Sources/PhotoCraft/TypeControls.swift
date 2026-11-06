import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum TypeControlScope { case all, character, paragraph }

struct TypeControls: View {
  var store: EditorStore
  var scope: TypeControlScope = .all
  private var current: (TypeStyle, TypeParagraph) {
    _ = store.typeSelectionRevision
    if let editor = store.typeEditor {
      let range = editor.selectedRange()
      let attrs = range.length > 0 ? editor.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? editor.typingAttributes : editor.typingAttributes
      return NativeTextLayout.styles(attrs, dpi: store.document.pixelsPerInch)
    }
    return (store.editableType?.typography?.defaultStyle ?? .init(), store.editableType?.typography?.defaultParagraph ?? .init())
  }
  private func number(_ label: String, _ key: WritableKeyPath<TypeStyle, Double>) -> some View {
    HStack {
      Text(label).frame(width: 83, alignment: .leading)
      TextField(label, value: Binding(get: { current.0[keyPath: key] }, set: { value in store.formatType { s, _ in s[keyPath: key] = value } }), format: .number)
        .textFieldStyle(.roundedBorder).accessibilityLabel(label)
    }
  }
  private func paragraphNumber(_ label: String, _ key: WritableKeyPath<TypeParagraph, Double>) -> some View {
    HStack {
      Text(label).frame(width: 83, alignment: .leading)
      TextField(label, value: Binding(get: { current.1[keyPath: key] }, set: { value in store.formatType(paragraph: true) { _, p in p[keyPath: key] = value } }), format: .number)
        .textFieldStyle(.roundedBorder)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if scope != .paragraph {
      HStack {
        Text("Character").fontWeight(.semibold)
        Spacer()
        if store.typeEditingDraft == nil {
          Button("Edit Text") { if let layer = store.activeLayer { store.beginType(layer) } }
        }
      }
      Picker("Font", selection: Binding(get: { current.0.font }, set: { value in store.formatType { s, _ in s.font = value;s.fontOptions=nil;s.glyphOverride=nil } })) {
        if !NSFontManager.shared.availableFonts.contains(current.0.font){Text(current.0.font).tag(current.0.font)}
        ForEach(NSFontManager.shared.availableFonts.sorted(), id: \.self) { Text($0).tag($0) }
      }.labelsHidden()
      number("Size (pt)", \.size)
      number("Leading (pt)", \.leading).help("Zero uses automatic leading")
      number("Tracking", \.tracking)
      number("Baseline (pt)", \.baseline)
      DisclosureGroup("Character scaling") {
        number("Horizontal ×", \.horizontalScale)
        number("Vertical ×", \.verticalScale)
      }
      ColorPicker("Color", selection: Binding(get: {
        return Color(NativeTextLayout.color(current.0))
      }, set: { value in
        if let color = NSColor(value).usingColorSpace(current.0.characterFormatting?.linearColor == true ? NativeTextLayout.linearColorSpace:.sRGB) {
          store.formatType { s, _ in s.color = Pixel(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent)) }
        }
      }))
      HStack {
        Toggle("Underline", isOn: Binding(get: { current.0.underline }, set: { v in store.formatType { s, _ in s.underline = v } }))
        Toggle("Strike", isOn: Binding(get: { current.0.strikethrough }, set: { v in store.formatType { s, _ in s.strikethrough = v } }))
      }
      AdvancedTypeControls(store:store,style:current.0)
      RichTypeControls(store:store,style:current.0,paragraph:current.1,scope:scope)
      Menu("Shaped Text…"){Button("Edit Layout…"){store.beginShapedType()};ForEach(TextGeometry.Mode.allCases,id:\.self){mode in Button(mode.rawValue.capitalized){store.beginShapedType(mode)}}}
      }
      if scope == .all { Divider() }
      if scope != .character {
      Text("Paragraph").fontWeight(.semibold)
      Picker("Alignment", selection: Binding(get: { current.1.alignment }, set: { v in store.formatType(paragraph: true) { _, p in p.alignment = v } })) {
        ForEach(TypeParagraph.Alignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
      }
      Picker("Direction", selection: Binding(get: { current.1.direction }, set: { v in store.formatType(paragraph: true) { _, p in p.direction = v } })) {
        Text("Automatic").tag(TypeParagraph.Direction.natural)
        Text("Left to right").tag(TypeParagraph.Direction.leftToRight)
        Text("Right to left").tag(TypeParagraph.Direction.rightToLeft)
      }
      DisclosureGroup("Indents and spacing (pt)") {
        paragraphNumber("First line", \.firstIndent); paragraphNumber("Left indent", \.startIndent)
        paragraphNumber("Right indent", \.endIndent); paragraphNumber("Before", \.spaceBefore); paragraphNumber("After", \.spaceAfter)
      }
      Toggle("Hyphenation", isOn: Binding(get: { current.1.hyphenation }, set: { v in store.formatType(paragraph: true) { _, p in p.hyphenation = v } }))
      Picker("Type", selection: Binding(get: { store.editableType?.typography?.kind ?? .point }, set: { store.setTypeFrame($0) })) {
        Text("Point").tag(TextTypography.Kind.point); Text("Paragraph").tag(TextTypography.Kind.paragraph)
      }
      if let text = store.editableType, text.typography?.kind == .paragraph {
        if let frame=text.typography?.sourceFrame,frame.kind == .box {
          FractionalTypeFrameControls(store:store,frame:frame)
        } else {
        HStack {
          Text("Box (px)")
          TextField("Width", value: Binding(get: { text.layoutWidth ?? 1 }, set: { store.setTypeFrame(.paragraph, width: $0) }), format: .number)
          Text("×")
          TextField("Height", value: Binding(get: { text.layoutHeight ?? 1 }, set: { store.setTypeFrame(.paragraph, height: $0) }), format: .number)
        }.textFieldStyle(.roundedBorder)
        }
        if let metrics = try? NativeTextLayout.metrics(text, dpi: store.document.pixelsPerInch), metrics.overset {
          Label("Text overflows the box", systemImage: "plus.square").foregroundStyle(.orange)
        }
      }
      if scope == .paragraph { RichTypeControls(store:store,style:current.0,paragraph:current.1,scope:.paragraph) }
      }
      if store.typeEditingDraft != nil {
        HStack { Button("Cancel") { store.finishType(cancel: true) }; Button("Commit") { store.finishType() }.keyboardShortcut(.return, modifiers: .command) }
        Text("Esc or ⌘Return commits. Typing Undo stays in this edit.").font(.caption).foregroundStyle(.secondary)
      }
    }.controlSize(.small).disabled(!store.canEditType || store.editableType == nil)
  }
}
