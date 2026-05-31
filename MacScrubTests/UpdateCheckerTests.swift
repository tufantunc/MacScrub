import Testing
import Foundation
@testable import MacScrub

@Suite("isVersion")
struct IsVersionTests {

    @Test("Newer major/minor/patch is detected")
    func testNewer() {
        #expect(isVersion("v1.1.0", newerThan: "1.0.0") == true)
        #expect(isVersion("2.0.0", newerThan: "1.9.9") == true)
        #expect(isVersion("v2", newerThan: "1.9.9") == true)
    }

    @Test("Equal versions are not newer (including differing component counts)")
    func testEqual() {
        #expect(isVersion("1.0.0", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0.0", newerThan: "1.0") == false)
    }

    @Test("Older versions are not newer")
    func testOlder() {
        #expect(isVersion("0.9.0", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0.0", newerThan: "1.1.0") == false)
    }

    @Test("Components compare numerically, not lexically")
    func testNumeric() {
        #expect(isVersion("1.10.0", newerThan: "1.2.0") == true)
        #expect(isVersion("1.2.0", newerThan: "1.10.0") == false)
    }

    @Test("Non-numeric components are treated as 0 and never crash")
    func testNonNumeric() {
        #expect(isVersion("abc", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0.0", newerThan: "abc") == true)
    }
}

@MainActor
@Suite("UpdateChecker")
struct UpdateCheckerTests {

    private func info(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tag_name: tag, html_url: URL(string: "https://github.com/tufantunc/MacScrub/releases/tag/\(tag)")!)
    }

    @Test("Newer release publishes availableUpdate")
    func testNewerPublishes() async {
        let checker = UpdateChecker(
            fetcher: MockReleaseFetcher(result: .success(info("v1.1.0"))),
            currentVersion: "1.0.0"
        )
        await checker.checkForUpdate()
        #expect(checker.availableUpdate?.version == "v1.1.0")
        #expect(checker.availableUpdate?.pageURL.absoluteString.contains("v1.1.0") == true)
    }

    @Test("Equal release leaves availableUpdate nil")
    func testEqualNil() async {
        let checker = UpdateChecker(
            fetcher: MockReleaseFetcher(result: .success(info("v1.0.0"))),
            currentVersion: "1.0.0"
        )
        await checker.checkForUpdate()
        #expect(checker.availableUpdate == nil)
    }

    @Test("Fetch error leaves availableUpdate nil")
    func testErrorNil() async {
        struct Boom: Error {}
        let checker = UpdateChecker(
            fetcher: MockReleaseFetcher(result: .failure(Boom())),
            currentVersion: "1.0.0"
        )
        await checker.checkForUpdate()
        #expect(checker.availableUpdate == nil)
    }

    @Test("checkForUpdate fetches only once per instance")
    func testFetchesOnce() async {
        final class CountingFetcher: ReleaseFetching {
            var callCount = 0
            let info: ReleaseInfo
            init(_ info: ReleaseInfo) { self.info = info }
            func fetchLatestRelease() async throws -> ReleaseInfo {
                callCount += 1
                return info
            }
        }
        let fetcher = CountingFetcher(info("v1.1.0"))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.0.0")
        await checker.checkForUpdate()
        await checker.checkForUpdate()
        #expect(fetcher.callCount == 1)
        #expect(checker.availableUpdate?.version == "v1.1.0")
    }
}

struct MockReleaseFetcher: ReleaseFetching {
    var result: Result<ReleaseInfo, Error>
    func fetchLatestRelease() async throws -> ReleaseInfo { try result.get() }
}
