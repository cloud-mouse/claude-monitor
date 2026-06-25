import Foundation
import Testing

@Suite
struct HookScriptTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func testInstallQuotesHookHandlerPathContainingSpaces() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let fixture = temp.appendingPathComponent("repo with spaces", isDirectory: true)
        try copyRepositoryFixture(to: fixture)

        let home = temp.appendingPathComponent("home", isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let settings = claude.appendingPathComponent("settings.json")
        try #"{"hooks":{}}"#.write(to: settings, atomically: true, encoding: .utf8)

        let result = runShell(
            fixture.appendingPathComponent("scripts/install-hooks.sh").path,
            environment: ["HOME": home.path]
        )

        #expect(result.status == 0)
        let json = try loadJSON(settings)
        let command = try #require(hookCommands(in: json, event: "PreToolUse").first)
        let expectedHandler = fixture.appendingPathComponent("Resources/hooks-handler.sh").path
        #expect(command == "'\(expectedHandler)' tool_call")
    }

    @Test
    func testInstallAddsMissingEventsEvenWhenAnotherEventAlreadyHasMonitorHook() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let fixture = temp.appendingPathComponent("repo", isDirectory: true)
        try copyRepositoryFixture(to: fixture)

        let home = temp.appendingPathComponent("home", isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let settings = claude.appendingPathComponent("settings.json")
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/old/path/hooks-handler.sh tool_call",
                    "timeout": 3
                  }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        let result = runShell(
            fixture.appendingPathComponent("scripts/install-hooks.sh").path,
            environment: ["HOME": home.path]
        )

        #expect(result.status == 0)
        let hooks = try #require(try loadJSON(settings)["hooks"] as? [String: Any])
        #expect(hooks["Stop"] != nil)
        #expect(hooks["StopFailure"] != nil)
        #expect(hooks["Notification"] != nil)
    }

    @Test
    func testUninstallOnlyRemovesHooksForThisRepositoryHandler() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let fixture = temp.appendingPathComponent("repo", isDirectory: true)
        try copyRepositoryFixture(to: fixture)

        let home = temp.appendingPathComponent("home", isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let ownHandler = fixture.appendingPathComponent("Resources/hooks-handler.sh").path
        let settings = claude.appendingPathComponent("settings.json")
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "\(ownHandler) tool_call",
                    "timeout": 3
                  },
                  {
                    "type": "command",
                    "command": "/other/tool/hooks-handler.sh tool_call",
                    "timeout": 3
                  }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        let result = runShell(
            fixture.appendingPathComponent("scripts/uninstall-hooks.sh").path,
            environment: ["HOME": home.path]
        )

        #expect(result.status == 0)
        let commands = hookCommands(in: try loadJSON(settings), event: "PreToolUse")
        #expect(commands == ["/other/tool/hooks-handler.sh tool_call"])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copyRepositoryFixture(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repoRoot.appendingPathComponent("scripts/install-hooks.sh"),
            to: destination.appendingPathComponent("scripts/install-hooks.sh")
        )
        try FileManager.default.copyItem(
            at: repoRoot.appendingPathComponent("scripts/uninstall-hooks.sh"),
            to: destination.appendingPathComponent("scripts/uninstall-hooks.sh")
        )
        try FileManager.default.copyItem(
            at: repoRoot.appendingPathComponent("Resources/hooks-handler.sh"),
            to: destination.appendingPathComponent("Resources/hooks-handler.sh")
        )
    }

    private func runShell(_ script: String, environment: [String: String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, "\(error)")
        }
    }

    private func loadJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hookCommands(in json: [String: Any], event: String) -> [String] {
        guard let hooks = json["hooks"] as? [String: Any],
              let configs = hooks[event] as? [[String: Any]] else {
            return []
        }

        return configs.flatMap { config -> [String] in
            guard let hookList = config["hooks"] as? [[String: Any]] else { return [] }
            return hookList.compactMap { $0["command"] as? String }
        }
    }
}
