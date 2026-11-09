import Testing

@testable import LanguageModels

private typealias Arguments = ToolCallAssembler.Arguments

@Suite("Tool call assembler", .timeLimit(.minutes(1)))
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

    @Test func `calls end in index order, with an empty object for each call that got no arguments or only whitespace`() throws {
        var calls = ToolCallAssembler()

        _ = calls.add(fragment(index: 2, id: "call_c", name: "date"))
        _ = calls.add(fragment(index: 0, id: "call_a", name: "weather"))
        _ = calls.add(fragment(index: 1, id: "call_b", name: "time", arguments: "{}"))
        _ = calls.add(fragment(index: 3, id: "call_d", name: "zone", arguments: " \n"))

        #expect(
            try calls.finish() == [
                Arguments(callID: "call_a", toolName: "weather", text: "{}"),
                Arguments(callID: "call_c", toolName: "date", text: "{}"),
                Arguments(callID: "call_d", toolName: "zone", text: "{}"),
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

    @Test(arguments: [
        // Each call whole in one fragment, with an id of its own.
        (
            [
                fragment(index: 0, id: "call_1", name: "fn", arguments: #"{"value":1}"#),
                fragment(index: 0, id: "call_2", name: "fn", arguments: #"{"value":2}"#),
            ],
            [#"fn {"value":1}"#, #"fn {"value":2}"#]
        ),
        // Each call opening with empty arguments, its later fragments repeating its id or leaving it out.
        (
            [
                fragment(index: 0, id: "call_1", name: "fn", arguments: ""), fragment(index: 0, id: "call_1", arguments: #"{"value":1}"#),
                fragment(index: 0, id: "call_2", name: "fn", arguments: ""), fragment(index: 0, id: "call_2", arguments: #"{"value":2}"#),
            ],
            [#"fn {"value":1}"#, #"fn {"value":2}"#]
        ),
        (
            [
                fragment(index: 0, id: "call_1", name: "fn", arguments: ""), fragment(index: 0, arguments: #"{"value":1}"#),
                fragment(index: 0, id: "call_2", name: "fn", arguments: ""), fragment(index: 0, arguments: #"{"value":2}"#),
            ],
            [#"fn {"value":1}"#, #"fn {"value":2}"#]
        ),
        // Calls without ids, told apart by their names, or by arguments that start a value after whole ones.
        (
            [
                fragment(index: 0, name: "read", arguments: #"{"path":"p0"}"#),
                fragment(index: 0, name: "write", arguments: #"{"path":"p1"}"#),
                fragment(index: 0, name: "read", arguments: #"{"path":"p2"}"#),
            ],
            [#"read {"path":"p0"}"#, #"write {"path":"p1"}"#, #"read {"path":"p2"}"#]
        ),
        (
            [fragment(index: 0, name: "fn", arguments: #"{"value":1}"#), fragment(index: 0, name: "fn", arguments: #"{"value":2}"#)],
            [#"fn {"value":1}"#, #"fn {"value":2}"#]
        ),
    ])
    func `calls that share an index stay apart`(fragments: [Fragment], expected: [String]) throws {
        var calls = ToolCallAssembler()

        let appended = fragments.compactMap { calls.add($0) }

        #expect(started(appended) == expected)
        #expect(try calls.finish().isEmpty)
    }

    @Test func `calls without arguments that share an index each end with an empty object, in the order they started`() throws {
        var calls = ToolCallAssembler()

        _ = calls.add(fragment(index: 0, id: "call_1", name: "readClock", arguments: ""))
        _ = calls.add(fragment(index: 0, id: "call_2", name: "readDate", arguments: ""))

        #expect(
            try calls.finish() == [
                Arguments(callID: "call_1", toolName: "readClock", text: "{}"),
                Arguments(callID: "call_2", toolName: "readDate", text: "{}"),
            ])
    }

    @Test(arguments: [
        // A new id on a call whose arguments aren't whole yet, with the name repeated or not.
        (
            [
                fragment(index: 0, id: "call_1", name: "read", arguments: #"{"pa"#),
                fragment(index: 0, id: "unexpected", name: "read", arguments: #"th":"a"}"#),
            ],
            #"{"path":"a"}"#
        ),
        (
            [
                fragment(index: 0, id: "call_1", name: "read", arguments: #"{"pa"#),
                fragment(index: 0, id: "unexpected", arguments: #"th":"a"}"#),
            ],
            #"{"path":"a"}"#
        ),
        // The call's own id and name repeated before a nested object.
        (
            [
                fragment(index: 0, id: "call_1", name: "read", arguments: #"{"value":"#),
                fragment(index: 0, id: "call_1", name: "read", arguments: #"{"nested":true}}"#),
            ],
            #"{"value":{"nested":true}}"#
        ),
        // An id the call switched to, repeated with the name once its arguments are whole.
        (
            [
                fragment(index: 0, id: "call_1", name: "read", arguments: #"{"city":"#),
                fragment(index: 0, id: "alias", name: "read", arguments: ""),
                fragment(index: 0, id: "alias", arguments: #""Berlin"}"#), fragment(index: 0, id: "alias", name: "read", arguments: ""),
            ],
            #"{"city":"Berlin"}"#
        ),
        // An id that arrives after the whole arguments of a call that brought none.
        (
            [fragment(index: 0, name: "read", arguments: #"{"value":1}"#), fragment(index: 0, id: "call_2", name: "read", arguments: "")],
            #"{"value":1}"#
        ),
    ])
    func `a fragment continues the call at its index unless it starts another one`(fragments: [Fragment], text: String) throws {
        var calls = ToolCallAssembler()

        let appended = fragments.compactMap { calls.add($0) }

        #expect(Set(appended.map(\.callID)).count == 1)
        #expect(appended.map(\.text).joined() == text)
        #expect(try calls.finish().isEmpty)
    }

    @Test func `no fragment leaves the assembler empty`() {
        var calls = ToolCallAssembler()
        #expect(calls.isEmpty)

        _ = calls.add(fragment(index: 0, arguments: "{}"))

        #expect(!calls.isEmpty)
    }
}

extension ToolCallAssemblerTests {
    /// A tool-call fragment as a chunk carries it.
    struct Fragment: Sendable {
        let index: Int?
        let id: String?
        let name: String?
        let arguments: String?
    }
}

/// A tool-call fragment with the members it carries.
private func fragment(index: Int? = nil, id: String? = nil, name: String? = nil, arguments: String? = nil)
    -> ToolCallAssemblerTests.Fragment
{
    ToolCallAssemblerTests.Fragment(index: index, id: id, name: name, arguments: arguments)
}

/// Each call's tool name and argument text, in the order the calls started.
private func started(_ appended: [Arguments]) -> [String] {
    var order: [String] = []
    var calls: [String: (name: String, text: String)] = [:]
    for arguments in appended {
        if calls[arguments.callID] == nil { order.append(arguments.callID) }
        calls[arguments.callID, default: (arguments.toolName, "")].text += arguments.text
    }
    return order.compactMap { id in calls[id].map { "\($0.name) \($0.text)" } }
}

extension ToolCallAssembler {
    /// Adds one of a chunk's tool-call fragments to its call, as the format's stream routes it.
    fileprivate mutating func add(_ fragment: ToolCallAssemblerTests.Fragment) -> Arguments? {
        add(index: fragment.index, id: fragment.id, name: fragment.name, arguments: fragment.arguments)
    }
}
