import Testing
@testable import SiriusMarkdownCore

private let explicitStreamingCorpus = """
# Matrix

Paragraph before a list with [link](https://example.com) and `code`.

- [ ] first
- [x] second


> quote one
> quote two

```swift
let value = "fence"
```

$$
a^2 + b^2
$$

<div>
html
</div>

Done.
"""

private func assertExplicitStreamingEquivalence(chunkSize: Int) {
    var streamed = MarkdownStream()
    var chunk = ""

    for character in explicitStreamingCorpus {
        chunk.append(character)
        if chunk.count == chunkSize {
            streamed.append(chunk)
            chunk.removeAll(keepingCapacity: true)
        }
    }

    if !chunk.isEmpty {
        streamed.append(chunk)
    }
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(explicitStreamingCorpus)
    oneShot.finish()

    let streamedSnapshot = streamed.snapshot()
    let oneShotSnapshot = oneShot.snapshot()

    #expect(streamedSnapshot.blocks.map(\.id) == oneShotSnapshot.blocks.map(\.id))
    #expect(streamedSnapshot.blocks.map(\.kind) == oneShotSnapshot.blocks.map(\.kind))
    #expect(streamedSnapshot.blocks.map(\.text) == oneShotSnapshot.blocks.map(\.text))
    #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
}

@Test func explicitStreamingEquivalenceChunk001() { assertExplicitStreamingEquivalence(chunkSize: 1) }
@Test func explicitStreamingEquivalenceChunk002() { assertExplicitStreamingEquivalence(chunkSize: 2) }
@Test func explicitStreamingEquivalenceChunk003() { assertExplicitStreamingEquivalence(chunkSize: 3) }
@Test func explicitStreamingEquivalenceChunk004() { assertExplicitStreamingEquivalence(chunkSize: 4) }
@Test func explicitStreamingEquivalenceChunk005() { assertExplicitStreamingEquivalence(chunkSize: 5) }
@Test func explicitStreamingEquivalenceChunk006() { assertExplicitStreamingEquivalence(chunkSize: 6) }
@Test func explicitStreamingEquivalenceChunk007() { assertExplicitStreamingEquivalence(chunkSize: 7) }
@Test func explicitStreamingEquivalenceChunk008() { assertExplicitStreamingEquivalence(chunkSize: 8) }
@Test func explicitStreamingEquivalenceChunk009() { assertExplicitStreamingEquivalence(chunkSize: 9) }
@Test func explicitStreamingEquivalenceChunk010() { assertExplicitStreamingEquivalence(chunkSize: 10) }
@Test func explicitStreamingEquivalenceChunk011() { assertExplicitStreamingEquivalence(chunkSize: 11) }
@Test func explicitStreamingEquivalenceChunk012() { assertExplicitStreamingEquivalence(chunkSize: 12) }
@Test func explicitStreamingEquivalenceChunk013() { assertExplicitStreamingEquivalence(chunkSize: 13) }
@Test func explicitStreamingEquivalenceChunk014() { assertExplicitStreamingEquivalence(chunkSize: 14) }
@Test func explicitStreamingEquivalenceChunk015() { assertExplicitStreamingEquivalence(chunkSize: 15) }
@Test func explicitStreamingEquivalenceChunk016() { assertExplicitStreamingEquivalence(chunkSize: 16) }
@Test func explicitStreamingEquivalenceChunk017() { assertExplicitStreamingEquivalence(chunkSize: 17) }
@Test func explicitStreamingEquivalenceChunk018() { assertExplicitStreamingEquivalence(chunkSize: 18) }
@Test func explicitStreamingEquivalenceChunk019() { assertExplicitStreamingEquivalence(chunkSize: 19) }
@Test func explicitStreamingEquivalenceChunk020() { assertExplicitStreamingEquivalence(chunkSize: 20) }
@Test func explicitStreamingEquivalenceChunk021() { assertExplicitStreamingEquivalence(chunkSize: 21) }
@Test func explicitStreamingEquivalenceChunk022() { assertExplicitStreamingEquivalence(chunkSize: 22) }
@Test func explicitStreamingEquivalenceChunk023() { assertExplicitStreamingEquivalence(chunkSize: 23) }
@Test func explicitStreamingEquivalenceChunk024() { assertExplicitStreamingEquivalence(chunkSize: 24) }
@Test func explicitStreamingEquivalenceChunk025() { assertExplicitStreamingEquivalence(chunkSize: 25) }
@Test func explicitStreamingEquivalenceChunk026() { assertExplicitStreamingEquivalence(chunkSize: 26) }
@Test func explicitStreamingEquivalenceChunk027() { assertExplicitStreamingEquivalence(chunkSize: 27) }
@Test func explicitStreamingEquivalenceChunk028() { assertExplicitStreamingEquivalence(chunkSize: 28) }
@Test func explicitStreamingEquivalenceChunk029() { assertExplicitStreamingEquivalence(chunkSize: 29) }
@Test func explicitStreamingEquivalenceChunk030() { assertExplicitStreamingEquivalence(chunkSize: 30) }
@Test func explicitStreamingEquivalenceChunk031() { assertExplicitStreamingEquivalence(chunkSize: 31) }
@Test func explicitStreamingEquivalenceChunk032() { assertExplicitStreamingEquivalence(chunkSize: 32) }
@Test func explicitStreamingEquivalenceChunk033() { assertExplicitStreamingEquivalence(chunkSize: 33) }
@Test func explicitStreamingEquivalenceChunk034() { assertExplicitStreamingEquivalence(chunkSize: 34) }
@Test func explicitStreamingEquivalenceChunk035() { assertExplicitStreamingEquivalence(chunkSize: 35) }
@Test func explicitStreamingEquivalenceChunk036() { assertExplicitStreamingEquivalence(chunkSize: 36) }
@Test func explicitStreamingEquivalenceChunk037() { assertExplicitStreamingEquivalence(chunkSize: 37) }
@Test func explicitStreamingEquivalenceChunk038() { assertExplicitStreamingEquivalence(chunkSize: 38) }
@Test func explicitStreamingEquivalenceChunk039() { assertExplicitStreamingEquivalence(chunkSize: 39) }
@Test func explicitStreamingEquivalenceChunk040() { assertExplicitStreamingEquivalence(chunkSize: 40) }
@Test func explicitStreamingEquivalenceChunk041() { assertExplicitStreamingEquivalence(chunkSize: 41) }
@Test func explicitStreamingEquivalenceChunk042() { assertExplicitStreamingEquivalence(chunkSize: 42) }
@Test func explicitStreamingEquivalenceChunk043() { assertExplicitStreamingEquivalence(chunkSize: 43) }
@Test func explicitStreamingEquivalenceChunk044() { assertExplicitStreamingEquivalence(chunkSize: 44) }
@Test func explicitStreamingEquivalenceChunk045() { assertExplicitStreamingEquivalence(chunkSize: 45) }
@Test func explicitStreamingEquivalenceChunk046() { assertExplicitStreamingEquivalence(chunkSize: 46) }
@Test func explicitStreamingEquivalenceChunk047() { assertExplicitStreamingEquivalence(chunkSize: 47) }
@Test func explicitStreamingEquivalenceChunk048() { assertExplicitStreamingEquivalence(chunkSize: 48) }
@Test func explicitStreamingEquivalenceChunk049() { assertExplicitStreamingEquivalence(chunkSize: 49) }
@Test func explicitStreamingEquivalenceChunk050() { assertExplicitStreamingEquivalence(chunkSize: 50) }
@Test func explicitStreamingEquivalenceChunk051() { assertExplicitStreamingEquivalence(chunkSize: 51) }
@Test func explicitStreamingEquivalenceChunk052() { assertExplicitStreamingEquivalence(chunkSize: 52) }
@Test func explicitStreamingEquivalenceChunk053() { assertExplicitStreamingEquivalence(chunkSize: 53) }
@Test func explicitStreamingEquivalenceChunk054() { assertExplicitStreamingEquivalence(chunkSize: 54) }
@Test func explicitStreamingEquivalenceChunk055() { assertExplicitStreamingEquivalence(chunkSize: 55) }
@Test func explicitStreamingEquivalenceChunk056() { assertExplicitStreamingEquivalence(chunkSize: 56) }
@Test func explicitStreamingEquivalenceChunk057() { assertExplicitStreamingEquivalence(chunkSize: 57) }
@Test func explicitStreamingEquivalenceChunk058() { assertExplicitStreamingEquivalence(chunkSize: 58) }
@Test func explicitStreamingEquivalenceChunk059() { assertExplicitStreamingEquivalence(chunkSize: 59) }
@Test func explicitStreamingEquivalenceChunk060() { assertExplicitStreamingEquivalence(chunkSize: 60) }
@Test func explicitStreamingEquivalenceChunk061() { assertExplicitStreamingEquivalence(chunkSize: 61) }
@Test func explicitStreamingEquivalenceChunk062() { assertExplicitStreamingEquivalence(chunkSize: 62) }
@Test func explicitStreamingEquivalenceChunk063() { assertExplicitStreamingEquivalence(chunkSize: 63) }
@Test func explicitStreamingEquivalenceChunk064() { assertExplicitStreamingEquivalence(chunkSize: 64) }
@Test func explicitStreamingEquivalenceChunk065() { assertExplicitStreamingEquivalence(chunkSize: 65) }
@Test func explicitStreamingEquivalenceChunk066() { assertExplicitStreamingEquivalence(chunkSize: 66) }
@Test func explicitStreamingEquivalenceChunk067() { assertExplicitStreamingEquivalence(chunkSize: 67) }
@Test func explicitStreamingEquivalenceChunk068() { assertExplicitStreamingEquivalence(chunkSize: 68) }
@Test func explicitStreamingEquivalenceChunk069() { assertExplicitStreamingEquivalence(chunkSize: 69) }
@Test func explicitStreamingEquivalenceChunk070() { assertExplicitStreamingEquivalence(chunkSize: 70) }
@Test func explicitStreamingEquivalenceChunk071() { assertExplicitStreamingEquivalence(chunkSize: 71) }
@Test func explicitStreamingEquivalenceChunk072() { assertExplicitStreamingEquivalence(chunkSize: 72) }
@Test func explicitStreamingEquivalenceChunk073() { assertExplicitStreamingEquivalence(chunkSize: 73) }
@Test func explicitStreamingEquivalenceChunk074() { assertExplicitStreamingEquivalence(chunkSize: 74) }
@Test func explicitStreamingEquivalenceChunk075() { assertExplicitStreamingEquivalence(chunkSize: 75) }
@Test func explicitStreamingEquivalenceChunk076() { assertExplicitStreamingEquivalence(chunkSize: 76) }
@Test func explicitStreamingEquivalenceChunk077() { assertExplicitStreamingEquivalence(chunkSize: 77) }
@Test func explicitStreamingEquivalenceChunk078() { assertExplicitStreamingEquivalence(chunkSize: 78) }
@Test func explicitStreamingEquivalenceChunk079() { assertExplicitStreamingEquivalence(chunkSize: 79) }
@Test func explicitStreamingEquivalenceChunk080() { assertExplicitStreamingEquivalence(chunkSize: 80) }
