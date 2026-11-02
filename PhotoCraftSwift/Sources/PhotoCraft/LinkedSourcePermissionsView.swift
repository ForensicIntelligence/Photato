import SwiftUI

struct LinkedSourcePermissionsView:View {
  let service:AutomationService
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Button("Authorize Linked Artwork…"){service.chooseLinkedArtwork()}.disabled(!service.isRunning)
        Text("\(service.linkedArtworkAssets.count) approved for this API session").font(.caption)
        if !service.linkedArtworkAssets.isEmpty {Button("Clear"){service.clearLinkedArtwork()}}
      }
      Text("Selected artwork can be read and linked. Source updates are off until enabled for an individual file below.").font(.caption).foregroundStyle(.secondary)
      ForEach(service.linkedArtworkAssets.keys.sorted{$0.uuidString<$1.uuidString},id:\.self) {id in
        if let grant=service.linkedArtworkAssets[id] {
          Toggle("Allow source updates to “"+grant.url.lastPathComponent+"”",isOn:Binding(
            get:{service.linkedArtworkWritableAssets.contains(id)},set:{service.setLinkedArtworkWritable(id,enabled:$0)}))
            .disabled(!service.isRunning).accessibilityIdentifier("linked-source-write-"+id.uuidString)
        }
      }
      if !service.linkedArtworkAssets.isEmpty {
        Text("Source updates overwrite the selected original. Undo in its parent document restores the preview, not the external file. These permissions end when the API stops or authorizations are cleared.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
      }
    }
  }
}
