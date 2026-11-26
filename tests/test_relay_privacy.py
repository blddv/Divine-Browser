#!/usr/bin/env python3
"""Linux integration test: Holynet process cannot open direct TCP/UDP; child is Tor."""
from pathlib import Path
import os, signal, subprocess, tempfile, time
binary = str(Path('./holy-browser').resolve())
def sockets(pid):
    inodes = set()
    for f in Path(f'/proc/{pid}/fd').iterdir():
        try:
            v = os.readlink(f)
            if v.startswith('socket:['): inodes.add(v[8:-1])
        except FileNotFoundError: pass
    out = []
    for proto in ('tcp', 'tcp6', 'udp', 'udp6'):
        for line in Path(f'/proc/{pid}/net/{proto}').read_text().splitlines()[1:]:
            f=line.split()
            if f[9] in inodes: out.append((proto,f[3],int(f[2].split(':')[1],16)))
    return out
def children(pid):
    return [int(x) for x in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
with tempfile.TemporaryDirectory(prefix='holy-relay-test-') as d:
    args = [binary, '--p2p-daemon', '--p2p-port', '31301', '--daemon-sec', '12']
    a = subprocess.Popen(args,cwd=d,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    b = subprocess.Popen(args,cwd=d,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        time.sleep(3)
        assert a.poll() is None and b.poll() is None, 'node stopped early'
        assert Path(d,'holynet_node_31301.lock').exists() and Path(d,'holynet_node_31302.lock').exists(), 'profile conflict'
        for p in (a,b):
            print('Holynet browser IP sockets:',sockets(p.pid))
            assert sockets(p.pid)==[], 'unexpected direct TCP/UDP socket in Holynet browser'
            # Tor is forked by mesh thread: /proc/<pid>/task/<tid>/children
            kids=[]
            for task in Path(f'/proc/{p.pid}/task').iterdir():
                kids += [int(x) for x in (task/'children').read_text().split()]
            assert len(kids)==1 and Path(f'/proc/{kids[0]}/exe').resolve().name=='tor',kids
            os.kill(kids[0],signal.SIGKILL)
        time.sleep(2)
        for p in (a,b): assert sockets(p.pid)==[], 'direct fallback after Tor failure'
        r=subprocess.run([binary,'--p2p-daemon','--peer','127.0.0.1:31301'],cwd=d,capture_output=True,text=True,timeout=5)
        assert r.returncode==2 and 'отключены' in r.stdout
    finally:
        for p in (a,b):
            try: p.wait(timeout=12)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
print('Holynet: no browser TCP/UDP, no direct fallback after killing Tor: OK')
