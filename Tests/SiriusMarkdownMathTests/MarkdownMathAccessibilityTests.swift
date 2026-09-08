import Testing
@testable import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath
#if canImport(SwiftMath)
import SwiftMath

private func mathNodes(_ node: MarkdownMathAccessibilityNode) -> [MarkdownMathAccessibilityNode] {
    [node] + node.children.flatMap(mathNodes)
}

@Test func nativeMathAccessibilityPreservesFractionRadicalAndScripts() throws {
    let latex = "\\frac{x_1^2}{\\sqrt[3]{y}}"
    let renderer = NativeMarkdownMathRenderer()
    guard case let .image(image) = renderer.preparedMath(latex, isBlock: true, fontSize: 20) else {
        Issue.record("Expected native math image"); return
    }
    let tree = try #require(image.accessibilityTree)
    let nodes = mathNodes(tree.root)
    let kinds: [MarkdownMathAccessibilityNode.Kind] = [.fraction, .numerator, .denominator, .radical, .radicand, .degree, .subscriptValue, .superscript]
    for kind in kinds {
        #expect(nodes.contains { $0.kind == kind })
    }
    #expect(!tree.isTruncated)
    #expect(image.accessibilityLabel.contains("Numerator"))
    #expect(image.accessibilityLabel.contains("Denominator"))
    #expect(image.latex == latex)
}

@Test func nativeMathAccessibilityExposesMatrixRowsAndColumns() throws {
    let list = try #require(MTMathListBuilder.build(fromString: "\\begin{matrix}a & b \\\\ c & d\\end{matrix}"))
    let nodes = mathNodes(SwiftMathAccessibilityBuilder.makeTree(from: list).root)
    #expect(nodes.filter { $0.kind == .row }.map(\.label) == ["Row 1", "Row 2"])
    #expect(nodes.filter { $0.kind == .cell }.map(\.label) == ["Column 1", "Column 2", "Column 1", "Column 2"])
}

@Test func nativeMathAccessibilityNodeBudgetIsBounded() throws {
    let list = try #require(MTMathListBuilder.build(fromString: String(repeating: "x+", count: 600) + "x"))
    let tree = SwiftMathAccessibilityBuilder.makeTree(from: list)
    #expect(tree.isTruncated)
    #expect(mathNodes(tree.root).count <= MarkdownMathAccessibilityTree.maximumNodeCount)
    #expect(tree.accessibilityLabel.count <= 4096)
}

@Test func publicMathAccessibilityTreeBoundsDepth() {
    var root = MarkdownMathAccessibilityNode(kind: .symbol, label: "x")
    for _ in 0..<40 { root = .init(kind: .group, label: "Group", children: [root]) }
    let tree = MarkdownMathAccessibilityTree(root: root)
    #expect(tree.isTruncated)
    #expect(mathNodes(tree.root).count == MarkdownMathAccessibilityTree.maximumDepth)
}
#endif

#if os(macOS)
import AppKit
import SwiftUI
import SiriusMarkdownCore

@MainActor
@Test func nativeMathBlockExposesNavigableAccessibilityParts() throws {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{x}{\\sqrt{y}}\n$$")
    stream.finish()
    let block = try #require(stream.snapshot().blocks.first)
    var configuration = MarkdownRendererConfiguration()
    configuration.mathRenderer = NativeMarkdownMathRenderer()
    let prepared = configuration.prepare(block: block)
    guard case let .image(image)? = prepared.mathRender else {
        Issue.record("Expected prepared native math"); return
    }
    #expect(image.latex == "\\frac{x}{\\sqrt{y}}")
    let hosting = NSHostingView(rootView: MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared))
    hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.orderOut(nil); window.contentView = nil; window.close() }
    func labels() -> [String] {
        var found: [String] = []
        var queue: [Any] = [hosting]
        var seen = Set<ObjectIdentifier>()
        while !queue.isEmpty, seen.count < 512 {
            let value = queue.removeFirst()
            guard let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { continue }
            for name in ["accessibilityLabel", "accessibilityValue"] {
                let selector = NSSelectorFromString(name)
                if object.responds(to: selector), let label = object.perform(selector)?.takeUnretainedValue() as? String { found.append(label) }
            }
            if let view = object as? NSView { queue.append(contentsOf: view.subviews) }
            let selector = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: selector), let children = object.perform(selector)?.takeUnretainedValue() as? [Any] { queue.append(contentsOf: children) }
        }
        return found
    }
    var exposed: [String] = []
    for _ in 0..<20 {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        exposed = labels()
        if exposed.contains("Numerator") && exposed.contains("Denominator") { break }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    #expect(exposed.contains("Numerator"))
    #expect(exposed.contains("Denominator"))
    #expect(exposed.contains("Radicand"))
}
#endif

#if os(macOS)
@MainActor
@Test func nativeInlineMathExposesAndPrunesSemanticAccessibility() throws {
    let configuration = MarkdownRendererConfiguration(nativeTextSelection: .enabled, mathRenderer: NativeMarkdownMathRenderer())
    func render(_ source: String) -> MarkdownPreparedSnapshot {
        var stream = MarkdownStream()
        stream.append(source)
        stream.finish()
        return configuration.prepare(snapshot: stream.snapshot())
    }
    let hosting = NSHostingView(rootView: StreamingMarkdownView(preparedSnapshot: render("Before $\\frac{x}{y}$ after"), configuration: configuration))
    hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.orderOut(nil); window.contentView = nil; window.close() }
    func textViews(_ view: NSView) -> [MarkdownAppKitNativeSelectableTextView] {
        (view as? MarkdownAppKitNativeSelectableTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }
    func pump() {
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    pump()
    let text = try #require(textViews(hosting).first)
    let roots = (text.accessibilityChildren() ?? []).compactMap { $0 as? MarkdownMathAccessibilityElement }
    #expect(roots.count == 1)
    let root = try #require(roots.first)
    #expect(root.accessibilityFrame().width > 0)
    func labels(_ element: MarkdownMathAccessibilityElement) -> [String] {
        [element.accessibilityLabel() ?? ""] + (element.accessibilityChildren() ?? []).compactMap { $0 as? MarkdownMathAccessibilityElement }.flatMap(labels)
    }
    #expect(labels(root).contains("Numerator"))
    #expect(labels(root).contains("Denominator"))
    let storage = try #require(text.textStorage)
    let range = (text.string as NSString).range(of: "\u{FFFC}")
    #expect(range.location != NSNotFound)
    if range.location != NSNotFound {
        #expect(MarkdownAppKitNativeSelectableTextView.plainTextRepresentation(in: range, textStorage: storage) == "\\frac{x}{y}")
    }
    hosting.rootView = StreamingMarkdownView(preparedSnapshot: render("Before plain after"), configuration: configuration)
    pump()
    let updated = try #require(textViews(hosting).first)
    #expect(updated === text)
    #expect((updated.accessibilityChildren() ?? []).compactMap { $0 as? MarkdownMathAccessibilityElement }.isEmpty)
}
#endif
