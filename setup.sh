#!/bin/bash

# Setup script for Proxmox container with SpotDL
# Run this script inside your LXC container after creating it

set -e

echo "=========================================="
echo "SpotDL Container Setup"
echo "=========================================="

# System update
echo "[1/6] Updating system..."
apt-get update
apt-get upgrade -y

# Install dependencies
echo "[2/6] Installing dependencies..."
apt-get install -y python3 python3-pip python3-venv ffmpeg curl

# Create application directory
echo "[3/6] Creating directory structure..."
mkdir -p /opt/spotdl-web
mkdir -p /music
chmod 755 /music

# Install SpotDL
echo "[4/6] Installing SpotDL..."
pip3 install spotdl --break-system-packages
pip3 install flask --break-system-packages

# Create application file
echo "[5/6] Creating web application..."
cat > /opt/spotdl-web/app.py << 'EOFAPP'
from flask import Flask, render_template_string, request, jsonify, session
import subprocess
from pathlib import Path
import secrets
import os
from functools import wraps

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# Access token - CHANGE THIS TOKEN!
ACCESS_TOKEN = os.environ.get("SPOTDL_TOKEN", "your-secret-token-here")

BASE_DIR = "/music"

# Output templates
OUT_BY_ARTIST_ALBUM = "{artist}/{album}/{artist} - {title}.{output-ext}"
OUT_PLAYLIST_FOLDER_FLAT = "playlists/{list-name}/{artist} - {title}.{output-ext}"
# Playlist file in the same folder (m3u8)
M3U_PLAYLIST = "playlists/{list-name}/{list-name}.m3u"


def require_token(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = session.get("token")
        if token != ACCESS_TOKEN:
            return "404 Not Found", 404
        return f(*args, **kwargs)

    return decorated


CYBER_MAIN = r"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>SpotDL Console</title>
  <style>
    :root{
      --bg: #070a0f;
      --panel: rgba(13, 18, 28, 0.78);
      --panel2: rgba(9, 12, 18, 0.72);
      --text: #cfe7ff;
      --muted: #86a3c3;
      --accent: #00ff9c;
      --accent2: #00d7ff;
      --danger: #ff4d6d;
      --border: rgba(0, 255, 156, 0.18);
      --shadow: 0 20px 60px rgba(0,0,0,.55);
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
    }

    * { box-sizing: border-box; }
    body{
      margin: 0;
      min-height: 100vh;
      font-family: var(--sans);
      color: var(--text);
      background:
        radial-gradient(1200px 700px at 20% 10%, rgba(0,215,255,.10), transparent 55%),
        radial-gradient(900px 600px at 85% 20%, rgba(0,255,156,.10), transparent 55%),
        linear-gradient(180deg, #05070b, #070a0f 60%, #05070b);
      padding: 14px;
    }

    body:before{
      content:"";
      position: fixed;
      inset: 0;
      pointer-events: none;
      background-image:
        linear-gradient(rgba(0,255,156,.05) 1px, transparent 1px),
        linear-gradient(90deg, rgba(0,215,255,.04) 1px, transparent 1px);
      background-size: 36px 36px;
      opacity: .35;
    }

    .wrap{ max-width: 860px; margin: 0 auto; position: relative; z-index: 1; }

    .header{
      display:flex;
      align-items:flex-start;
      justify-content:space-between;
      gap: 10px;
      margin-bottom: 12px;
    }

    .brand{ display:flex; flex-direction:column; gap: 4px; }
    .brand h1{
      margin:0;
      font-family: var(--mono);
      font-size: 18px;
      letter-spacing: .6px;
      font-weight: 700;
    }
    .brand .sub{
      font-family: var(--mono);
      font-size: 11px;
      color: var(--muted);
      line-height: 1.35;
    }

    .pill{
      font-family: var(--mono);
      font-size: 11px;
      padding: 7px 9px;
      border: 1px solid var(--border);
      border-radius: 999px;
      background: rgba(0,255,156,.06);
      color: var(--accent);
      white-space: nowrap;
      align-self: flex-start;
    }

    .panel{
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 16px;
      box-shadow: var(--shadow);
      overflow:hidden;
    }

    .panel-top{
      padding: 14px;
      border-bottom: 1px solid rgba(0,255,156,.12);
      background: linear-gradient(180deg, rgba(0,255,156,.06), transparent);
    }

    /* Mobile-first: stack everything */
    .grid{
      display:grid;
      grid-template-columns: 1fr;
      gap: 10px;
      align-items: stretch;
    }

    .label{
      font-family: var(--mono);
      font-size: 12px;
      color: var(--muted);
      margin: 2px 0 6px 2px;
    }

    select, input[type="text"]{
      width: 100%;
      padding: 12px 12px;
      border-radius: 12px;
      border: 1px solid rgba(0,215,255,.18);
      background: var(--panel2);
      color: var(--text);
      font-family: var(--mono);
      outline: none;
    }
    input[type="text"]::placeholder{ color: rgba(134,163,195,.7); }

    select:focus, input[type="text"]:focus{
      border-color: rgba(0,255,156,.45);
      box-shadow: 0 0 0 3px rgba(0,255,156,.12);
    }

    button{
      width: 100%;
      padding: 13px 14px;
      border-radius: 12px;
      border: 1px solid rgba(0,255,156,.35);
      background: linear-gradient(135deg, rgba(0,255,156,.16), rgba(0,215,255,.10));
      color: var(--text);
      cursor: pointer;
      font-family: var(--mono);
      font-weight: 800;
      letter-spacing: .5px;
      transition: transform .12s ease, box-shadow .12s ease, opacity .12s ease;
      white-space: nowrap;
    }
    button:hover{ box-shadow: 0 10px 30px rgba(0,255,156,.12); transform: translateY(-1px); }
    button:active{ transform: translateY(0); }
    button:disabled{ opacity: .55; cursor:not-allowed; transform:none; box-shadow:none; }

    .meta{
      margin-top: 10px;
      font-family: var(--mono);
      font-size: 11px;
      color: var(--muted);
      display:flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items:center;
    }
    .meta code{
      color: var(--accent2);
      background: rgba(0,215,255,.08);
      border: 1px solid rgba(0,215,255,.12);
      padding: 2px 6px;
      border-radius: 8px;
      line-height: 1.35;
    }

    .status{
      display:none;
      margin-top: 12px;
      padding: 10px 12px;
      border-radius: 12px;
      border: 1px solid rgba(0,215,255,.18);
      background: rgba(0,215,255,.06);
      font-family: var(--mono);
      font-size: 12px;
    }
    .status.show{ display:block; }
    .status.ok{
      border-color: rgba(0,255,156,.28);
      background: rgba(0,255,156,.08);
      color: var(--accent);
    }
    .status.err{
      border-color: rgba(255,77,109,.30);
      background: rgba(255,77,109,.10);
      color: #ffd1da;
    }
    .status.info{ color: var(--text); }

    .terminal{ padding: 12px 14px 14px 14px; }
    .term-head{
      display:flex;
      align-items:center;
      justify-content:space-between;
      margin-bottom: 10px;
      gap: 8px;
    }
    .term-title{
      font-family: var(--mono);
      font-size: 12px;
      color: var(--muted);
    }
    .term-actions{ display:flex; gap: 8px; }
    .smallbtn{
      padding: 9px 10px;
      border-radius: 10px;
      font-size: 12px;
      font-weight: 800;
    }

    pre{
      margin: 0;
      padding: 12px;
      border-radius: 14px;
      border: 1px solid rgba(0,255,156,.14);
      background: rgba(2, 6, 12, .72);
      color: #d7fbe9;
      font-family: var(--mono);
      font-size: 12px;
      line-height: 1.55;
      max-height: 50vh; /* better on mobile */
      overflow: auto;
      white-space: pre-wrap;
      word-break: break-word;
    }

    .hint{
      margin-top: 10px;
      font-family: var(--mono);
      font-size: 11px;
      color: rgba(134,163,195,.85);
    }

    /* Desktop enhancement (optional): still simple, but can be 2-column */
    @media (min-width: 820px){
      body{ padding: 22px; }
      .brand h1{ font-size: 20px; }
      .brand .sub{ font-size: 12px; }
      .grid{
        grid-template-columns: 220px 1fr;
        grid-template-areas:
          "mode url"
          "run  run";
        gap: 12px;
        align-items:end;
      }
      .mode { grid-area: mode; }
      .url  { grid-area: url; }
      .run  { grid-area: run; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <div class="brand">
        <h1>SPOTDL_CONSOLE</h1>
        <div class="sub">FLAC • 320k • Genius lyrics • verified results</div>
      </div>
      <div class="pill">AUTH: SESSION_TOKEN</div>
    </div>

    <div class="panel">
      <div class="panel-top">
        <div class="grid">
          <div class="mode">
            <div class="label">Mode</div>
            <select id="mode" onchange="updateCommandHint()">
              <option value="track">Track</option>
              <option value="albums">Albums (fetch)</option>
              <option value="playlist">Playlist</option>
            </select>
          </div>

          <div class="url">
            <div class="label">Spotify URL</div>
            <input id="url" type="text" placeholder="https://open.spotify.com/..." autocomplete="off" />
          </div>

          <div class="run">
            <div class="label">&nbsp;</div>
            <button id="btn" onclick="run()">RUN</button>
          </div>
        </div>

        <div class="meta">
          <div>Command:</div>
          <code id="cmdhint"></code>
        </div>

        <div id="status" class="status"></div>
      </div>

      <div class="terminal">
        <div class="term-head">
          <div class="term-title">OUTPUT</div>
          <div class="term-actions">
            <button class="smallbtn" onclick="clearOutput()">CLEAR</button>
            <button class="smallbtn" onclick="copyOutput()">COPY</button>
          </div>
        </div>
        <pre id="output">Ready.</pre>
        <div class="hint">Tip: press Enter in the URL field to run.</div>
      </div>
    </div>
  </div>

  <script>
    function setStatus(kind, msg){
      const s = document.getElementById('status');
      if(!msg){
        s.className = 'status';
        s.textContent = '';
        return;
      }
      s.className = 'status show ' + (kind || 'info');
      s.textContent = msg;
    }

    function setOutput(text){
      const o = document.getElementById('output');
      o.textContent = text || '';
      o.scrollTop = o.scrollHeight;
    }

    function clearOutput(){
      setOutput('Ready.');
      setStatus('', '');
    }

    async function copyOutput(){
      const text = document.getElementById('output').textContent || '';
      try{
        await navigator.clipboard.writeText(text);
        setStatus('ok', 'Copied output to clipboard.');
      }catch(e){
        setStatus('err', 'Copy failed: ' + e.message);
      }
    }

    function updateCommandHint() {
      const mode = document.getElementById('mode').value;
      const el = document.getElementById('cmdhint');

      if (mode === 'albums') {
        el.textContent =
          'spotdl download <URL> --fetch-albums --format flac --bitrate 320k --lyrics genius --only-verified-results ' +
          '--output "{artist}/{album}/{artist} - {title}.{output-ext}"';
      } else if (mode === 'playlist') {
        el.textContent =
          'spotdl download <URL> --format flac --bitrate 320k --lyrics genius --only-verified-results ' +
          '--output "playlists/{list-name}/{artist} - {title}.{output-ext}"';
      } else {
        el.textContent =
          'spotdl download <URL> --format flac --bitrate 320k --lyrics genius --only-verified-results ' +
          '--output "{artist}/{album}/{artist} - {title}.{output-ext}"';
      }
    }

    async function run(){
      const url = document.getElementById('url').value.trim();
      const mode = document.getElementById('mode').value;
      const btn = document.getElementById('btn');

      if(!url){
        setStatus('err', 'Please enter a Spotify URL.');
        return;
      }

      btn.disabled = true;
      setStatus('info', 'Running SpotDL...');
      setOutput('Executing...\n');

      try{
        const resp = await fetch('/download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url, mode })
        });

        const data = await resp.json();

        if(data.success){
          setStatus('ok', 'Download completed successfully.');
        }else{
          setStatus('err', 'Download failed.');
        }

        setOutput(data.output || '(no output)');
      }catch(e){
        setStatus('err', 'Request error: ' + e.message);
      }finally{
        btn.disabled = false;
      }
    }

    document.getElementById('url').addEventListener('keypress', function(e){
      if(e.key === 'Enter') run();
    });

    updateCommandHint();
  </script>
</body>
</html>
"""

CYBER_LOGIN = r"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>SPOTDL_AUTH</title>
  <style>
    :root{
      --panel: rgba(13, 18, 28, 0.78);
      --text: #cfe7ff;
      --muted: #86a3c3;
      --border: rgba(0,255,156,0.18);
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
    }
    *{ box-sizing:border-box; }
    body{
      margin:0;
      min-height:100vh;
      display:flex;
      align-items:center;
      justify-content:center;
      padding: 22px;
      color: var(--text);
      font-family: var(--sans);
      background:
        radial-gradient(1200px 700px at 20% 10%, rgba(0,215,255,.10), transparent 55%),
        radial-gradient(900px 600px at 85% 20%, rgba(0,255,156,.10), transparent 55%),
        linear-gradient(180deg, #05070b, #070a0f 60%, #05070b);
    }
    .box{
      width: 100%;
      max-width: 420px;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 20px;
      box-shadow: 0 20px 60px rgba(0,0,0,.55);
    }
    h1{
      margin:0 0 6px 0;
      font-family: var(--mono);
      font-size: 18px;
      letter-spacing:.6px;
    }
    .sub{
      font-family: var(--mono);
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 14px;
    }
    .err{
      margin-bottom: 12px;
      padding: 10px 12px;
      border-radius: 12px;
      border: 1px solid rgba(255,77,109,.30);
      background: rgba(255,77,109,.10);
      color: #ffd1da;
      font-family: var(--mono);
      font-size: 12px;
    }
    input{
      width:100%;
      padding: 12px 12px;
      border-radius: 12px;
      border: 1px solid rgba(0,215,255,.18);
      background: rgba(9, 12, 18, 0.72);
      color: var(--text);
      font-family: var(--mono);
      outline:none;
      margin-bottom: 12px;
    }
    input:focus{
      border-color: rgba(0,255,156,.45);
      box-shadow: 0 0 0 3px rgba(0,255,156,.12);
    }
    button{
      width:100%;
      padding: 12px 14px;
      border-radius: 12px;
      border: 1px solid rgba(0,255,156,.35);
      background: linear-gradient(135deg, rgba(0,255,156,.16), rgba(0,215,255,.10));
      color: var(--text);
      cursor:pointer;
      font-family: var(--mono);
      font-weight: 700;
      letter-spacing: .3px;
    }
  </style>
</head>
<body>
  <div class="box">
    <h1>SPOTDL_AUTH</h1>
    <div class="sub">Enter session token to continue.</div>
    {% if error %}
      <div class="err">Invalid token.</div>
    {% endif %}
    <form method="POST">
      <input type="password" name="token" placeholder="Token" required />
      <button type="submit">AUTH</button>
    </form>
  </div>
</body>
</html>
"""

def looks_like_spotify(url: str) -> bool:
    u = (url or "").strip().lower()
    return (
        u.startswith("spotify:")
        or "open.spotify.com/" in u
        or "spotify.link/" in u
        or "spotify.com/" in u
    )


@app.route("/")
def index():
    if session.get("token") == ACCESS_TOKEN:
        return render_template_string(CYBER_MAIN)
    return render_template_string(CYBER_LOGIN, error=False)


@app.route("/", methods=["POST"])
def login():
    token = request.form.get("token", "")
    if token == ACCESS_TOKEN:
        session["token"] = token
        return render_template_string(CYBER_MAIN)
    return render_template_string(CYBER_LOGIN, error=True)


@app.route("/download", methods=["POST"])
@require_token
def download():
    data = request.get_json(silent=True) or {}
    url = (data.get("url") or "").strip()
    mode = (data.get("mode") or "track").strip().lower()

    if not url:
        return jsonify({"success": False, "output": "Invalid URL (empty)."})
    if not looks_like_spotify(url):
        return jsonify({"success": False, "output": "Invalid URL. Expected a Spotify link/URI."})

    cmd = [
        "spotdl",
        "download",
        url,
        "--format", "flac",
        "--bitrate", "320k",
        "--lyrics", "genius",
        "--only-verified-results",
    ]

    # Mode-specific behavior
    if mode == "albums":
        cmd += ["--fetch-albums", "--output", OUT_BY_ARTIST_ALBUM]
    elif mode == "playlist":
        cmd += ["--output", OUT_PLAYLIST_FOLDER_FLAT]
    else:
        cmd += ["--output", OUT_BY_ARTIST_ALBUM]

    try:
        os.makedirs(BASE_DIR, exist_ok=True)

        # If playlist mode, snapshot /music/playlists before running
        playlists_root = Path(BASE_DIR) / "playlists"
        before = {}
        if mode == "playlist":
            playlists_root.mkdir(parents=True, exist_ok=True)
            before = {p: p.stat().st_mtime for p in playlists_root.iterdir() if p.is_dir()}

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=3600,
            cwd=BASE_DIR,
        )

        output = (result.stdout or "") + (result.stderr or "")
        success = (result.returncode == 0)

        # Generate minimal m3u inside the detected playlist folder
        if mode == "playlist" and success:
            try:
                candidates = [p for p in playlists_root.iterdir() if p.is_dir()]
                if candidates:
                    changed = [p for p in candidates if before.get(p, 0) != p.stat().st_mtime]
                    playlist_dir = max((changed or candidates), key=lambda p: p.stat().st_mtime)

                    m3u_path = generate_simple_m3u(playlist_dir)
                    output += f"\n[M3U] Generated: {m3u_path}\n"
                else:
                    output += "\n[M3U] No playlist folder found under /music/playlists.\n"
            except Exception as e:
                output += f"\n[M3U] Generation failed: {str(e)}\n"

        if not output.strip():
            output = "Done (no output)."

        return jsonify({"success": success, "output": output})
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "output": "Timeout: download took too long."})
    except Exception as e:
        return jsonify({"success": False, "output": f"Error: {str(e)}"})


def generate_simple_m3u(playlist_dir: str) -> str:
    """
    Create a minimal .m3u file inside playlist_dir, containing only file names:
    Track1.flac
    Track2.flac
    ...
    Returns the full path to the generated m3u.
    """
    pdir = Path(playlist_dir)
    pdir.mkdir(parents=True, exist_ok=True)

    m3u_path = pdir / f"{pdir.name}.m3u"

    tracks = sorted(
        (p for p in pdir.iterdir() if p.is_file() and p.suffix.lower() == ".flac"),
        key=lambda p: p.name.lower(),
    )

    with open(m3u_path, "w", encoding="utf-8") as f:
        for t in tracks:
            f.write(t.name + "\n")

    return str(m3u_path)


@app.route("/<path:path>")
def catch_all(path):
    return "404 Not Found", 404


if __name__ == "__main__":
    os.makedirs("/music", exist_ok=True)
    app.run(host="0.0.0.0", port=5000, debug=False)

EOFAPP

# Create systemd service
echo "[6/6] Creating systemd service..."
cat > /etc/systemd/system/spotdl-web.service << 'EOFSERVICE'
[Unit]
Description=SpotDL Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spotdl-web
Environment="SPOTDL_TOKEN=your-secret-token-here"
ExecStart=/usr/bin/python3 /opt/spotdl-web/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Enable and start service
systemctl daemon-reload
systemctl enable spotdl-web.service
systemctl start spotdl-web.service

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Change the access token/password!"
echo "1. Edit: nano /etc/systemd/system/spotdl-web.service"
echo "2. Replace 'your-secret-token-here' with your own token"
echo "3. Run:"
echo "   systemctl daemon-reload"
echo "   systemctl restart spotdl-web"
echo ""
echo "Application running at: http://CONTAINER_IP:5000"
echo "Music downloads to: /music"
echo ""
echo "Service status: systemctl status spotdl-web"
echo "Logs: journalctl -u spotdl-web -f"
echo "=========================================="