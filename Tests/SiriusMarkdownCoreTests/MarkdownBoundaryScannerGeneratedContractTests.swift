import SiriusMarkdownCore
import Testing

@Test
func scannerGeneratedInlineReferenceCasesDoNotSealBeforeOneShotReferenceResolution() {
    let candidates = [
        "See [ref].",
        "See [text][ref].",
        "See [text][].",
        "See [ref] and more text.",
        "Escaped \\[ref] prose.",
        "Literal `[ref]` code.",
        "Literal ``[ref]`` code.",
        "Literal `[ref]`` unmatched code.",
        "Literal code starts `[ref]",
        "Literal code starts `\n\n[ref]\n`",
        "See [[ref]](https://example.com).",
        "See [now](https://example.com/[ref]).",
        "See [now](<broken [ref]>).",
        "See [now](broken [ref]).",
        "See [now](foo([ref])).",
        "See [now](foo\\ [ref]).",
        "See <https://example.com/[ref]>.",
        "See <x:[ref]>.",
        "See <abcdefghijklmnopqrstuvwxyzabcdefg:[ref]>.",
        "See < value [ref] >.",
        "See <span data-label=\"[ref]\">text</span>.",
        "See <span [ref]>text</span>.",
        "See <?[ref]?>.",
        "See <!A [ref]>.",
        "See <!-- [ref] -->.",
        "See <![CDATA[[ref]]]>.",
        "Image ![alt [ref]](image.png).",
        "Image ![alt](image-[ref].png).",
        "Math \\([ref]\\).",
        "HTML entity &[ref];.",
        "Autolink email <user[ref]@example.com>.",
        "Plain <user [ref]@example.com>."
    ]

    for line in candidates {
        let scannerSealed = scannerSealsAfterParagraph(line)
        let oneShotResolvesReference = referenceDestinations(
            in: line + "\n\n[ref]: https://example.com/reference\n"
        ).contains("https://example.com/reference")

        if scannerSealed && oneShotResolvesReference {
            Issue.record("Unsafe seal for generated scanner contract candidate: \(line)")
        }
    }
}

@Test
func scannerGeneratedInlineReferenceContextMatrixDoesNotSealBeforeOneShotReferenceResolution() {
    let referenceForms = [
        (text: "[ref]", definitionLabel: "ref"),
        (text: "[REF]", definitionLabel: "ref"),
        (text: "[text][ref]", definitionLabel: "ref"),
        (text: "[text][REF]", definitionLabel: "ref"),
        (text: "[ref][]", definitionLabel: "ref"),
        (text: "[text][]", definitionLabel: "text")
    ]
    let contexts: [(String) -> String] = [
        { "See \($0)." },
        { "\($0) at paragraph start." },
        { "Before \($0) after." },
        { "*\($0)* emphasized." },
        { "**\($0)** strong." },
        { "(\($0)) parenthesized." },
        { "Image !\($0)." },
        { "Inline HTML <span>\($0)</span>." },
        { "Link label [before \($0) after](https://example.com)." },
        { "Nested label [outer [before \($0) after]](https://example.com)." },
        { "Malformed link [before](broken \($0))." },
        { "Angle prose <before \($0) after>." },
        { "Invalid autolink <x:\($0)>." },
        { "Declaration <!A \($0)>." },
        { "Processing <?\($0)?>." },
        { "CDATA <![CDATA[\($0)]]>." }
    ]

    for referenceForm in referenceForms {
        for context in contexts {
            let line = context(referenceForm.text)
            let scannerSealed = scannerSealsAfterParagraph(line)
            let oneShotResolvesReference = referenceDestinations(
                in: line + "\n\n[\(referenceForm.definitionLabel)]: https://example.com/reference\n"
            ).contains("https://example.com/reference")

            if scannerSealed && oneShotResolvesReference {
                Issue.record("Unsafe seal for generated scanner context matrix candidate: \(line)")
            }
        }
    }
}

@Test
func streamedGeneratedReferenceDefinitionCasesMatchOneShotResolution() {
    let cases: [[String]] = [
        [
            "See [ref].\n\n",
            "[ref]: https://example.com/reference\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]:\n",
            "  https://example.com/reference\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]:\n",
            "\thttps://example.com/tab-continuation\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]:\n",
            "    https://example.com/four-space-continuation\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]: https://example.com/reference\n",
            "  \"title\"\n\n"
        ],
        [
            "[a[b]]: https://example.com/nested\n\n",
            "See [text][a[b]].\n\n"
        ],
        [
            "See [text][a[b]].\n\n",
            "[a[b]]: https://example.com/nested\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]: <https://example.com/reference>\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]: https://example.com/reference \"title [ref]\"\n\n"
        ],
        [
            "See [ref].\n\n",
            "[ref]: https://example.com/reference\n\n",
            "Later [again][ref].\n\n"
        ]
    ]

    for chunks in cases {
        let streamed = referenceDestinationsAfterStreaming(chunks)
        let oneShot = referenceDestinations(in: chunks.joined())

        if streamed != oneShot {
            Issue.record(
                """
                Streamed reference-definition resolution diverged.
                Chunks: \(chunks)
                Streamed: \(streamed)
                One shot: \(oneShot)
                """
            )
        }
    }
}

@Test
func hostBoundaryGeneratedReferenceDefinitionCasesMatchOneShotLaterReference() {
    let cases: [(definition: String, laterReference: String)] = [
        (
            "[ref]: https://example.com/reference\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: https://example.com/list-reference\n\n",
            "- Later [ref].\n\n"
        ),
        (
            "[ref]: https://example.com/quote-reference\n\n",
            "> Later [ref].\n\n"
        ),
        (
            "[ref]: https://example.com/table-reference\n\n",
            "| A |\n| - |\n| Later [ref]. |\n\n"
        ),
        (
            "[ref]: https://example.com/linked-image\n\n",
            "- Later [![diagram](diagram.png)][ref].\n\n"
        ),
        (
            "   [ref]: https://example.com/indented\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]:\n   https://example.com/continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]:\t<https://example.com/tab-after-colon>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: <https://example.com/with space> \"title\"\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: <https://example.com/with\ttab>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: <https://example.com/escaped\\>angle>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: <>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: https://example.com/a(b(c)d)\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: https://example.com/reference \"title \\\" quote\"\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]: https://example.com/reference (title (nested))\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[foo\\*bar]: https://example.com/escaped-label\n\n",
            "Later [foo*bar].\n\n"
        ),
        (
            "[foo  bar]: https://example.com/space-label\n\n",
            "Later [foo bar].\n\n"
        ),
        (
            "[foo\tbar]: https://example.com/tab-label\n\n",
            "Later [foo bar].\n\n"
        ),
        (
            "[ref]: https://example.com/reference\n  plain continuation paragraph\n\n",
            "Later [ref].\n\n"
        ),
        (
            "\t[ref]: https://example.com/code-indented\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]:\n\thttps://example.com/tab-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "[ref]:\n    https://example.com/four-space-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> [ref]: https://example.com/quote\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> [ref]:\n>   https://example.com/quote-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- [ref]: https://example.com/list\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- [ref]:\n  https://example.com/list-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "1. [ref]: https://example.com/ordered-list\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> - [ref]: https://example.com/quote-list\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- > [ref]: https://example.com/list-quote\n\n",
            "Later [ref].\n\n"
        ),
        (
            "  - [ref]: https://example.com/indented-list\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- [ref]:\n    https://example.com/list-four-space-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "1. [ref]:\n   https://example.com/ordered-list-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> - [ref]:\n>   https://example.com/quote-list-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- > [ref]:\n  >   https://example.com/list-quote-continuation\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> [multi\n> line]: https://example.com/quote-multiline\n\n",
            "Later [multi line].\n\n"
        ),
        (
            "> [multi\n> line]:\n>   https://example.com/quote-multiline-continuation\n\n",
            "Later [multi line].\n\n"
        ),
        (
            "- [multi\n  line]: https://example.com/list-multiline\n\n",
            "Later [multi line].\n\n"
        ),
        (
            "- [multi\n  line]:\n    https://example.com/list-multiline-continuation\n\n",
            "Later [multi line].\n\n"
        ),
        (
            "> - [multi\n>   line]: https://example.com/quote-list-multiline\n\n",
            "Later [multi line].\n\n"
        ),
        (
            "- > [multi\n  > line]: https://example.com/list-quote-multiline\n\n",
            "Later [multi line].\n\n"
        ),
        (
            "> ```\n> [ref]: https://example.com/quote-code\n> ```\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> <div>\n> [ref]: https://example.com/quote-html\n> </div>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "> <div>\n> [ref]: https://example.com/quote-html\n>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- ```\n  [ref]: https://example.com/list-code\n  ```\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- <div>\n  [ref]: https://example.com/list-html\n  </div>\n\n",
            "Later [ref].\n\n"
        ),
        (
            "- <div>\n  [ref]: https://example.com/list-html\n\n",
            "Later [ref].\n\n"
        )
    ]

    for testCase in cases {
        let oneShot = snapshotSignature(afterStreaming: [testCase.definition, testCase.laterReference])
        let streamed = snapshotSignatureAfterHostBoundary(
            definition: testCase.definition,
            laterReference: testCase.laterReference
        )

        if streamed != oneShot {
            Issue.record(
                """
                Host-boundary reference-definition harvest diverged from one-shot parse.
                Definition:
                \(testCase.definition)
                Later reference:
                \(testCase.laterReference)
                Streamed: \(streamed)
                One shot: \(oneShot)
                """
            )
        }
    }
}

@Test
func streamedFollowingLineBlockConstructsMatchOneShotAcrossChunking() {
    let documents = [
        "Setext heading\n==============\n\nNext paragraph.\n\n",
        "Setext heading\n--------------\n\nNext paragraph.\n\n",
        "Paragraph\n\n---\n\nNext paragraph.\n\n",
        "A | B\n--- | ---\n1 | 2\n\nNext paragraph.\n\n",
        "| A | B |\n| - | - |\n| 1 | 2 |\n\nNext paragraph.\n\n",
        "> Setext heading\n> ==============\n\nNext paragraph.\n\n",
        "- Setext-looking item\n  ----\n\nNext paragraph.\n\n",
        "- A | B\n  --- | ---\n\nNext paragraph.\n\n",
        "Paragraph\n---\nnot a heading continuation\n\n",
        "Paragraph\n***\nnot a heading continuation\n\n",
        "Paragraph\n___\nnot a heading continuation\n\n",
        "1. Item\n2. Item\n\nParagraph.\n\n",
        "1) Item\n2) Item\n\nParagraph.\n\n"
    ]

    for markdown in documents {
        let oneShot = snapshotSignature(afterStreaming: [markdown])
        let lineStream = snapshotSignature(
            afterStreaming: markdown.split(separator: "\n", omittingEmptySubsequences: false).map { "\($0)\n" }
        )
        if lineStream != oneShot {
            Issue.record(
                """
                Line-streamed following-line construct diverged from one-shot parse.
                Streamed: \(lineStream)
                One shot: \(oneShot)
                Markdown:
                \(markdown)
                """
            )
        }

        for chunkSize in 1...min(markdown.count, 32) {
            let streamed = snapshotSignature(afterStreaming: characterChunks(markdown, size: chunkSize))
            if streamed != oneShot {
                Issue.record(
                    """
                    Character-streamed following-line construct diverged from one-shot parse.
                    Chunk size: \(chunkSize)
                    Streamed: \(streamed)
                    One shot: \(oneShot)
                    Markdown:
                    \(markdown)
                    """
                )
            }
        }
    }
}

@Test
func streamedContainerReferenceDefinitionsAfterContainerTextMatchOneShotAcrossChunking() {
    let documents = [
        "> Quote\n>\n> [ref]: https://quote.example\n\nLater [ref].\n\n",
        "> Quote\n>\n> [multi\n> line]: https://quote-multiline.example\n\nLater [multi line].\n\n",
        "- Item\n\n  [ref]: https://list.example\n\nLater [ref].\n\n",
        "- Item\n\n  [multi\n  line]: https://list-multiline.example\n\nLater [multi line].\n\n",
        "> - Item\n>\n>   [ref]: https://quote-list.example\n\nLater [ref].\n\n",
        "- > Quote\n  >\n  > [ref]: https://list-quote.example\n\nLater [ref].\n\n"
    ]

    for markdown in documents {
        let oneShot = snapshotSignature(afterStreaming: [markdown])
        let lineStream = snapshotSignature(
            afterStreaming: markdown.split(separator: "\n", omittingEmptySubsequences: false).map { "\($0)\n" }
        )
        if lineStream != oneShot {
            Issue.record(
                """
                Line-streamed container reference definition diverged after prior container text.
                Streamed: \(lineStream)
                One shot: \(oneShot)
                Markdown:
                \(markdown)
                """
            )
        }

        for chunkSize in 1...min(markdown.count, 32) {
            let streamed = snapshotSignature(afterStreaming: characterChunks(markdown, size: chunkSize))
            if streamed != oneShot {
                Issue.record(
                    """
                    Character-streamed container reference definition diverged after prior container text.
                    Chunk size: \(chunkSize)
                    Streamed: \(streamed)
                    One shot: \(oneShot)
                    Markdown:
                    \(markdown)
                    """
                )
            }
        }
    }
}

@Test
func streamedStructuredBlockReferenceCandidatesMatchOneShotAcrossChunking() {
    let cases: [(name: String, chunks: [String])] = [
        (
            "table shortcut reference",
            [
                "| A |\n| - |\n| [ref] |\n\n",
                "[ref]: https://example.com/table-shortcut\n\n"
            ]
        ),
        (
            "table collapsed reference",
            [
                "| A |\n| - |\n| [ref][] |\n\n",
                "[ref]: https://example.com/table-collapsed\n\n"
            ]
        ),
        (
            "table full reference",
            [
                "| A |\n| - |\n| [text][ref] |\n\n",
                "[ref]: https://example.com/table-full\n\n"
            ]
        ),
        (
            "table linked image reference",
            [
                "| A |\n| - |\n| [![alt](image.png)][ref] |\n\n",
                "[ref]: https://example.com/table-image\n\n"
            ]
        ),
        (
            "blockquote table reference",
            [
                "> | A |\n> | - |\n> | [ref] |\n\n",
                "[ref]: https://example.com/quote-table\n\n"
            ]
        ),
        (
            "list table reference",
            [
                "- | A |\n  | - |\n  | [ref] |\n\n",
                "[ref]: https://example.com/list-table\n\n"
            ]
        )
    ]

    for testCase in cases {
        let markdown = testCase.chunks.joined()
        let oneShot = snapshotSignature(afterStreaming: [markdown])
        let streamed = snapshotSignature(afterStreaming: testCase.chunks)
        if streamed != oneShot {
            Issue.record(
                """
                Chunk-streamed structured reference candidate diverged from one-shot parse.
                Case: \(testCase.name)
                Streamed: \(streamed)
                One shot: \(oneShot)
                Markdown:
                \(markdown)
                """
            )
        }

        for chunkSize in 1...min(markdown.count, 32) {
            let streamed = snapshotSignature(afterStreaming: characterChunks(markdown, size: chunkSize))
            if streamed != oneShot {
                Issue.record(
                    """
                    Character-streamed structured reference candidate diverged from one-shot parse.
                    Case: \(testCase.name)
                    Chunk size: \(chunkSize)
                    Streamed: \(streamed)
                    One shot: \(oneShot)
                    Markdown:
                    \(markdown)
                    """
                )
            }
        }
    }
}

@Test
func streamedGeneratedReferenceDocumentsMatchOneShotAcrossChunkSizes() {
    let documents = [
        """
        See [later][ref].

        [ref]:
          https://example.com/reference

        """,
        """
        [ref]:
          https://example.com/reference

        See [later][ref].

        """,
        """
        See [later][ref].

        [ref]: https://example.com/reference
          "title"

        """,
        """
        See [text][a[b]].

        [a[b]]: https://example.com/nested

        """,
        """
        See <x:[ref]>.

        [ref]: https://example.com/reference

        """,
        """
        See [[ref]](https://example.com).

        [ref]: https://example.com/reference

        """,
        """
        - > [x] quote reference

        [x]: https://example.com/reference

        """,
        """
        First [one][ref].

        Second [two][ref].

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: <https://example.com/broken

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: <bad destination>

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: <>

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: bad<destination

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: bad(destination

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: bad destination

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: bad "unterminated title

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: bad 'unterminated title

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        [ref]: bad (unterminated title

        [ref]: https://example.com/reference

        """,
        """
        See [later][a].

        [a]:
        [b]: https://example.com/b

        [a]: https://example.com/a

        """,
        """
        See [later][ref].

        > ```
        > [ref]: https://quote-code.example
        > ```

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        > <div>
        > [ref]: https://quote-html.example
        > </div>

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        - ```
          [ref]: https://list-code.example
          ```

        [ref]: https://example.com/reference

        """,
        """
        See [later][ref].

        - <div>
          [ref]: https://list-html.example
          </div>

        [ref]: https://example.com/reference

        """,
        """
        - Item [later][ref].

        [ref]: https://example.com/reference

        """,
        """
        > Quote [later][ref].

        [ref]: https://example.com/reference

        """,
        """
        | A |
        | - |
        | [later][ref] |

        [ref]: https://example.com/reference

        """,
        """
        - Linked image [![diagram](diagram.png)][ref].

        [ref]: https://example.com/linked-image

        """
    ]

    for markdown in documents {
        let oneShot = snapshotSignature(afterStreaming: [markdown])
        for chunkSize in 1...min(markdown.count, 96) {
            let streamed = snapshotSignature(afterStreaming: characterChunks(markdown, size: chunkSize))
            if streamed != oneShot {
                Issue.record(
                    """
                    Streamed document diverged from one-shot parse for generated reference document.
                    Chunk size: \(chunkSize)
                    Streamed: \(streamed)
                    One shot: \(oneShot)
                    Markdown:
                    \(markdown)
                    """
                )
            }
        }
    }
}

@Test
func streamedGeneratedReferenceDefinitionDestinationTitleEdgesMatchOneShotAcrossChunkSizes() {
    let documents = [
        """
        See [later][ref].

        [ref]: https://example.com/a(b(c)d)

        """,
        """
        See [later][ref].

        [ref]: https://example.com/a(b\\)c)

        """,
        """
        See [later][ref].

        [ref]: <https://example.com/a\\>b>

        """,
        """
        See [later][ref].

        [ref]: https://example.com/reference "title with \\\"escaped quote\\\""

        """,
        """
        See [later][ref].

        [ref]: https://example.com/reference 'title with \\'escaped quote\\''

        """,
        """
        See [later][ref].

        [ref]: https://example.com/reference (title with \\) escaped paren)

        """,
        """
        See [later][ref].

        [ref]: https://example.com/a)b

        [ref]: https://example.com/recovery

        """,
        """
        See [later][ref].

        [ref]: <https://example.com/a

        [ref]: https://example.com/recovery

        """,
        """
        See [later][ref].

        [ref]: https://example.com/reference "unterminated title

        [ref]: https://example.com/recovery

        """,
        """
        See [later][ref].

        [ref]: https://example.com/reference (unterminated title

        [ref]: https://example.com/recovery

        """
    ]

    for markdown in documents {
        let oneShot = snapshotSignature(afterStreaming: [markdown])
        for chunkSize in 1...min(markdown.count, 24) {
            let streamed = snapshotSignature(afterStreaming: characterChunks(markdown, size: chunkSize))
            if streamed != oneShot {
                Issue.record(
                    """
                    Streamed reference-definition destination/title edge case diverged from one-shot parse.
                    Chunk size: \(chunkSize)
                    Streamed: \(streamed)
                    One shot: \(oneShot)
                    Markdown:
                    \(markdown)
                    """
                )
            }
        }
    }
}

private func scannerSealsAfterParagraph(_ line: String) -> Bool {
    var buffer = MarkdownSourceBuffer()
    buffer.append(line + "\n\n")
    return MarkdownBoundaryScanner().safeSealUpperBound(in: buffer, after: 0) != nil
}

private func referenceDestinationsAfterStreaming(_ chunks: [String]) -> [String] {
    var stream = MarkdownStream()
    for chunk in chunks {
        stream.append(chunk)
    }
    stream.finish()
    return referenceDestinations(in: stream.snapshot().blocks)
}

private func referenceDestinations(in markdown: String) -> [String] {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return referenceDestinations(in: stream.snapshot().blocks)
}

private func snapshotSignature(afterStreaming chunks: [String]) -> [String] {
    var stream = MarkdownStream()
    for chunk in chunks {
        stream.append(chunk)
    }
    stream.finish()

    return blockSignatures(in: stream.snapshot().blocks)
}

private func snapshotSignatureAfterHostBoundary(definition: String, laterReference: String) -> [String] {
    var stream = MarkdownStream()
    stream.append(definition)
    stream.appendHostBoundary(id: MarkdownHostBoundaryID("native-card"))
    stream.append(laterReference)
    stream.finish()

    return blockSignature(in: stream)
}

private func blockSignature(in stream: MarkdownStream) -> [String] {
    blockSignatures(in: stream.snapshot().blocks)
}

private func referenceDestinations(in blocks: [MarkdownBlock]) -> [String] {
    blocks.flatMap { block in
        inlineDestinations(in: block.inlines)
            + block.listItems.flatMap(listItemDestinations)
            + tableDestinations(in: block.table)
    }
}

private func listItemDestinations(_ item: MarkdownListItem) -> [String] {
    inlineDestinations(in: item.inlines) + item.childItems.flatMap(listItemDestinations)
}

private func tableDestinations(in table: MarkdownTableBlock?) -> [String] {
    guard let table else {
        return []
    }

    return (table.header + table.rows.flatMap { $0 }).flatMap { cell in
        inlineDestinations(in: cell.inlines)
    }
}

private func inlineDestinations(in runs: [MarkdownInlineRun]) -> [String] {
    runs.compactMap(\.destination)
}

private func blockSignatures(in blocks: [MarkdownBlock]) -> [String] {
    blocks.map(blockSignature)
}

private func blockSignature(_ block: MarkdownBlock) -> String {
    [
        "block=\(block.kind.rawValue)",
        "text=\(block.text)",
        "inlines=\(inlineSignature(block.inlines))",
        "list=\(listSignature(block.listItems))",
        "table=\(tableSignature(block.table))"
    ].joined(separator: ";")
}

private func listSignature(_ items: [MarkdownListItem]) -> String {
    items.map { item in
        [
            "itemText=\(item.text)",
            "task=\(item.taskState?.rawValue ?? "")",
            "inlines=\(inlineSignature(item.inlines))",
            "children=\(listSignature(item.childItems))"
        ].joined(separator: ",")
    }.joined(separator: "|")
}

private func tableSignature(_ table: MarkdownTableBlock?) -> String {
    guard let table else {
        return ""
    }

    let header = table.header.map { cell in
        "headerCell=\(cell.text):\(inlineSignature(cell.inlines))"
    }.joined(separator: "|")
    let rows = table.rows.map { row in
        row.map { cell in
            "cell=\(cell.text):\(inlineSignature(cell.inlines))"
        }.joined(separator: ",")
    }.joined(separator: "|")
    return "alignments=\(table.columnAlignments.map { $0?.rawValue ?? "" }.joined(separator: ","));header=\(header);rows=\(rows)"
}

private func inlineSignature(_ runs: [MarkdownInlineRun]) -> String {
    runs.map { run in
        [
            run.kind.rawValue,
            "presentation=\(run.presentation.rawValue)",
            "text=\(run.text)",
            "destination=\(run.destination ?? "")",
            "imageSource=\(run.imageSource ?? "")"
        ].joined(separator: ":")
    }.joined(separator: "|")
}

private func characterChunks(_ text: String, size: Int) -> [String] {
    var chunks: [String] = []
    var start = text.startIndex
    while start < text.endIndex {
        let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
        chunks.append(String(text[start..<end]))
        start = end
    }
    return chunks
}
