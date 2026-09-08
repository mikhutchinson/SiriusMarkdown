#if canImport(SwiftMath)
import SwiftMath
import SiriusMarkdownSwiftUI

/// Consumes the already-parsed SwiftMath atoms while the typesetter lock is held.
struct SwiftMathAccessibilityBuilder {
    private var remaining = MarkdownMathAccessibilityTree.maximumNodeCount
    private var truncated = false
    private typealias Node = MarkdownMathAccessibilityNode

    static func makeTree(from list: MTMathList) -> MarkdownMathAccessibilityTree {
        var builder = Self()
        let root = builder.list(list, kind: .equation, label: "Equation", depth: 1) ?? .init(kind: .equation, label: "Equation")
        return .init(root: root, isTruncated: builder.truncated)
    }

    private mutating func reserve(_ depth: Int) -> Bool {
        guard remaining > 0, depth <= MarkdownMathAccessibilityTree.maximumDepth else {
            truncated = true
            return false
        }
        remaining -= 1
        return true
    }

    private mutating func list(_ list: MTMathList?, kind: Node.Kind, label: String, depth: Int) -> Node? {
        guard reserve(depth) else { return nil }
        var children: [Node] = []
        if let list {
            for atom in list.atoms {
                guard remaining > 0 else { truncated = true; break }
                if let node = atomNode(atom, depth: depth + 1) { children.append(node) }
            }
        }
        return .init(kind: kind, label: label, children: children)
    }

    private mutating func atomNode(_ atom: MTMathAtom, depth: Int) -> Node? {
        // Spacing/style atoms are not spoken mathematical terms.
        if atom is MTMathSpace || atom is MTMathStyle { return nil }
        guard reserve(depth) else { return nil }
        var kind: Node.Kind = .symbol
        var label = atom.nucleus
        var children: [Node] = []
        if let fraction = atom as? MTFraction {
            kind = .fraction; label = "Fraction"
            if let node = list(fraction.numerator, kind: .numerator, label: "Numerator", depth: depth + 1) { children.append(node) }
            if let node = list(fraction.denominator, kind: .denominator, label: "Denominator", depth: depth + 1) { children.append(node) }
        } else if let radical = atom as? MTRadical {
            kind = .radical; label = radical.degree == nil ? "Square root" : "Root"
            if let degree = radical.degree, let node = list(degree, kind: .degree, label: "Degree", depth: depth + 1) { children.append(node) }
            if let node = list(radical.radicand, kind: .radicand, label: "Radicand", depth: depth + 1) { children.append(node) }
        } else if let table = atom as? MTMathTable {
            kind = .table; label = "Math table"
            for (rowIndex, row) in table.cells.enumerated() {
                guard reserve(depth + 1) else { break }
                var cells: [Node] = []
                for (column, cell) in row.enumerated() {
                    guard remaining > 0 else { truncated = true; break }
                    if let node = list(cell, kind: .cell, label: "Column \(column + 1)", depth: depth + 2) { cells.append(node) }
                }
                children.append(.init(kind: .row, label: "Row \(rowIndex + 1)", children: cells))
            }
        } else {
            let inner: MTMathList?
            switch atom {
            case let value as MTInner: inner = value.innerList; kind = .group; label = "Group"
            case let value as MTOverLine: inner = value.innerList; kind = .overline; label = "Overline"
            case let value as MTUnderLine: inner = value.innerList; kind = .underline; label = "Underline"
            case let value as MTAccent: inner = value.innerList; kind = .accent; label = "Accent \(value.nucleus)"
            case let value as MTMathColor: inner = value.innerList; kind = .group; label = "Group"
            case let value as MTMathTextColor: inner = value.innerList; kind = .group; label = "Group"
            case let value as MTMathColorbox: inner = value.innerList; kind = .group; label = "Group"
            default: inner = nil
            }
            if let inner, let node = list(inner, kind: .row, label: "Expression", depth: depth + 1) { children.append(node) }
        }
        if let script = atom.subScript, let node = list(script, kind: .subscriptValue, label: "Subscript", depth: depth + 1) { children.append(node) }
        if let script = atom.superScript, let node = list(script, kind: .superscript, label: "Superscript", depth: depth + 1) { children.append(node) }
        return .init(kind: kind, label: label.isEmpty ? "Expression" : label, children: children)
    }
}
#endif
