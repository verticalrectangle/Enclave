//  Marks.swift  (shared: app + EnclaveWidgets extension)
//  The Enclave figure that sits inside the ring: a sealed vertical slit — a
//  vesica with a center seam. Vertical Rectangle's rectangle, collapsed and shut.
//  Drawn monoline in a normalized 0…1 box so it scales from the Dynamic Island
//  to a splash lockup unchanged.

import SwiftUI

struct EnclaveSlit: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        // the almond / slit
        path.move(to: p(0.50, 0.28))
        path.addCurve(to: p(0.50, 0.72), control1: p(0.41, 0.40), control2: p(0.41, 0.60))
        path.addCurve(to: p(0.50, 0.28), control1: p(0.59, 0.60), control2: p(0.59, 0.40))
        path.closeSubpath()
        // the seal
        path.move(to: p(0.445, 0.50))
        path.addLine(to: p(0.555, 0.50))
        return path
    }
}
