#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$SOURCE")"

DB=${HYPER_INDEX_DB:-"$HOME/.cache/hyper_index/hyper_index.db"}

usage() {
  cat <<'USAGE'
Usage: hyper_index.sh <command> [options]

Commands:
  init                              Initialize the persistent index database.
  index-fs [--root PATH] [--hash] [--max-bytes N]
                                    Recursively index filesystem metadata.
  index-wiki <title> [--depth N] [--lang CODE]
                                    Pull a concept and linked concepts from Wikipedia.
  search <files|wiki> <query> [--limit N] [--json]
                                    Search the filesystem (files) or concepts (wiki).
  visualize <concept> [--depth N] [--format dot|json] [--lang CODE]
                                    Output a relationship graph for a concept.
  stats                             Display aggregate database statistics.
  doctor                            Run dependency and environment checks.
  quickstart                        Initialize, index the repo, and seed concept data.
  auto-test                         Execute a built-in smoke test suite.
  auto-debug                        Inspect the index for common issues.
  serve [--host HOST] [--port PORT]
                                    Launch a minimal multi-user HTTP API for queries.

Environment:
  HYPER_INDEX_DB   Override the SQLite database path (default: $HOME/.cache/hyper_index/hyper_index.db)
USAGE
}

mkdir -p "$(dirname "$DB")"

ensure_schema() {
  sqlite3 "$DB" <<'SQL'
PRAGMA journal_mode=WAL;
PRAGMA synchronous=OFF;
CREATE TABLE IF NOT EXISTS files (
  path TEXT PRIMARY KEY,
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  inode INTEGER NOT NULL,
  device INTEGER NOT NULL,
  hash TEXT
);
CREATE VIRTUAL TABLE IF NOT EXISTS file_index USING fts5(path, tokenize='unicode61');
CREATE TABLE IF NOT EXISTS concepts (
  title TEXT NOT NULL,
  summary TEXT,
  fetched_at INTEGER NOT NULL,
  lang TEXT NOT NULL,
  PRIMARY KEY(title, lang)
);
CREATE VIRTUAL TABLE IF NOT EXISTS concept_index USING fts5(title, summary, tokenize='unicode61');
CREATE TABLE IF NOT EXISTS concept_edges (
  source TEXT NOT NULL,
  target TEXT NOT NULL,
  lang TEXT NOT NULL,
  PRIMARY KEY(source, target, lang)
);
SQL
}

index_fs() {
  local root="."
  local compute_hash=0
  local max_bytes=1048576
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        root="$2"; shift 2 ;;
      --hash)
        compute_hash=1; shift ;;
      --max-bytes)
        max_bytes="$2"; shift 2 ;;
      *)
        echo "Unknown option for index-fs: $1" >&2
        exit 1 ;;
    esac
  done
  ensure_schema
  python3 - "$DB" "$root" "$compute_hash" "$max_bytes" <<'PY'
import hashlib
import os
import sqlite3
import sys

DB, ROOT, DO_HASH, MAX_BYTES = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
conn = sqlite3.connect(DB)
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('PRAGMA synchronous=OFF;')
cur = conn.cursor()

records, fts_rows = [], []
BATCH_SIZE = 500

def flush():
    if not records:
        return
    cur.executemany(
        'INSERT INTO files(path, size, mtime, inode, device, hash) VALUES(?,?,?,?,?,?)\n'
        'ON CONFLICT(path) DO UPDATE SET size=excluded.size, mtime=excluded.mtime,\n'
        'inode=excluded.inode, device=excluded.device, hash=excluded.hash;',
        records,
    )
    cur.executemany(
        'INSERT OR REPLACE INTO file_index(rowid, path) VALUES ((SELECT rowid FROM files WHERE path=?), ?);',
        fts_rows,
    )
    records.clear()
    fts_rows.clear()

for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if not d.startswith('.git')]
    for name in filenames:
        full = os.path.join(dirpath, name)
        try:
            st = os.stat(full, follow_symlinks=False)
        except (FileNotFoundError, PermissionError):
            continue
        digest = None
        if DO_HASH:
            try:
                h = hashlib.blake2b(digest_size=32)
                remaining = MAX_BYTES
                with open(full, 'rb') as fh:
                    while remaining > 0:
                        chunk = fh.read(min(65536, remaining))
                        if not chunk:
                            break
                        h.update(chunk)
                        remaining -= len(chunk)
                digest = h.hexdigest()
            except (OSError, PermissionError):
                digest = None
        records.append((full, st.st_size, int(st.st_mtime), st.st_ino, st.st_dev, digest))
        fts_rows.append((full, full))
        if len(records) >= BATCH_SIZE:
            flush()

flush()
conn.commit()
conn.close()
PY
}

index_wiki() {
  if [[ $# -lt 1 ]]; then
    echo "index-wiki requires a title" >&2
    exit 1
  fi
  local title="$1"; shift
  local depth=1
  local lang="en"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --depth)
        depth="$2"; shift 2 ;;
      --lang)
        lang="$2"; shift 2 ;;
      *)
        echo "Unknown option for index-wiki: $1" >&2
        exit 1 ;;
    esac
  done
  ensure_schema
  python3 - "$DB" "$title" "$depth" "$lang" <<'PY'
import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

DB, TITLE, DEPTH, LANG = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

API = f"https://{LANG}.wikipedia.org/w/api.php"
conn = sqlite3.connect(DB)
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('PRAGMA synchronous=OFF;')

seen = set()
queue = [(TITLE, 0)]
now = int(time.time())

while queue:
    title, depth = queue.pop(0)
    if (title.lower(), LANG) in seen or depth > DEPTH:
        continue
    seen.add((title.lower(), LANG))

    params = {
        'action': 'query',
        'prop': 'extracts|links',
        'explaintext': 1,
        'exintro': 1,
        'plnamespace': 0,
        'pllimit': 'max',
        'format': 'json',
        'titles': title,
    }
    data = urllib.parse.urlencode(params).encode()
    with urllib.request.urlopen(API, data=data, timeout=15) as resp:
        payload = json.load(resp)
    pages = payload.get('query', {}).get('pages', {})
    if not pages:
        continue
    page = next(iter(pages.values()))
    if 'missing' in page:
        continue
    summary = page.get('extract', '')
    conn.execute(
        'INSERT INTO concepts(title, summary, fetched_at, lang) VALUES(?,?,?,?)\n'
        'ON CONFLICT(title, lang) DO UPDATE SET summary=excluded.summary, fetched_at=excluded.fetched_at;',
        (page['title'], summary, now, LANG)
    )
    conn.execute(
        'INSERT OR REPLACE INTO concept_index(rowid, title, summary) VALUES ((SELECT rowid FROM concepts WHERE title=? AND lang=?), ?, ?);',
        (page['title'], LANG, page['title'], summary)
    )
    links = page.get('links', [])
    for link in links:
        target = link.get('title')
        if not target:
            continue
        conn.execute(
            'INSERT OR IGNORE INTO concept_edges(source, target, lang) VALUES(?,?,?);',
            (page['title'], target, LANG)
        )
        if depth < DEPTH:
            queue.append((target, depth + 1))
conn.commit()
conn.close()
PY
}

search_domain() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: hyper_index.sh search <domain> <query> [--limit N] [--json]" >&2
    exit 1
  fi
  local domain="$1"; shift
  local query="$1"; shift
  local limit=50
  local json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit)
        limit="$2"; shift 2 ;;
      --json)
        json=1; shift ;;
      *)
        echo "Unknown option for search: $1" >&2
        exit 1 ;;
    esac
  done
  ensure_schema
  python3 - "$DB" "$domain" "$query" "$limit" "$json" <<'PY'
import json
import sqlite3
import sys

DB, DOMAIN, QUERY, LIMIT, AS_JSON = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), bool(int(sys.argv[5]))
conn = sqlite3.connect(DB)
cur = conn.cursor()
if DOMAIN == 'files':
    try:
        cur.execute('''
            SELECT f.path, f.size, f.mtime, IFNULL(f.hash, '')
            FROM file_index
            JOIN files f ON file_index.rowid = f.rowid
            WHERE file_index MATCH ?
            LIMIT ?;
        ''', (QUERY.replace('"', ' '), LIMIT))
        fetch = cur.fetchall()
    except sqlite3.OperationalError:
        cur.execute('''
            SELECT path, size, mtime, IFNULL(hash, '')
            FROM files
            WHERE path LIKE ?
            ORDER BY mtime DESC
            LIMIT ?;
        ''', (f'%{QUERY}%', LIMIT))
        fetch = cur.fetchall()
    rows = [
        {
            'path': row[0],
            'size': row[1],
            'mtime': row[2],
            'hash': row[3] or None,
        }
        for row in fetch
    ]
elif DOMAIN == 'wiki':
    try:
        cur.execute('''
            SELECT c.title, c.summary, c.lang, c.fetched_at
            FROM concept_index
            JOIN concepts c ON concept_index.rowid = c.rowid
            WHERE concept_index MATCH ?
            LIMIT ?;
        ''', (QUERY.replace('"', ' '), LIMIT))
        fetch = cur.fetchall()
    except sqlite3.OperationalError:
        cur.execute('''
            SELECT title, summary, lang, fetched_at
            FROM concepts
            WHERE title LIKE ? OR summary LIKE ?
            ORDER BY fetched_at DESC
            LIMIT ?;
        ''', (f'%{QUERY}%', f'%{QUERY}%', LIMIT))
        fetch = cur.fetchall()
    rows = [
        {
            'title': row[0],
            'summary': row[1],
            'lang': row[2],
            'fetched_at': row[3],
        }
        for row in fetch
    ]
else:
    raise SystemExit(f'Unknown search domain: {DOMAIN}')
if AS_JSON:
    print(json.dumps(rows, ensure_ascii=False, indent=2))
else:
    for row in rows:
        if DOMAIN == 'files':
            suffix = ''
            if row['hash']:
                suffix = f" hash={row['hash']}"
            print(f"{row['path']} size={row['size']} mtime={row['mtime']}{suffix}")
        else:
            summary = (row['summary'] or '').replace('\n', ' ')
            if len(summary) > 160:
                summary = summary[:157] + '...'
            print(f"[{row['lang']}] {row['title']}: {summary}")
conn.close()
PY
}

visualize() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: hyper_index.sh visualize <concept> [--depth N] [--format dot|json]" >&2
    exit 1
  fi
  local concept="$1"; shift
  local depth=2
  local fmt="dot"
  local lang=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --depth)
        depth="$2"; shift 2 ;;
      --format)
        fmt="$2"; shift 2 ;;
      --lang)
        lang="$2"; shift 2 ;;
      *)
        echo "Unknown option for visualize: $1" >&2
        exit 1 ;;
    esac
  done
  ensure_schema
  python3 - "$DB" "$concept" "$depth" "$fmt" "$lang" <<'PY'
import json
import sqlite3
import sys

DB, SEED, DEPTH, FMT, LANG = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
conn = sqlite3.connect(DB)
cur = conn.cursor()
if not LANG:
    cur.execute('SELECT lang FROM concepts WHERE title=? ORDER BY fetched_at DESC LIMIT 1;', (SEED,))
    row = cur.fetchone()
    if not row:
        raise SystemExit(f'Concept not found: {SEED}')
    LANG = row[0]

edges = {}
queue = [(SEED, 0)]
seen = set()
while queue:
    node, depth = queue.pop(0)
    if (node, depth) in seen or depth > DEPTH:
        continue
    seen.add((node, depth))
    cur.execute('SELECT target FROM concept_edges WHERE source=? AND lang=?;', (node, LANG))
    children = [r[0] for r in cur.fetchall()]
    edges[node] = children
    if depth < DEPTH:
        for child in children:
            queue.append((child, depth + 1))
if FMT == 'json':
    print(json.dumps({'root': SEED, 'lang': LANG, 'edges': edges}, ensure_ascii=False, indent=2))
else:
    print('digraph concepts {')
    print('  rankdir=LR;')
    for src, targets in edges.items():
        print(f'  "{src}" [shape=box];')
        for tgt in targets:
            print(f'  "{src}" -> "{tgt}";')
    print('}')
conn.close()
PY
}

stats() {
  ensure_schema
  sqlite3 "$DB" <<'SQL'
.headers on
.mode column
SELECT 'files' AS table_name, COUNT(*) AS rows FROM files
UNION ALL
SELECT 'concepts', COUNT(*) FROM concepts
UNION ALL
SELECT 'concept_edges', COUNT(*) FROM concept_edges;
SQL
}

doctor() {
  local ok=1
  echo "[doctor] Checking required executables..."
  for bin in sqlite3 python3 curl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "  - Missing: $bin" >&2
      ok=0
    else
      echo "  - Found: $(command -v "$bin")"
    fi
  done
  echo "[doctor] Verifying sqlite3 has FTS5 support..."
  if ! sqlite3 :memory: 'CREATE VIRTUAL TABLE t USING fts5(x);' >/dev/null 2>&1; then
    echo "  - ERROR: sqlite3 binary lacks FTS5 support" >&2
    ok=0
  else
    echo "  - OK: FTS5 available"
  fi
  echo "[doctor] Checking Python HTTP connectivity..."
  if ! python3 - <<'PY'
import urllib.request
urllib.request.urlopen('https://www.wikipedia.org', timeout=5)
PY
  then
    echo "  - WARNING: Unable to reach wikipedia.org (network/firewall?)" >&2
  else
    echo "  - OK: wikipedia.org reachable"
  fi
  if [[ $ok -eq 0 ]]; then
    echo "doctor checks failed." >&2
    exit 1
  fi
  echo "doctor checks passed."
}

quickstart() {
  echo "[quickstart] Preparing database at $DB"
  ensure_schema
  echo "[quickstart] Indexing repository files (size-limited for speed)..."
  index_fs --root "$PWD" --max-bytes 65536
  echo "[quickstart] Seeding Wikipedia concepts (Linux, depth 1)..."
  index_wiki "Linux" --depth 1 --lang en || echo "[quickstart] Wikipedia seeding skipped (network error?)" >&2
  echo "[quickstart] Launching health checks..."
  doctor || true
  cat <<'NOTE'

Next steps:
  1. Explore the CLI: ./hyper_index.sh search files Linux
  2. Launch the API & UI: ./hyper_index.sh serve --host 0.0.0.0
  3. Open http://localhost:8765 in your browser for the interactive visual explorer.

NOTE
}

auto_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir:-}"' EXIT
  local tmpdb="$tmpdir/test.db"
  echo "[auto-test] Running shell syntax check"
  bash -n "$SCRIPT_PATH"
  echo "[auto-test] Exercising core commands"
  env HYPER_INDEX_DB="$tmpdb" "$SCRIPT_PATH" init
  env HYPER_INDEX_DB="$tmpdb" "$SCRIPT_PATH" index-fs --root "$SCRIPT_DIR" --max-bytes 4096
  env HYPER_INDEX_DB="$tmpdb" "$SCRIPT_PATH" search files hyper_index.sh --limit 1 --json >/dev/null
  env HYPER_INDEX_DB="$tmpdb" "$SCRIPT_PATH" stats >/dev/null
  echo "[auto-test] All smoke tests completed"
  rm -rf "$tmpdir"
  trap - EXIT
}

auto_debug() {
  ensure_schema
  python3 - "$DB" <<'PY'
import sqlite3
import sys

db = sys.argv[1]
conn = sqlite3.connect(db)
cur = conn.cursor()
print('[auto-debug] File entries:', cur.execute('SELECT COUNT(*) FROM files').fetchone()[0])
print('[auto-debug] Concept entries:', cur.execute('SELECT COUNT(*) FROM concepts').fetchone()[0])
print('[auto-debug] Edge entries:', cur.execute('SELECT COUNT(*) FROM concept_edges').fetchone()[0])
missing = cur.execute('''
  SELECT COUNT(*) FROM files f
  LEFT JOIN file_index fi ON fi.rowid = f.rowid
  WHERE fi.rowid IS NULL;
''').fetchone()[0]
print('[auto-debug] Files missing FTS rows:', missing)
missing = cur.execute('''
  SELECT COUNT(*) FROM concepts c
  LEFT JOIN concept_index ci ON ci.rowid = c.rowid
  WHERE ci.rowid IS NULL;
''').fetchone()[0]
print('[auto-debug] Concepts missing FTS rows:', missing)
conn.close()
PY
}

serve() {
  local host="127.0.0.1"
  local port=8765
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        host="$2"; shift 2 ;;
      --port)
        port="$2"; shift 2 ;;
      *)
        echo "Unknown option for serve: $1" >&2
        exit 1 ;;
    esac
  done
  ensure_schema
  python3 - "$DB" "$host" "$port" "$SCRIPT_DIR/web" <<'PY'
import json
import sqlite3
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from pathlib import Path

DB, HOST, PORT, STATIC_ROOT = sys.argv[1], sys.argv[2], int(sys.argv[3]), Path(sys.argv[4])

class Handler(BaseHTTPRequestHandler):
    conn = sqlite3.connect(DB, check_same_thread=False)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/health':
            self.respond(HTTPStatus.OK, {'status': 'ok'})
            return
        if parsed.path == '/search':
            params = parse_qs(parsed.query)
            domain = params.get('domain', ['files'])[0]
            query = params.get('q', [''])[0]
            limit = int(params.get('limit', ['50'])[0])
            if not query:
                self.respond(HTTPStatus.BAD_REQUEST, {'error': 'missing q'})
                return
            cur = self.conn.cursor()
            if domain == 'files':
                try:
                    cur.execute('''
                        SELECT f.path, f.size, f.mtime, f.hash
                        FROM file_index
                        JOIN files f ON file_index.rowid = f.rowid
                        WHERE file_index MATCH ?
                        LIMIT ?;
                    ''', (query.replace('"', ' '), limit))
                    fetch = cur.fetchall()
                except sqlite3.OperationalError:
                    cur.execute('''
                        SELECT path, size, mtime, hash
                        FROM files
                        WHERE path LIKE ?
                        ORDER BY mtime DESC
                        LIMIT ?;
                    ''', (f'%{query}%', limit))
                    fetch = cur.fetchall()
                rows = [
                    {
                        'path': r[0],
                        'size': r[1],
                        'mtime': r[2],
                        'hash': r[3],
                    }
                    for r in fetch
                ]
            elif domain == 'wiki':
                try:
                    cur.execute('''
                        SELECT c.title, c.summary, c.lang, c.fetched_at
                        FROM concept_index
                        JOIN concepts c ON concept_index.rowid = c.rowid
                        WHERE concept_index MATCH ?
                        LIMIT ?;
                    ''', (query.replace('"', ' '), limit))
                    fetch = cur.fetchall()
                except sqlite3.OperationalError:
                    cur.execute('''
                        SELECT title, summary, lang, fetched_at
                        FROM concepts
                        WHERE title LIKE ? OR summary LIKE ?
                        ORDER BY fetched_at DESC
                        LIMIT ?;
                    ''', (f'%{query}%', f'%{query}%', limit))
                    fetch = cur.fetchall()
                rows = [
                    {
                        'title': r[0],
                        'summary': r[1],
                        'lang': r[2],
                        'fetched_at': r[3],
                    }
                    for r in fetch
                ]
            else:
                self.respond(HTTPStatus.BAD_REQUEST, {'error': 'unknown domain'})
                return
            self.respond(HTTPStatus.OK, rows)
            return
        if parsed.path == '/graph':
            params = parse_qs(parsed.query)
            concept = params.get('concept', [''])[0]
            depth = int(params.get('depth', ['2'])[0])
            lang = params.get('lang', [''])[0]
            if not concept:
                self.respond(HTTPStatus.BAD_REQUEST, {'error': 'missing concept'})
                return
            payload = self.fetch_graph(concept, depth, lang)
            if payload is None:
                self.respond(HTTPStatus.NOT_FOUND, {'error': 'concept not indexed'})
            else:
                self.respond(HTTPStatus.OK, payload)
            return
        if parsed.path == '/' or parsed.path.startswith('/ui'):
            self.serve_file(STATIC_ROOT / 'index.html')
            return
        candidate = STATIC_ROOT / parsed.path.lstrip('/')
        if candidate.is_file():
            self.serve_file(candidate)
            return
        self.respond(HTTPStatus.NOT_FOUND, {'error': 'not found'})

    def log_message(self, fmt, *args):
        return

    def serve_file(self, path: Path):
        if not path.is_file():
            self.respond(HTTPStatus.NOT_FOUND, {'error': 'file not found'})
            return
        data = path.read_bytes()
        if path.suffix == '.html':
            ctype = 'text/html; charset=utf-8'
        elif path.suffix == '.js':
            ctype = 'application/javascript; charset=utf-8'
        elif path.suffix == '.css':
            ctype = 'text/css; charset=utf-8'
        elif path.suffix == '.json':
            ctype = 'application/json; charset=utf-8'
        else:
            ctype = 'application/octet-stream'
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def fetch_graph(self, seed: str, depth: int, lang: str):
        cur = self.conn.cursor()
        if not lang:
            cur.execute('SELECT lang FROM concepts WHERE title=? ORDER BY fetched_at DESC LIMIT 1;', (seed,))
            row = cur.fetchone()
            if not row:
                return None
            lang = row[0]
        queue = [(seed, 0)]
        seen = set()
        edges = {}
        while queue:
            node, d = queue.pop(0)
            if (node, d) in seen or d > depth:
                continue
            seen.add((node, d))
            cur.execute('SELECT target FROM concept_edges WHERE source=? AND lang=?;', (node, lang))
            children = [r[0] for r in cur.fetchall()]
            edges[node] = children
            if d < depth:
                for child in children:
                    queue.append((child, d + 1))
        return {'root': seed, 'lang': lang, 'edges': edges}

    def respond(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

server = ThreadingHTTPServer((HOST, PORT), Handler)
print(f"Serving hyper-index on http://{HOST}:{PORT}")
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
PY
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"; shift
case "$cmd" in
  init)
    ensure_schema ;;
  index-fs)
    index_fs "$@" ;;
  index-wiki)
    index_wiki "$@" ;;
  search)
    search_domain "$@" ;;
  visualize)
    visualize "$@" ;;
  stats)
    stats ;;
  doctor)
    doctor ;;
  quickstart)
    quickstart ;;
  auto-test)
    auto_test ;;
  auto-debug)
    auto_debug ;;
  serve)
    serve "$@" ;;
  --help|-h|help)
    usage ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1 ;;
 esac
