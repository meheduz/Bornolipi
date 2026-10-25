import Foundation

/// Reads GitHub's "latest release" document for Bornolipi. Only a published release of this project
/// with a plain version tag is accepted; nothing is downloaded or run, the user is shown the page.
public struct ReleaseInfo: Equatable {
    public let version: String
    public let page: URL
    /// Release notes as plain text (GitHub's Markdown source), at most `ReleaseFeed.notesLimit` characters.
    public let notes: String

    public init(version: String, page: URL, notes: String) {
        self.version = version
        self.page = page
        self.notes = notes
    }
}

public enum ReleaseFeed {
    public static let api = URL(string: "https://api.github.com/repos/meheduz/Bornolipi/releases/latest")!
    static let releasesPath = "/meheduz/Bornolipi/releases/"
    static let notesLimit = 4000

    public enum Problem: Error, Equatable { case unreadable, notThisProject, badVersion }

    /// The release if it is newer than `current`, nil if it is not, or a `Problem` if the document
    /// does not look like one of this project's releases.
    public static func newer(than current: Keyboard.Version, from data: Data) throws -> ReleaseInfo? {
        struct Release: Decodable {
            let tagName: String, htmlURL: URL, draft: Bool?, prerelease: Bool?, body: String?
            enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, body }
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { throw Problem.unreadable }
        guard release.htmlURL.scheme == "https", release.htmlURL.host == "github.com",
              release.htmlURL.path.hasPrefix(releasesPath) else { throw Problem.notThisProject }
        let tag = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let parts = tag.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 4 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else {
            throw Problem.badVersion
        }
        guard release.draft != true, release.prerelease != true,
              Keyboard.Version(short: current.short, build: 0) < Keyboard.Version(short: tag, build: 0) else { return nil }
        let notes = String((release.body ?? "").prefix(notesLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseInfo(version: tag, page: release.htmlURL, notes: notes)
    }
}
