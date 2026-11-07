import LanguageModels
import Testing

@Suite("Tagged reasoning")
struct TaggedReasoningTests {
    @Test(
        arguments: [
            ("\n <think>\nPlan.\n</think>\n\nHello", "\nPlan.\n", "Hello", "\n <think>\nPlan.\n</think>\n\n"),
            ("<thinking></thinking>Hi", "", "Hi", "<thinking></thinking>"),
            ("<think>Plan.</think> \n", "Plan.", "", "<think>Plan.</think> \n"),
            ("<think>A</thinking>B", "A</thinking>B", "", "<think>A</thinking>B"),
            ("<think>Cut off", "Cut off", "", "<think>Cut off"),
            ("<thinking>Plan.</think", "Plan.</think", "", "<thinking>Plan.</think"),
        ],
        [false, true]
    )
    func `a block keeps what the model wrote, and the answer what follows it`(
        sample: (answer: String, reasoning: String, text: String, block: String),
        characterByCharacter: Bool
    ) {
        let result = split(sample.answer, characterByCharacter: characterByCharacter)

        #expect(result.split == TaggedReasoning.Split(reasoning: sample.reasoning, text: sample.text))
        #expect(result.block == sample.block)
    }

    @Test(
        arguments: ["Hello", "  <b>Hi</b>", "<thinker> Hi", "<Think>Hi</Think>", "Hi <think>A</think>", "<think", " \n"],
        [false, true]
    )
    func `text that doesn't open with a block comes out unchanged`(answer: String, characterByCharacter: Bool) {
        let result = split(answer, characterByCharacter: characterByCharacter)

        #expect(result.split == TaggedReasoning.Split(text: answer))
        #expect(result.block == nil)
    }

    @Test func `text is held back only while it may still be a tag`() {
        var tagged = TaggedReasoning()

        #expect(tagged.split(" <thi") == TaggedReasoning.Split())
        #expect(tagged.split("nk>Pl") == TaggedReasoning.Split(reasoning: "Pl"))
        #expect(tagged.split("an.</th") == TaggedReasoning.Split(reasoning: "an."))
        #expect(tagged.split("is is</") == TaggedReasoning.Split(reasoning: "</this is"))
        #expect(tagged.split("think>\n") == TaggedReasoning.Split())
        #expect(tagged.split(" Hi") == TaggedReasoning.Split(text: "Hi"))
        #expect(tagged.finish() == TaggedReasoning.Split())
        #expect(tagged.block == " <think>Plan.</this is</think>\n ")
    }

    @Test func `the start of an answer that isn't a tag comes out as soon as it's clear`() {
        var tagged = TaggedReasoning()

        #expect(tagged.split("  ") == TaggedReasoning.Split())
        #expect(tagged.split("<thin") == TaggedReasoning.Split())
        #expect(tagged.split("g ") == TaggedReasoning.Split(text: "  <thing "))
        #expect(tagged.split("<think>") == TaggedReasoning.Split(text: "<think>"))
    }

    /// The whole answer split, and the block it opened with, from one delta or one delta per character.
    private func split(_ answer: String, characterByCharacter: Bool) -> (split: TaggedReasoning.Split, block: String?) {
        var tagged = TaggedReasoning()
        let deltas = characterByCharacter ? answer.map(String.init) : [answer]
        let splits = deltas.map { tagged.split($0) } + [tagged.finish()]
        let split = TaggedReasoning.Split(reasoning: splits.map(\.reasoning).joined(), text: splits.map(\.text).joined())
        return (split, tagged.block)
    }
}
