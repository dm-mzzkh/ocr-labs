import Vision
import CoreGraphics
import CoreML

// Каталог Vision-запросов: по одной функции на каждый тип анализа.
// Все функции принимают CGImage и возвращают observation(ы).

// MARK: - Текст и документы

func recognizeText(in image: CGImage) async throws -> [RecognizedTextObservation] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    return try await request.perform(on: image)
}

@available(macOS 26.0, *)
func recognizeDocuments(in image: CGImage) async throws -> [DocumentObservation] {
    try await RecognizeDocumentsRequest().perform(on: image)
}

func detectTextRectangles(in image: CGImage) async throws -> [TextObservation] {
    try await DetectTextRectanglesRequest().perform(on: image)
}

func detectBarcodes(in image: CGImage) async throws -> [BarcodeObservation] {
    var request = DetectBarcodesRequest()
    request.symbologies = [.qr, .ean13, .code128]
    return try await request.perform(on: image)
}

func detectDocumentSegmentation(in image: CGImage) async throws -> DetectedDocumentObservation? {
    try await DetectDocumentSegmentationRequest().perform(on: image)
}

// MARK: - Лица

func detectFaces(in image: CGImage) async throws -> [FaceObservation] {
    try await DetectFaceRectanglesRequest().perform(on: image)
}

func detectFaceLandmarks(in image: CGImage, using input: [FaceObservation]? = nil) async throws -> [FaceObservation] {
    var request = DetectFaceLandmarksRequest()
    request.inputFaceObservations = input
    return try await request.perform(on: image)
}

func detectFaceCaptureQuality(in image: CGImage, using input: [FaceObservation]? = nil) async throws -> [FaceObservation] {
    var request = DetectFaceCaptureQualityRequest()
    request.inputFaceObservations = input
    return try await request.perform(on: image)
}

// MARK: - Сегментация / subject lifting

@available(macOS 15.0, *)
func segmentPerson(in image: CGImage) async throws -> InstanceMaskObservation? {
    try await GeneratePersonInstanceMaskRequest().perform(on: image)
}

@available(macOS 15.0, *)
func generateForegroundMasks(in image: CGImage) async throws -> InstanceMaskObservation? {
    try await GenerateForegroundInstanceMaskRequest().perform(on: image)
}

// MARK: - Позы

@available(macOS 15.0, *)
func detectBodyPose(in image: CGImage) async throws -> [HumanBodyPoseObservation] {
    var request = DetectHumanBodyPoseRequest()
    request.detectsHands = true // holistic: тело + руки одним запросом
    return try await request.perform(on: image)
}

@available(macOS 15.0, *)
func detectHandPose(in image: CGImage) async throws -> [HumanHandPoseObservation] {
    var request = DetectHumanHandPoseRequest()
    request.maximumHandCount = 2
    return try await request.perform(on: image)
}

/// 3D-поза: точки относительно камеры (HWAR-матрица), требует A12+.
@available(macOS 15.0, *)
func detectBodyPose3D(in image: CGImage) async throws -> [HumanBodyPose3DObservation] {
    try await DetectHumanBodyPose3DRequest().perform(on: image)
}

@available(macOS 15.0, *)
func detectAnimalPose(in image: CGImage) async throws -> [AnimalBodyPoseObservation] {
    try await DetectAnimalBodyPoseRequest().perform(on: image)
}

// MARK: - Качество изображения

@available(macOS 15.0, *)
func aestheticsScore(in image: CGImage) async throws -> ImageAestheticsScoresObservation {
    try await CalculateImageAestheticsScoresRequest().perform(on: image)
}

/// Новое в iOS 26: вероятность «грязного объектива», 0…1.
@available(macOS 26.0, *)
func lensSmudgeConfidence(in image: CGImage) async throws -> Float {
    try await DetectLensSmudgeRequest().perform(on: image).confidence
}

@available(macOS 15.0, *)
func objectnessSaliency(in image: CGImage) async throws -> SaliencyImageObservation {
    try await GenerateObjectnessBasedSaliencyImageRequest().perform(on: image)
}

@available(macOS 15.0, *)
func attentionSaliency(in image: CGImage) async throws -> SaliencyImageObservation {
    try await GenerateAttentionBasedSaliencyImageRequest().perform(on: image)
}

// MARK: - Классификация и поиск

func classifyImage(in image: CGImage) async throws -> [ClassificationObservation] {
    let request = ClassifyImageRequest()
    return try await request.perform(on: image)
}

func detectHumanRectangles(in image: CGImage) async throws -> [HumanObservation] {
    try await DetectHumanRectanglesRequest().perform(on: image)
}

func recognizeAnimals(in image: CGImage) async throws -> [RecognizedObjectObservation] {
    try await RecognizeAnimalsRequest().perform(on: image)
}

/// Feature print: эмбеддинг изображения для сравнения «похожести».
@available(macOS 15.0, *)
func featurePrint(in image: CGImage) async throws -> FeaturePrintObservation {
    try await GenerateImageFeaturePrintRequest().perform(on: image)
}

func featurePrintDistance(_ a: FeaturePrintObservation, _ b: FeaturePrintObservation) throws -> Double {
    try a.distance(to: b)
}

// MARK: - Формы и линии

func detectContours(in image: CGImage) async throws -> ContoursObservation {
    try await DetectContoursRequest().perform(on: image)
}

func detectRectangles(in image: CGImage) async throws -> [RectangleObservation] {
    var request = DetectRectanglesRequest()
    request.minimumConfidence = 0.5
    return try await request.perform(on: image)
}

func detectHorizon(in image: CGImage) async throws -> HorizonObservation? {
    try await DetectHorizonRequest().perform(on: image)
}

// MARK: - Движение и трекинг (stateful — требуют цепочки кадров)

/// Трекинг: стартовое наблюдение (bounding box + observation) → TrackObjectRequest на следующем кадре.
func trackObject(initial: any BoundingBoxProviding & VisionObservation, next frame: CGImage) async throws -> DetectedObjectObservation? {
    let request = TrackObjectRequest(detectedObject: initial)
    return try await request.perform(on: frame) // Result = DetectedObjectObservation?
}

/// Классический matte-маска человека (иная, более лёгкая модель, чем instance mask).
/// ВАЖНО: возвращаемая matte маска инвертированная — белый = фон, человек = тёмный.
@available(macOS 15.0, *)
func personMatte(in image: CGImage) async throws -> PixelBufferObservation {
    var request = GeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    return try await request.perform(on: image)
}

/// Тепловая карта внимания (attention saliency) как изображение.
@available(macOS 15.0, *)
func attentionHeatMap(in image: CGImage) async throws -> PixelBufferObservation {
    try await GenerateAttentionBasedSaliencyImageRequest().perform(on: image).heatMap
}

/// Аффинное (сдвиговое) выравнивание двух кадров.
@available(macOS 15.0, *)
func registerTranslational(source: CGImage, target: CGImage) async throws -> ImageTranslationAlignmentObservation {
    let handler = TargetedImageRequestHandler(source: source, target: target)
    return try await handler.perform(TrackTranslationalImageRegistrationRequest())
}

/// Гомографическое (поворот/перспектива) выравнивание двух кадров.
@available(macOS 15.0, *)
func registerHomographic(source: CGImage, target: CGImage) async throws -> ImageHomographicAlignmentObservation {
    let handler = TargetedImageRequestHandler(source: source, target: target)
    return try await handler.perform(TrackHomographicImageRegistrationRequest())
}

// MARK: - Custom Core ML

/// Подмена своего Core ML-модели: compile(.mlmodelc) → CoreMLRequest.
/// Пример-заглушка: механизм одинаков для любой модели.
@available(macOS 15.0, *)
func coreMLRequest(modelURL: URL, in image: CGImage) async throws -> [any VisionObservation] {
    let container = try CoreMLModelContainer(model: try MLModel(contentsOf: modelURL))
    let request = CoreMLRequest(model: container)
    return try await request.perform(on: image)
}
