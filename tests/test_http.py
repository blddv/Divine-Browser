from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from subprocess import run
from pathlib import Path
import sys
import tempfile
import atexit
tmp = tempfile.TemporaryDirectory(prefix="divineweb-test-")
atexit.register(tmp.cleanup)
hits=[]
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        hits.append(self.path)
        if self.path == '/redir-script':
            self.send_response(302); self.send_header('Location','/must-not-follow'); self.end_headers(); return
        body={
          '/': '''<!doctype html><html><head><title>Network test</title><link rel="stylesheet" href="/x.css"></head><body><h1 id="out">ORIGINAL</h1><script src="/x.js"></script><script>fetch('/data').then(r=>r.text()).then(t=>{document.getElementById('out').textContent=t;});</script></body></html>''',
          '/x.css': 'body { background-color: #d0efdd } h1 {color: #d00000; font-size: 32px}',
          '/x.js': "document.getElementById('out').textContent='EXTERNAL SCRIPT';",
          '/data': 'HTTP FETCH WORKED',
          '/redirect': "<html><body><script>location.href='/next'</script>Redirecting</body></html>",
          '/redirect-script-page': "<html><body><script src='/redir-script'></script>safe</body></html>",
          '/next': '<html><head><title>Redirect destination</title></head><body>REDIRECT SUCCESS</body></html>',
        }.get(self.path)
        if body is None: self.send_error(404); return
        body=body.encode(); self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
srv=ThreadingHTTPServer(('127.0.0.1',0),H); Thread(target=srv.serve_forever,daemon=True).start()
base='http://127.0.0.1:%s'%srv.server_port
for path,name in [('/','network-test.png'),('/redirect','redirect-test.png'),('/redirect-script-page','redirect-script-test.png')]:
    r=run(['./holy-browser','--screenshot',str(Path(tmp.name)/name),base+path],capture_output=True,text=True,timeout=20)
    print(r.stdout, r.stderr, 'exit',r.returncode)
    assert r.returncode==0 and Path(str(Path(tmp.name)/name)).stat().st_size>1000
assert all(p in hits for p in ['/', '/x.css','/x.js','/data','/redirect','/next']),hits
assert '/redir-script' in hits and '/must-not-follow' not in hits,hits
print('HTTP resource requests and redirect:',hits)
srv.shutdown()
