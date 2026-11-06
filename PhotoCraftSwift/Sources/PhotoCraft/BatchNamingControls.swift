import SwiftUI

struct BatchNamingControls:View {
  @Bindable var model:BatchWorkspace
  @State private var expanded=true
  var example:String {
    do{return try model.naming.plan(sources:[model.sources.first?.name ?? "Document"],format:model.format)[0]}
    catch{return error.localizedDescription}
  }
  func kindBinding(_ id:UUID)->Binding<BatchFileNaming.Kind> {
    Binding(get:{model.naming.elements.first{$0.id==id}?.kind ?? .literal},set:{value in
      guard let i=model.naming.elements.firstIndex(where:{$0.id==id})else{return}
      model.naming.elements[i].kind=value;model.naming.elements[i].text=""
    })
  }
  func textBinding(_ id:UUID)->Binding<String> {
    Binding(get:{model.naming.elements.first{$0.id==id}?.text ?? ""},set:{value in
      guard let i=model.naming.elements.firstIndex(where:{$0.id==id})else{return};model.naming.elements[i].text=value
    })
  }
  func move(_ id:UUID,_ offset:Int){guard let i=model.naming.elements.firstIndex(where:{$0.id==id}),model.naming.elements.indices.contains(i+offset)else{return};model.naming.elements.swapAt(i,i+offset)}
  var body:some View {
    DisclosureGroup("File Naming",isExpanded:$expanded) {
      VStack(alignment:.leading,spacing:6) {
        ForEach(model.naming.elements) {field in
          HStack {
            Picker("Field",selection:kindBinding(field.id)) {
              ForEach(BatchFileNaming.Kind.allCases,id:\.rawValue){Text($0.title).tag($0)}
            }.frame(width:240)
            if field.kind == .literal {TextField("Text",text:textBinding(field.id))}
            Spacer(minLength:0)
            Button("↑"){move(field.id,-1)}.disabled(model.naming.elements.first?.id==field.id).help("Move naming field up")
            Button("↓"){move(field.id,1)}.disabled(model.naming.elements.last?.id==field.id).help("Move naming field down")
            Button("−"){model.naming.elements.removeAll{$0.id==field.id}}.disabled(model.naming.elements.count==1).help("Remove naming field")
          }
        }
        HStack {
          Button("Add Field"){model.naming.elements.append(.init(kind:.literal))}.disabled(model.naming.elements.count==6)
          Spacer();Text("Starting Serial Number")
          TextField("1",value:$model.naming.startingSerial,format:.number.grouping(.never)).frame(width:110)
        }
        HStack {
          Text("Compatibility")
          Toggle("Windows",isOn:$model.naming.windows);Toggle("Mac OS",isOn:$model.naming.macOS);Toggle("UNIX",isOn:$model.naming.unix)
        }.toggleStyle(.checkbox)
        Text("Example: "+example).font(.caption).textSelection(.enabled)
      }.padding(.top,6)
    }
  }
}
