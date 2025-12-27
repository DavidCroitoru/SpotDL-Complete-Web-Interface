from flask import Flask, render_template, request, session, Response, jsonify
import subprocess
from pathlib import Path
import secrets
import os
import sys
from functools import wraps
import threading
import queue
import time

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# Access token - CHANGE THIS TOKEN!
ACCESS_TOKEN = os.environ.get("SPOTDL_TOKEN", "your-secret-token-here")

BASE_DIR = "/music"

# Get spotdl path from env
SPOTDL_PATH = os.environ.get("SPOTDL_PATH", "/usr/local/bin/spotdl")

# Output templates
OUT_BY_ARTIST_ALBUM = "{artist}/{album}/{artist} - {title}.{output-ext}"
OUT_PLAYLIST_FOLDER_FLAT = "playlists/{list-name}/{artist} - {title}.{output-ext}"
M3U_PLAYLIST = "playlists/{list-name}/{list-name}.m3u"


def require_token(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = session.get("token")
        if token != ACCESS_TOKEN:
            return "404 Not Found", 404
        return f(*args, **kwargs)
    return decorated



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
        return render_template("index.html")
    return render_template("login.html", error=False)

@app.route("/", methods=["POST"])
def login():
    token = request.form.get("token", "")
    if token == ACCESS_TOKEN:
        session["token"] = token
        return render_template("index.html")
    return render_template("login.html", error=True)


@app.route("/download/stream")
@require_token
def download_stream():
    """Server-Sent Events endpoint for real-time output streaming"""
    url = request.args.get("url", "").strip()
    mode = request.args.get("mode", "track").strip().lower()

    def generate():
        if not url:
            yield f'data: {{"type": "error", "message": "Invalid URL (empty)."}}\n\n'
            return
        
        if not looks_like_spotify(url):
            yield f'data: {{"type": "error", "message": "Invalid URL. Expected a Spotify link/URI."}}\n\n'
            return

        # Build command
        cmd = [
            SPOTDL_PATH,
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

            yield f'data: {{"type": "status", "message": "Starting SpotDL..."}}\n\n'
            cmd_str = " ".join(cmd)
            yield f'data: {{"type": "output", "data": "Command: {cmd_str}\\n\\n"}}\n\n'

            # Start the subprocess
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                cwd=BASE_DIR,
            )

            # Track statistics
            tracks_found = 0
            tracks_downloaded = 0
            tracks_errors = 0

            # Stream output line by line
            for line in iter(process.stdout.readline, ''):
                if line:
                    # Parse statistics from output
                    import re
                    found_match = re.search(r'Found (\d+) songs? in', line)
                    if found_match:
                        tracks_found = int(found_match.group(1))
                    
                    if 'Downloaded "' in line or line.startswith('Downloaded '):
                        tracks_downloaded += 1
                    
                    if any(err in line for err in ['LookupError', 'AudioProviderError', 'Error:', 'Failed']):
                        if 'rate/request limit' not in line:  # Don't count rate limits as errors
                            tracks_errors += 1
                    
                    # Send each line as it comes
                    import json
                    yield f'data: {json.dumps({"type": "output", "data": line, "stats": {"found": tracks_found, "downloaded": tracks_downloaded, "errors": tracks_errors}})}\n\n'
                    time.sleep(0.01)  # Small delay to prevent overwhelming the client

            process.wait()
            
            success = (process.returncode == 0)

            # Generate m3u for playlists
            if mode == "playlist" and success:
                try:
                    candidates = [p for p in playlists_root.iterdir() if p.is_dir()]
                    if candidates:
                        changed = [p for p in candidates if before.get(p, 0) != p.stat().st_mtime]
                        playlist_dir = max((changed or candidates), key=lambda p: p.stat().st_mtime)
                        
                        m3u_path = generate_simple_m3u(playlist_dir)
                        yield f'data: {{"type": "output", "data": "\\n[M3U] Generated: {m3u_path}\\n"}}\n\n'
                except Exception as e:
                    yield f'data: {{"type": "output", "data": "\\n[M3U] Generation failed: {str(e)}\\n"}}\n\n'

            if success:
                yield f'data: {{"type": "complete", "message": "All downloads completed successfully."}}\n\n'
            else:
                yield f'data: {{"type": "error", "message": "SpotDL exited with errors. Check output above."}}\n\n'

        except FileNotFoundError:
            yield f'data: {{"type": "error", "message": "SpotDL not found. Make sure it is installed. Path: {SPOTDL_PATH}"}}\n\n'
        except Exception as e:
            yield f'data: {{"type": "error", "message": "Unexpected error: {str(e)}"}}\n\n'

    return Response(generate(), mimetype='text/event-stream')


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
    print(f"SpotDL path: {SPOTDL_PATH}")
    print(f"SpotDL exists: {os.path.exists(SPOTDL_PATH)}")
    app.run(host="0.0.0.0", port=5000, debug=False)
