import SiriusMarkdownMath
import Testing

@Test
func nativeMathRendererNormalizesCommonLatexTokens() {
    let normalized = NativeMarkdownMathRenderer.normalizedMath("x^2 \\rightarrow y_1 + \\alpha")

    #expect(normalized.contains("x²"))
    #expect(normalized.contains("→"))
    #expect(normalized.contains("y₁"))
    #expect(normalized.contains("α"))
}

@Test
func nativeMathRendererFallbackPreservesUnknownCommandPrefixesAndNondigitScripts() {
    let source = "\\integral + \\alphaBeta + x^{n+1} + y_{ij} + z^{}"

    #expect(NativeMarkdownMathRenderer.normalizedMath(source) == source)
}

@Test
func nativeMathRendererFallbackConvertsCompleteDigitScriptGroups() {
    let normalized = NativeMarkdownMathRenderer.normalizedMath("x^{12} + y_{34} + \\alpha")

    #expect(normalized == "x¹² + y₃₄ + α")
}

@Test
func nativeMathRendererFallbackDoesNotConvertEscapedScriptMarkers() {
    let source = "x\\^2 + y\\_1"

    #expect(NativeMarkdownMathRenderer.normalizedMath(source) == source)
}
