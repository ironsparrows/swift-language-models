/// One event of a server-sent event stream: its name, when it has one, and its data, with the lines of a multi-line
/// `data` field joined by line breaks.
package struct ServerSentEvent: Equatable, Sendable {
    package var name: String?
    package var data: String

    package init(name: String? = nil, data: String) {
        self.name = name
        self.data = data
    }
}

extension ServerSentEvent {
    /// One line of a server-sent event stream.
    ///
    /// A blank line ends an event. A comment line, which servers send to keep a connection open, carries nothing.
    package enum Line: Equatable, Sendable {
        /// A `data:` line's payload.
        case data(String)

        /// An `event:` line's name.
        case event(String)

        /// The blank line that ends an event.
        case endOfEvent

        /// A comment, or a field the reader doesn't use, such as `id:` or `retry:`.
        case ignored

        /// Reads one line.
        ///
        /// - Parameter line: The line, without its line break.
        package init(_ line: some StringProtocol) {
            guard !line.isEmpty else {
                self = .endOfEvent
                return
            }
            // A line without a colon is a field with an empty value, and one that starts with a colon is a comment.
            let line = String(line)
            var field = line[...]
            var value = ""[...]
            if let colon = line.firstIndex(of: ":") {
                guard colon != line.startIndex else {
                    self = .ignored
                    return
                }
                field = line[..<colon]
                value = line[line.index(after: colon)...]
                if value.first == " " { value = value.dropFirst() }
            }
            switch String(field) {
            case "data": self = .data(String(value))
            case "event": self = .event(String(value))
            default: self = .ignored
            }
        }
    }

    /// The events of a byte stream, each ending at a blank line, and the last one also at the stream's end. An event
    /// without data, such as one of comments only, is skipped.
    package struct Events<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
        package typealias Element = ServerSentEvent
        package typealias Failure = Base.Failure

        private let base: Base

        package init(_ base: Base) {
            self.base = base
        }

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(lines: ByteLines(base).makeAsyncIterator())
        }

        package struct AsyncIterator: AsyncIteratorProtocol {
            private var lines: ByteLines<Base>.AsyncIterator
            private var isAtStart = true

            fileprivate init(lines: ByteLines<Base>.AsyncIterator) {
                self.lines = lines
            }

            package mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Base.Failure)
                -> ServerSentEvent?
            {
                var name: String?
                var data: [String] = []
                while var line = try await lines.next(isolation: actor) {
                    // A byte order mark may open the stream.
                    if isAtStart {
                        isAtStart = false
                        if line.unicodeScalars.first == "\u{FEFF}" { line.unicodeScalars.removeFirst() }
                    }
                    switch Line(line) {
                    case .data(let text): data.append(text)
                    case .event(let event): name = event
                    case .endOfEvent:
                        if !data.isEmpty { return ServerSentEvent(name: name, data: data.joined(separator: "\n")) }
                        name = nil
                    case .ignored: continue
                    }
                }
                return data.isEmpty ? nil : ServerSentEvent(name: name, data: data.joined(separator: "\n"))
            }

            package mutating func next() async throws(Base.Failure) -> ServerSentEvent? {
                try await next(isolation: #isolation)
            }
        }
    }
}
