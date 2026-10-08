import Foundation
import Vision
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
@testable import VisionLab

// Простейший CLI для ручной проверки Vision-функций над своими картинками.
// Пример: swift run CheckerCLI text photo.jpg [out.png]
// Если последний аргумент выглядит как путь картинки — команда дополнительно
// сохранит аннотированный PNG: рамки/точки/полигоны/подписи поверх фото.

func printUsage() {
    print("""
    CheckerCLI — Vision over your photos
    usage: swift run CheckerCLI <command> <image> [out.png]
    commands:
      text <img> [out]            — распознанный текст построчно + рамки
      docs <img> [out]            — структура документа (26): параграфы/таблицы/QR + рамки
      barcodes <img> [out]        — тип + payload баркодов + полигоны
      faces <img> [out]           — рамки лиц, roll/yaw, capture quality
      landmarks <img> [out]       — точки ландмарок лиц
      aesthetics <img>            — эстетический score (-1…1)
      smudge <img>                — «грязный объектив» (26), 0…1
      salience <img> [out]        — рамка самого заметного объекта
      classify <img>              — топ-10 меток
      animals <img> [out]         — рамки животных + confidence
      humans <img> [out]          — рамки людей
      contours <img> [out]        — контуры поверх картинки
      rects <img> [out]           — найденные прямоугольники
      horizon <img> [out]         — угол горизонта + линия
      segment <img> [out]         — маска человека, наложенная на фото → PNG
      textrects <img> [out]       — рамки всевозможных текстовых регионов
      docseg <img> [out]          — рамка документа (страница с текстом)
      heat <img> [out]            — тепловая карта внимания (где взгляд)
      matte <img> [out]           — классический matte-маска человека (зелёная)
      register <img1> <img2> [-H] — выравнивание двух кадров (-H — гомография/перспектива)
      featureprint <img1> <img2>  — сходство двух картинок
      track <img1> <img2> [out]   — трекинг объекта кадр1 → кадр2 (bbox на кадре 2)
      everything <img> [out-<cmd>.png каждый]  — все запросы, отдельная картинка на каждый
      --demo qr|text|table|face|person  — сгенерировать тест-картинку /tmp/visionlab-demo.png
    """)
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("Error: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fail("не удалось прочитать картинку: \(path)")
    }
    // EXIF-поворот нормализуем в пиксели: дальше Vision и рисование работают в одном «визуальном» пространстве.
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as Dictionary?
    let exifOrientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    guard exifOrientation != 1 else { return img }
    let ci = CIImage(cgImage: img).oriented(CIImageOrientationTable[exifOrientation] ?? .up)
    let context = CIContext()
    guard let normalized = context.createCGImage(ci, from: ci.extent) else {
        fail("не удалось нормализовать ориентацию: \(path)")
    }
    return normalized
}

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "webp"]

// EXIF 1…8 → CGImagePropertyOrientation (совпадает с CIImage.Orientation исходами)
let CIImageOrientationTable: [UInt32: CGImagePropertyOrientation] = [
    1: .up, 2: .upMirrored, 3: .down, 4: .downMirrored,
    5: .leftMirrored, 6: .right, 7: .rightMirrored, 8: .left,
]

func looksLikeImagePath(_ path: String) -> Bool {
    imageExtensions.contains(path.lowercased().split(separator: ".").last.map(String.init) ?? "")
}

func size(of image: CGImage) -> CGSize {
    CGSize(width: image.width, height: image.height)
}

func fmt(_ rect: NormalizedRect, size: CGSize) -> String {
    let r = Overlay.rectInPixels(rect, size: size)
    return String(format: "[x=%.0f y=%.0f w=%.0f h=%.0f]", r.minX, r.minY, r.width, r.height)
}

func savePNG(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// out-путь: необязательный последний аргумент после входных картинок
func outputArg(_ rest: [String], inputs: Int) -> String? {
    guard rest.count > inputs, let last = rest.last, looksLikeImagePath(last) else { return nil }
    return last
}

/// Сохраняет аннотированную картинку, если указан out-путь.
@MainActor
func finish(_ base: CGImage, markers: [Marker], outPath: String?) {
    guard let outPath else { return }
    let annotated = Overlay.annotate(base: base, markers: markers)
    savePNG(annotated, to: outPath)
    print("сохранено: \(outPath)")
}

func tagged(_ out: String, command: String) -> String {
    let ns = out as NSString
    let stem = ns.deletingPathExtension.isEmpty ? out : ns.deletingPathExtension
    let ext = ns.pathExtension.isEmpty ? "png" : ns.pathExtension
    return "\(stem)-\(command).\(ext)"
}

@MainActor
func run(_ args: [String]) async throws {
    if args.isEmpty { printUsage(); return }

    if args[0] == "--demo" {
        let kind = args.count > 1 ? args[1] : "qr"
        let image: CGImage
        switch kind {
        case "qr": image = ImageFactory.drawQRCode("https://developer.apple.com/vision")
        case "text": image = ImageFactory.drawText("HELLO VISION 2026")
        case "table": image = ImageFactory.drawTable()
        case "face": image = ImageFactory.drawFace()
        case "person": image = ImageFactory.drawPerson()
        default:
            printUsage(); return
        }
        let path = "/tmp/visionlab-demo.png"
        savePNG(image, to: path)
        print("сгенерировано: \(path)")
        return
    }

    guard let command = args.first else { printUsage(); return }
    let rest = Array(args.dropFirst())

    func imageArg() -> CGImage {
        guard let path = rest.first else {
            printUsage()
            fail("нужен путь к картинке")
        }
        return loadImage(path)
    }

    switch command {
    case "text":
        let image = imageArg()
        let observations = try await recognizeText(in: image)
        guard !observations.isEmpty else { print("текст не найден"); return }
        var markers: [Marker] = []
        for (i, obs) in observations.enumerated() {
            guard let candidate = obs.topCandidates(1).first else { continue }
            print("\(String(format: "%.2f", candidate.confidence))  \(candidate.string)")
            markers.append(Marker(color: Overlay.color(i), kind: .box(rect: obs.boundingBox, text: candidate.string)))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "docs":
        let image = imageArg()
        guard #available(macOS 26.0, *) else { fail("docs доступно с macOS 26 / iOS 26") }
        let observations = try await recognizeDocuments(in: image)
        guard let document = observations.first?.document else {
            print("документ не найден"); return
        }
        let text = document.text
        print("полный текст (\(text.lines.count) строк):")
        var markers: [Marker] = []
        for (i, line) in text.lines.enumerated() {
            print("  \(line.transcript)")
            markers.append(Marker(color: Overlay.color(i), kind: .box(rect: line.boundingBox, text: line.transcript)))
        }
        for (i, paragraph) in document.paragraphs.enumerated() {
            print("параграф\(i): \(paragraph.transcript)")
        }
        for (i, table) in document.tables.enumerated() {
            print("таблица\(i) \(table.rows.count)x\(table.rows.first?.count ?? 0):")
            markers.append(Marker(color: Overlay.color(i + 3), kind: .polygon(points: Overlay.points(in: table.boundingRegion), text: "table\(i)")))
        }
        for (i, barcode) in document.barcodes.enumerated() {
            print("barcode\(i): \(barcode.payloadString ?? "—")")
            markers.append(Marker(color: Overlay.color(i), kind: .polygon(points: Overlay.points(in: barcode.boundingRegion), text: "qr")))
        }
        for match in text.detectedData {
            print("данные: \(match.match)")
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "barcodes":
        let image = imageArg()
        let observations = try await detectBarcodes(in: image)
        guard !observations.isEmpty else { print("баркоды не найдены"); return }
        var markers: [Marker] = []
        for (i, obs) in observations.enumerated() {
            let payload = obs.payloadString ?? "—"
            print("\(obs.symbology)  \(payload)")
            markers.append(Marker(color: Overlay.color(i), kind: .polygon(points: [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft], text: payload)))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "faces":
        let image = imageArg()
        let faces = try await detectFaces(in: image)
        guard !faces.isEmpty else { print("лица не найдены"); return }
        let quality = try await detectFaceCaptureQuality(in: image, using: faces)
        var markers: [Marker] = []
        for (i, face) in faces.enumerated() {
            let q: Double? = quality.count == faces.count ? Double(quality[i].captureQuality?.score ?? 0) : nil
            let label = String(format: "q=%.2f roll=%.0f° yaw=%.0f°", q ?? -1, face.roll.converted(to: .degrees).value, face.yaw.converted(to: .degrees).value)
            print("face\(i) \(fmt(face.boundingBox, size: size(of: image))) quality=\(q.map { String(format: "%.2f", $0) } ?? "—")")
            markers.append(Marker(color: Overlay.color(i), kind: .box(rect: face.boundingBox, text: label)))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "landmarks":
        let image = imageArg()
        let faces = try await detectFaces(in: image)
        let withLandmarks = try await detectFaceLandmarks(in: image, using: faces)
        guard !withLandmarks.isEmpty else { print("ландмарки не найдены"); return }
        var markers: [Marker] = []
        for (i, face) in withLandmarks.enumerated() {
            guard let landmarks = face.landmarks else { continue }
            let regions: [(String, FaceObservation.Landmarks2D.Region)] = [
                ("faceContour", landmarks.faceContour), ("leftEye", landmarks.leftEye),
                ("rightEye", landmarks.rightEye), ("nose", landmarks.nose), ("outerLips", landmarks.outerLips)]
            let found = regions.filter { !$0.1.points.isEmpty }
            print("face\(i): \(landmarks.allPoints.points.count) точек; регионы: \(found.map(\.0).joined(separator: ", "))")
            for (j, (_, region)) in found.enumerated() {
                // points — в системе лица; переводим в систему картинки
                let imagePoints = region.pointsInImageCoordinates(CGSize(width: image.width, height: image.height), origin: .upperLeft)
                markers.append(Marker(color: Overlay.color(i + j), kind: .pointsCG(imagePoints)))
                _ = j
            }
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "aesthetics":
        guard #available(macOS 15.0, *) else { fail("aesthetics доступно с macOS 15 / iOS 18") }
        let image = imageArg()
        let score = try await aestheticsScore(in: image)
        print(String(format: "overall: %.3f", score.overallScore))
        print("isUtility: \(score.isUtility)")

    case "smudge":
        guard #available(macOS 26.0, *) else { fail("smudge доступно с macOS 26 / iOS 26") }
        let image = imageArg()
        let confidence = try await lensSmudgeConfidence(in: image)
        print(String(format: "smudge confidence: %.3f (<0.9 — хорошо)", confidence))

    case "salience":
        guard #available(macOS 15.0, *) else { fail("нужен macOS 15 / iOS 18") }
        let image = imageArg()
        let observation = try await objectnessSaliency(in: image)
        guard let rect = observation.salientObjects.first else {
            print("заметный объект не найден"); return
        }
        print("\(fmt(rect.boundingBox, size: size(of: image)))")
        finish(image, markers: [Marker(color: Overlay.color(4), kind: .box(rect: rect.boundingBox, text: "salient"))], outPath: outputArg(rest, inputs: 1))

    case "classify":
        let image = imageArg()
        let observations = try await classifyImage(in: image)
        guard !observations.isEmpty else { print("меток нет"); return }
        for obs in observations.prefix(10) {
            print(String(format: "%.3f  %@", obs.confidence, obs.identifier))
        }

    case "animals":
        let image = imageArg()
        let observations = try await recognizeAnimals(in: image)
        guard !observations.isEmpty else { print("животные не найдены"); return }
        var markers: [Marker] = []
        for (i, obs) in observations.enumerated() {
            let labels = obs.labels.map(\.identifier).joined(separator: "/")
            print("\(fmt(obs.boundingBox, size: size(of: image))) conf=\(String(format: "%.2f", obs.confidence)) \(labels)")
            markers.append(Marker(color: Overlay.color(i), kind: .box(rect: obs.boundingBox, text: labels)))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "humans":
        let image = imageArg()
        let observations = try await detectHumanRectangles(in: image)
        guard !observations.isEmpty else { print("люди не найдены"); return }
        var markers: [Marker] = []
        for (i, obs) in observations.enumerated() {
            print("\(fmt(obs.boundingBox, size: size(of: image)))")
            markers.append(Marker(color: Overlay.color(i), kind: .box(rect: obs.boundingBox, text: "human")))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "contours":
        let image = imageArg()
        let observation = try await detectContours(in: image)
        print("топ-уровень контуров: \(observation.topLevelContours.count)")
        var markers: [Marker] = []
        for (i, c) in observation.topLevelContours.prefix(20).enumerated() {
            print(String(format: "  #%d points=%d area=%.0f", i, c.pointCount, c.calculateArea() * Double(image.width * image.height)))
            markers.append(Marker(color: Overlay.color(i), kind: .polygon(points: Overlay.points(in: c), text: nil)))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "rects":
        let image = imageArg()
        var request = DetectRectanglesRequest()
        request.minimumSize = 0.05
        let observations = try await request.perform(on: image)
        guard !observations.isEmpty else { print("прямоугольники не найдены"); return }
        var markers: [Marker] = []
        for (i, obs) in observations.enumerated() {
            print("rect\(i) \(fmt(obs.boundingBox, size: size(of: image))) conf=\(String(format: "%.2f", obs.confidence))")
            markers.append(Marker(color: Overlay.color(i), kind: .polygon(points: [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft], text: nil)))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "horizon":
        let image = imageArg()
        let observation = try await detectHorizon(in: image)
        guard let angle = observation?.angle else {
            print("горизонт не найден"); return
        }
        let deg = angle.converted(to: .degrees).value
        print(String(format: "угол: %.1f°", deg))
        finish(image, markers: [Marker(color: Overlay.color(3), kind: .horizon(angleDeg: deg))], outPath: outputArg(rest, inputs: 1))

    case "segment":
        guard #available(macOS 15.0, *) else { fail("нужен macOS 15 / iOS 18") }
        guard let path = rest.first else { printUsage(); fail("нужен путь") }
        let image = loadImage(path)
        let observation = try await segmentPerson(in: image)
        guard let observation else { print("маска не сгенерирована"); return }
        let mask = try observation.allInstancesMask.cgImage
        // накладываем цветную маску поверх исходника
        let ciInput = CIImage(cgImage: image)
        var ciMask = CIImage(cgImage: mask)
        ciMask = ciMask.transformed(by: CGAffineTransform(
            scaleX: ciInput.extent.width / CGFloat(mask.width),
            y: ciInput.extent.height / CGFloat(mask.height)))
        let tint = CIImage(color: CIColor(red: 0.0, green: 0.5, blue: 1.0)).cropped(to: ciInput.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = ciInput
        blend.backgroundImage = tint
        blend.maskImage = ciMask
        guard let output = blend.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else {
            fail("blend failed")
        }
        let outPath = rest.count > 1 ? rest[1] : "/tmp/visionlab-overlay.png"
        savePNG(cg, to: outPath)
        print("сохранено: \(outPath)")

    case "heat":
        guard #available(macOS 15.0, *) else { fail("нужен macOS 15 / iOS 18") }
        let image = imageArg()
        let heat = try await attentionHeatMap(in: image)
        let heatCG = try heat.cgImage
        if let raw = rest.dropFirst().first(where: { $0.hasPrefix("--raw=") }) {
            savePNG(heatCG, to: String(raw.dropFirst(6)))
            print("heatmap сохранена")
            return
        }
        let ciInput = CIImage(cgImage: image)
        var ciHeat = CIImage(cgImage: heatCG)
        ciHeat = ciHeat.transformed(by: CGAffineTransform(
            scaleX: ciInput.extent.width / CGFloat(heatCG.width),
            y: ciInput.extent.height / CGFloat(heatCG.height)))
        // heatmap серо-тусклая: нормализуем по максимуму и растягиваем контраст,
        // чтобы подкрасились только действительно «горячие» зоны
        let maxFilter = CIFilter(name: "CIAreaMaximum", parameters: [kCIInputImageKey: ciHeat.clampedToExtent()])!
        let onePixel = CIContext().createCGImage(maxFilter.outputImage!, from: CGRect(x: 0, y: 0, width: 1, height: 1))
        if let onePixel,
           let dataProvider = onePixel.dataProvider,
           let bytes = CFDataGetBytePtr(dataProvider.data) {
            let maxR = Int(bytes[0]) // 1×1 пиксель; R-канал = максимум heatmap
            if maxR > 0 {
                let scale = CGFloat(255) / CGFloat(maxR)
                let matrix = CIFilter(name: "CIColorMatrix", parameters: [
                    kCIInputImageKey: ciHeat,
                    "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                ])!
                ciHeat = matrix.outputImage ?? ciHeat
                let gammaFilter = CIFilter.gammaAdjust()
                gammaFilter.inputImage = ciHeat
                gammaFilter.power = 0.5
                ciHeat = gammaFilter.outputImage ?? ciHeat
            }
        }
        // подкрашиваем горячие зоны оранжевым
        let tint = CIImage(color: CIColor(red: 1.0, green: 0.45, blue: 0.1)).cropped(to: ciInput.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = ciInput
        blend.backgroundImage = tint
        // blendWithMask: белое = inputImage; hot должен показывать tint → инвертируем
        blend.maskImage = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: ciHeat])!.outputImage!
        guard let output = blend.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { fail("blend failed") }
        let heatPath = rest.count > 1 && looksLikeImagePath(rest.last!) ? rest.last! : "/tmp/visionlab-heat.png"
        savePNG(cg, to: heatPath)
        print("сохранено: \(heatPath)")

    case "matte":
        guard #available(macOS 15.0, *) else { fail("нужен macOS 15 / iOS 18") }
        guard let path = rest.first else { printUsage(); fail("нужен путь") }
        let image = loadImage(path)
        let matte = try await personMatte(in: image)
        let matteCG = try matte.cgImage
        let ciInput = CIImage(cgImage: image)
        var ciMask = CIImage(cgImage: matteCG)
        ciMask = ciMask.transformed(by: CGAffineTransform(
            scaleX: ciInput.extent.width / CGFloat(matteCG.width),
            y: ciInput.extent.height / CGFloat(matteCG.height)))
        let tint = CIImage(color: CIColor(red: 0.2, green: 1.0, blue: 0.4)).cropped(to: ciInput.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = ciInput
        blend.backgroundImage = tint
        // у GeneratePersonSegmentation маска инвертированная (белый = фон, человек тёмный) —
        // инвертируем: подсветится человек, останется фото
        blend.maskImage = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: ciMask])!.outputImage!
        guard let output = blend.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { fail("blend failed") }
        let mattePath = rest.count > 1 ? rest[1] : "/tmp/visionlab-matte.png"
        savePNG(cg, to: mattePath)
        print("сохранено: \(mattePath)")

    case "textrects":
        let image = imageArg()
        let observations = try await DetectTextRectanglesRequest().perform(on: image)
        guard !observations.isEmpty else { print("текстовые регионы не найдены"); return }
        var markers: [Marker] = []
        for (i, obs) in observations.enumerated() {
            print("text\(i) \(fmt(obs.boundingBox, size: size(of: image))) conf=\(String(format: "%.2f", obs.confidence))")
            markers.append(Marker(color: Overlay.color(i), kind: .box(rect: obs.boundingBox, text: "text")))
        }
        finish(image, markers: markers, outPath: outputArg(rest, inputs: 1))

    case "docseg":
        let image = imageArg()
        guard let observation = try await DetectDocumentSegmentationRequest().perform(on: image) else {
            print("документный регион не найден"); return
        }
        print(fmt(observation.boundingBox, size: size(of: image)))
        finish(image, markers: [Marker(color: Overlay.color(2), kind: .box(rect: observation.boundingBox, text: "document"))], outPath: outputArg(rest, inputs: 1))

    case "register":
        guard rest.count >= 2 else { printUsage(); fail("нужны два изображения") }
        guard #available(macOS 15.0, *) else { fail("нужен macOS 15 / iOS 18") }
        let src = loadImage(rest[0])
        let tgt = loadImage(rest[1])
        let homographic = rest.contains("-H")
        if homographic {
            let obs = try await registerHomographic(source: src, target: tgt)
            let m = obs.warpTransform
            let c = m.columns
            print("гомография:")
            print(String(format: "  [%.4f %.4f %.4f]", c.0.x, c.0.y, c.0.z))
            print(String(format: "  [%.4f %.4f %.4f]", c.1.x, c.1.y, c.1.z))
            print(String(format: "  [%.4f %.4f %.4f]", c.2.x, c.2.y, c.2.z))
            print(String(format: "уверенность: %.2f", obs.confidence))
        } else {
            let obs = try await registerTranslational(source: src, target: tgt)
            let t = obs.alignmentTransform
            print(String(format: "сдвиг: dx=%.1f px dy=%.1f px (уверенность %.2f)", t.tx, t.ty, obs.confidence))
        }

    case "featureprint":
        guard #available(macOS 15.0, *) else { fail("нужен macOS 15 / iOS 18") }
        guard rest.count >= 2 else { printUsage(); fail("нужны два изображения") }
        let a = try await featurePrint(in: loadImage(rest[0]))
        let b = try await featurePrint(in: loadImage(rest[1]))
        let distance = try featurePrintDistance(a, b)
        print(String(format: "distance: %.4f (<0.5 — почти одинаковые, >10 — разные)", distance))

    case "track":
        guard rest.count >= 2 else { printUsage(); fail("нужны два кадра") }
        let frame1 = loadImage(rest[0])
        let rects = try await detectRectangles(in: frame1).filter { $0.confidence > 0.5 }
        guard let initial: RectangleObservation = rects.first else { print("объект на кадре 1 не найден"); return }
        let frame2 = loadImage(rest[1])
        let observation = try await trackObject(initial: initial, next: frame2)
        guard let observation else { print("объект не отслежен на кадре 2"); return }
        print("\(fmt(observation.boundingBox, size: size(of: frame2)))")
        finish(frame2, markers: [Marker(color: Overlay.color(1), kind: .box(rect: observation.boundingBox, text: "tracked"))], outPath: outputArg(rest, inputs: 2))

    case "everything":
        let inputPath = rest.first
        let out = outputArg(rest, inputs: 1)
        for command in ["text", "barcodes", "faces", "salience", "classify", "animals", "humans", "contours", "rects", "horizon"] {
            print("== \(command) ==")
            let base = [command] + (inputPath.map { [$0] } ?? [])
            if let out {
                try await run(base + [tagged(out, command: command)])
            } else {
                try await run(base)
            }
        }

    default:
        printUsage()
        fail("неизвестная команда: \(command)")
    }
}

do {
    try await run(CommandLine.arguments.dropFirst().map { $0 })
} catch {
    fail("\(error)")
}
