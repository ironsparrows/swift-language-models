import Testing

@testable import LanguageModels

private typealias Arguments = ToolCallAssembler.Arguments

@Suite("Tool call assembler")
struct ToolCallAssemblerTests {
    @Test func `fragments form the calls of one round by index, each announced when it starts`() throws {
        var calls = ToolCallAssembler()

        let appended = [
            calls.add(fragment(index: 0, id: "call_a", name: "weather")),
            calls.add(fragment(index: 1, id: "call_b", name: "time", arguments: "{}")),
            calls.add(fragment(index: 0, arguments: #"{"city":"#)),
            calls.add(fragment(index: 0, arguments: #""Athens"}"#)),
        ]

        #expect(
            appended == [
                Arguments(callID: "call_a", toolName: "weather", text: ""),
                Arguments(callID: "call_b", toolName: "time", text: "{}"),
                Arguments(callID: "call_a", toolName: "weather", text: #"{"city":"#),
                Arguments(callID: "call_a", toolName: "weather", text: #""Athens"}"#),
            ])
        #expect(try calls.finish().isEmpty)
    }

    @Test func `argument text that arrives before the name waits until the call starts`() {
        var calls = ToolCallAssembler()

        let early = calls.add(fragment(index: 0, arguments: #"{"city":"#))
        let start = calls.add(fragment(index: 0, id: "call_a", name: "weather", arguments: #""Athens"}"#))

        #expect(early == nil)
        #expect(start == Arguments(callID: "call_a", toolName: "weather", text: #"{"city":"Athens"}"#))
    }

    @Test func `a fragment without an index continues the last call, unless it brings a new id`() throws {
        var calls = ToolCallAssembler()

        _ = calls.add(fragment(id: "call_a", name: "weather"))
        let continued = calls.add(fragment(arguments: "{}"))
        let next = calls.add(fragment(id: "call_b", name: "time"))

        #expect(continued == Arguments(callID: "call_a", toolName: "weather", text: "{}"))
        #expect(next == Arguments(callID: "call_b", toolName: "time", text: ""))
        #expect(try calls.finish() == [Arguments(callID: "call_b", toolName: "time", text: "{}")])
    }

    @Test func `a call without an id, or with one another call uses, gets an id of its own`() throws {
        var calls = ToolCallAssembler()

        let unnamed = calls.add(fragment(index: 0, name: "weather"))
        _ = calls.add(fragment(index: 1, id: "call_b", name: "time"))
        let repeated = calls.add(fragment(index: 2, id: "call_b", name: "date"))

        let ids = try [unnamed, repeated].map { try #require($0).callID }
        #expect(ids.allSatisfy { $0.hasPrefix("call_") })
        #expect(Set(ids + ["call_b"]).count == 3)
    }

    @Test func `calls end in index order, with an empty object for each call that got no arguments`() throws {
        var calls = ToolCallAssembler()

        _ = calls.add(fragment(index: 2, id: "call_c", name: "date"))
        _ = calls.add(fragment(index: 0, id: "call_a", name: "weather"))
        _ = calls.add(fragment(index: 1, id: "call_b", name: "time", arguments: "{}"))

        #expect(
            try calls.finish() == [
                Arguments(callID: "call_a", toolName: "weather", text: "{}"),
                Arguments(callID: "call_c", toolName: "date", text: "{}"),
            ])
    }

    @Test func `a call that never got its name throws when the calls end`() {
        var calls = ToolCallAssembler()

        let appended = calls.add(fragment(index: 0, id: "call_a", arguments: "{}"))

        #expect(appended == nil)
        let error = #expect(throws: ToolCallAssembler.Failure.self) { try calls.finish() }
        guard case .missingName? = error else {
            Issue.record("The calls ended with \(String(describing: error)).")
            return
        }
    }

    @Test(arguments: [#"{"food":"eg"#, #"["egg"]"#, "eggs"])
    func `arguments that aren't a whole JSON object throw when the calls end`(arguments: String) {
        var calls = ToolCallAssembler()

        _ = calls.add(fragment(index: 0, id: "call_a", name: "order", arguments: arguments))

        let error = #expect(throws: ToolCallAssembler.Failure.self) { try calls.finish() }
        guard case .incompleteArguments(let toolName)? = error else {
            Issue.record("The calls ended with \(String(describing: error)).")
            return
        }
        #expect(toolName == "order")
    }

    @Test func `no fragment leaves the assembler empty`() {
        var calls = ToolCallAssembler()
        #expect(calls.isEmpty)

        _ = calls.add(fragment(index: 0, arguments: "{}"))

        #expect(!calls.isEmpty)
    }
}

/// A tool-call fragment as a chunk carries it.
private struct Fragment {
    let index: Int?
    let id: String?
    let name: String?
    let arguments: String?
}

/// A tool-call fragment with the members it carries.
private func fragment(index: Int? = nil, id: String? = nil, name: String? = nil, arguments: String? = nil) -> Fragment {
    Fragment(index: index, id: id, name: name, arguments: arguments)
}

extension ToolCallAssembler {
    /// Adds one of a chunk's tool-call fragments to its call, as the format's stream routes it.
    fileprivate mutating func add(_ fragment: Fragment) -> Arguments? {
        add(index: fragment.index, id: fragment.id, name: fragment.name, arguments: fragment.arguments)
    }
}
