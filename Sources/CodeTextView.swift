//  CodeTextView.swift
//  UIViewRepresentable bridge for UITextView so code blocks render UIKit-scope
//  attributed-string colors (foreground + background) that SwiftUI Text drops.

import SwiftUI
import UIKit

struct CodeTextView: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.contentInset = .zero
        tv.scrollIndicatorInsets = .zero
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let target = CGSize(width: proposal.width ?? .infinity, height: .infinity)
        return uiView.sizeThatFits(target)
    }
}
