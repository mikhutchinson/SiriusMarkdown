import SwiftUI

extension View {
    @ViewBuilder
    func markdownOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        #if os(visionOS)
        onChange(of: value) { _, newValue in
            action(newValue)
        }
        #else
        if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value) { newValue in
                action(newValue)
            }
        }
        #endif
    }

    @ViewBuilder
    func markdownContextMenu<MenuItems: View>(
        @ViewBuilder _ menuItems: () -> MenuItems
    ) -> some View {
        #if os(watchOS)
        self
        #else
        contextMenu(menuItems: menuItems)
        #endif
    }
}
