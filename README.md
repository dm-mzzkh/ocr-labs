# VisionLab — Apple Vision OCR: web API + нативный Swift

Две проекции одной темы — **OCR на Apple Vision**:

1. **Web API (afm server)** — OCR через HTTP: ссылка/эндпойнт `POST /v1/vision/ocr`, 6 форматов входа, 7 режимов, curl-проверка всего + найденные баги.
2. **Нативный Swift** — каталог живых примеров всего нового Vision API (iOS 18+/macOS 15+, новинки 26/27 отмечены) с самопроверками.

```bash
sh check_all_ocr.sh   # Прогон ВСЕГО OCR web API сервера: PASS/FAIL по каждому кейсу (дефолт http://127.0.0.1:9999)
swift run SelfCheck   # Нативно: 23 проверки Vision API, PASS/SKIP/FAIL
```

## Что где есть (карта файлов)

| Файл/папка | Что это | Зачем |
|---|---|---|
| `check_all_ocr.sh` | сам-контейнерный curl-пробник OCR web API | проверяет все ручки/режимы/опции/ошибки сервера afm (text, table, barcode, classify, saliency×2, auto, debug + 400/404/413/422); сам генерирует ассеты (QR, PDF, пустая/большая картинка) |
| `OCR-API-REFERENCE.md` | полный справочник web-ручки `/v1/vision/ocr` | все аргументы, схемы ответов по режимам, лимиты, коды ошибок, curl-минимум |
| `OCR-WEB-MATRIX.md` | таблица 27 Vision-возможностей | что покрыто web-ручкой (✅8 / ⚠️2 / ❌18), и как проверено |
| `Sources/CheckerCLI` | CLI для своих картинок | `text`, `docs`, `barcodes`, `faces`, `contours`, … (см. ниже) |
| `Sources/SelfCheck` | автотесты Vision API | `swift run SelfCheck` → PASS/SKIP/FAIL по каждой возможности |
| `Sources/VisionLab` | библиотека примеров | `Examples.swift` (request'ы), `ImageFactory.swift` (синтетика), `Overlay.swift` (аннотации) |
| `web/index.html` | статический сайт (без сборки) | кидаете картинку → afm OCR → области блюрятся, текст рисуется поверх → «Скачать PNG» |
| `local.afm.ocr.plist` | LaunchAgent для afm-сервера | автостарт при логине, перезапуск при падении (`afm --prewarm n -H 0.0.0.0 -p 9999`) |
| `Package.swift` | Swift Package (VisionLab + SelfCheck + CheckerCLI) | macOS 15+/iOS 18+ |

## OCR через web API: три ручки afm

1. **`POST /v1/vision/ocr`** — основной OCR: режимы `text` (дефолт) / `table` / `barcode` / `classify` / `saliency` (`saliency_type=attention|objectness`) / `auto` (все три сразу, `modes_run`) / `debug` (raw Vision, macOS 26); опции `recognition_level`, `uses_language_correction` (дефолт true), `languages[]` (BCP-47), `max_pages` (дефолт 50), `response_format=json|text`, `auto_crop`; входы: `file` (путь на сервере), `data` (base64/data-URL), `image_url`, `messages[]` (OpenAI-стиль), multipart `file=@`.
2. **`OPTIONS /v1/vision/ocr`** — CORS-preflight (200, origin `*`).
3. **`POST /v1/chat/completions`** + tool **`apple_vision_ocr`** — «умный OCR»: текст инъецируется в промпт Foundation-модели (`[Apple Vision OCR image 1] …`), модель отвечает по смыслу; без тулов Foundation и так мультимодальный.

Лимиты: 25MB файл / 50 страниц / 4096px; форматы BMP,GIF,HEIC,JPEG,JPG,PDF,PNG,TIF,TIFF,WEBP. Полное описание всех аргументов и ответов — [`OCR-API-REFERENCE.md`](OCR-API-REFERENCE.md).

### Найденные баги (для issues вверх по afm)

1. Битый base64 → **500** вместо задокументированного 400.
2. Upload >25–30MB → **крешит процесс afm целиком** (лимитер не возвращает 413; воспроизведено дважды: 36MB `PNG → сервер уходит из сети`).
3. `/v1/ocr` объявлен в `/openapi.json` → фактически **404** (dead path).
4. multipart: берётся только поле `file` — вторые (`file2`, `image`) игнорируются.

## afm OCR: web-оверлей + сервис

`web/index.html` — кидаете картинку, она уходит в OCR, найденные области блюрятся, поверх рисуется распознанный текст белым с чёрной обводкой; результат — «Скачать PNG».

Требуется сервер `afm`. Запуск как LaunchAgent (автостарт при логине + перезапуск при падении), т.к. у Homebrew-формулы нет встроенного service-блока:

```bash
# plist уже установлен: ~/Library/LaunchAgents/local.afm.ocr.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.afm.ocr.plist  # установить
launchctl kickstart -k gui/$(id -u)/local.afm.ocr                            # перезапустить
launchctl bootout gui/$(id -u)/local.afm.ocr                                 # удалить/выключить
```

Внимание: агент слушает `0.0.0.0` (порт 9999 доступен в LAN). У afm нет авторизации — не открывайте это в недоверенные сети; для «только себе» верните `-H 127.0.0.1` в plist.

### headless-beast

На `headless` (`builder@100.64.89.91`) сервис поднят тем же plist. Запуск и проверка:

```bash
ssh headless 'launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.afm.ocr.plist'
curl http://100.64.89.91:9999/health
```

`local.afm.ocr.plist` запускает `/opt/homebrew/bin/afm --prewarm n -H 0.0.0.0 -p 9999`; `RunAtLoad` включает автозапуск при логине, `KeepAlive` перезапускает процесс после падения. OCR проверен: multipart image upload → HTTP 200, 8 blocks.

## Нативный Swift: каталог живых примеров Apple Vision

```bash
swift run SelfCheck     # PROG: выполняет каждую проверку, PASS/SKIP/FAIL
                        #   на этой машине (macOS 26.5): 23 passed, 0 failed
```

## Try it: CLI для своих картинок

```bash
swift run CheckerCLI <команда> <картинка.jpg>   # свои файлы
swift run CheckerCLI --demo qr                  # сгенерировать тест-картинку в /tmp/visionlab-demo.png
```

Команды: `text` (OCR построчно), `docs` (таблицы/параграфы/QR/email — iOS 26), `barcodes`, `faces` (ramki+quality), `landmarks`, `aesthetics`, `smudge` (iOS 26), `salience`, `classify`, `animals`, `humans`, `contours`, `rects`, `horizon`, `segment <img> [out.png]` (маска человека → PNG-оверлей), `featureprint <img1> <img2>` (сходство), `track <img1> <img2>`, `everything <img>` (паспорт: прогон всего).

Примеры:
```bash
swift run CheckerCLI text a.jpg out.png        # + аннотированный PNG: рамка каждой строки + текст
swift run CheckerCLI faces a.jpg out.png       # + рамки лиц с quality/roll/yaw
swift run CheckerCLI everything a.jpg passport # на каждую команду — свой passport-<команда>.png
```

Паттерн у всего: `let request = XRequest(); let obs = try await request.perform(on: image)` — obs (observations) содержат результат.
Входы синтетические (генерируются в `ImageFactory`) — детерминированно и без внешних файлов.

## Таблица-справочник Vision API

| Функционал | Функция (Examples.swift) | Что проверяет (SelfCheck/main.swift) | Availability |
|---|---|---|---|
| Текст (26 языков, коррекция) | `recognizeText(in:)` | найден "HELLO" на синтетич. тексте | iOS 18 / macOS 15 |
| **Документы со структурой (новое в 26)** | `recognizeDocuments(in:)` | таблица распарсилась, текст не пуст | iOS 26 / macOS 26 |
| Регионы текста | `detectTextRectangles(in:)` | ≥1 текстовый регион | iOS 18 |
| Баркоды/QR | `detectBarcodes(in:)` | payload QR-кода прочитан точно | iOS 18 |
| Сегментация документа | `detectDocumentSegmentation(in:)` | документная страница найдена | iOS 18 |
| Лица | `detectFaces(in:)` | запрос выполняется на каркасном лице | iOS 18 |
| Ландмарки лица | `detectFaceLandmarks(_:using:)` | пайплайн лицо→landmarks→quality | iOS 18 |
| Качество лица | `detectFaceCaptureQuality(_:using:)` | score 0…1 | iOS 18 |
| Маска человека (Instance mask) | `segmentPerson(in:)` | маска сгенерировалась | iOS 18 / macOS 15 |
| Foreground masks (subject lifting) | `generateForegroundMasks(in:)` | маска объекта получена | iOS 18 / macOS 15 |
| Поза тела + руки (holistic) | `detectBodyPose(in:)` | выполняется; SKIP на силуэте — нужно фото | iOS 18 / macOS 15 |
| Поза руки (21 сустав) | `detectHandPose(in:)` | ≤2 рук | iOS 18 |
| 3D-поза (относительно камеры) | `detectBodyPose3D(in:)` | выполняется | iOS 18 (A12+) |
| Поза животного | `detectAnimalPose(in:)` | ≥0 наблюдений, тип JSON не нарушен | iOS 18 |
| Эстетика фото (score −1…1) | `aestheticsScore(in:)` | score в диапазоне | iOS 18 |
| **Грязный объектив (новое в 26)** | `lensSmudgeConfidence(in:)` | чистое фото → confidence < 0.9 | iOS 26 / macOS 26 |
| Saliency (объект) | `objectnessSaliency(in:)` | salientObjects 0…1 | iOS 18 |
| Saliency (внимание) | `attentionSaliency(in:)` | heat map получена | iOS 18 |
| Классификация | `classifyImage(in:)` | confidence 0…1 у всех меток | iOS 18 |
| Люди (прямоугольники) | `detectHumanRectangles(in:)` | ≤1 зоны | iOS 18 |
| Животные | `recognizeAnimals(in:)` | на человеке — пусто (negative test) | iOS 18 |
| Feature print (эмбеддинги) | `featurePrint(in:)` + `featurePrintDistance` | одинаковые → distance ≈ 0 | iOS 18 |
| Контуры | `detectContours(in:)` | контуры квадрата не пусты | iOS 18 |
| Прямоугольники | `DetectRectanglesRequest` (в тесте) | 0…2 прямоугольника | iOS 18 |
| Горизонт | `detectHorizon(in:)` | угол в разумных пределах | iOS 18 |
| Трекинг объекта | `trackObject(initial:next:)` | код-пример (stateful, нужен видеопоток) | iOS 18 |
| Custom Core ML | `coreMLRequest(modelURL:in:)` | код-пример (нужна .mlmodel модель) | iOS 18 |

## Ещё есть в Vision (код-примеры, требуют уточнения на своём входе)

- **Tap-to-segment** (`GenerateIterativeSegmentationRequest`) — WWDC26: маска по точке/боксу/лассо/штриху, уточнение `addIncludedPoint`, модель докачивается:
```swift
let request = GenerateIterativeSegmentationRequest(seed: point)   // iOS 27
var observation = try await request.perform(on: image)
request.addIncludedPoint(newPoint)                                // уточнение маски
observation = try await request.perform(on: image)
```
  ⚠️ нет в SDK 26.5 (нужен Xcode 27 — компилируется только там), потому не в сборке.
- **Foundation Models + Vision** (iOS 27) — готовые tools для LLM и свои:
```swift
let session = LanguageModelSession(tools: [OCRTool(), BarcodeReaderTool()])
let response = try await session.respond(generating: EventInfo.self) {
    "Get the date, location, and website from this flyer"
    Attachment(image).label("flyer")
}
```
- **Видео**: stateful-запросы (`TrackObjectRequest`, `TrackOpticalFlowRequest`, `DetectTrajectoriesRequest`) идут в цепочке кадров через `VideoProcessor` / `performAll`.
- **Регистрация изображений**: `TrackHomographicImageRegistrationRequest`, `TrackTranslationalImageRegistrationRequest` — выравнивание двух кадров.

## Как добавить свой полный тест

1. Добавить синтетический вход в `ImageFactory` (или положить реальное фото рядом и загрузить).
2. Обёртка в `Examples.swift` (или прямой request в чеке).
3. Строка `await check("имя") { ... }` в `runAll()`.

## Источники
- https://developer.apple.com/documentation/vision (полный индекс — 33 request'а)
- WWDC25/272 «Read documents using the Vision framework», WWDC24/10163 «Discover Swift Enhancements in the Vision Framework», WWDC26/237 «What's new in image understanding»
- Sample apps: «Recognizing tables within a document», «Analyzing a selfie and visualizing its content», «Detecting human body poses in 3D»
