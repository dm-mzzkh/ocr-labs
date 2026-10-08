import Vision
import CoreGraphics
import Foundation

// Аннотирование картинки результатами Vision: рамки, точки, полигоны, подписи.

struct Marker {
    enum Kind {
        case box(rect: NormalizedRect, text: String?)
        case points([NormalizedPoint])
        case pointsCG([CGPoint]) // уже в пиксельных координатах, origin — верхний-левый
        case polygon(points: [NormalizedPoint], text: String?)
        case horizon(angleDeg: Double)
    }
    let color: CGColor
    let kind: Kind
}

enum Overlay {
    static let palette: [CGColor] = [
        CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1),   // красный
        CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1),   // синий
        CGColor(red: 0.1, green: 0.8, blue: 0.3, alpha: 1), // зелёный
        CGColor(red: 1, green: 0.7, blue: 0, alpha: 1),     // оранжевый
        CGColor(red: 0.9, green: 0.2, blue: 0.9, alpha: 1), // розовый
        CGColor(red: 0.2, green: 0.9, blue: 0.9, alpha: 1), // голубой
    ]

    static func color(_ index: Int) -> CGColor {
        palette[index % palette.count]
    }

    static func annotate(base: CGImage, markers: [Marker]) -> CGImage {
        let ctx = CGContext(
            data: nil, width: base.width, height: base.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: base.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard let ctx else { return base }
        let size = CGSize(width: base.width, height: base.height)

        for marker in markers {
            ctx.setStrokeColor(marker.color)
            ctx.setFillColor(marker.color)
            switch marker.kind {
            case .box(let rect, let text):
                let r = rectInPixels(rect, size: size).insetBy(dx: -2, dy: -2)
                let cg = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
                ctx.setLineWidth(4)
                ctx.stroke(cg)
                if let text, !text.isEmpty {
                    // верхняя рамка в CG-координатах = cg.maxY; подпись НАД рамкой
                    drawLabel(text, at: CGPoint(x: cg.minX, y: cg.maxY - 4), in: ctx)
                }
            case .points(let points):
                ctx.setLineWidth(2)
                for p in points {
                    let pt = pointInPixels(p, size: size)
                    ctx.fillEllipse(in: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
                }
            case .pointsCG(let points):
                ctx.setLineWidth(2)
                for p in points {
                    let pt = CGPoint(x: p.x, y: size.height - p.y) // top-left → CG
                    ctx.fillEllipse(in: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
                }
            case .polygon(let points, let text):
                ctx.setLineWidth(3)
                let path = CGMutablePath()
                let pts = points.map { pointInPixels($0, size: size) }
                guard let first = pts.first else { continue }
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.strokePath()
                if let text, !text.isEmpty {
                    // самая верхняя точка полигона (CG-координаты) — подпись над ней
                    let top = pts.min(by: { $0.y < $1.y }) ?? first
                    drawLabel(text, at: CGPoint(x: top.x, y: top.y - 6), in: ctx)
                }
            case .horizon(let angleDeg):
                let dy = tan(angleDeg * .pi / 180) * Double(size.width)
                ctx.setLineWidth(4)
                ctx.setLineDash(phase: 10, lengths: [20, 14])
                ctx.move(to: CGPoint(x: 0, y: size.height / 2 + CGFloat(dy) / 2))
                ctx.addLine(to: CGPoint(x: size.width, y: size.height / 2 - CGFloat(dy) / 2))
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        return ctx.makeImage() ?? base
    }

    static func rectInPixels(_ rect: NormalizedRect, size: CGSize) -> CGRect {
        rect.toImageCoordinates(size, origin: .upperLeft)
    }

    static func pointInPixels(_ p: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }

    /// contour-region (NormalizedRegion/Contour) → точки; simd_float2 → NormalizedPoint
    @available(macOS 15.0, *)
    static func points(in region: ContoursObservation.Contour) -> [NormalizedPoint] {
        region.normalizedPoints.map { NormalizedPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    }

    private static func drawLabel(_ text: String, at point: CGPoint, in ctx: CGContext) {
        let font = CTFontCreateWithName("Menlo" as CFString, 26, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let pad: CGFloat = 4
        // point — верхний-левый угол подписи в CG-координатах (origin снизу-слева):
        // bg растёт ВНИЗ от point, базлайн текста чуть ниже point.
        let bg = CGRect(x: point.x - pad, y: point.y - bounds.height - 2 * pad,
                        width: bounds.width + 2 * pad, height: bounds.height + 2 * pad)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.65))
        ctx.fill(bg)
        ctx.textPosition = CGPoint(x: point.x, y: point.y - pad)
        CTLineDraw(line, ctx)
    }
}
