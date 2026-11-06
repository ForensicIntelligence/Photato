import SwiftUI

struct ShapeCreationSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:ShapeCreationDraft
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Create "+draft.request.name).font(.headline)
      Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:10) {
        GridRow {Text("Width");TextField("Width",value:$draft.definition.components[0].geometry.width,format:.number);Text("px")}
        GridRow {Text("Height");TextField("Height",value:$draft.definition.components[0].geometry.height,format:.number);Text("px")}
      }
      if draft.definition.components[0].geometry.kind == .rectangle {
        Toggle("Link corner radii",isOn:Binding(get:{draft.linkedCorners},set:{draft.setLinkedCorners($0)}))
        Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:8) {
          ForEach(0..<4,id:\.self){i in GridRow {
            Text(["Top Left","Top Right","Bottom Right","Bottom Left"][i])
            TextField("Radius",value:Binding(get:{draft.definition.components[0].geometry.radii[i]},set:{draft.setRadius($0,corner:i)}),format:.number)
            Text("px")
          }}
        }
      }
      Toggle("From Center",isOn:$draft.fromCenter)
      if let error=draft.error{Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      HStack {Spacer();Button("Cancel"){store.cancelShapeCreation()}.keyboardShortcut(.cancelAction)
        Button("OK"){store.commitShapeCreation(draft)}.keyboardShortcut(.defaultAction).disabled(!draft.valid)}
    }.textFieldStyle(.roundedBorder).padding(20).frame(width:360)
  }
}
