# AFM Web API — OCR-ручки: полный справочник

Источник: исходник `Sources/AFMServer/Controllers/VisionAPIController.swift` (main, 973 строки) + живые прогоны на `http://100.64.89.91:9999` (v1.0.0, macOS 26, `foundation`). Дата: 2026-10-08.

---

## 1. Ручки, относящиеся к OCR (полный список)

| # | Ручка | Что делает |
|---|---|---|
| 1 | **`POST /v1/vision/ocr`** | основная: OCR текст/таблицы/баркоды/классификация/saliency/debug по 1+ входам |
| 2 | **`OPTIONS /v1/vision/ocr`** | CORS-preflight: `200`, `Access-Control-Allow-Origin: *`, методы `POST, OPTIONS`, заголовки `Content-Type, Authorization` |
| 3 | **`POST /v1/chat/completions`** (с tool `apple_vision_ocr`) | авто-OCR: текст картинки инъецируется в промпт Foundation-модели |
| 4 | `POST /v1/ocr` | объявлен в `/openapi.json`, на сервере **404** — dead path, игнорировать |
| 5 | `CLI afm vision` | тот же Vision-сервис, но вне HTTP — не входит в web-периметр |

Только #1-#3. Всё ниже — про `/v1/vision/ocr`, кроме §7 (chat).

---

## 2. Входы (6 форматов, можно смешивать; `documents[]` = по одному на вход)

| Формат | JSON — как выглядит |
|---|---|
| **file-path** | `{"file":"/var/…/scan.pdf"}` — путь **на машине сервера**, не клиента. Для headless-сервера бесполезен извне (→404) |
| **base64** | `{"data":"<b64>","filename":"scan.png","media_type":"image/png"}` |
| **data-URL** | `{"data":"data:application/pdf;base64,JVBERi…"}` — media_type внутри URL |
| **image_url** | `{"image_url":{"url":"data:image/png;base64,…"}}` — OpenAI-стиль |
| **messages-parts** | `{"messages":[{"role":"user","content":[{"type":"text","text":"Read"},{"type":"image_url","image_url":{"url":"data:…"}}]}]}` |
| **multipart** | `-F "file=@a.jpg"` + опции как form-поля (строки: `"true"`, `"["ru-RU"]`-в JSON для массивов или plain) |

- Скачанные в temp копии (base64/dataURL) сервер удаляет сам (`defer cleanup`).
- В multipart берётся **только** поле `file` — вторые (`file2`, `image`) игнорируются (проверено: documents=1).

---

## 3. Аргументы (полная схема `VisionOCRRequest`)

### Входовые (см. §2)
`file` · `data` · `filename` · `media_type` · `image_url` · `messages`

### Режим и переключатели

| Аргумент | Тип | Дефолт | Что делает |
|---|---|---|---|
| `mode` | string | — | `text` \| `table` \| `barcode` \| `classify` \| `saliency` \| `auto` \| `debug` |
| `table` | bool | false | легаси-флаг → если нет `mode`, включает режим `table` |
| `debug` | bool | false | легаси-флаг → **приоритетнее `mode`**, включает режим `debug` |
| `response_format` | string | `"json"` | только в text/table: `"json"` (полный объект) или **`"text"` → `Content-Type: text/plain`,-body = `combined_text`** |
| `auto_crop` | bool | false | препроцесс: авто-обрезка документа (временный PNG, авто-очистка). Если вход >25MB — 413 |

### Распознавание

| Аргумент | Тип | Дефолт | Что делает |
|---|---|---|---|
| `recognition_level` | string | accuse (fast\|accurate) | точность Vision OCR |
| `uses_language_correction` | bool | **true** | языковая коррекция Vision |
| `languages` | [string] | `[]` | предпочитаемые BCP-47 теги, напр. `["ru-RU"]`; мусорный тег не ломает запрос |
| `max_pages` | int | **50** | лимит страниц PDF/мультифрейма; `0` → 422 «exceeds the limit of 0» |

### Под-режимы

| Аргумент | Относится к | Тип | Дефолт | Что делает |
|---|---|---|---|---|
| `max_labels` | `classify` | int | — | сколько меток вернуть |
| `saliency_type` | `saliency` | string | `attention` | `attention` (тепло-зоны внимания) \| `objectness` (салиентные объекты) |
| `include_heat_map` | `saliency` | bool | — | включить тепловую карту |

**Приоритет режима** (из кода): `debug: true` > `mode` > `table: true` > `text`.

---

## 4. Ответы по режимам (все — `object:"vision.ocr"`)

### `text` / `table` (macOS 26: `recognizeDocuments`)
```json
{
  "object":"vision.ocr","mode":"text",
  "documents":[{
    "source_type":"upload","file":"…","page_count":N,
    "text":"…","full_text":"…",
    "pages":[{"page_number":1,"width":…,"height":…,"text":"…","text_blocks":[],"tables":[]}],
    "text_blocks":[{"text":"…","bounding_box":{"x":0.1,"y":0.8,"width":0.2,"height":0.05},"confidence":…}],
    "tables":[{"headers":[],"rows":[],"row_objects":[],"csv":"…","bounding_box":…}]
  }],
  "combined_text":"…",           // все входы через "\n\n"
  "document_hints":["document","invoice","multi_page","table_like",…]
}
```
- `text_blocks` — плоские по документу, `pages[]` — с по-страничными; bbox нормализованный 0…1 (у pages | height=4080 в живом тесте).
- `table` mode: та же схема, таблицы распарсены в `tables[]` (CSV включён).
- `response_format:"text"` → просто текст.

### `barcode` (только изображения, PDF → 400)
```json
{"object":"vision.ocr","mode":"barcode","results":[
  {"confidence":1.0,"type":"QR","payload":"HELLO-AFM-OCR-2026","bounding_box":{"x":…,"y":…,"width":…,"height":…}}]}
```
- Нет баркода → `results: []` (не ошибка).
- Проверено: QR-payload читается побайтно точно.

### `classify`
```json
{"object":"vision.ocr","mode":"classify",
 "labels":[{"label":"structure","confidence":0.743},{"label":"wood_processed","confidence":0.739},{"label":"people","confidence":0.631}],
 "salient_regions":[{"x":0.108,"y":0.058,"width":0.716,"height":0.876}]}
```

### `saliency`
```json
{"object":"vision.ocr","mode":"saliency","regions":[
  {"type":"attention","bounding_box":{…}},     // saliency_type=attention (дефолт)
  {"type":"objectness","bounding_box":{…}}]}   // saliency_type=objectness
```

### `auto` (barcode + classify + text одним запросом)
```json
{"object":"vision.ocr","mode":"auto","modes_run":["text","barcode","classify"],
 "barcodes":[…],"labels":[…],"text":…}
```
- barcode/classify гоняются только по изображениям (PDF отфильтровывается), text — по всем входам (PDF ок).
- «нет текста» на конкретном входе не валид весь запрос — пустой OCR второй под-режимов продолжают.

### `debug` (только macOS 26)
```json
{"object":"vision.ocr","mode":"debug","debug_output":"<сырой вывод Vision, входы через \n\n>"}
```

---

## 5. Лимиты и форматы

| Лимит | Значение | Проявление |
|---|---|---|
| HTTP-тело | collect **30 MB** (код), docs говорят 25 MB на файл | >30MB → по-хорошему 413; **наблюдается crash сервера на 36MB** (дважды воспроизведено — bug) |
| Размер файла | **25 MB** (`defaultMaxFileBytes`) — гейтится в `auto_crop`-пробе | 413 fileTooLarge |
| Страниц PDF | **50** (`defaultMaxPages`) | 422 превышение |
| Изображение | **4096 px** сторона (docs) | 422 imageDimensionsExceeded |
| Форматы — карта кода | `png, jpg, heic, pdf` (по media_type) | |
| Форматы — реально принимает (ошибка 400 перечисляет) | `BMP, GIF, HEIC, JPEG, JPG, PDF, PNG, TIF, TIFF, WEBP` | шире, чем docs (png/jpg/jpeg/heic/pdf) |

multipart `barcode`/`classify` на PDF → 400 «Unsupported file format» (задокументировано: image-only).

---

## 6. Ошибки (наблюдение + код)

| Статус | Когда | Тело |
|---|---|---|
| 400 | нет входа | `{"error":{"type":"invalid_request_error","message":"No OCR input was provided"}}` |
| 400 | формат не поддержан | `…Unsupported file format. Supported formats: …` |
| 404 | file-path не найден | `…The specified file was not found…` |
| 413 | >25MB (по замыслу) | fileTooLarge |
| 422 | нет текста / страниц слишком много / картинка слишком большая / нет таблиц / segmentation fail | `…No text was found in the image…` и др. |
| 501 | `debug` (и **неизвестное значение `mode` тоже попадает сюда** — особенность кода) на macOS <26 | modeRequiresMacOS26 |
| 503 | Vision-сервис недоступен | type `vision_unavailable` |
| **500** | **битый base64 → должен быть 400** (bug): `{"error":true,"reason":"Something went wrong."}` | |
| 404/405 | GET вместо POST (на live-ноут-сервере 404) | |

Ошибка-конверт: обычные — `{"error":{"message","type"}}`; часть путей nightly — `{"error":true,"reason":"…"}`.

---

## 7. Chat-ручка с OCR: `POST /v1/chat/completions`

Условия включения авто-OCR (все три):
1. в `messages[].content[]` есть image-часть (`image_url` с data-URL);
2. в `tools` есть встроенный tool с именем **`apple_vision_ocr`** (зарегистрирован сервером);
3. `tool_choice` отсутствует, либо `auto` / `required` / явно `apple_vision_ocr`.

Что происходит: Vision OCR гоняется до вызова модели, текст подставляется в контент с префиксом
`[Apple Vision OCR image 1]\n<распознанный текст>`, и Foundation отвечает осмысленно (не сырым текстом).
Проверено на `model:"foundation"`: отвечает `-инъекция` вместо чистого OCR.

Параметры OCR на этом пути **не настраиваются** (фиксированные дефолты Vision).

Без тулов Foundation и так мультимодальный — сам смотрит картинку и отвечает по смыслу.

---

## 8. Прочее

- Заголовки ответов: `X-Request-ID`, `OpenAI-Request-ID` (req_…); большинство ответов `application/json; charset=utf-8`.
- CORS: только `OPTIONS`-preflight (origin `*`); на самих POST-ответах ACAO есть в text/table-ветке.
- Баги найденные: (1) битый base64 → 500 (должен 400); (2) >25-30MB телом крешит процесс afm (limiter не срабатывает — headless-beast дважды падал); (3) `/v1/ocr` в openapi — 404; (4) multipart multi-file игнорирует не-first поля.

## 9. curl-минимум для каждого режима

```bash
B=http://127.0.0.1:9999
# text (дефолт) — multipart
curl -s -X POST $B/v1/vision/ocr -F file=@a.jpg
# plain text вместо JSON
curl -s -X POST $B/v1/vision/ocr -F file=@a.jpg -F response_format=text
# table + параметры
curl -s -X POST $B/v1/vision/ocr -F file=@a.pdf -F table=true -F recognition_level=accurate -F languages='["ru-RU"]' -F max_pages=10
# barcode
curl -s -X POST $B/v1/vision/ocr -F file=@qr.png -F mode=barcode
# classify
curl -s -X POST $B/v1/vision/ocr -F file=@a.jpg -F mode=classify -F max_labels=5
# saliency attention / objectness
curl -s -X POST $B/v1/vision/ocr -F file=@a.jpg -F mode=saliency -F saliency_type=objectness -F include_heat_map=true
# auto (всё сразу)
curl -s -X POST $B/v1/vision/ocr -F file=@a.jpg -F mode=auto
# debug (raw Vision)
curl -s -X POST $B/v1/vision/ocr -F file=@a.jpg -F mode=debug
# auto_crop
curl -s -X POST $B/v1/vision/ocr -F file=@photo.jpg -F auto_crop=true
# base64 / dataURL / image_url / messages
curl -s -X POST $B/v1/vision/ocr -H 'Content-Type: application/json' \
  -d '{"image_url":{"url":"data:image/png;base64,'$(base64 -i a.png)'"}}'
# chat «умный OCR»
curl -s -X POST $B/v1/chat/completions -H 'Content-Type: application/json' -d '{
 "model":"foundation",
 "messages":[{"role":"user","content":[{"type":"text","text":"Опиши текст скриншота"},
   {"type":"image_url","image_url":{"url":"data:image/jpeg;base64,…"}}]}],
 "tools":[{"type":"function","function":{"name":"apple_vision_ocr","description":"built-in","parameters":{"type":"object"}}}]}'
```
