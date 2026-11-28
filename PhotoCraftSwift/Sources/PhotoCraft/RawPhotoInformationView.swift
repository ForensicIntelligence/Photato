import PhotoCraftImaging
import SwiftUI

struct RawPhotoInformationView: View {
  let information: RawPhotoInformation

  var body: some View {
    ScrollView {
      Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 9) {
        row("File", information.fileName)
        row("Format", information.formatTitle)
        row("Image Size", "\(information.width.formatted()) × \(information.height.formatted()) px")
        row("File Size", information.byteCount.formatted(.byteCount(style: .file)))
        row("Camera", information.camera)
        optionalRow("Lens", information.lens)
        optionalRow("Captured", information.captureDate.map { date in
          date + (information.captureOffset.map { " " + $0 } ?? "")
        })
        optionalRow("Caption", information.caption)
        optionalRow("Copyright", information.copyright)
      }
      .padding(16)
      .textSelection(.enabled)
    }
    .frame(idealHeight: 260, maxHeight: 450)
    .frame(width: 328)
    .accessibilityLabel("Photo information")
  }

  private func row(_ title: String, _ value: String) -> some View {
    GridRow {
      Text(title).foregroundStyle(.secondary)
      Text(value).frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func optionalRow(_ title: String, _ value: String?) -> some View {
    if let value { row(title, value) }
  }
}
