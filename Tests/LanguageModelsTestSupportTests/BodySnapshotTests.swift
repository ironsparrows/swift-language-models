import Foundation
import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

@Suite("Body snapshot")
struct BodySnapshotTests {
    @Test func `a body shows one member per line and keeps its order, escapes and number spellings`() {
        let body = Data(
            #"{"model":"m","messages":[{"role":"user","content":"a \"q\" , { } : [ ] \u00e9 é\\"}],"temperature":0.10,"n":1e3,"empty":{},"list":[],"stream":true}"#
                .utf8)

        assertInlineSnapshot(of: body, as: .memberLines) {
            #"""
            {
              "model": "m",
              "messages": [
                {
                  "role": "user",
                  "content": "a \"q\" , { } : [ ] \u00e9 é\\"
                }
              ],
              "temperature": 0.10,
              "n": 1e3,
              "empty": {},
              "list": [],
              "stream": true
            }
            """#
        }
    }

    @Test(
        arguments: [
            #"{}"#,
            #"[]"#,
            #"[[],{},[{}]]"#,
            #"{"a":{"b":[1,2,{"c":null}]}}"#,
            #""a string, with: {punctuation}""#,
            #"{"key with spaces":"value\twith\nescapes \\\" and \\"}"#,
            #"{"unicode":"é 𝄞 \u2028","e":-1.5e-7}"#,
        ])
    func `removing the added whitespace gives the bytes back`(json: String) throws {
        let body = Data(json.utf8)

        #expect(BodySnapshot.bytes(of: try BodySnapshot.text(of: body)) == body)
    }

    @Test(arguments: [#"{ "a":1}"#, "{\"a\":\n1}", "[1,\t2]", "{\"a\":1}\r\n", "1]", "[1]]", #"{"a":1}}"#])
    func `a body with whitespace outside its strings, or a bracket that closes nothing, is refused`(json: String) {
        #expect(throws: BodySnapshot.NotCompact.self) {
            try BodySnapshot.text(of: Data(json.utf8))
        }
    }

    @Test(.snapshots(record: .never))
    func `a body that isn't compact fails its test, so it can't be recorded as right`() {
        withKnownIssue {
            assertInlineSnapshot(of: Data(#"{ "a":1}"#.utf8), as: .memberLines) {
                """
                The body isn't compact JSON, so its bytes can't be shown one member per line.
                """
            }
        } matching: { issue in
            issue.description.hasSuffix("The body isn't compact JSON, so its bytes can't be shown one member per line.")
        }
    }
}
