import XCTest

/// Before the repository went public (2026-11-23) its docs had to be scrubbed: they carried the owner's
/// real usage numbers, save state, verbatim quotes, this Mac's absolute paths and a home-relative path to
/// a private side project. Usage numbers and quotes need a reviewer's eye (CLAUDE.md rule), but local paths
/// are mechanical, so this scan fails when one comes back.
///
/// Placeholder homes used by upstream tests (`/Users/x`, `/Users/testhome`, ...) are allowed; any other
/// `/Users/<name>` (or its Claude-project spelling `-Users-<name>`) is someone's real home.
final class RepositoryPrivacyTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Names that only ever appear as made-up homes in test fixtures.
    static let placeholderHomes: Set<String> = ["x", "testhome", "example", "dev", "tester", "someone"]

    /// Local-only locations. Built from parts so this file does not match itself in a history scan.
    static let localFragments = ["/private" + "/tmp/", "claude" + "-501", "digimon-tokenbar" + "-test", "~/" + "Projects/"]

    private static let textExtensions: Set<String> = ["swift", "md", "py", "json", "sh", "js", "txt", "yml", "yaml",
                                                      "plist", "html", "css", "csv", "tsv", "toml"]

    /// Every tracked-text area of the repository, minus hidden folders (caches), upstream fixtures and this file.
    private func scannedFiles() throws -> [URL] {
        let me = URL(fileURLWithPath: #filePath).standardizedFileURL.path
        var files = ["README.md", "README.ko.md", "README.ja.md", "AGENTS.md", "CLAUDE.md"]
            .map { Self.root.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        for folder in ["docs", "tools", "Sources", "Tests"] {
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(
                at: Self.root.appendingPathComponent(folder), includingPropertiesForKeys: [.isDirectoryKey]))
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if name.hasPrefix(".") || name == "Fixtures" || name == "__pycache__" { enumerator.skipDescendants() }
                    continue
                }
                if Self.textExtensions.contains(url.pathExtension), url.standardizedFileURL.path != me {
                    files.append(url)
                }
            }
        }
        return files
    }

    /// What in `text` points at a real local place, as "line: match".
    static func localPaths(in text: String) -> [String] {
        let homes = try! NSRegularExpression(pattern: "(?:/Users/|-Users-)([A-Za-z0-9._]+)")
        var found: [String] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for match in homes.matches(in: line, range: range) {
                let name = (line as NSString).substring(with: match.range(at: 1))
                if !placeholderHomes.contains(name) {
                    found.append("\(index + 1): \((line as NSString).substring(with: match.range))")
                }
            }
            for fragment in localFragments where line.contains(fragment) {
                found.append("\(index + 1): \(fragment)")
            }
        }
        return found
    }

    func testTheScanCatchesARealHomeButNotPlaceholders() {
        XCTAssertEqual(Self.localPaths(in: "let home = \"/Users/testhome/.claude\"\n-Users-x-Proj"), [])
        XCTAssertEqual(Self.localPaths(in: "a\nsee /Users/somebody/notes").count, 1)
        XCTAssertEqual(Self.localPaths(in: "dir -Users-somebody-Projects-app").count, 1)
        XCTAssertEqual(Self.localPaths(in: "copy to " + "/private" + "/tmp/" + "x.png").count, 1)
        XCTAssertEqual(Self.localPaths(in: "see " + "~/" + "Projects/" + "other").count, 1)
    }

    func testNoTrackedTextPointsAtThisMac() throws {
        let files = try scannedFiles()
        XCTAssertGreaterThan(files.count, 150, "the scan must actually read the repository")
        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(Self.root.standardizedFileURL.path.count + 1))
            offenders += Self.localPaths(in: text).map { "\(relative):\($0)" }
        }
        XCTAssertEqual(offenders, [], "local paths leak the owner's machine into a public repository")
    }
}
