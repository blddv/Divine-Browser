#!/usr/bin/env python3
"""Deterministic SOCKS test, peer impersonation test, and no-Tor fail-closed check."""
import os, subprocess, tempfile
from pathlib import Path
project = Path.cwd()
with tempfile.TemporaryDirectory(prefix='divine-tor-unit-') as temp:
    d=Path(temp); (d/'vendor/tor').mkdir(parents=True)
    (d/'harness.c').write_text('''#include <stdio.h>\n#include <unistd.h>\nint HolyTorConnect(const char*,int);\nint main(void){int fd=HolyTorConnect("relay.no-local-dns.invalid",8883); if(fd<0){puts("FAILED");return 2;} close(fd); puts("OK");return 0;}\n''')
    subprocess.run(['cc','-O2','-pthread',str(d/'harness.c'),str(project/'tor_bridge.c'),'-o',str(d/'harness')],check=True)
    missing=subprocess.run([str(d/'harness')],capture_output=True,text=True,timeout=10)
    assert missing.returncode==2,missing
    fake=d/'vendor/tor/tor'
    fake.write_text('''#!/usr/bin/python3
import os,socket,sys
p=sys.argv[sys.argv.index("--SocksPort")+1][5:]
if os.environ.get("SPOOF"):
 if os.fork():
  os.wait();sys.exit(0)
s=socket.socket(socket.AF_UNIX);s.bind(p);s.listen(1)
c,_=s.accept()
def read(n):
 b=b""
 while len(b)<n:
  v=c.recv(n-len(b))
  if not v: raise SystemExit
  b+=v
 return b
try:
 assert read(3)==b"\\x05\\x01\\x00";c.sendall(b"\\x05\\x00")
 a=read(5); assert a[:4]==b"\\x05\\x01\\x00\\x03"
 host=read(a[4]);port=read(2)
 open(os.environ["RESULT"],"wb").write(host+b":"+str(int.from_bytes(port,"big")).encode())
 c.sendall(b"\\x05\\x00\\x00\\x01\\x00\\x00\\x00\\x00\\x00\\x00")
except (BrokenPipeError,ConnectionResetError): pass
''')
    fake.chmod(0o755); result=d/'result'
    env=dict(os.environ,RESULT=str(result))
    ok=subprocess.run([str(d/'harness')],env=env,capture_output=True,text=True,timeout=15)
    assert ok.returncode==0,(ok.stdout,ok.stderr)
    assert result.read_bytes()==b'relay.no-local-dns.invalid:8883'
    result.unlink(); env['SPOOF']='1'
    bad=subprocess.run([str(d/'harness')],env=env,capture_output=True,text=True,timeout=15)
    assert bad.returncode==2,(bad.stdout,bad.stderr)
    assert not result.exists(),'SOCKS peer impersonation accepted'
print('Tor bridge: remote DNS, no missing-Tor fallback, peer PID verification: OK')
