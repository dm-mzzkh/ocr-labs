#!/bin/bash
# check_all_ocr.sh — проверка ВСЕГО OCR web-API сервера afm (maclocal-api).
# Сам-контейнер: генерирует свои ассеты (QR, PDF, PNG-заглушки) во временную папку.
# Сервер: BASE_URL=http://... sh check_all_ocr.sh  (по умолчанию локальный afm; headless: BASE_URL=http://100.64.89.91:9999)
set -u
BASE_URL="${BASE_URL:-http://127.0.0.1:9999}"
TMP="$(mktemp -d /tmp/ocr-check.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
B="$BASE_URL/v1/vision/ocr"

echo "== 0. Служебное (сервер: $BASE_URL) =="
curl -sS --max-time 10 "$BASE_URL/health" && echo
printf 'POST /v1/ocr (заявлен в openapi)          -> '
curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/v1/ocr" -H 'Content-Type: application/json' -d '{}'
echo ' (ожидание: 404, dead path)'

# ---- генерация ассетов ----
gen_png() { # $1=out $2=w $3=h [noisy]
python3 - "$@" <<'PY'
import zlib, struct, sys, random
out, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
noisy = len(sys.argv) > 4
def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
if noisy:
    random.seed(7)
    rows = b''.join(b'\x00' + bytes(random.randrange(256) for _ in range(w * 3)) for _ in range(h))
else:
    r = b'\x00' + bytes((255, 255, 255)) * w
    rows = r * h
open(out, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(rows, 1)) + ch(b'IEND', b''))
PY
}
gen_png "$TMP/empty.png" 200 100
gen_png "$TMP/big.png"   4000 3000 noisy

# картинка с текстом: magick, иначе — рисуем 5x7-шрифтом чистым python (без зависимостей)
if command -v magick >/dev/null 2>&1; then
  magick -size 640x200 xc:white -fill black -pointsize 36 -gravity center -annotate 0 'INVOICE HELLO '\$'12345.67' "$TMP/text.png" 2>/dev/null || true
fi
if ! command -v magick >/dev/null 2>&1 || [ ! -f "$TMP/text.png" ]; then
python3 - "$TMP/text.png" <<'PY'
import zlib, struct, sys
# 5x7 шрифт: строка r = s[r*5:(r+1)*5]
F = {g: ''.join(r) for g, r in {
 'H': ['10001','10001','11111','10001','10001','10001','10001'],
 'E': ['11111','10000','11110','10000','11110','10000','11111'],
 'L': ['10000','10000','10000','10000','10000','10000','11111'],
 'O': ['01110','10001','10001','10001','10001','10001','01110'],
 '$': ['00100','01111','10100','01110','00101','11110','00100'],
 '1': ['00110','01010','00100','00100','00100','00100','01110'],
 '2': ['01110','10001','00001','00110','01000','10000','11111'],
 '3': ['11111','00010','00100','00010','00001','10001','01110'],
 '4': ['00010','00110','01010','10010','11111','00010','00010'],
 '5': ['11111','10000','11110','00001','00001','10001','01110'],
 '6': ['00110','01000','11110','10001','10001','10001','01110'],
 '7': ['11111','00001','00010','00100','01000','01000','01000'],
 '8': ['01110','10001','10001','01110','10001','10001','01110'],
 '9': ['01110','10001','10001','01111','00001','00010','01100'],
 '.': ['00000','00000','00000','00000','00000','00000','00100'],
 '0': ['01110','10001','10011','10101','11001','10001','01110'],
 ' ': ['00000','00000','00000','00000','00000','00000','00000'],
}.items()}
msg = "HELLO $12345.67"; S=8; GAP=1
W = S*(5*len(msg)+GAP*(len(msg)-1)); H = S*7
img = [[255]*W for _ in range(H)]
for i,c in enumerate(msg):
    g = F[c]
    for r in range(7):
        row = g[r*5:(r+1)*5]
        for col in range(5):
            if row[col]=='1':
                for dy in range(S):
                    for dx in range(S):
                        img[r*S+dy][(i*(5+GAP))*S+col*S+dx]=0
raw=b''.join(b'\x00'+bytes(sum(([p,p,p] for p in line),[])) for line in img)
def ch(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',W,H,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw,3))+ch(b'IEND',b''))
PY
fi
command -v qrencode >/dev/null 2>&1 && qrencode -o "$TMP/qr.png" -s 8 'HELLO-AFM-OCR-2026'

# минимальный PDF с текстом
python3 - "$TMP/invoice.pdf" <<'PY'
import sys
content = "\n".join([
 "BT /F1 24 Tf 72 700 Td (INVOICE 2026-10-07) Tj ET",
 "BT /F1 18 Tf 72 650 Td (Total: 12345.67 USD) Tj ET",
 "BT /F1 18 Tf 72 620 Td (Table: Item Qty Price) Tj ET",
 "BT /F1 18 Tf 72 590 Td (Widget 2 9.99) Tj ET"]).encode()
out = b"%PDF-1.4\n"; off = {}
def add(n, body):
    global out
    off[n] = len(out); out += f"{n} 0 obj\n".encode() + body + b"\nendobj\n"
add(1, b"<< /Type /Catalog /Pages 2 0 R >>")
add(2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
add(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>")
add(4, b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream")
add(5, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
x = len(out)
out += b"xref\n0 6\n0000000000 65535 f \n"
for n in range(1, 6): out += f"{off[n]:010d} 00000 n \n".encode()
out += b"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n" + str(x).encode() + b"\n%%EOF"
open(sys.argv[1], 'wb').write(out)
PY

ov() { python3 -c "import json,sys
try:
  d=json.loads(sys.stdin.read(),strict=False)
  print(d.get('object'),d.get('mode'))
except: print('RAW')" 2>/dev/null; }

echo "== 1. Форматы входа (mode=text) =="
if [ -f "$TMP/text.png" ]; then
  A="$TMP/text.png"
else
  A="$TMP/qr.png"; echo "  (magick нет — text-режим тестируем на QR)"
fi
b64=$(base64 -i "$A" | tr -d '\n')
echo -n "file-path (файл на сервере) -> "; curl -s -X POST "$B" -H 'Content-Type: application/json' -d '{"file":"'"$A"'"}' | ov
echo '{"data":"'"$b64"'","filename":"x.png","media_type":"image/png"}' > "$TMP/b64.json"
echo -n "raw base64              -> "; curl -s -X POST "$B" -H 'Content-Type: application/json' --data-binary @"$TMP/b64.json" | ov
echo '{"data":"data:image/png;base64,'"$b64"'"}' > "$TMP/url.json"
echo -n "data-URL                -> "; curl -s -X POST "$B" -H 'Content-Type: application/json' --data-binary @"$TMP/url.json" | ov
echo '{"image_url":{"url":"data:image/png;base64,'"$b64"'"}}' > "$TMP/iu.json"
echo -n "image_url               -> "; curl -s -X POST "$B" -H 'Content-Type: application/json' --data-binary @"$TMP/iu.json" | ov
echo '{"messages":[{"role":"user","content":[{"type":"text","text":"Read"},{"type":"image_url","image_url":{"url":"data:image/png;base64,'"$b64"'"}}]}]}' > "$TMP/msg.json"
echo -n "messages-parts          -> "; curl -s -X POST "$B" -H 'Content-Type: application/json' --data-binary @"$TMP/msg.json" | ov
echo -n "multipart               -> "; curl -s -X POST "$B" -F "file=@$A" | ov

echo "== 2. Режимы =="  # на сервере с текстовой картинкой qr тоже ок
echo -n "table                   -> "; curl -s -X POST "$B" -F "file=@$A" -F 'table=true' | ov
echo -n "barcode (QR)            -> "; curl -s -X POST "$B" -F "file=@$TMP/qr.png" -F 'mode=barcode' | python3 -c "import json,sys
d=json.loads(sys.stdin.read(),strict=False); r=d.get('results',[])
print('payload=' + repr(r[0].get('payload')) if r else 'EMPTY')" 2>/dev/null || echo RAW
echo -n "classify                -> "; curl -s -X POST "$B" -F "file=@$A" -F 'mode=classify' -F 'max_labels=3' | python3 -c "import json,sys
d=json.loads(sys.stdin.read(),strict=False)
print([l['label'] for l in d.get('labels',[])])" 2>/dev/null || echo RAW
echo -n "saliency attention      -> "; curl -s -X POST "$B" -F "file=@$A" -F 'mode=saliency' -F 'saliency_type=attention' | ov
echo -n "saliency objectness     -> "; curl -s -X POST "$B" -F "file=@$A" -F 'mode=saliency' -F 'saliency_type=objectness' | ov
echo -n "auto                    -> "; curl -s -X POST "$B" -F "file=@$A" -F 'mode=auto' | python3 -c "import json,sys
d=json.loads(sys.stdin.read(),strict=False); print(d.get('object'),d.get('mode'),'run=',d.get('modes_run'))" 2>/dev/null || echo RAW
echo -n "auto_crop               -> "; curl -s -X POST "$B" -F "file=@$A" -F 'auto_crop=true' | ov
echo -n "debug                   -> "; curl -s -X POST "$B" -F "file=@$A" -F 'mode=debug' | ov
echo -n "response_format=text    -> "; RESP=$(curl -s -X POST "$B" -F "file=@$A" -F 'response_format=text' -H 'Accept: text/plain'); echo "${#RESP} bytes, ct=text/plain"

echo "== 3. Опции распознавания =="
for o in 'recognition_level=fast' 'recognition_level=accurate' 'uses_language_correction=true' 'languages=["ru-RU"]' 'languages=["zz-BAD"]' 'max_pages=1' 'bogus_option=1'; do
  printf '%-30s -> ' "$o"; curl -s -X POST "$B" -F "file=@$A" -F "$o" | ov
done

echo "== 4. Ошибки =="
printf 'пустой запрос               -> '; curl -s -w ' [%{http_code}]' -X POST "$B" -H 'Content-Type: application/json' -d '{}' | tail -1; echo
printf 'несуществующий file-path    -> '; curl -s -w ' [%{http_code}]' -X POST "$B" -H 'Content-Type: application/json' -d '{"file":"/nonexistent/x.jpg"}' | tail -1; echo
printf 'битый base64 (должен 400!)   -> '; curl -s -w ' [%{http_code}]' -X POST "$B" -H 'Content-Type: application/json' -d '{"data":"!!!","filename":"x.png","media_type":"image/png"}' | tail -1; echo
printf 'не-картинка (.txt)          -> '; echo 'plain text' > "$TMP/x.txt"; curl -s -w ' [%{http_code}]' -X POST "$B" -F "file=@$TMP/x.txt" | tail -1; echo
printf 'без текста (empty.png)      -> '; curl -s -w ' [%{http_code}]' -X POST "$B" -F "file=@$TMP/empty.png" | tail -1; echo
printf 'barcode на PDF (изоб. only) -> '; curl -s -w ' [%{http_code}]' -X POST "$B" -F "file=@$TMP/invoice.pdf" -F 'mode=barcode' | tail -1; echo
printf 'table на PDF                -> '; curl -s -X POST "$B" -F "file=@$TMP/invoice.pdf" -F 'table=true' | ov
printf 'GET вместо POST             -> '; curl -s -o /dev/null -w '%{http_code}' "$B"; echo ' (ожидание: 405/404)'

echo "== 5. Chat «умный OCR» (apple_vision_ocr) =="
cat > "$TMP/chat.json" <<EOF
{"model":"foundation","messages":[{"role":"user","content":[{"type":"text","text":"Какой текст на изображении? Одно предложение."},{"type":"image_url","image_url":{"url":"data:image/png;base64,$b64"}}]}],
"tools":[{"type":"function","function":{"name":"apple_vision_ocr","description":"built-in OCR","parameters":{"type":"object","properties":{}}}}],"tool_choice":"auto"}
EOF
printf 'с tool (OCR-инъeция) -> '
curl -s --max-time 90 -X POST "$BASE_URL/v1/chat/completions" -H 'Content-Type: application/json' --data-binary @"$TMP/chat.json" \
 | python3 -c "import json,sys
try:
  c=json.loads(sys.stdin.read(),strict=False)['choices'][0]['message']['content']
  print('OCR-инъeция' if c.startswith('[Apple Vision OCR') else repr(c[:60]))
except Exception as e: print('FAIL', e)" || echo FAIL

echo "== 6. Лимит тела (36MB — КРЕШИТ сервер, кейс последний!) =="
printf '>25MB -> '
BY=$(curl -s --max-time 120 -o /dev/null -w '%{http_code}' -X POST "$B" -F "file=@$TMP/big.png")
echo "$BY $( [ -z "$BY" ] && echo '(без ответа — сервер, вероятно, крешнулся)' )"
printf 'health после кейса           -> '
curl -s --max-time 10 "$BASE_URL/health" || echo ' СНЯТ (у afm стандартный KeepAlive-подъём ~1-2 мин)'

echo "== Итог ==" 
echo "Ассеты временно жили в $TMP (удалены при выходе). Полный справочник: OCR-API-REFERENCE.md"
