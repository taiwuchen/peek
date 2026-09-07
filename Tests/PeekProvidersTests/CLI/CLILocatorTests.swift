import Testing
@testable import PeekProviders

struct CLILocatorTests {
    @Test func overrideAndCandidateOrder() async {
        let paths = ["/custom/claude", "/test/.local/bin/claude", "/test/.npm-global/bin/claude",
                     "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/test/.claude/local/bin/claude", "/test/.bun/bin/claude"]
        for index in paths.indices {
            let available = Set(paths[index...])
            let locator = CLILocator(home: "/test", isExecutable: { available.contains($0) }, shellLookup: { _ in
                Issue.record("Shell lookup should not run when a candidate is executable")
                return nil
            })
            #expect(await locator.locate("claude", override: "/custom/claude") == paths[index])
        }
    }

    @Test func shellFallbackValidatesExecutableAndIgnoresStartupNoise() async {
        let locator = CLILocator(home: "/test", isExecutable: { $0 == "/shell/codex" }, shellLookup: { _ in "Welcome\n/shell/codex\n" })
        #expect(await locator.locate("codex", override: "/missing") == "/shell/codex")
        #expect(await locator.locate("codex; touch /tmp/unsafe", override: nil) == nil)
        let missing = CLILocator(home: "/test", isExecutable: { _ in false }, shellLookup: { _ in "/missing/codex" })
        #expect(await missing.locate("codex", override: nil) == nil)
    }
}
