#!/usr/bin/env python3
"""Local, original-content source website; optional iOS API fixture for UI tests."""
import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=0)
parser.add_argument('--mobile-api', action='store_true')
parser.add_argument('--ready-file')
args = parser.parse_args()
state_lock = threading.Lock()
offline = False
requests = {}
revision = 0
book_index = 0
book_position = 0


def book(base):
    return dict(name='书源全流程测试小说', author='测试作者', bookUrl=base + '/book/1',
                origin=base, tocUrl=base + '/toc/1', durChapterIndex=book_index,
                durChapterPos=book_position, durChapterTime=revision, totalChapterNum=6,
                durChapterTitle=f'第{book_index + 1}章 测试章节')


def chapters(base):
    return [dict(title=f'第{i + 1}章 测试章节', index=i, url=f'{base}/chapter/{i + 1}') for i in range(6)]


def content(index):
    return '\n\n'.join(f'第{index + 1}章正文，第{p + 1}段。这是我们自行编写的测试文字，用于验证阅读、翻章和离线缓存。' for p in range(70))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    @property
    def base(self):
        return f'http://127.0.0.1:{self.server.server_port}'

    def send(self, value, status=200, content_type='application/json; charset=utf-8'):
        data = (json.dumps(value, ensure_ascii=False) if content_type.startswith('application/json') else value).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def ok(self, value):
        self.send(dict(isSuccess=True, errorMsg='', data=value))

    def do_GET(self):
        global requests
        path = urlsplit(self.path).path
        with state_lock:
            requests[path] = requests.get(path, 0) + 1
        if path == '/__state':
            self.send(dict(book=book(self.base), requests=requests, offline=offline))
        elif path.startswith('/reader3/') and args.mobile_api:
            if offline:
                self.send(dict(isSuccess=False, errorMsg='fixture offline', data=None), 503)
            elif path == '/reader3/getUserInfo':
                authorized = self.headers.get('Authorization') == 'e2e-session'
                self.ok(dict(secure=True, secureKeyRequired=False, adminAuthorized=False,
                             userInfo=dict(username='e2ereader', accessToken='e2e-session') if authorized else None))
            elif path == '/reader3/getBookshelf':
                self.ok([book(self.base)])
            else:
                self.send(dict(isSuccess=False, errorMsg='not found', data=None), 404)
        elif path == '/source.json':
            self.send([dict(bookSourceName='受控测试书源', bookSourceUrl=self.base, enabled=True,
                            searchUrl=self.base + '/search?q={{key}}',
                            ruleSearch=dict(bookList='.result', name='a@text', author='.author@text', bookUrl='a@href'),
                            ruleBookInfo=dict(name='h1@text', author='.author@text', tocUrl='#toc@href'),
                            ruleToc=dict(chapterList='#catalog a', chapterName='@text', chapterUrl='@href'),
                            ruleContent=dict(content='#content@text'))])
        elif path == '/search':
            self.send('<html><div class="result"><a href="/book/1">书源全流程测试小说</a><span class="author">测试作者</span></div></html>', content_type='text/html; charset=utf-8')
        elif path == '/book/1':
            self.send('<h1>书源全流程测试小说</h1><span class="author">测试作者</span><a id="toc" href="/toc/1">目录</a>', content_type='text/html; charset=utf-8')
        elif path == '/toc/1':
            html = '<div id="catalog">' + ''.join(f'<a href="/chapter/{i + 1}">第{i + 1}章 测试章节</a>' for i in range(6)) + '</div>'
            self.send(html, content_type='text/html; charset=utf-8')
        elif path.startswith('/chapter/'):
            index = int(path.rsplit('/', 1)[-1]) - 1
            html = '<article id="content">' + ''.join('<p>' + p + '</p>' for p in content(index).split('\n\n')) + '</article>'
            self.send(html, content_type='text/html; charset=utf-8')
        else:
            self.send(dict(error='not found'), 404)

    def do_POST(self):
        global offline, revision, book_index, book_position
        path = urlsplit(self.path).path
        with state_lock:
            requests[path] = requests.get(path, 0) + 1
        payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or '{}')
        if path == '/__control':
            with state_lock:
                if 'offline' in payload:
                    offline = payload['offline']
                if 'index' in payload:
                    book_index = payload['index']
                    book_position = payload.get('position', 0)
                    revision += 1
            self.send(dict(book=book(self.base)))
            return
        if not args.mobile_api:
            self.send(dict(error='not found'), 404)
            return
        if offline:
            self.send(dict(isSuccess=False, errorMsg='fixture offline', data=None), 503)
            return
        if path == '/reader3/login':
            if payload.get('username') != 'e2ereader' or payload.get('password') != 'e2epassword':
                self.send(dict(isSuccess=False, errorMsg='fixture login rejected', data=None), 400)
            else:
                self.ok(dict(username='e2ereader', accessToken='e2e-session'))
        elif path == '/reader3/getShelfBook':
            self.ok(book(self.base))
        elif path == '/reader3/getChapterList':
            self.ok(chapters(self.base))
        elif path == '/reader3/getBookContent':
            index = int(urlsplit(payload['chapterUrl']).path.rsplit('/', 1)[-1]) - 1
            self.ok(content(index))
        elif path == '/reader3/syncBookProgress':
            with state_lock:
                accepted = payload['expectedUpdatedAt'] == revision
                same = payload['index'] == book_index and payload['position'] == book_position
                if accepted:
                    book_index, book_position = payload['index'], payload['position']
                    revision += 1
                result = dict(accepted=accepted or same, book=book(self.base))
            self.ok(result)
        else:
            self.send(dict(isSuccess=False, errorMsg='not found', data=None), 404)


server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
ready = json.dumps(dict(url=f'http://127.0.0.1:{server.server_port}'))
if args.ready_file:
    Path(args.ready_file).write_text(ready)
print(ready, flush=True)
server.serve_forever()
