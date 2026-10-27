import os, sys, threading, urllib.request

URL = open('/c/Users/hp/blob_url.txt').read().strip()
OUT = 'd:/Users/hp/Downloads/ManManMusic-2.9.1/apk.zip'
OUT = 'C:/Users/hp/Downloads/ManManMusic-2.9.1/apk.zip'

req = urllib.request.Request(URL, method='HEAD')
with urllib.request.urlopen(req) as r:
    size = int(r.headers['Content-Length'])
print('size', size, flush=True)

N = 8
chunk = size // N + 1
parts = []

def worker(i):
    start = i * chunk
    end = min(start + chunk, size) - 1
    if start >= size:
        return
    path = f'{OUT}.part{i}'
    have = os.path.getsize(path) if os.path.exists(path) else 0
    if have > end - start:
        return
    r = urllib.request.Request(URL, headers={'Range': f'bytes={start + have}-{end}'})
    with urllib.request.urlopen(r, timeout=60) as resp, open(path, 'ab') as f:
        while True:
            buf = resp.read(65536)
            if not buf:
                break
            f.write(buf)

threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(N)]
[t.start() for t in threads]
[t.join() for t in threads]

with open(OUT, 'wb') as out:
    for i in range(N):
        p = f'{OUT}.part{i}'
        if os.path.exists(p):
            with open(p, 'rb') as f:
                out.write(f.read())
            os.remove(p)
print('done', os.path.getsize(OUT), flush=True)