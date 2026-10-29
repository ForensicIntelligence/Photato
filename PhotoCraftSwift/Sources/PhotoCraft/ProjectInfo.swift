import AppKit
import Foundation
import SwiftUI

/// Local source-repository metadata for the free and open-source release.
struct ProjectLinks: Decodable, Equatable {
  var repositoryURL: URL?
  static let upstreamURL = URL(string: "https://github.com/storytold/photocraft")!

  init(repositoryURL: String? = nil) throws {
    self.repositoryURL = try Self.webURL(repositoryURL)
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      repositoryURL: values.decodeIfPresent(String.self, forKey: .repositoryURL))
  }
  private enum CodingKeys: String, CodingKey { case repositoryURL }
  private static func webURL(_ value: String?) throws -> URL? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    guard let url = URL(string: value), url.scheme?.lowercased() == "https",
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return url
  }
  static func bundled(in bundle: Bundle = .main) -> Self {
    guard let file = bundle.url(forResource: "ProjectLinks", withExtension: "json"),
      let data = try? Data(contentsOf: file),
      let links = try? JSONDecoder().decode(Self.self, from: data)
    else {
      return try! Self()
    }
    return links
  }
}

struct ProjectInfoView: View {
  let links: ProjectLinks
  @State private var showLicenses = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
          .scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Photato").font(.title).fontWeight(.semibold)
          Text("Native macOS editor · Development preview").font(.caption).foregroundStyle(
            .secondary)
        }
      }
      Text(
        "An independent native Swift fork and port of PhotoCraft, originally written in Rust by the ArtCraft Team and PhotoCraft contributors."
      )
      Text("Free and open-source · MIT OR Apache-2.0 · macOS 14+")
        .font(.callout).foregroundStyle(.secondary)
      Text(
        "Photoshop feature parity is still in progress. See Help → Workspace Feature Map for current capabilities."
      )
      HStack {
        if let url = links.repositoryURL { Link("Photato on GitHub", destination: url) }
        Link("Upstream PhotoCraft", destination: ProjectLinks.upstreamURL)
        Button("Licenses & Credits") { showLicenses = true }
      }.buttonStyle(.bordered)
      Divider()
      Text("The repository is private during development and will become public on release day.")
        .foregroundStyle(.secondary)
      Text("Code, bug reports, testing and documentation contributions are welcome.")
        .foregroundStyle(.secondary)
      Text("Independent project; not affiliated with Adobe or endorsed by the upstream authors.")
        .font(.caption).foregroundStyle(.secondary)
    }.padding(24).frame(width: 540).fixedSize(horizontal: false, vertical: true)
      .sheet(isPresented: $showLicenses) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Licenses & Credits").font(.title2)
          ScrollView {
            Text(licenseText).font(.system(size: 11, design: .monospaced))
              .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          }
          HStack {
            Spacer()
            Button("Done") { showLicenses = false }.keyboardShortcut(.defaultAction)
          }
        }.padding(20).frame(width: 620, height: 490)
      }
  }
  private var licenseText: String {
    let text = ["ATTRIBUTION.md", "NOTICE", "LICENSE-MIT", "LICENSE-APACHE", "LICENSE-psd-tools"]
      .compactMap { name in
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
          let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return name + "\n\n" + text
      }.joined(separator: "\n\n────────────────────────────────\n\n")
    return text.isEmpty
      ? "License texts are included in packaged builds and in the repository’s LICENSE-MIT, LICENSE-APACHE, NOTICE and ATTRIBUTION.md files."
      : text
  }
}
