import Testing
import Foundation
import SiriusMarkdownCore

@Test
func inlineMathIsDetectedWithoutRewritingCodeSpans() throws {
    var stream = MarkdownStream()
    stream.append("Inline $x^2$ survives, but `price $5` stays code.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .math && $0.text == "x^2" })
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "price $5" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func escapedDollarDoesNotStartInlineMath() throws {
    var stream = MarkdownStream()
    stream.append("Cost is \\$5 and math is $a_1$.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .math && $0.text == "a_1" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func escapedParenInlineMathIsDetectedInPlainTextNodes() throws {
    var stream = MarkdownStream()
    stream.append("Inline \\(x^2 + y^2\\) survives in prose.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .math && $0.text == "x^2 + y^2" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func escapedBackslashBeforeParenDoesNotStartInlineMath() throws {
    var stream = MarkdownStream()
    stream.append("Literal \\\\(x\\\\) stays prose, while \\(y\\) is math.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .text && $0.text.contains("\\(x\\)") })
    #expect(block.inlines.contains { $0.kind == .math && $0.text == "y" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func escapedBackslashBeforeDollarStillAllowsDollarMath() throws {
    var stream = MarkdownStream()
    stream.append("Literal backslash before math: \\\\$x$ stays parsed.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .text && $0.text.contains("\\") })
    #expect(block.inlines.contains { $0.kind == .math && $0.text == "x" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func currencyRangesDoNotBecomeInlineMath() throws {
    var stream = MarkdownStream()
    stream.append("Rewards: $100-$5,500, $100 - $5,500, and math $x^2$ remains; adjacent $y$2 remains math.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(
        block.inlines.map(\.text).joined() ==
            "Rewards: $100-$5,500, $100 - $5,500, and math x^2 remains; adjacent y2 remains math."
    )
    #expect(block.inlines.contains { $0.kind == .math && $0.text == "x^2" })
    #expect(block.inlines.contains { $0.kind == .math && $0.text == "y" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 2)
}

@Test
func tableCurrencyAmountsDoNotBecomeInlineMath() throws {
    var stream = MarkdownStream()
    stream.append("""
    | Program | Reward |
    | --- | --- |
    | Coveo Public Bug Bounty | $100 - $5,500 |
    | ICI PARIS XL / AS Watson | $108,500 |
    | Nutaku Bug Bounty | $504,000 |
    | Math sample | $x^2$ |
    """)
    stream.finish()

    let table = try #require(stream.snapshot().blocks.first?.table)
    let rewardCells = table.rows.map { $0[1] }

    #expect(rewardCells[0].text == "$100 - $5,500")
    #expect(rewardCells[0].inlines.allSatisfy { $0.kind != .math })
    #expect(rewardCells[1].text == "$108,500")
    #expect(rewardCells[1].inlines.allSatisfy { $0.kind != .math })
    #expect(rewardCells[2].text == "$504,000")
    #expect(rewardCells[2].inlines.allSatisfy { $0.kind != .math })
    #expect(rewardCells[3].inlines.contains { $0.kind == .math && $0.text == "x^2" })
}

@Test
func dollarMathMayStartWithANumber() throws {
    var stream = MarkdownStream()
    stream.append("The identity $1 + 1 = 2$ still parses as math.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .math && $0.text == "1 + 1 = 2" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func currencyLikeDollarRunsDoNotBecomeInlineMath() throws {
    let cases = [
        "Currency code $5 USD$ stays text.",
        "Compact currency code $5USD$ stays text.",
        "Compact dirham $5AED$ stays text.",
        "Precious metal $5XAU$ stays text.",
        "No currency code $5XXX$ stays text.",
        "Large amount $108,500$ stays text.",
        "Range $100-$5,500 stays text.",
        "Discount $5 off $10 order and math $x$ stays math."
    ]

    for markdown in cases {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()

        let block = try #require(stream.snapshot().blocks.first)
        let mathRuns = block.inlines.filter { $0.kind == .math }

        if markdown.contains("$x$") {
            #expect(mathRuns.map(\.text) == ["x"])
            #expect(block.inlines.map(\.text).joined() == "Discount $5 off $10 order and math x stays math.")
        } else {
            #expect(mathRuns.isEmpty)
            #expect(block.inlines.map(\.text).joined() == markdown)
        }
    }
}

@Test
func compactISOCurrencyCodesDoNotBecomeInlineMath() throws {
    for code in Locale.Currency.isoCurrencies.map(\.identifier).sorted() {
        var stream = MarkdownStream()
        stream.append("Compact currency $5\(code)$ stays text while $x$ stays math.")
        stream.finish()

        let block = try #require(stream.snapshot().blocks.first)
        #expect(block.inlines.filter { $0.kind == .math }.map(\.text) == ["x"])
        #expect(block.inlines.map(\.text).joined() == "Compact currency $5\(code)$ stays text while x stays math.")
    }
}

@Test
func numericLeadingDollarMathParsesWhenFormulaLike() throws {
    let cases = [
        ("Scalar $5$ remains math.", "5"),
        ("Decimal constant $3.14$ remains math.", "3.14"),
        ("Subtraction $1-2$ remains math.", "1-2"),
        ("Scale $2x$ remains math.", "2x"),
        ("Uppercase variables $2XY$ remain math.", "2XY"),
        ("The identity $1 + 1 = 2$ remains math.", "1 + 1 = 2"),
        ("Scientific notation $1e10$ remains math.", "1e10"),
        ("Percent expression $5\\%$ remains math.", "5\\%")
    ]

    for (markdown, expectedMath) in cases {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()

        let block = try #require(stream.snapshot().blocks.first)
        #expect(block.inlines.filter { $0.kind == .math }.map(\.text) == [expectedMath])
    }
}

@Test
func inlineMathKeepsPresentationAndLinkContext() throws {
    var stream = MarkdownStream()
    stream.append("Strong **$x^2$**, emphasis *\\(y\\)*, and [linked $z$](https://example.com/math).")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let strongMath = try #require(block.inlines.first { $0.kind == .math && $0.text == "x^2" })
    let emphasisMath = try #require(block.inlines.first { $0.kind == .math && $0.text == "y" })
    let linkedMath = try #require(block.inlines.first { $0.kind == .link && $0.text == "z" })

    #expect(strongMath.presentation.contains(.math))
    #expect(strongMath.presentation.contains(.strong))
    #expect(emphasisMath.presentation.contains(.math))
    #expect(emphasisMath.presentation.contains(.emphasis))
    #expect(linkedMath.presentation.contains(.math))
    #expect(linkedMath.destination == "https://example.com/math")
}

@Test
func bareTexCommandsInProseBecomeMathRuns() throws {
    var stream = MarkdownStream()
    stream.append("The strike price (Z \\approx 0) and volatility scales with \\sqrt{t}.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let mathRuns = block.inlines.filter { $0.kind == .math }

    #expect(mathRuns.map(\.text) == ["Z \\approx 0", "\\sqrt{t}"])
    #expect(block.inlines.map(\.text).joined() == "The strike price (Z \\approx 0) and volatility scales with \\sqrt{t}.")
}

@Test
func adjacentBareTexCommandsStayTogetherWithoutEatingProse() throws {
    var stream = MarkdownStream()
    stream.append("The denominator \\sigma \\sqrt{t} shrinks as time falls.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let mathRuns = block.inlines.filter { $0.kind == .math }

    #expect(mathRuns.map(\.text) == ["\\sigma \\sqrt{t}"])
    #expect(block.inlines.contains { $0.kind == .text && $0.text == " shrinks as time falls." })
}

@Test
func bareTexRecoveryDoesNotRewritePathsUnknownCommandsOrEscapedMarkdown() throws {
    var stream = MarkdownStream()
    stream.append("Path C:\\Users\\mike, C:\\theta\\sqrt, and C:\\mathbb\\operatorname stay prose; unknown \\foobar and escaped \\*text\\* stay prose while \\sqrt{x} renders.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let mathRuns = block.inlines.filter { $0.kind == .math }

    #expect(mathRuns.map(\.text) == ["\\sqrt{x}"])
    #expect(block.inlines.map(\.text).joined().contains("C:\\Users\\mike"))
    #expect(block.inlines.map(\.text).joined().contains("C:\\theta\\sqrt"))
    #expect(block.inlines.map(\.text).joined().contains("C:\\mathbb\\operatorname"))
    #expect(block.inlines.map(\.text).joined().contains("\\foobar"))
    #expect(block.inlines.map(\.text).joined().contains("*text*"))
}

@Test
func styledAndLinkedCurrencyDoesNotBecomeInlineMath() throws {
    var stream = MarkdownStream()
    stream.append("Strong **$5 USD$**, linked [$108,500](https://example.com/reward), formula **$2x$**.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let strongCurrency = try #require(block.inlines.first { $0.text == "$5 USD$" })
    let linkedCurrency = try #require(block.inlines.first { $0.text == "$108,500" })
    let formula = try #require(block.inlines.first { $0.kind == .math && $0.text == "2x" })

    #expect(strongCurrency.kind == .strong)
    #expect(strongCurrency.presentation.contains(.strong))
    #expect(!strongCurrency.presentation.contains(.math))
    #expect(linkedCurrency.kind == .link)
    #expect(linkedCurrency.destination == "https://example.com/reward")
    #expect(!linkedCurrency.presentation.contains(.math))
    #expect(formula.presentation.contains(.strong))
    #expect(formula.presentation.contains(.math))
}

@Test
func codeSpansDoNotParseLatexOrDollarDelimiters() throws {
    var stream = MarkdownStream()
    stream.append("Code `\\(x\\)`, `$y$`, `\\operatorname{softmax}`, `\\mathbb{R}`, and `\\partial L` stay code, while \\(z\\) is math.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .code && $0.text == "\\(x\\)" })
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "$y$" })
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "\\operatorname{softmax}" })
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "\\mathbb{R}" })
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "\\partial L" })
    #expect(block.inlines.filter { $0.kind == .math }.map(\.text) == ["z"])
}

@Test
func bareTextCommandFormulaStaysTogetherAsOneMathRun() throws {
    let formula = "S_c = w₁ · \\text{Match}\\text{NPI} + w₂ · \\text{Match}\\text{Google} + w₃ · \\text{Match}\\text{Website} - \\text{Penalty}\\text{Conflicts}"
    var stream = MarkdownStream()
    stream.append("Formula: \(formula).")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let mathRuns = block.inlines.filter { $0.kind == .math }

    #expect(mathRuns.map(\.text) == [formula])
}

@Test
func bareTexRecoveryKeepsGeneratedFormulaFamiliesTogether() throws {
    let cases = [
        "p(y \\mid x) = \\operatorname{softmax}(Wx + b)_y",
        "\\mathbb{E}[X] = \\sum_i p_i x_i",
        "\\hat{\\theta} = \\arg\\max_\\theta \\log p(D \\mid \\theta)",
        "\\partial L / \\partial w = 0",
        "\\nabla_\\theta J(\\theta) = \\mathbb{E}[r \\nabla_\\theta \\log \\pi_\\theta(a \\mid s)]",
        "\\mathrm{score}(x) = \\log p(x)",
        "\\Pr(A \\mid B) = \\frac{\\Pr(B \\mid A)\\Pr(A)}{\\Pr(B)}",
        "\\left\\|x\\right\\|_2 = \\sqrt{x^\\top x}",
        "\\mathbf{x}^{\\top}\\mathbf{w} + b",
        "x_i \\in \\mathbb{R}^d",
        "\\begin{cases} x + y = 5 \\\\ 2x - y = 1 \\end{cases}",
        "f(x) = \\begin{cases} x^2 & x \\ge 0 \\\\ -x & x < 0 \\end{cases}",
        "\\operatorname*{argmax}_{x \\in \\mathbb{R}^d} f(x)",
        "\\left\\langle x, y \\right\\rangle = \\sum_i x_i y_i",
        "\\begin{equation} x^2 + y^2 = z^2 \\end{equation}",
        "\\begin{align*} x &= y + 1 \\\\ y &= z - 1 \\end{align*}",
        "\\psi(t) = e^{-i\\omega t}",
        "\\mathfrak{g} \\oplus \\mathcal{h}",
        "\\Delta E \\approx \\hbar\\omega",
        "A \\subseteq B \\Rightarrow A \\cap C \\subseteq B \\cap C",
        "\\det(A) \\neq 0 \\iff A^{-1}\\text{ exists}",
        "\\mu \\pm 1.96\\sigma"
    ]

    for formula in cases {
        var stream = MarkdownStream()
        stream.append("Formula: \(formula).")
        stream.finish()

        let block = try #require(stream.snapshot().blocks.first)
        let mathRuns = block.inlines.filter { $0.kind == .math }

        #expect(mathRuns.map(\.text) == [formula])
    }
}
