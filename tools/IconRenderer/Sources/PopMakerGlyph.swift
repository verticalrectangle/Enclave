//  PopMakerGlyph.swift
//  The PopMaker Studio figure: a play triangle — the universal video symbol.
//  Drawn in a normalized 0…1 box so it scales like EnclaveSlit. Works as both
//  .fill (liquidMark glass sculpt) and .stroke (flatGlass etched seam).
//  Supports blade-cut split into two independent halves (top/bottom) like EnclaveSlit.

import SwiftUI

struct PopMakerGlyph: Shape {
    var split: CGFloat = 0          // gap fraction (0 = solid; >0 = blade cut into two halves)
    var splitHalf: SplitHalf? = nil // when split>0, render only one half
    enum SplitHalf: Equatable { case top, bottom }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        // Triangle vertices: top-left (0.36, 0.28), right (0.70, 0.50), bottom-left (0.36, 0.72)
        let tx = 0.36, ty1 = 0.28, ty2 = 0.72
        let rx = 0.70, ry = 0.50

        if split > 0 {
            let half = split / 2
            let topCut: CGFloat = 0.50 - half
            let botCut: CGFloat = 0.50 + half

            // For the left edge (x=tx, y: ty1→ty2) and the two slanted edges,
            // find x at a given y by linear interpolation.
            // Left edge is vertical at x=tx, so x at any y is just tx.
            // Top-left → right edge: from (tx, ty1) to (rx, ry)
            func xOnTopEdge(y: CGFloat) -> CGFloat {
                let t = (y - ty1) / (ry - ty1)
                return tx + (rx - tx) * t
            }
            // Right → bottom-left edge: from (rx, ry) to (tx, ty2)
            func xOnBottomEdge(y: CGFloat) -> CGFloat {
                let t = (y - ry) / (ty2 - ry)
                return rx + (tx - rx) * t
            }

            // At topCut: both edges are the top edge (since topCut < 0.50 = ry)
            let topRightX = xOnTopEdge(y: topCut)
            // At botCut: both edges are the bottom edge (since botCut > 0.50 = ry)
            let botRightX = xOnBottomEdge(y: botCut)

            var path = Path()
            // Top half: top vertex → left edge to topCut → right edge to topCut → close
            if splitHalf != .bottom {
                path.move(to: p(tx, ty1))
                path.addLine(to: p(tx, topCut))
                path.addLine(to: p(topRightX, topCut))
                path.closeSubpath()
            }
            // Bottom half: left edge at botCut → bottom vertex → right edge at botCut → close
            if splitHalf != .top {
                path.move(to: p(tx, botCut))
                path.addLine(to: p(tx, ty2))
                path.addLine(to: p(botRightX, botCut))
                path.closeSubpath()
            }
            return path
        }

        // Solid play triangle
        var path = Path()
        path.move(to: p(tx, ty1))
        path.addLine(to: p(rx, ry))
        path.addLine(to: p(tx, ty2))
        path.closeSubpath()
        return path
    }
}
