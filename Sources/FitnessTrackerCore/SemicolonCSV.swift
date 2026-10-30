import Foundation

/// Bounded RFC-style fields: quotes, escaped quotes, embedded newlines, CRLF and UTF-8 BOM.
enum SemicolonCSV {
  static let maximumRows = 100_000
  static func read(_ data: Data) throws -> [(line: Int, fields: [String])] {
    guard data.count <= WorkoutArchiveCodec.maximumBytes else { throw WorkoutArchiveError.tooLarge }
    guard var source = String(data: data, encoding: .utf8) else {
      throw FitSessionCSVError.invalidEncoding
    }
    if source.first == "\u{feff}" { source.removeFirst() }
    var rows: [(line: Int, fields: [String])] = []
    var fields: [String] = []
    var field = ""
    var quoted = false
    var closedQuote = false
    var line = 1
    var startLine = 1
    var count = 0
    func flush() throws {
      fields.append(field)
      if fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        guard rows.count < maximumRows else { throw FitSessionCSVError.tooManyRows }
        rows.append((startLine, fields))
      }
      fields = []
      field = ""
      closedQuote = false
    }
    for character in source {
      count += 1
      if count % 4096 == 0 { try Task.checkCancellation() }
      let newline = character == "\n" || character == "\r" || character == "\r\n"
      if quoted {
        if character == "\"" {
          quoted = false
          closedQuote = true
        } else {
          field.append(character)
        }
        if newline { line += 1 }
      } else if closedQuote && character == "\"" {
        field.append(character)
        quoted = true
        closedQuote = false
      } else if character == ";" {
        fields.append(field)
        field = ""
        closedQuote = false
        guard fields.count < 12 else { throw FitSessionCSVError.malformed(line: startLine) }
      } else if newline {
        try flush()
        line += 1
        startLine = line
      } else if character == "\"" {
        guard field.isEmpty && !closedQuote else {
          throw FitSessionCSVError.malformed(line: startLine)
        }
        quoted = true
      } else if closedQuote {
        throw FitSessionCSVError.malformed(line: startLine)
      } else {
        field.append(character)
      }
    }
    guard !quoted else { throw FitSessionCSVError.malformed(line: startLine) }
    if !field.isEmpty || !fields.isEmpty || closedQuote { try flush() }
    return rows
  }
}
