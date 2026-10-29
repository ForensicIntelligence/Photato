import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct VariableExportOptions: Sendable {
  var prefix = "data-set"
  var format: DocumentIO.Format = .psd
  var dataSetIDs: [UUID] = []
  func selectedRows(in document: CraftDocument) throws -> [VariableDataSet] {
    guard !prefix.isEmpty, prefix.utf8.count <= 64,
          prefix.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_- ".unicodeScalars.contains($0) }),
          Set(dataSetIDs).count == dataSetIDs.count,
          [.native, .psd, .psb, .png, .tiff, .jpeg].contains(format),
          let variables = document.variables else { throw CraftError.invalid("Choose a filename prefix, output format and data sets.") }
    let ids = Set(dataSetIDs)
    guard ids.isSubset(of: Set(variables.dataSets.map(\.id))) else { throw CraftError.invalid("An export data set no longer exists.") }
    let rows = variables.dataSets.filter { ids.isEmpty || ids.contains($0.id) }
    guard !rows.isEmpty else { throw CraftError.invalid("Create a data set before exporting.") }
    return rows
  }
}
enum VariableDataExport {
  static let maximumBytes = 128 * 1024 * 1024
  static func fileName(prefix: String, row: VariableDataSet, index: Int, format: DocumentIO.Format) -> String {
    var safe = row.name.map { "/:\\".contains($0) || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? Character("_") : $0 }
    while String(safe).utf8.count > 160 { safe.removeLast() }
    return prefix + String(format: "-%04d-", index + 1) + String(safe) + "." + format.rawValue
  }
  static func render(_ document: CraftDocument, options: VariableExportOptions,
                     maximumBytes: Int = maximumBytes) throws -> ImageSequenceOutput {
    try document.validate()
    guard maximumBytes > 0, maximumBytes <= Self.maximumBytes else { throw CraftError.invalid("Invalid data-set output budget.") }
    let rows = try options.selectedRows(in: document)
    var files: [StoredZIP.File] = [], records: [[String: String]] = [], total = 0
    for (index, row) in rows.enumerated() {
      try Task.checkCancellation()
      // Every variation begins at the same template, including Do Not Replace values.
      var variation = document
      try Command.variables(.apply(row.id)).apply(to: &variation)
      variation.name = options.prefix + "-" + row.name
      if options.format != .native { variation.variables = nil }
      let bytes = try DocumentIO.encode(variation, format: options.format)
      guard bytes.count <= maximumBytes - total else { throw CraftError.invalid("Data-set output exceeds 128 MiB. Export fewer rows at a time.") }
      total += bytes.count
      let name = fileName(prefix: options.prefix, row: row, index: index, format: options.format)
      files.append(.init(name: name, data: bytes))
      records.append(["id": row.id.uuidString, "name": row.name, "file": name])
    }
    let metadata: [String: Any] = ["format": "photato-data-sets", "version": 1, "template": document.name,
      "outputFormat": options.format.rawValue, "retainsTemplateDefinitions": options.format == .native,
      "rows": records]
    let manifest = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
    guard manifest.count <= maximumBytes - total else { throw CraftError.invalid("The data-set manifest exceeds the export limit.") }
    files.append(.init(name: "data-sets.json", data: manifest))
    return .init(files: files)
  }
}
