import os, ssl, tempfile, threading, subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        b=b'OK'; self.send_response(200); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
with tempfile.TemporaryDirectory(prefix='divineweb-tls-') as tmp:
    cert=str(Path(tmp)/'cert.pem'); key=str(Path(tmp)/'key.pem')
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost','-keyout',key,'-out',cert],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
    server=HTTPServer(('127.0.0.1',0),Handler)
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cert,key); server.socket=ctx.wrap_socket(server.socket,server_side=True)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    port=server.server_port
    def test(host, trust):
        env=os.environ.copy(); env.pop('SSL_CERT_FILE',None); env.pop('SSL_CERT_DIR',None)
        if trust: env['SSL_CERT_FILE']=cert; env['SSL_CERT_DIR']=tmp
        r=subprocess.run(['./tests/test_tls',f'https://{host}:{port}/'],env=env,capture_output=True,text=True,timeout=10,check=True)
        print(host,'trusted' if trust else 'untrusted',r.stdout.strip())
        return r.stdout
    assert 'TLS_STATUS=525' in test('localhost',False)
    assert 'TLS_STATUS=525' in test('127.0.0.1',True)
    assert 'TLS_STATUS=200' in test('localhost',True)
    server.shutdown()
print('TLS CA and hostname verification: OK')
