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
    var split: CGFloat = 0       // gap fraction (0 = sealed; >0 = blade cut into two cross-section slices)
    var splitHalf: SplitHalf? = nil   // when split>0, render only one half (for independent .glassEffect)
    var animatableData: CGFloat { get { open } set { open = newValue } }

    enum SplitHalf: Equatable { case top, bottom }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        let b = 0.09 * open
        let s = 0.055 * open
        var path = Path()
        if split > 0 {
            // Blade cut: De Casteljau split of the original almond at two y-values,
            // producing cross-section slices that keep the full curve width at the cut.
            let half = split / 2
            let topCut: CGFloat = 0.50 - half
            let botCut: CGFloat = 0.50 + half
            // Binary search: t on left curve (y: 0.28→0.72) where y = target
            func findT(_ target: CGFloat) -> CGFloat {
                var lo: CGFloat = 0, hi: CGFloat = 1
                for _ in 0..<24 {
                    let t = (lo + hi) * 0.5, mt = 1 - t
                    let y = mt*mt*mt*0.28 + 3*mt*mt*t*0.40 + 3*mt*t*t*0.60 + t*t*t*0.72
                    if y < target { lo = t } else { hi = t }
                }
                return (lo + hi) * 0.5
            }
            func lerp(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ t: CGFloat) -> (CGFloat, CGFloat) {
                (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
            }
            let tT = findT(topCut), tB = findT(botCut)
            // Left curve: L0→L3  Right curve: R0→R3 (reversed direction)
            let L0: (CGFloat, CGFloat) = (0.50, 0.28), L1: (CGFloat, CGFloat) = (0.50-b, 0.40), L2: (CGFloat, CGFloat) = (0.50-b, 0.60), L3: (CGFloat, CGFloat) = (0.50, 0.72)
            let R0: (CGFloat, CGFloat) = (0.50, 0.72), R1: (CGFloat, CGFloat) = (0.50+b, 0.60), R2: (CGFloat, CGFloat) = (0.50+b, 0.40), R3: (CGFloat, CGFloat) = (0.50, 0.28)
            let rtT = 1 - tT, rtB = 1 - tB
            // De Casteljau splits
            let lq1 = lerp(L0,L1,tT), lq2 = lerp(L1,L2,tT), lq3 = lerp(L2,L3,tT)
            let lr1 = lerp(lq1,lq2,tT), lr2 = lerp(lq2,lq3,tT)
            let lsT = lerp(lr1,lr2,tT)
            let lbq1 = lerp(L0,L1,tB), lbq2 = lerp(L1,L2,tB), lbq3 = lerp(L2,L3,tB)
            let lbr1 = lerp(lbq1,lbq2,tB), lbr2 = lerp(lbq2,lbq3,tB)
            let lsB = lerp(lbr1,lbr2,tB)
            let rq1 = lerp(R0,R1,rtT), rq2 = lerp(R1,R2,rtT), rq3 = lerp(R2,R3,rtT)
            let rr1 = lerp(rq1,rq2,rtT), rr2 = lerp(rq2,rq3,rtT)
            let rsT = lerp(rr1,rr2,rtT)
            let rbq1 = lerp(R0,R1,rtB), rbq2 = lerp(R1,R2,rtB), rbq3 = lerp(R2,R3,rtB)
            let rbr1 = lerp(rbq1,rbq2,rtB), rbr2 = lerp(rbq2,rbq3,rtB)
            let rsB = lerp(rbr1,rbr2,rtB)
            // top slice: top tip → left curve to lsT → line to rsT → right curve to R3(=top tip)
            if splitHalf != .bottom {
                path.move(to: p(L0.0, L0.1))
                path.addCurve(to: p(lsT.0, lsT.1), control1: p(lq1.0,lq1.1), control2: p(lr1.0,lr1.1))
                path.addLine(to: p(rsT.0, rsT.1))
                path.addCurve(to: p(R3.0, R3.1), control1: p(rr2.0,rr2.1), control2: p(rq3.0,rq3.1))
                path.closeSubpath()
            }
            // bottom slice: lsB → left curve to L3(bottom tip) → right curve to rsB → close
            if splitHalf != .top {
                path.move(to: p(lsB.0, lsB.1))
                path.addCurve(to: p(L3.0, L3.1), control1: p(lbr2.0,lbr2.1), control2: p(lbq3.0,lbq3.1))
                path.addCurve(to: p(rsB.0, rsB.1), control1: p(rbq1.0,rbq1.1), control2: p(rbr1.0,rbr1.1))
                path.closeSubpath()
            }
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
