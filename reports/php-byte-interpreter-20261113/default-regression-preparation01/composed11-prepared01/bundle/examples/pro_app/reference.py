"""Same API specification as service.all. Standard-library-only reference app."""
import argparse, json, sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / 'items.sqlite'

def migrate():
    with sqlite3.connect(DB) as db:
        db.execute('CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, qty INTEGER NOT NULL CHECK (qty >= 0))')

class API(BaseHTTPRequestHandler):
    def respond(self, status, body, mime='text/plain; charset=utf-8'):
        data = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        if self.path == '/health':
            return self.respond(200, 'OK')
        if self.path == '/items':
            with sqlite3.connect(DB) as db:
                db.row_factory = sqlite3.Row
                items = [dict(r) for r in db.execute('SELECT id,name,qty FROM items ORDER BY id')]
            return self.respond(200, json.dumps(items, ensure_ascii=False, separators=(',',':')),
                                'application/json; charset=utf-8')
        self.respond(404,'Not found')
    def do_POST(self):
        if self.path != '/items':
            return self.respond(404, 'Not found')
        length = int(self.headers.get('Content-Length','0'))
        if length < 0 or length > 65536:
            return self.respond(400, 'Bad Request')
        try:
            item = json.loads(self.rfile.read(length))
            name, qty = item['name'], item['qty']
            with sqlite3.connect(DB) as db:
                db.execute('INSERT INTO items(name,qty) VALUES(?,?)',(name,qty))
            return self.respond(201,'created')
        except (ValueError, KeyError, TypeError, sqlite3.Error):
            self.respond(400,'Bad Request')

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18889)
    args=parser.parse_args()
    migrate()
    ThreadingHTTPServer(('127.0.0.1',args.port),API).serve_forever()
