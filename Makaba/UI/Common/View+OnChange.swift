//
//  View+OnChange.swift
//  Makaba
//
//  Backward-compatible iOS 16/17+ value change observation wrapper.
//

import SwiftUI

extension View {
    /// Safe cross-version value change listener adapting dynamically between iOS 16 and iOS 17+.
    @ViewBuilder
    public func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}
