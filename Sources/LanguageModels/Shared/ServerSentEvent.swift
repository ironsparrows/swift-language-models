// MARK: - Events

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

// MARK: - Lines

/// The lines of a byte stream, split at line feeds, carriage returns and the pair of both, as server-sent events end
/// their lines, each without its line break.
///
/// `URLSession.AsyncBytes.lines` also splits at Unicode line breaks such as U+2028, which JSON may carry unescaped
/// inside a string, so one server-sent event could arrive as two broken halves.
package struct ByteLines<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    package typealias Element = String
    package typealias Failure = Base.Failure

    private let base: Base

    /// The lines of a byte stream.
    ///
    /// - Parameter base: The bytes, such as a response body.
    package init(_ base: Base) {
        self.base = base
    }

    package func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator())
    }

    package struct AsyncIterator: AsyncIteratorProtocol {
        private var base: Base.AsyncIterator
        private var isFinished = false

        /// Whether the last line ended at a carriage return, so a line feed right after it ends no line of its own.
        private var followsCarriageReturn = false

        fileprivate init(base: Base.AsyncIterator) {
            self.base = base
        }

        package mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Base.Failure) -> String? {
            guard !isFinished else { return nil }
            var line: [UInt8] = []
            while let byte = try await base.next(isolation: actor) {
                if followsCarriageReturn {
                    followsCarriageReturn = false
                    if byte == 0x0A { continue }
                }
                switch byte {
                case 0x0A:
                    return Self.text(line)
                case 0x0D:
                    followsCarriageReturn = true
                    return Self.text(line)
                default:
                    line.append(byte)
                }
            }
            isFinished = true
            return line.isEmpty ? nil : Self.text(line)
        }

        package mutating func next() async throws(Base.Failure) -> String? {
            try await next(isolation: #isolation)
        }

        /// A line's text.
        private static func text(_ line: [UInt8]) -> String {
            String(decoding: line, as: UTF8.self)
        }
    }
}
