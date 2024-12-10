@testable import SwiftGodot
import SwiftGodotTestability
import XCTest

@available(macOS 14, *)
extension Vector2 {
    static func gen(_ coordinateGen: TinyGen<Float>) -> TinyGen<Self> {
        return TinyGen { rng in
            return Vector2(x: coordinateGen(rng.left()), y: coordinateGen(rng.right()))
        }
    }

    static let mixed: TinyGen<Self> = gen(.mixedFloats)

    static let normalizedGen: TinyGen<Self> = TinyGenBuilder {
        TinyGen.gaussianFloats
        TinyGen.gaussianFloats
    }.map { x, y in
        // https://stackoverflow.com/q/6283080/77567
        let d = (x * x + y * y).squareRoot()
        return Vector2(x: x / d, y: y / d)
    }
}

@available(macOS 14, *)
final class Vector2CoverTests: GodotTestCase {

    static let testInt64s: [Int64] = [
        .min,
        Int64(Int32.min) - 1,
        Int64(Int32.min),
        -2,
        -1,
        0,
        1,
        2,
        Int64(Int32.max),
        Int64(Int32.max) + 1,
        .max
    ]
    
    static let testDoubles: [Double] = testInt64s.map { Double($0) } + [
        -.infinity,
        -1e100,
        -0.0,
         0.0,
         1e100,
         .infinity,
         .nan
    ]
    
    static let testFloats: [Float] = testDoubles.map { Float($0) }
    
    static let testVectors: [Vector2] = testFloats.flatMap { y in
        testFloats.map { x in
            Vector2(x: x, y: y)
        }
    }
    
    // Vector2.method()
    func testNullaryCovers() {
        func checkMethod(
            _ method: (Vector2) -> () -> some TestEquatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) {
            forAll(filePath: filePath, line: line) {
                Vector2.mixed
            } checkCover: {
                method($0)()
            }
        }
        
        checkMethod(Vector2.angle)
        checkMethod(Vector2.length)
        checkMethod(Vector2.lengthSquared)
        checkMethod(Vector2.normalized)
        checkMethod(Vector2.sign)
        checkMethod(Vector2.floor)
        checkMethod(Vector2.ceil)
        checkMethod(Vector2.round)
    }
    
    // Vector2.method(Double)
    func testUnaryDoubleCovers() {
        func checkMethod(
            _ method: (Vector2) -> (Double) -> some TestEquatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) {
            forAll(filePath: filePath, line: line) {
                Vector2.mixed
                TinyGen<Double>.mixedDoubles
            } checkCover: {
                method($0)($1)
            }
        }

        Float.$closeEnoughUlps.withValue(256) {
            checkMethod(Vector2.rotated)
        }

        checkMethod(Vector2.snappedf)
        checkMethod(Vector2.limitLength)
    }

    // Vector2.method(Vector2)
    func testUnaryCovers() {
        func checkMethod(
            _ method: (Vector2) -> (Vector2) -> some TestEquatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) {
            forAll(filePath: filePath, line: line) {
                Vector2.mixed
                Vector2.mixed
            } checkCover: {
                method($0)($1)
            }
        }
        
        checkMethod(Vector2.distanceTo(_:))
        checkMethod(Vector2.distanceSquaredTo(_:))
        checkMethod(Vector2.angleTo(_:))
        checkMethod(Vector2.angleToPoint)
        checkMethod(Vector2.dot)
        checkMethod(Vector2.cross)
        checkMethod(Vector2.project)

        func checkMethodNormalized(
            _ method: (Vector2) -> (Vector2) -> some TestEquatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) {
            forAll(filePath: filePath, line: line) {
                Vector2.mixed
                Vector2.normalizedGen
            } checkCover: {
                method($0)($1)
            }
        }
        
        checkMethodNormalized(Vector2.slide)
        checkMethodNormalized(Vector2.reflect(line:))
        checkMethodNormalized(Vector2.bounce)
    }

#if false

    // Static
    func testFromAngle() throws {
        for d in Self.testDoubles {
            try checkCover { Vector2.fromAngle(d) }
        }
    }
    
    func testClamp() throws {
        for v in Self.testVectors {
            for u in Self.testVectors {
                for w in Self.testVectors {
                    try checkCover { v.clamp(min: u, max: w) }
                }
            }
        }
    }
    
    func testClampf() throws {
        for v in Self.testVectors {
            for d in Self.testDoubles {
                for e in Self.testDoubles {
                    try checkCover { v.clampf(min: d, max: e) }
                }
            }
        }
    }
    
    func testMoveToward() throws {
        for v in Self.testVectors {
            for u in Self.testVectors {
                for d in Self.testDoubles {
                    try checkCover { v.moveToward(to: u, delta: d) }
                }
            }
        }
    }
    
    // Operator Covers
    
    func testBinaryOperators_Vector2i_Vector2i() throws {
        // Operators of the form Vector2i * Vector2i.

        func checkOperator(
            _ op: (Vector2, Vector2) -> some Equatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) throws {
            for v in Self.testVectors {
                for u in Self.testVectors {
                    try checkCover(filePath: filePath, line: line) { op(v, u) }
                }
            }
        }
        
        // Arithmetic Operators
        try checkOperator(+)
        try checkOperator(-)
        try checkOperator(*)
        try checkOperator(/)
        // Comparison Operators
        try checkOperator(==)
        try checkOperator(!=)
        try checkOperator(<)
        try checkOperator(<=)
        try checkOperator(>)
        try checkOperator(>=)
    }
    
    func testBinaryOperators_Vector2i_Int64() throws {
        // Operators of the form Vector2i * Int64.

        func checkOperator(
            _ op: (Vector2, Int64) -> some Equatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) throws {
            for v in Self.testVectors {
                for i in Self.testInt64s {
                    try checkCover(filePath: filePath, line: line) { op(v, i) }
                }
            }
        }

        try checkOperator(/)
        try checkOperator(*)
    }
    
    func testBinaryOperators_Vector2i_Double() throws {
        // Operators of the form Vector2i * Int64.

        func checkOperator(
            _ op: (Vector2, Double) -> some Equatable,
            filePath: StaticString = #filePath, line: UInt = #line
        ) throws {
            for v in Self.testVectors {
                for d in Self.testDoubles {
                    try checkCover(filePath: filePath, line: line) { op(v, d) }
                }
            }
        }

        try checkOperator(/)
        try checkOperator(*)
    }
    
    
    // Non-covers tests
    
    func testOperatorUnaryMinus () {
        var value: Vector2
        
        value = -Vector2 (x: -1.1, y: 2.2)
        XCTAssertEqual (value.x, 1.1)
        XCTAssertEqual (value.y, -2.2)
        
        value = -Vector2 (x: 3.3, y: -4.4)
        XCTAssertEqual (value.x, -3.3)
        XCTAssertEqual (value.y, 4.4)
        
        value = -Vector2 (x: -.greatestFiniteMagnitude, y: .greatestFiniteMagnitude)
        XCTAssertEqual (value.x, .greatestFiniteMagnitude)
        XCTAssertEqual (value.y, -.greatestFiniteMagnitude)
        
        value = -Vector2 (x: .infinity, y: -.infinity)
        XCTAssertEqual (value.x, -.infinity)
        XCTAssertEqual (value.y, .infinity)
        
        value = -Vector2 (x: .nan, y: .nan)
        XCTAssertTrue (value.x.isNaN)
        XCTAssertTrue (value.y.isNaN)
    }
#endif
}

