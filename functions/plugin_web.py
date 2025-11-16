#!/usr/bin/env python3
import http.server, socketserver, os, html, sys, traceback, cgi
from pathlib import Path

SERVER_NAME = os.environ.get("MC_SERVER_NAME","server")
SERVER_DIR  = Path(os.environ.get("MC_SERVER_DIR",".")).resolve()
PLUG_DIR    = (SERVER_DIR / "plugins")
PLUG_DIR.mkdir(parents=True, exist_ok=True)

INDEX_HTML = """<!doctype html>
<html lang="id"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Upload Plugin — {name}</title>
<style>
:root{{--bg:#0b1020;--card:#141a2a;--fg:#e7eefc;--muted:#9bb1d4;--accent:#3b82f6}}
*{{box-sizing:border-box}}html,body{{margin:0;padding:0;background:var(--bg);color:var(--fg);font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu}}
.container{{max-width:800px;margin:20px auto;padding:16px}}
.card{{background:var(--card);border:1px solid #243045;border-radius:16px;padding:16px}}
h1,h2,h3{{margin:0 0 12px 0}}
small,.muted{{color:var(--muted)}}
.row{{display:flex;gap:12px;flex-wrap:wrap;align-items:center}}
input[type=file]{{width:100%;background:#0f1525;border:1px dashed #2a3a58;border-radius:12px;padding:10px;color:var(--fg)}}
button{{background:var(--accent);color:white;border:0;border-radius:12px;padding:10px 14px;font-weight:600}}
button:disabled{{opacity:.6}}
#loading{{display:none;margin-top:10px;color:#a7f3d0;font-weight:700}}
.table{{width:100%;border-collapse:collapse;margin-top:8px}}
.table th,.table td{{padding:10px;border-bottom:1px solid #22324d;font-size:14px}}
.badge{{display:inline-block;padding:4px 8px;border-radius:999px;background:#1f2937;color:#e5e7eb;font-size:12px}}
.footer{{margin-top:14px;color:var(--muted);font-size:12px}}
@media (max-width:480px){{.row{{flex-direction:column;align-items:stretch}}}}
</style>
<script>
function onSubmit(){{
  const l=document.getElementById('loading');
  l.style.display='block';
  const btn=document.getElementById('btn');
  if(btn){{btn.disabled=true; btn.innerText='Mengunggah...';}}
}}
</script>
</head><body>
<div class="container">
  <div class="card">
    <h2>Upload Plugin <small class="muted">({name})</small></h2>
    <form method="POST" enctype="multipart/form-data" onsubmit="onSubmit()">
      <div class="row">
        <input type="file" name="file" accept=".jar" required>
        <button id="btn" type="submit">Upload</button>
      </div>
      <div id="loading">Mengunggah… mohon tunggu ⏳</div>
    </form>
    <h3 style="margin-top:14px">Plugins</h3>
    {table}
    <div class="footer">File akan disalin ke folder <span class="badge">plugins/</span> server ini.</div>
  </div>
</div>
</body></html>
"""

def list_plugins():
    rows=[]
    for p in sorted(PLUG_DIR.glob("*.jar")):
        size = f"{p.stat().st_size/1024/1024:.2f} MB"
        rows.append(f"<tr><td>{html.escape(p.name)}</td><td class='muted'>{size}</td></tr>")
    if not rows:
        rows.append("<tr><td colspan='2' class='muted'><i>(Belum ada plugin)</i></td></tr>")
    return "<table class='table'><thead><tr><th>Nama</th><th>Ukuran</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>"

class Handler(http.server.BaseHTTPRequestHandler):
    # Kurangi spam log standar
    def log_message(self, fmt, *args):
        sys.stderr.write("[web] " + fmt % args + "\n")

    def _send_html(self, code, html_text):
        body = html_text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type","text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            if self.path == "/health":
                self.send_response(200)
                self.send_header("Content-Type","text/plain; charset=utf-8")
                self.send_header("Content-Length","2")
                self.end_headers()
                self.wfile.write(b"OK")
                return
            page = INDEX_HTML.format(name=html.escape(SERVER_NAME), table=list_plugins())
            self._send_html(200, page)
        except Exception:
            traceback.print_exc()
            self._send_html(500, "<h1>500</h1><p>Kesalahan server.</p>")

    def do_POST(self):
        try:
            ctype = self.headers.get('Content-Type','')
            if not ctype or not ctype.startswith('multipart/form-data'):
                self._send_html(400, "<h1>400</h1><p>Gunakan form upload multipart.</p>")
                return

            # Parse form dgn keep_blank_values agar stabil
            form = cgi.FieldStorage(fp=self.rfile, headers=self.headers,
                                    environ={'REQUEST_METHOD':'POST','CONTENT_TYPE':ctype},
                                    keep_blank_values=True)

            if 'file' not in form:
                self._send_html(400, "<h1>400</h1><p>Bagian file tidak ditemukan.</p>")
                return

            fileitem = form['file']
            # Bisa jadi multiple: ambil elemen pertama
            if isinstance(fileitem, list):
                fileitem = fileitem[0]

            filename = getattr(fileitem, 'filename', None)
            if not filename:
                self._send_html(400, "<h1>400</h1><p>Nama file tidak ada.</p>")
                return

            name = os.path.basename(filename)
            if not name.lower().endswith(".jar"):
                self._send_html(400, "<h1>400</h1><p>Hanya file .jar yang diizinkan.</p>")
                return

            target = PLUG_DIR / name
            tmp = target.with_suffix(target.suffix + ".part")
            # Tulis bertahap (hindari crash karena file besar)
            with open(tmp,'wb') as out:
                while True:
                    chunk = fileitem.file.read(1024*1024)
                    if not chunk: break
                    out.write(chunk)
            os.replace(tmp, target)

            # Redirect ke halaman utama (303 See Other)
            self.send_response(303)
            self.send_header("Location","/")
            self.send_header("Content-Length","0")
            self.end_headers()
        except Exception:
            traceback.print_exc()
            self._send_html(500, "<h1>500</h1><p>Upload gagal (lihat log).</p>")

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def run(host, port):
    srv = ThreadingHTTPServer((host, port), Handler)
    print(f"[uploader] http://{host}:{port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()

if __name__=="__main__":
    host=os.environ.get("MC_WEB_HOST","0.0.0.0")
    port=int(os.environ.get("MC_WEB_PORT","8088"))
    run(host, port)