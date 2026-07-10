//  Marks.swift  (shared: app + EnclaveWidgets extension)
//  The Enclave figure that sits inside the ring: a sealed vertical slit — a
//  vesica with a center seam. Vertical Rectangle's rectangle, collapsed and shut.
//  Drawn monoline in a normalized 0…1 box so it scales from the Dynamic Island
//  to a splash lockup unchanged.

import SwiftUI

struct EnclaveSlit: Shape {
    /// Pupil dilation. 1 = the sealed default almond; animate ~0.2…1.3 for a
    /// cat's-eye pupil widening and closing. Height stays fixed; the almond bulge
    /// and the seal scale together so the seam always sits inside the slit.
    var open: CGFloat = 1
    var split: CGFloat = 0       // gap fraction (0 = sealed; ~0.15 = thick split into two halves)
    var animatableData: CGFloat { get { open } set { open = newValue } }
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        let b = 0.09 * open     // half-bulge from center (0.09 = the sealed default)
        let s = 0.055 * open    // half-length of the seal
        var path = Path()
        if split > 0 {
            // split almond — two separate halves with a thick gap where the seal sat
            let half = split / 2
            let topEnd = 0.50 - half
            let botStart = 0.50 + half
            let r1 = 0.273, r2 = 0.727     // control-point ratios preserved from the sealed almond
            // top half
            let st = topEnd - 0.28
            path.move(to: p(0.50, 0.28))
            path.addCurve(to: p(0.50, topEnd),
                          control1: p(0.50 - b, 0.28 + st * r1),
                          control2: p(0.50 - b, 0.28 + st * r2))
            path.addCurve(to: p(0.50, 0.28),
                          control1: p(0.50 + b, 0.28 + st * r2),
                          control2: p(0.50 + b, 0.28 + st * r1))
            path.closeSubpath()
            // bottom half
            let sb = 0.72 - botStart
            path.move(to: p(0.50, botStart))
            path.addCurve(to: p(0.50, 0.72),
                          control1: p(0.50 - b, botStart + sb * r1),
                          control2: p(0.50 - b, botStart + sb * r2))
            path.addCurve(to: p(0.50, botStart),
                          control1: p(0.50 + b, botStart + sb * r2),
                          control2: p(0.50 + b, botStart + sb * r1))
            path.closeSubpath()
        } else {
            // the almond / slit
            path.move(to: p(0.50, 0.28))
            path.addCurve(to: p(0.50, 0.72), control1: p(0.50 - b, 0.40), control2: p(0.50 - b, 0.60))
            path.addCurve(to: p(0.50, 0.28), control1: p(0.50 + b, 0.60), control2: p(0.50 + b, 0.40))
            path.closeSubpath()
            // the seal
            path.move(to: p(0.50 - s, 0.50))
            path.addLine(to: p(0.50 + s, 0.50))
        }
        return path
    }
}
