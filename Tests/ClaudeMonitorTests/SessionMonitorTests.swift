@testable import ClaudeMonitor
import Testing

@Suite
struct SessionMonitorTests {
    @Test
    func testStatusMapKeepsNewestSessionWhenPidAppearsMoreThanOnce() {
        let old = makeSession(pid: 42, sessionId: "old", updatedAt: 100, status: "busy")
        let newest = makeSession(pid: 42, sessionId: "new", updatedAt: 200, status: "idle")

        let map = SessionMonitor.statusMap(for: [old, newest], now: 250)

        #expect(map[42] == newest.displayStatus(now: 250))
    }

    @Test
    func testPreviousSessionMapKeepsNewestSessionWhenPidAppearsMoreThanOnce() {
        let old = makeSession(pid: 42, sessionId: "old", updatedAt: 100, status: "busy")
        let newest = makeSession(pid: 42, sessionId: "new", updatedAt: 200, status: "idle")

        let map = SessionMonitor.sessionMapByPid([old, newest])

        #expect(map[42]?.sessionId == "new")
    }

    @Test
    func testAppleScriptBooleanResultTreatsFalseStringAsFalse() {
        #expect(!SessionMonitor.appleScriptBooleanResult("false"))
        #expect(!SessionMonitor.appleScriptBooleanResult("0"))
        #expect(SessionMonitor.appleScriptBooleanResult("true"))
        #expect(SessionMonitor.appleScriptBooleanResult("1"))
    }

    private func makeSession(
        pid: Int,
        sessionId: String,
        updatedAt: Int64,
        status: String
    ) -> Session {
        Session(
            pid: pid,
            sessionId: sessionId,
            cwd: "/tmp/project-\(sessionId)",
            startedAt: updatedAt - 10,
            procStart: "",
            version: "test",
            peerProtocol: nil,
            kind: nil,
            entrypoint: nil,
            status: status,
            updatedAt: updatedAt
        )
    }
}
