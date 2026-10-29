import Foundation

public enum VariableDataDelimiter: String, Codable, CaseIterable, Sendable {
  case comma, tab
  var byte: UInt8 { self == .comma ? 44 : 9 }
}
public struct VariableDataImportOptions: Codable, Equatable, Sendable {
  public var delimiter: VariableDataDelimiter = .comma
  public var firstColumnNames = false
  public var replaceExisting = true
  public init() {}
}
/// Strict CSV/TSV parsing: quoted multiline text, doubled quotes, CR/LF/CRLF and
/// Adobe's trimming of unquoted surrounding whitespace. No filesystem access.
public enum VariableDataImport {
  public static func table(_ text: String, delimiter: VariableDataDelimiter) throws -> [[String]] {
    guard text.utf8.count <= DataDrivenGraphics.maximumMetadataBytes else {
      throw CraftError.invalid("The data set file exceeds 16 MiB.")
    }
    let input = Array(text.utf8)
    var i = input.starts(with: [0xef, 0xbb, 0xbf]) ? 3 : 0
    var rows: [[String]] = [], row: [String] = [], field: [UInt8] = []
    var quoted = false, inside = false, closed = false, fields = 0
    func value() -> String {
      let s = String(decoding: field, as: UTF8.self)
      return quoted ? s : s.trimmingCharacters(in: .whitespaces)
    }
    func finishField() throws {
      fields += 1
      guard fields <= DataDrivenGraphics.maximumValues + DataDrivenGraphics.maximumDefinitions else {
        throw CraftError.invalid("The data set file has too many values.")
      }
      row.append(value()); field = []; quoted = false; closed = false
    }
    func finishRow() throws {
      guard rows.count <= DataDrivenGraphics.maximumDataSets else { throw CraftError.invalid("The data set file has too many rows.") }
      rows.append(row); row = []
    }
    while i < input.count {
      if i % 4096 == 0 { try Task.checkCancellation() }
      let c = input[i]
      if inside {
        if c == 34 {
          if i + 1 < input.count && input[i + 1] == 34 { field.append(34); i += 2; continue }
          inside = false; closed = true
        } else { field.append(c) }
        i += 1; continue
      }
      if c == delimiter.byte { try finishField(); i += 1; continue }
      if c == 13 || c == 10 {
        if !row.isEmpty || quoted || !value().isEmpty { try finishField(); try finishRow() }
        else { field = []; closed = false }
        i += c == 13 && i + 1 < input.count && input[i + 1] == 10 ? 2 : 1
        continue
      }
      if closed {
        guard c == 32 || c == 9 else { throw CraftError.invalid("Unexpected characters after a quoted data value.") }
      } else if c == 34 {
        guard value().isEmpty else { throw CraftError.invalid("Quote the entire value and double any literal quotation marks.") }
        field = []; quoted = true; inside = true
      } else { field.append(c) }
      i += 1
    }
    guard !inside else { throw CraftError.invalid("A quoted data value is missing its closing quote.") }
    if !row.isEmpty || quoted || !value().isEmpty { try finishField(); try finishRow() }
    guard let first = rows.first, !first.isEmpty, rows.count >= 2,
          rows.allSatisfy({ $0.count == first.count }) else {
      throw CraftError.invalid("Include a header and at least one data set, with the same number of columns in each row.")
    }
    return rows
  }
  /// The resolver receives image references as data. The desktop resolves chosen local
  /// files; API clients resolve explicitly supplied assets, never arbitrary local paths.
  public static func dataSets(_ text: String, variables: DataDrivenGraphics,
                             options: VariableDataImportOptions = .init(),
                             resolveImage: (String) throws -> UUID) throws -> [VariableDataSet] {
    let table = try table(text, delimiter: options.delimiter)
    let header = table[0], names = Set(variables.variableNames)
    guard !names.isEmpty else { throw CraftError.invalid("Define variables before importing data sets.") }
    let metadataColumn = options.firstColumnNames && !names.contains(header[0]) && (header[0].isEmpty || header[0] == "DataSet")
    let columns = Array(header.dropFirst(metadataColumn ? 1 : 0))
    guard Set(columns) == names, Set(columns).count == columns.count else {
      throw CraftError.invalid("The header must contain every defined variable exactly once.")
    }
    let kinds = Dictionary(variables.definitions.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
    var usedNames = options.replaceExisting ? Set<String>() : Set(variables.dataSets.map(\.name))
    var next = options.replaceExisting ? 1 : variables.dataSets.count + 1
    var result: [VariableDataSet] = []
    for row in table.dropFirst() {
      try Task.checkCancellation()
      let name: String
      if options.firstColumnNames { name = row[0] }
      else {
        while usedNames.contains("Data Set \(next)") { next += 1 }
        name = "Data Set \(next)"; next += 1
      }
      guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 256,
            usedNames.insert(name).inserted else { throw CraftError.invalid("Data set names must be nonempty and unique.") }
      var values: [String: VariableValue] = [:]
      for (column, value) in zip(columns, row.dropFirst(metadataColumn ? 1 : 0)) {
        switch kinds[column] {
        case .visibility:
          guard value == "true" || value == "false" else { throw CraftError.invalid("Visibility values must be true or false (\(column)).") }
          values[column] = .visibility(value == "true")
        case .textReplacement:
          guard value.utf16.count <= 100_000 else { throw CraftError.invalid("Replacement text exceeds the type limit.") }
          values[column] = .text(value)
        case .pixelReplacement:
          guard !value.isEmpty else { throw CraftError.invalid("An imported pixel variable must name an image.") }
          values[column] = .pixels(try resolveImage(value))
        case nil: throw CraftError.invalid("Unknown variable in the import header.")
        }
      }
      result.append(.init(name: name, values: values))
    }
    guard result.count + (options.replaceExisting ? 0 : variables.dataSets.count) <= DataDrivenGraphics.maximumDataSets else {
      throw CraftError.invalid("The template has too many data sets.")
    }
    return result
  }
}
