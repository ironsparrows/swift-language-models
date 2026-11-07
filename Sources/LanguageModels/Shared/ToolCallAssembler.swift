import Foundation
package import FoundationModels
import LanguageModelsCore

/// An answer's tool calls, assembled from their fragments as they arrive.
///
/// Fragments are routed by index, so parallel calls form one round. A fragment without an index continues the last
/// call, unless it brings a new id, which starts the next call. A call starts once it has a name, with an id made up if
/// the model sent none or one another call already uses, so the calls keep their order and none replaces another.
/// Argument text that arrives before the name is held until the call starts.
package struct ToolCallAssembler {
    private var calls: [Int: Call] = [:]
    private var lastIndex: Int?

    /// Starts an answer with no tool calls.
    package init() {}

    /// Whether no fragment has arrived.
    package var isEmpty: Bool {
        calls.isEmpty
    }

    /// Adds one fragment to its call.
    ///
    /// - Parameters:
    ///   - index: The call's index in the answer, when the fragment names one.
    ///   - id: The call's id, when the fragment brings one.
    ///   - name: The tool's name, when the fragment brings it.
    ///   - arguments: The next part of the call's argument text.
    /// - Returns: The text to append to the call's arguments: all of it so far when the fragment starts the call, even
    ///   none, which announces the call; otherwise the fragment's own. `nil` when the call hasn't started or the
    ///   fragment has no text.
    package mutating func add(index: Int?, id: String?, name: String?, arguments: String?) -> Arguments? {
        let index = self.index(of: index, id: id)
        lastIndex = index
        var call = calls[index] ?? Call()
        let wasStarted = call.id != nil && call.name != nil
        if call.id == nil, let id, !id.isEmpty, !calls.values.contains(where: { $0.id == id }) { call.id = id }
        if call.name == nil, let name, !name.isEmpty { call.name = name }
        if call.name != nil, call.id == nil { call.id = "call_\(UUID().uuidString)" }
        call.pendingArguments += arguments ?? ""
        var arguments: Arguments?
        if let id = call.id, let name = call.name, !wasStarted || !call.pendingArguments.isEmpty {
            arguments = Arguments(callID: id, toolName: name, text: call.pendingArguments)
            call.argumentText += call.pendingArguments
            call.pendingArguments = ""
        }
        calls[index] = call
        return arguments
    }

    /// The id and tool name of the first call to start, in index order, which carries the round's facts, or `nil`
    /// before any call has started.
    package var firstCall: (id: String, toolName: String)? {
        for (_, call) in calls.sorted(by: { $0.key < $1.key }) {
            if let id = call.id, let name = call.name { return (id, name) }
        }
        return nil
    }

    /// Ends the calls.
    ///
    /// Foundation Models reads arguments that stop partway, so arguments that aren't a whole JSON object are refused
    /// here, before any tool runs with them.
    ///
    /// - Returns: An empty JSON object, in index order, as the arguments of each call that got none, since a call to a
    ///   tool without arguments may send none, and Foundation Models parses them as JSON.
    /// - Throws: ``Failure/missingName`` when a call never got its name, and ``Failure/incompleteArguments(toolName:)``
    ///   when a call's arguments aren't a whole JSON object.
    package func finish() throws(Failure) -> [Arguments] {
        var arguments: [Arguments] = []
        for (_, call) in calls.sorted(by: { $0.key < $1.key }) {
            guard let id = call.id, let name = call.name else { throw .missingName }
            if call.argumentText.isEmpty {
                arguments.append(Arguments(callID: id, toolName: name, text: "{}"))
            } else if case .object? = try? JSONValue(json: Data(call.argumentText.utf8)) {
                continue
            } else {
                throw .incompleteArguments(toolName: name)
            }
        }
        return arguments
    }

    /// The index of the call a fragment belongs to.
    private func index(of index: Int?, id: String?) -> Int {
        if let index { return index }
        guard let last = lastIndex else { return 0 }
        guard let id, !id.isEmpty, let lastID = calls[last]?.id, id != lastID else { return last }
        return (calls.keys.max() ?? last) + 1
    }
}

extension ToolCallAssembler {
    /// Text to append to the arguments of a started call.
    package struct Arguments: Equatable {
        package let callID: String
        package let toolName: String
        package let text: String

        package init(callID: String, toolName: String, text: String) {
            self.callID = callID
            self.toolName = toolName
            self.text = text
        }

        /// The event that appends the text to the call in the answer's tool-calls entry.
        package func event(in entryID: String) -> LanguageModelExecutorGenerationChannel.Event {
            .toolCalls(
                entryID: entryID,
                action: .toolCall(id: callID, name: toolName, action: .appendArguments(text, tokenCount: text.isEmpty ? 0 : 1))
            )
        }
    }

    /// Why the calls can't end.
    package enum Failure: Error {
        /// A call never got its name.
        case missingName

        /// A call's arguments aren't a whole JSON object, such as ones that stop partway.
        case incompleteArguments(toolName: String)
    }

    /// One call as its fragments arrive.
    private struct Call {
        var id: String?
        var name: String?
        /// Argument text that arrived before the call's name, held until the call can start.
        var pendingArguments = ""
        /// The argument text sent so far.
        var argumentText = ""
    }
}
