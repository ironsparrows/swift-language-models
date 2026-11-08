import FoundationModels
import LanguageModelsCore
import Testing

@Suite("Guide check")
struct GuideCheckTests {
    @Test func `an answer that breaks a guide throws the parsing error, naming the value and the guide`() async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: #"{"minutes":2,"steps":["Boil."]}"#))

        let error = await #expect(throws: GeneratedContent.ParsingError.self) {
            try await session.respond(to: "A quick dinner.", generating: Dinner.self)
        }

        #expect(error?.rawContent == #"{"minutes":2,"steps":["Boil."]}"#)
        #expect(
            error?.debugDescription
                == "The answer breaks its schema's guides: minutes is 2, below the minimum of 5; steps has 1 item, fewer than the minimum of 3."
        )
    }

    @Test func `the parsing error carries each violation, with its path, keyword, value and limit`() async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: #"{"minutes":2,"steps":["Boil."]}"#))

        let error = await #expect(throws: GeneratedContent.ParsingError.self) {
            try await session.respond(to: "A quick dinner.", generating: Dinner.self)
        }

        let broken = try #require(error?.underlyingError as? GuideViolations)
        #expect(broken.violations.map(\.path) == ["minutes", "steps"])
        #expect(broken.violations.map(\.keyword) == [.minimum, .minItems])
        #expect(broken.violations.map(\.value) == [GeneratedContent(kind: .number(2)), GeneratedContent(elements: ["Boil."])])
        #expect(broken.violations.map(\.limit) == [GeneratedContent(kind: .number(5)), GeneratedContent(kind: .number(3))])
        #expect(broken.description == "minutes is 2, below the minimum of 5; steps has 1 item, fewer than the minimum of 3")
    }

    @Test func `an answer that meets its guides decodes`() async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: #"{"minutes":20,"steps":["Chop.","Fry.","Serve."]}"#))

        let dinner = try await session.respond(to: "A quick dinner.", generating: Dinner.self).content

        #expect(dinner.minutes == 20)
    }

    @Test func `an enum's case is checked against the case it names`() async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: #"{"shape":{"type":"circle","value":{"radius":0}}}"#))

        let error = await #expect(throws: GeneratedContent.ParsingError.self) {
            try await session.respond(to: "A shape.", generating: Drawing.self)
        }

        #expect(error?.debugDescription == "The answer breaks its schema's guides: shape.value.radius is 0, below the minimum of 1.")
    }

    @Test(arguments: ["Twenty minutes.", #"{"minutes":20,"steps":["Chop.","Fr"#])
    func `an object answer that isn't complete JSON throws the parsing error`(answer: String) async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: answer))

        let error = await #expect(throws: GeneratedContent.ParsingError.self) {
            try await session.respond(to: "A quick dinner.", generating: Dinner.self)
        }

        #expect(error?.debugDescription == "The answer isn't complete JSON.")
    }

    @Test func `a string answer that isn't JSON is left to the decoding`() async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: "Twenty minutes."))

        #expect(try await session.respond(to: "How long?", generating: String.self).content == "Twenty minutes.")
    }

    @Test func `an answer without a schema isn't checked`() async throws {
        let session = LanguageModelSession(model: FixedAnswerModel(answer: #"{"minutes":2}"#))

        #expect(try await session.respond(to: "A quick dinner.").content == #"{"minutes":2}"#)
    }
}

@Generable
private struct Circle {
    @Guide(.minimum(1))
    var radius: Int
}

@Generable
private enum Shape {
    case circle(Circle)
    case square(side: Int)
}

@Generable
private struct Drawing {
    var shape: Shape
}

@Generable
private struct Dinner {
    @Guide(.range(5...120))
    var minutes: Int

    @Guide(.count(3))
    var steps: [String]
}
