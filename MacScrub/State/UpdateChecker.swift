import Foundation
import Observation

/// Subset of GitHub's `/releases/latest` payload we care about. Keys match the
/// JSON (snake_case), so no custom CodingKeys are needed; extra fields are ignored.
struct ReleaseInfo: Decodable, Equatable {
    let tag_name: String
    let html_url: URL
}

/// What the UI needs to surface an available update.
struct UpdateInfo: Equatable {
    let version: String   // the release tag as published, e.g. "v1.1.0"
    let pageURL: URL      // the GitHub release page
}

protocol ReleaseFetching {
    func fetchLatestRelease() async throws -> ReleaseInfo
}

/// Fetches the latest published (non-draft, non-prerelease) GitHub release.
struct GitHubReleaseFetcher: ReleaseFetching {
    private let url = URL(string: "https://api.github.com/repos/tufantunc/MacScrub/releases/latest")!

    func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
}

/// Returns true only when `latest` is strictly newer than `current`. Strips a
/// leading `v`/`V`, compares dot-separated components numerically (missing trailing
/// components count as 0, so "1.0" == "1.0.0"); non-numeric components count as 0.
func isVersion(_ latest: String, newerThan current: String) -> Bool {
    func components(_ s: String) -> [Int] {
        let trimmed = (s.first == "v" || s.first == "V") ? String(s.dropFirst()) : s
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
    let a = components(latest)
    let b = components(current)
    for i in 0..<max(a.count, b.count) {
        let l = i < a.count ? a[i] : 0
        let c = i < b.count ? b[i] : 0
        if l != c { return l > c }
    }
    return false
}

@MainActor
@Observable
final class UpdateChecker {
    private(set) var availableUpdate: UpdateInfo?

    private let fetcher: ReleaseFetching
    private let currentVersion: String
    private var didCheck = false

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
    }

    /// Checks once per process; failures are silent (availableUpdate stays nil).
    func checkForUpdate() async {
        guard !didCheck else { return }
        do {
            let release = try await fetcher.fetchLatestRelease()
            didCheck = true
            if isVersion(release.tag_name, newerThan: currentVersion) {
                availableUpdate = UpdateInfo(version: release.tag_name, pageURL: release.html_url)
            }
        } catch {
            // Silent on failure/cancellation; didCheck stays false so a later
            // .task can retry the check.
        }
    }
}
