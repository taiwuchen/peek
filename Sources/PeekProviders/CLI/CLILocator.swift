import Foundation

internal struct CLILocator: Sendable {
    var home: String = FileManager.default.homeDirectoryForCurrentUser.path
    var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    var shellLookup: @Sendable (String) async -> String? = { name in
        try? await Subprocess(executable: "/bin/zsh", arguments: ["-lic", "command -v \(name)"], timeout: 3).output()
    }

    func locate(_ name: String, override: String?) async -> String? {
        guard name == "claude" || name == "codex" else { return nil }
        let directories = ["\(home)/.local/bin", "\(home)/.npm-global/bin", "/opt/homebrew/bin",
                           "/usr/local/bin", "\(home)/.claude/local/bin", "\(home)/.bun/bin"]
        let paths = [override].compactMap { $0 }.map { ($0 as NSString).expandingTildeInPath }
            + directories.map { "\($0)/\(name)" }
        if let path = paths.first(where: isExecutable) { return path }
        guard let output = await shellLookup(name) else { return nil }
        return output.split(separator: "\n").reversed().map(String.init).first { $0.hasPrefix("/") && isExecutable($0) }
    }
}
