@_spi(SwiftCovers) import SwiftGodot

extension Vector2i {

    public init(from: Vector2i) {
        self = from
    }

    public init(from: Vector2) {
        /*
         The Godot engine casts `int32_t` to `float` using `fcvtzs` (on ARM). Swift `Int32(_: Float)` does the same, but then checks for and aborts on overflow, which is unacceptable. To get good Swift code gen, I call an inlinable imported C function. In an optimized build, I compile down to this:

         fcvtzs     w8, s0
         fcvtzs     w9, s1
         orr        x0, x8, x9, lsl #32
         ret
         */

        self.init(x: cCastToInt32(from.x), y: cCastToInt32(from.y))
    }

    public func aspect() -> Double {
        return Double(Float(x) / Float(y))
    }

    public func maxAxisIndex() -> Int64 {
        return (x < y ? Axis.y : .x).rawValue
    }

    public func minAxisIndex() -> Int64 {
        return (x < y ? Axis.x : .y).rawValue
    }

    public func distanceTo(_ to: Vector2i) -> Double {
        return (to - self).length()
    }

    public func distanceSquaredTo(_ to: Vector2i) -> Double {
        return Double((to - self).lengthSquared())
    }

    public func length() -> Double {
        return Double(lengthSquared()).squareRoot()
    }

    public func lengthSquared() -> Int64 {
        let x = Int64(x)
        let y = Int64(y)
        return x &* x &+ y &* y
    }

    public func sign() -> Vector2i {
        return Vector2i(x: x.signum(), y: y.signum())
    }

    public func abs() -> Vector2i {
        // This handles Int32.min exactly the way C would.
        return Vector2i(
            x: Int32(truncatingIfNeeded: x.magnitude),
            y: Int32(truncatingIfNeeded: y.magnitude)
        )
    }

    public func clamp(min: Vector2i, max: Vector2i) -> Vector2i {
        return Vector2i(
            x: x.clamped(min: min.x, max: max.x),
            y: y.clamped(min: min.y, max: max.y)
        )
    }

    public func clampi(min: Int64, max: Int64) -> Vector2i {
        let min = Int32(truncatingIfNeeded: min)
        let max = Int32(truncatingIfNeeded: max)
        return Vector2i(
            x: x.clamped(min: min, max: max),
            y: y.clamped(min: min, max: max)
        )
    }

    // snapped is special-cased.

    public func snappedi(step: Int64) -> Vector2i {
        let step = Double(Int32(truncatingIfNeeded: step))
        return Vector2i(
            x: cCastToInt32(Double(x).snapped(step: step)),
            y: cCastToInt32(Double(y).snapped(step: step))
        )
    }

    public func min(with: Vector2i) -> Vector2i {
        return Vector2i(
            x: Swift.min(x, with.x),
            y: Swift.min(y, with.y)
        )
    }

    public func mini(with: Int64) -> Vector2i {
        let i = Int32(truncatingIfNeeded: with)
        return Vector2i(
            x: Swift.min(x, i),
            y: Swift.min(y, i)
        )
    }

    public func max(with: Vector2i) -> Vector2i {
        return Vector2i(
            x: Swift.max(x, with.x),
            y: Swift.max(y, with.y)
        )
    }

    public func maxi(with: Int64) -> Vector2i {
        let i = Int32(truncatingIfNeeded: with)
        return Vector2i(
            x: Swift.max(x, i),
            y: Swift.max(y, i)
        )
    }

    public subscript(index: Int64) -> Int64 {
        get {
            return Int64(SIMD2(x, y)[Int(index)])
        }
        set {
            var simd = SIMD2(x, y)
            simd[Int(index)] = Int32(truncatingIfNeeded: newValue)
            (x, y) = (simd.x, simd.y)
        }
    }

    public static func * (lhs: Vector2i, rhs: Int64) -> Vector2i {
        let f = Int32(truncatingIfNeeded: rhs)
        return Vector2i(
            x: lhs.x &* f,
            y: lhs.y &* f
        )
    }

    public static func / (lhs: Vector2i, rhs: Int64) -> Vector2i {
        /*
         Swift doesn't provide an `&/` operator like it does `&*`, `&+` and `&-`. Using `lhs.x.dividedReportingOverflow(by: rhs).partialValue` gives the correct answer with suboptimal code gen. I call an inlinable imported C function, which gives extremely good code gen:

         lsr        x8, x0, #0x20
         sdiv       w9, w0, w1
         sdiv       w8, w8, w1
         orr        x0, x9, x8, lsl #32
         ret
         */

        let rhs = Int32(truncatingIfNeeded: rhs)
        return Self(
            x: cDivide(numerator: lhs.x, denominator: rhs),
            y: cDivide(numerator: lhs.y, denominator: rhs)
        )
    }

    public static func % (lhs: Vector2i, rhs: Int64) -> Vector2i {
        /*
         See comment in `/`. Code gen:

         lsr        x8, x0, #0x20
         sdiv       w9, w0, w1
         msub       w9, w9, w1, w0
         sdiv       w10, w8, w1
         msub       w8, w10, w1, w8
         orr        x0, x9, x8, lsl #32
         ret
         */

        let rhs = Int32(truncatingIfNeeded: rhs)
        return Self(
            x: cRemainder(numerator: lhs.x, denominator: rhs),
            y: cRemainder(numerator: lhs.y, denominator: rhs)
        )
    }

    public static func * (lhs: Vector2i, rhs: Double) -> Vector2 {
        let rhs = Float(rhs)
        return Vector2(
            x: Float(lhs.x) * rhs,
            y: Float(lhs.y) * rhs
        )
    }

    public static func / (lhs: Vector2i, rhs: Double) -> Vector2 {
        let rhs = Float(rhs)
        return Vector2(
            x: Float(lhs.x) / rhs,
            y: Float(lhs.y) / rhs
        )
    }

    public static func == (lhs: Vector2i, rhs: Vector2i) -> Bool {
        return lhs.tuple == rhs.tuple
    }

    public static func != (lhs: Vector2i, rhs: Vector2i) -> Bool {
        return !(lhs == rhs)
    }

    public static func < (lhs: Vector2i, rhs: Vector2i) -> Bool {
        return lhs.tuple < rhs.tuple
    }

    public static func <= (lhs: Vector2i, rhs: Vector2i) -> Bool {
        return lhs.tuple <= rhs.tuple
    }

    public static func > (lhs: Vector2i, rhs: Vector2i) -> Bool {
        return lhs.tuple > rhs.tuple
    }

    public static func >= (lhs: Vector2i, rhs: Vector2i) -> Bool {
        return lhs.tuple >= rhs.tuple
    }

    public static func + (lhs: Vector2i, rhs: Vector2i) -> Vector2i {
        return Vector2i(
            x: lhs.x &+ rhs.x,
            y: lhs.y &+ rhs.y
        )
    }

    public static func - (lhs: Vector2i, rhs: Vector2i) -> Vector2i {
        return Vector2i(
            x: lhs.x &- rhs.x,
            y: lhs.y &- rhs.y
        )
    }

    public static func * (lhs: Vector2i, rhs: Vector2i) -> Vector2i {
        return Vector2i(
            x: lhs.x &* rhs.x,
            y: lhs.y &* rhs.y
        )
    }

    public static func / (lhs: Vector2i, rhs: Vector2i) -> Vector2i {
        return Vector2i(
            x: cDivide(numerator: lhs.x, denominator: rhs.x),
            y: cDivide(numerator: lhs.y, denominator: rhs.y)
        )
    }

    public static func % (lhs: Vector2i, rhs: Vector2i) -> Vector2i {
        return Vector2i(
            x: cRemainder(numerator: lhs.x, denominator: rhs.x),
            y: cRemainder(numerator: lhs.y, denominator: rhs.y)
        )
    }
}
