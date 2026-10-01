import Foundation

/// The geometry of an SVG `<path d="…">`, reduced to moves, lines, cubic curves and closes in absolute coordinates,
/// which any drawing API can replay (SwiftUI's `Path`, Compose's `Path`). Covers the whole path grammar: M L H V C S
/// Q T A Z in both cases, implicit repeats, and the compact number and arc-flag forms icon sets use ("1.5.5",
/// "a1 1 0 011 1").
public struct SVGPath: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Segment: Sendable, Equatable {
        case move(Point)
        case line(Point)
        case cubic(Point, Point, Point)
        case close
    }

    public let segments: [Segment]

    /// nil when `data` is not a valid path.
    public init?(_ data: String) {
        var parser = Parser(Array(data.utf8))
        guard let segments = parser.parse() else { return nil }
        self.segments = segments
    }

    /// The smallest box holding every end point and control point.
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var points: [Point] = []
        for segment in segments {
            switch segment {
            case .move(let point), .line(let point): points.append(point)
            case .cubic(let first, let second, let end): points += [first, second, end]
            case .close: break
            }
        }
        return (points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0,
                points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
    }
}

private struct Parser {
    private let bytes: [UInt8]
    private var index = 0
    private var segments: [SVGPath.Segment] = []
    private var current = SVGPath.Point(x: 0, y: 0)
    private var start = SVGPath.Point(x: 0, y: 0)
    /// The second control point of the last C/S (or the control of the last Q/T), for the smooth forms.
    private var lastCubicControl: SVGPath.Point?
    private var lastQuadControl: SVGPath.Point?

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parse() -> [SVGPath.Segment]? {
        var command: UInt8?
        while true {
            skipSeparators()
            guard index < bytes.count else { break }
            if isCommand(bytes[index]) {
                command = bytes[index]
                index += 1
            } else if command == nil || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
                return nil
            }
            // A path starts with a move.
            guard let letter = command, !segments.isEmpty || letter | 0x20 == UInt8(ascii: "m"), apply(letter) else {
                return nil
            }
            // After a move, further coordinate pairs are lines.
            if letter == UInt8(ascii: "M") { command = UInt8(ascii: "L") }
            if letter == UInt8(ascii: "m") { command = UInt8(ascii: "l") }
        }
        return segments.isEmpty ? nil : segments
    }

    private mutating func apply(_ letter: UInt8) -> Bool {
        let relative = letter >= UInt8(ascii: "a")
        let origin = relative ? current : SVGPath.Point(x: 0, y: 0)
        func point(_ x: Double, _ y: Double) -> SVGPath.Point {
            SVGPath.Point(x: origin.x + x, y: origin.y + y)
        }
        var cubicControl: SVGPath.Point?
        var quadControl: SVGPath.Point?
        switch letter | 0x20 {
        case UInt8(ascii: "m"):
            guard let x = number(), let y = number() else { return false }
            current = point(x, y)
            start = current
            segments.append(.move(current))
        case UInt8(ascii: "l"):
            guard let x = number(), let y = number() else { return false }
            current = point(x, y)
            segments.append(.line(current))
        case UInt8(ascii: "h"):
            guard let x = number() else { return false }
            current = SVGPath.Point(x: relative ? current.x + x : x, y: current.y)
            segments.append(.line(current))
        case UInt8(ascii: "v"):
            guard let y = number() else { return false }
            current = SVGPath.Point(x: current.x, y: relative ? current.y + y : y)
            segments.append(.line(current))
        case UInt8(ascii: "c"):
            guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(),
                  let y = number() else { return false }
            cubicControl = point(x2, y2)
            curve(point(x1, y1), point(x2, y2), point(x, y))
        case UInt8(ascii: "s"):
            guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return false }
            let first = reflected(lastCubicControl)
            cubicControl = point(x2, y2)
            curve(first, point(x2, y2), point(x, y))
        case UInt8(ascii: "q"):
            guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return false }
            quadControl = point(x1, y1)
            quadratic(point(x1, y1), point(x, y))
        case UInt8(ascii: "t"):
            guard let x = number(), let y = number() else { return false }
            let control = reflected(lastQuadControl)
            quadControl = control
            quadratic(control, point(x, y))
        case UInt8(ascii: "a"):
            guard let rx = number(), let ry = number(), let rotation = number(), let large = flag(), let sweep = flag(),
                  let x = number(), let y = number() else { return false }
            arc(rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep, to: point(x, y))
        case UInt8(ascii: "z"):
            segments.append(.close)
            current = start
        default:
            return false
        }
        lastCubicControl = cubicControl
        lastQuadControl = quadControl
        return true
    }

    private func reflected(_ control: SVGPath.Point?) -> SVGPath.Point {
        guard let control else { return current }
        return SVGPath.Point(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    private mutating func curve(_ first: SVGPath.Point, _ second: SVGPath.Point, _ end: SVGPath.Point) {
        segments.append(.cubic(first, second, end))
        current = end
    }

    /// A quadratic curve is the cubic with its control points two thirds of the way to the control.
    private mutating func quadratic(_ control: SVGPath.Point, _ end: SVGPath.Point) {
        func twoThirds(_ from: SVGPath.Point) -> SVGPath.Point {
            SVGPath.Point(x: from.x + (control.x - from.x) * 2 / 3, y: from.y + (control.y - from.y) * 2 / 3)
        }
        curve(twoThirds(current), twoThirds(end), end)
    }

    /// An elliptical arc as cubic curves of at most 90° each (SVG 1.1, appendix F.6).
    private mutating func arc(rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool,
                              to end: SVGPath.Point) {
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0, end != current else {
            if end != current { segments.append(.line(end)) }
            current = end
            return
        }
        let phi = rotation * .pi / 180
        let (cosPhi, sinPhi) = (cos(phi), sin(phi))
        let dx = (current.x - end.x) / 2
        let dy = (current.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        // Radii too small for the distance are scaled up until the arc fits.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = (max(0, numerator) / denominator).squareRoot()
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = SVGPath.Point(x: cosPhi * cx1 - sinPhi * cy1 + (current.x + end.x) / 2,
                                   y: sinPhi * cx1 + cosPhi * cy1 + (current.y + end.y) / 2)
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let sign: Double = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / ((ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot())
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let pieces = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(pieces)
        let handle = 4 / 3 * tan(step / 4)
        func onEllipse(_ t: Double) -> (point: SVGPath.Point, derivative: SVGPath.Point) {
            let (cosT, sinT) = (cos(t), sin(t))
            let point = SVGPath.Point(x: center.x + rx * cosT * cosPhi - ry * sinT * sinPhi,
                                      y: center.y + rx * cosT * sinPhi + ry * sinT * cosPhi)
            let derivative = SVGPath.Point(x: -rx * sinT * cosPhi - ry * cosT * sinPhi,
                                           y: -rx * sinT * sinPhi + ry * cosT * cosPhi)
            return (point, derivative)
        }
        var t = theta
        for piece in 0..<pieces {
            let from = onEllipse(t)
            let to = onEllipse(t + step)
            let first = SVGPath.Point(x: from.point.x + handle * from.derivative.x,
                                      y: from.point.y + handle * from.derivative.y)
            let second = SVGPath.Point(x: to.point.x - handle * to.derivative.x,
                                       y: to.point.y - handle * to.derivative.y)
            // The last piece ends exactly where the path says, without rounding drift.
            curve(first, second, piece == pieces - 1 ? end : to.point)
            t += step
        }
    }

    private mutating func skipSeparators() {
        while index < bytes.count, [UInt8(ascii: " "), UInt8(ascii: ","), 9, 10, 13].contains(bytes[index]) {
            index += 1
        }
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private func isCommand(_ byte: UInt8) -> Bool {
        "MmLlHhVvCcSsQqTtAaZz".utf8.contains(byte)
    }

    /// An arc flag is one character, "0" or "1", with or without a separator after it.
    private mutating func flag() -> Bool? {
        skipSeparators()
        guard index < bytes.count, bytes[index] == UInt8(ascii: "0") || bytes[index] == UInt8(ascii: "1") else {
            return nil
        }
        index += 1
        return bytes[index - 1] == UInt8(ascii: "1")
    }

    /// "-1.5", ".5", "1e-3"; a second dot or a sign ends the number ("1.5.5" is 1.5 and .5).
    private mutating func number() -> Double? {
        skipSeparators()
        let begin = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
        var digits = false
        var dot = false
        while index < bytes.count {
            let byte = bytes[index]
            if isDigit(byte) {
                digits = true
            } else if byte == UInt8(ascii: "."), !dot {
                dot = true
            } else {
                break
            }
            index += 1
        }
        if digits, index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            var exponent = index + 1
            if exponent < bytes.count, bytes[exponent] == UInt8(ascii: "-") || bytes[exponent] == UInt8(ascii: "+") {
                exponent += 1
            }
            if exponent < bytes.count, isDigit(bytes[exponent]) {
                index = exponent
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
        }
        guard digits else {
            index = begin
            return nil
        }
        return Double(String(decoding: bytes[begin..<index], as: UTF8.self))
    }
}
