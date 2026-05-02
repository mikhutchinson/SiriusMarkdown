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
