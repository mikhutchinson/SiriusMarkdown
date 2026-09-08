import SiriusMarkdownCore

/// Pipeline-owned dependency index. Sealed prepared blocks are not rescanned
/// when an unrelated streaming tail changes.
struct MarkdownPreparedImageResourceIndex {
    private var byBlock: [MarkdownBlockID: Set<String>] = [:]
    private(set) var owners: [String: Set<MarkdownBlockID>] = [:]

    mutating func update(_ snapshot: MarkdownPreparedSnapshot) {
        let live = Set(snapshot.snapshot.blocks.map(\.id))
        for id in Array(byBlock.keys) where !live.contains(id) { replace(id, with: nil) }
        for block in snapshot.snapshot.blocks {
            guard byBlock[block.id] == nil || snapshot.diff.contains("block:\(block.id.rawValue)") else { continue }
            guard let content = snapshot.preparedContentByBlockID[block.id] else { continue }
            replace(block.id, with: Self.sources(in: content))
        }
    }

    private mutating func replace(_ id: MarkdownBlockID, with sources: Set<String>?) {
        for source in byBlock[id] ?? [] {
            owners[source]?.remove(id)
            if owners[source]?.isEmpty == true { owners.removeValue(forKey: source) }
        }
        byBlock[id] = sources
        for source in sources ?? [] { owners[source, default: []].insert(id) }
    }

    private static func sources(in content: MarkdownPreparedBlockContent) -> Set<String> {
        var sources: Set<String> = []
        func inline(_ value: MarkdownPreparedInlineContent?) {
            guard let value else { return }
            for attachment in value.attachments.values {
                guard !attachment.isDecorative, case .allow = attachment.policyDecision else { continue }
                sources.insert(attachment.image.source)
            }
        }
        func list(_ items: [MarkdownPreparedListItem]) {
            for item in items {
                inline(item.inlineLayout)
                inline(item.selectionInlineLayout)
                list(item.childItems)
                item.childBlocks.forEach { block($0.preparedContent) }
            }
        }
        func block(_ value: MarkdownPreparedBlockContent) {
            guard value.policyDenialReason == nil else { return }
            inline(value.inlineLayout)
            inline(value.selectionInlineLayout)
            list(value.listItems)
            value.childBlocks.forEach { block($0.preparedContent) }
            value.richContent?.blocks.forEach { block($0.preparedContent) }
            if let table = value.table {
                for cell in table.header { inline(cell.inlineLayout); inline(cell.selectionInlineLayout) }
                for row in table.rows { for cell in row.cells { inline(cell.inlineLayout); inline(cell.selectionInlineLayout) } }
            }
        }
        block(content)
        return sources
    }
}
