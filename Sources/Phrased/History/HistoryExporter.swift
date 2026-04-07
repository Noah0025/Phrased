import AppKit
import UniformTypeIdentifiers

enum HistoryExporter {
    /// Shows a NSSavePanel and exports entries in the user-chosen format (JSON / CSV / TXT).
    static func export(entries: [HistoryEntry]) {
        guard !entries.isEmpty else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("history.export.alert.no_history", comment: "")
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("history.export.title", comment: "")
        panel.nameFieldStringValue = NSLocalizedString("history.export.default_filename", comment: "")
        panel.allowedContentTypes = [.plainText, .json, .commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let ext = url.pathExtension.lowercased()
            let data: Data?
            switch ext {
            case "json": data = encodeJSON(entries)
            case "csv":  data = encodeCSV(entries)
            default:     data = encodeTXT(entries)
            }
            guard let data else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Formats

    private static func encodeJSON(_ entries: [HistoryEntry]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }

    private static func encodeCSV(_ entries: [HistoryEntry]) -> Data? {
        let iso = ISO8601DateFormatter()
        var lines = [NSLocalizedString("history.export.csv.header", comment: "")]
        for e in entries {
            func q(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            lines.append([q(iso.string(from: e.createdAt)), q(e.templateName),
                          q(e.appName ?? ""), q(e.input), q(e.output)].joined(separator: ","))
        }
        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private static func encodeTXT(_ entries: [HistoryEntry]) -> Data? {
        let body = entries.map { e in
            let meta = String(
                format: NSLocalizedString("history.export.txt.meta_format", comment: ""),
                e.createdAt.formatted(date: .abbreviated, time: .shortened),
                e.templateName,
                e.appName.map {
                    String(format: NSLocalizedString("history.export.txt.app_suffix_format", comment: ""), $0)
                } ?? ""
            )
            let input = String(format: NSLocalizedString("history.export.txt.input_format", comment: ""), e.input)
            let output = String(format: NSLocalizedString("history.export.txt.output_format", comment: ""), e.output)
            return "\(meta)\n\(input)\n\(output)"
        }.joined(separator: "\n\n---\n\n")
        let header = String(
            format: NSLocalizedString("history.export.txt.header_format", comment: ""),
            Date().formatted()
        )
        return (header + body).data(using: .utf8)
    }
}
