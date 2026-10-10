import CoreGraphics
import Foundation

/// A circle fitted to a thumb sweep.
public struct CircleFit: Equatable, Sendable {
    public var center: CGPoint
    public var radius: CGFloat
    /// Root-mean-square radial residual: how far the samples stray from the circle.
    public var rms: CGFloat
}

/// The geometry behind Arc: least-squares circle fitting and small numeric helpers.
public enum ArcMath {
    /// Least-squares circle through `points`.
    ///
    /// An algebraic (Kasa) fit gives the starting point, then Gauss-Newton steps minimise
    /// the true geometric error (sum of squared distances to the circle). The algebraic fit
    /// alone is biased toward small radii on short noisy arcs, which is exactly what a
    /// thumb sweep is.
    ///
    /// nil when the points are (nearly) collinear, too few, or the radius is absurd.
    public static func fitCircle(_ points: [CGPoint]) -> CircleFit? {
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0.0) { $0 + Double($1.x) } / n
        let my = points.reduce(0.0) { $0 + Double($1.y) } / n
        var suu = 0.0, suv = 0.0, svv = 0.0, suz = 0.0, svz = 0.0, sz = 0.0
        for p in points {
            let u = Double(p.x) - mx, v = Double(p.y) - my
            let z = u * u + v * v
            suu += u * u; suv += u * v; svv += v * v
            suz += u * z; svz += v * z; sz += z
        }
        let det = suu * svv - suv * suv
        guard det > 1e-9 * (suu + svv) * (suu + svv), det.isFinite else { return nil }
        // z + D u + E v + F = 0 with u, v centred, so F = -mean(z).
        let d = (-suz * svv + svz * suv) / det
        let e = (-svz * suu + suz * suv) / det
        let f = -sz / n
        var a = -d / 2, b = -e / 2
        let r2 = a * a + b * b - f
        guard r2 > 0 else { return nil }
        var r = r2.squareRoot()

        func cost(_ a: Double, _ b: Double, _ r: Double) -> Double {
            var c = 0.0
            for p in points {
                let du = Double(p.x) - mx - a, dv = Double(p.y) - my - b
                let res = (du * du + dv * dv).squareRoot() - r
                c += res * res
            }
            return c
        }

        var current = cost(a, b, r)
        for _ in 0..<40 {
            var jtj = [[Double]](repeating: [0, 0, 0], count: 3)
            var jtr = [0.0, 0.0, 0.0]
            for p in points {
                let du = Double(p.x) - mx - a, dv = Double(p.y) - my - b
                let di = (du * du + dv * dv).squareRoot()
                guard di > 1e-9 else { continue }
                let row = [-du / di, -dv / di, -1.0]
                let res = di - r
                for i in 0..<3 {
                    jtr[i] += row[i] * res
                    for j in 0..<3 { jtj[i][j] += row[i] * row[j] }
                }
            }
            guard let step = solve3(jtj, [-jtr[0], -jtr[1], -jtr[2]]) else { break }
            var scale = 1.0
            var improved = false
            for _ in 0..<8 {
                let c = cost(a + step[0] * scale, b + step[1] * scale, r + step[2] * scale)
                if c <= current {
                    a += step[0] * scale; b += step[1] * scale; r += step[2] * scale
                    current = c; improved = true
                    break
                }
                scale /= 2
            }
            if !improved || (step[0] * step[0] + step[1] * step[1] + step[2] * step[2]) < 1e-12 { break }
        }
        guard r.isFinite, r > 0, r < 1e6 else { return nil }
        return CircleFit(center: CGPoint(x: a + mx, y: b + my), radius: CGFloat(r),
                         rms: CGFloat((current / n).squareRoot()))
    }

    /// Gaussian elimination with partial pivoting.
    static func solve3(_ m: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = m
        var b = rhs
        for col in 0..<3 {
            var pivot = col
            for row in (col + 1)..<3 where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot); b.swapAt(col, pivot)
            for row in (col + 1)..<3 {
                let k = a[row][col] / a[col][col]
                for j in col..<3 { a[row][j] -= k * a[col][j] }
                b[row] -= k * b[col]
            }
        }
        var x = [0.0, 0.0, 0.0]
        for row in stride(from: 2, through: 0, by: -1) {
            var s = b[row]
            for j in (row + 1)..<3 { s -= a[row][j] * x[j] }
            x[row] = s / a[row][row]
        }
        return x
    }

    /// The q-quantile (0...1) of `values`.
    static func quantile(_ values: [CGFloat], _ q: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let i = min(max(q, 0), 1) * CGFloat(s.count - 1)
        let lo = Int(i.rounded(.down)), hi = Int(i.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (i - CGFloat(lo))
    }

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}
