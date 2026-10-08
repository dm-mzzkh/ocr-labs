# Vision-возможности → веб-ручки AFM (maclocal-api, http://100.64.89.91:9999)

Ручка: `POST /v1/vision/ocr` (в nightly также объявлена `/v1/ocr` — фактически 404).
Параметр `mode`: `text` (дефолт) | `table` | `barcode` | `classify` | `saliency` | `auto` | `debug` (macOS 26).
`mode=saliency` + `saliency_type`: `attention` (дефолт) | `objectness`.

**Ответ на вопрос: «как OCR через API?» — да, два пути:**
1. `POST /v1/vision/ocr` — прямой OCR (6 форматов входа, 7 режимов, параметры ниже).
2. `POST /v1/chat/completions` на модели `foundation` + tool `apple_vision_ocr` — OCR-текст автоматически инъецируется в промпт (`[Apple Vision OCR image 1] …`), модель отвечает осмысленно, а не просто сырой текст.

Квест-скрипт: `sh /tmp/ocr-check/check_all_ocr.sh`. Матрица проверки — пройдена 2026-10-07:

## Результаты прогона (server v1.0.0, macOS 26)

| Кейс | Статус |
|---|---|
| multipart `file=@` | ✅ 200 (a.jpg, русский текст, 38 blocks, bounding boxes) |
| JSON `file:` (локальный путь) | ❌ **404 «The specified file was not found»** — путь сервера (`/var/folders/...`) ≠ путь клиента; на headless-сервере файлам там неоткуда взяться |
| base64 `data`+`filename`+`media_type` | ✅ 200 |
| data-URL | ✅ 200 |
| `image_url.url=data:...` | ✅ 200 |
| messages-parts (OpenAI-стиль) | ✅ 200 |
| 2 файла (file + file2/file+image) | ⚠️ документы=1 — берётся только `file` |
| table=true | ✅ 200, но tables=[] на нетабличных снимках (graceful) |
| table=true на PDF (text-rows) | ✅ 200, но tables=[] (распознаёт как text; настоящий табличный шаблон не тестирован) |
| barcode на QR (exact) | ✅ 200 payload=`HELLO-AFM-OCR-2026`, type=QR, conf=1, bbox |
| barcode на PDF | ❌ 400 «Unsupported file format» (задокументировано — barcode reject PDFs) |
| classify | ✅ labels: structure 0.74 / wood_processed 0.74 / people 0.63 + salient_regions |
| saliency attention / objectness | ✅ четы region + bounding_box у обоих типов |
| auto | ✅ modes_run=[text,barcode,classify] (barcode и classify при image-only); на QR=[barcode,classify] |
| debug | ✅ 200 |
| recognition_level fast/accurate | ✅ |
| uses_language_correction | ✅ |
| languages: en-US / ru-RU / мусорный тег | ✅ (мусорный тег не мешает) |
| max_pages=1 / max_pages=0 | ✅; `0` даёт 422 «exceeds limit of 0» |
| debug=true option | ✅ (переходит в mode=debug) |
| bogus_option | ✅ игнорируется |
| пустой запрос | ✅ 400 |
| нет файла | ✅ 404 |
| битый base64 | ❌ **500 вместо 400** (по docs/openapi должен быть 400) |
| не-картинка | ✅ 400 (принятые форматы: BMP,GIF,HEIC,JPEG,JPG,PDF,PNG,TIF,TIFF,WEBP — шире, чем docs: png/jpg/jpeg/heic/pdf) |
| без текста | ✅ 422 |
| GET /v1/vision/ocr | ✅ 405/404 (nightly 405; v0.9.19 404) |
| **POST файл 36MB** | ❌ **креш сервера целиком** — только на nightly headless (v1.0.0), воспроизведено дважды. На стабле **v0.9.19 — честный `413`** ✅ |
| chat+tool `apple_vision_ocr` (tool_choice=auto) | ✅ OCR-инъекция: `[Apple Vision OCR image 1] <OCR-текст>` — на v0.9.19 500, если OCR не дал текста (QR-вход) |
| chat без тулов (посмотрит сам) | nightly ✅ мультимодальный ответ; v0.9.19 ❌ 500 на любой image-контент |

**2 бага:** (1) битый base64 → 500 вместо 400; (2) nightly: >25MB upload крешит процесс (должен 413; в стабле v0.9.19 исправлено).

**Регресс локального v0.9.19 от 2026-10-08** (`./check_all_ocr.sh`, дефолт `127.0.0.1:9999`): все 6 форматов входа, text/table/barcode(QR exact: `HELLO-AFM-OCR-2026`, conf=1)/classify/saliency×2/auto(`modes_run=[text,barcode,classify]`)/debug, `response_format=text` → text/plain, опции, 400/404/422, 413, chat-инъекция — PASS. Нюанс: `recognition_level=fast` на мелком шрифте → 422 «No text» (accurate находит).

| Возможность | Vision API | Ваш прогон (нативно) | Web-ручка AFM |
|---|---|---|---|
| Текст (26 яз., коррекция) | `recognizeText(in:)` | HELLO найден | ✅ `mode=text` (дефолт; + chat-tool `apple_vision_ocr`) — подтверждено |
| Документы со структурой (новое в 26) | `recognizeDocuments(in:)` | таблица распарсилась | ✅ `mode=table`; на macOS 26 в основе text-ответа (pages/text_blocks/tables) — подтверждено |
| Регионы текста | `detectTextRectangles(in:)` | ≥1 текстовый регион | ⚠️ частично — только `text_blocks[].bounding_box`, отдельной ручки нет |
| Баркоды/QR | `detectBarcodes(in:)` | payload QR прочитан | ✅ `mode=barcode` |
| Сегментация документа | `detectDocumentSegmentation(in:)` | страница найдена | ⚠️ внутренняя (PDF по страницам); наружу только `mode=debug` |
| Лица | `detectFaces(in:)` | выполняется | ❌ нет |
| Ландмарки лица | `detectFaceLandmarks(_:using:)` | пайплайн работает | ❌ нет |
| Качество лица | `detectFaceCaptureQuality(_:using:)` | score 0…1 | ❌ нет |
| Маска человека | `segmentPerson(in:)` | маска сгенерировалась | ❌ нет (CLI тоже) |
| Foreground masks | `generateForegroundMasks(in:)` | маска получена | ❌ нет |
| Поза тела | `detectBodyPose(in:)` | SKIP (нужно фото) | ❌ нет |
| Поза руки (21) | `detectHandPose(in:)` | ≤2 рук | ❌ нет |
| 3D-поза | `detectBodyPose3D(in:)` | выполняется | ❌ нет |
| Поза животного | `detectAnimalPose(in:)` | ≥0 наблюдений | ❌ нет |
| Эстетика | `aestheticsScore(in:)` | score −1…1 | ❌ нет |
| Грязный объектив (новое в 26) | `lensSmudgeConfidence(in:)` | conf < 0.9 | ❌ нет |
| Saliency (объект) | `objectnessSaliency(in:)` | salientObjects 0…1 | ✅ `mode=saliency` + `saliency_type=objectness` |
| Saliency (внимание) | `attentionSaliency(in:)` | heat map | ✅ `mode=saliency` + `saliency_type=attention` |
| Классификация | `classifyImage(in:)` | conf 0…1 | ✅ `mode=classify` (+`max_labels`) |
| Люди (прямоугольники) | `detectHumanRectangles(in:)` | ≤1 зона | ❌ нет |
| Животные | `recognizeAnimals(in:)` | пусто (negative) | ❌ нет |
| Feature print | `featurePrint(in:)` + distance | distance ≈ 0 | ❌ нет (NL-embeddings это не Vision) |
| Контуры | `detectContours(in:)` | не пусты | ❌ нет |
| Прямоугольники | `DetectRectanglesRequest` | 0…2 | ❌ нет |
| Горизонт | `detectHorizon(in:)` | угол ок | ❌ нет |
| Трекинг объекта | `trackObject(initial:next:)` | stateful | ❌ нет (видео, не HTTP) |
| Custom Core ML | `coreMLRequest(modelURL:in:)` | нужна .mlmodel | ❌ нет |

Итог: веб-покрытие = 8 из 27 (`text`, `table`, `barcode`, `classify`, `saliency`×2, `auto`, debug-сырьё) + OCR-инъекция в chat (`apple_vision_ocr`). Остальные — только нативно.

Проверено живьём до падения сервера: multipart `text` (кириллица), chat-tool. Полная матрица: `check_all_ocr.sh`.
