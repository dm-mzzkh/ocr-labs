import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum ImageFactory {
    static func cg(basedOn context: CGContext) -> CGImage {
        context.makeImage()!
    }

    static func context(size: (Int, Int)) -> CGContext {
        let (w, h) = size
        let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)) // белый фон
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx
    }

    /// Текст тёмно-синим по белому, крупный шрифт — детерминированно.
    static func drawText(_ string: String, size: (Int, Int) = (600, 200)) -> CGImage {
        let ctx = context(size: size)
        let font = CTFontCreateWithName("Helvetica" as CFString, 72, nil)
        let attr = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(size.0) - bounds.width) / 2, y: (CGFloat(size.1) - bounds.height) / 2)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    /// Прямоугольный объект в центре — для contours/rectangles/saliency.
    static func drawRect(size: (Int, Int) = (512, 512)) -> CGImage {
        let ctx = context(size: size)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 150, y: 150, width: 200, height: 200))
        return ctx.makeImage()!
    }

    /// Лицо-каркас: овал + глаза + рот тёмным по белому.
    static func drawFace(size: (Int, Int) = (512, 512)) -> CGImage {
        let ctx = context(size: size)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(12)
        let face = CGRect(x: 130, y: 100, width: 250, height: 320)
        ctx.strokeEllipse(in: face)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addEllipse(in: CGRect(x: face.minX + 60, y: face.midY + 30, width: 40, height: 50))
        ctx.fillPath()
        ctx.addEllipse(in: CGRect(x: face.maxX - 100, y: face.midY + 30, width: 40, height: 50))
        ctx.fillPath()
        return ctx.makeImage()!
    }

    /// Реальный QR-код через CoreImage — детерминированный вход для детектора баркодов.
    static func drawQRCode(_ payload: String) -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        let ciImage = filter.outputImage!
        let scale = 20.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        return ctx.createCGImage(scaled, from: scaled.extent)!
    }

    /// «Человек»: залитые голова и туловище, толстые конечности —
    /// ближе к фото, чем схематичный силуэт (модели поз капризнее).
    static func drawPerson(size: (Int, Int) = (512, 512)) -> CGImage {
        let ctx = context(size: size)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        // голова
        ctx.fillEllipse(in: CGRect(x: 226, y: 390, width: 70, height: 70))
        // торс
        ctx.fill(CGRect(x: 210, y: 240, width: 100, height: 160))
        // конечности (толстые линии)
        ctx.setLineWidth(34)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 250, y: 330))
        ctx.addLine(to: CGPoint(x: 160, y: 290)) // левая рука
        ctx.move(to: CGPoint(x: 270, y: 330))
        ctx.addLine(to: CGPoint(x: 360, y: 290)) // правая рука
        ctx.move(to: CGPoint(x: 235, y: 250))
        ctx.addLine(to: CGPoint(x: 200, y: 100)) // левая нога
        ctx.move(to: CGPoint(x: 285, y: 250))
        ctx.addLine(to: CGPoint(x: 320, y: 100)) // правая нога
        ctx.strokePath()
        return ctx.makeImage()!
    }

    /// Таблица: сетка линий + текст — вход для RecognizeDocumentsRequest.
    static func drawTable() -> CGImage {
        let ctx = context(size: (800, 600))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(3)
        let rect = CGRect(x: 100, y: 150, width: 600, height: 300)
        ctx.addRect(rect)
        for i in 1...2 {
            ctx.move(to: CGPoint(x: rect.minX + CGFloat(i) * 200, y: rect.minY))
            ctx.addLine(to: CGPoint(x: rect.minX + CGFloat(i) * 200, y: rect.maxY))
        }
        ctx.move(to: CGPoint(x: rect.minX, y: rect.midY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        ctx.strokePath()
        let cells: [(CGFloat, CGFloat, String)] = [
            (110, 380, "NAME"), (310, 380, "EMAIL"), (510, 380, "PHONE"),
            (110, 240, "Ann"),  (310, 240, "a@x.com"), (510, 240, "5550101"),
        ]
        for (x, y, text) in cells {
            let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
            let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
            ctx.textPosition = CGPoint(x: x, y: y)
        }
        return ctx.makeImage()!
    }
}
