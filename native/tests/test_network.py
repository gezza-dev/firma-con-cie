#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Bounded HTTP/proxy tests on loopback only. No CIE, system proxy or trust changes."""
import base64,json,os,socket,subprocess,sys,threading
from socketserver import ThreadingTCPServer,StreamRequestHandler
from contextlib import contextmanager
CLIENT=sys.argv[1]; checks=0
class Server(ThreadingTCPServer):
 allow_reuse_address=True;daemon_threads=True
 def handle_error(self,request,client_address):pass
 def __init__(self,handler):super().__init__(('127.0.0.1',0),handler);self.seen=[];self.connects=[];self.auth=[];self.redirect=None;self.deny=False
class Handler(StreamRequestHandler):
 def handle(self):
  self.connection.settimeout(3)
  first=self.rfile.readline(4096).decode('ascii',errors='replace').strip();headers={}
  if not first.startswith(('GET ','HEAD ','CONNECT ')):return
  while True:
   line=self.rfile.readline(4096)
   if line in [b'\r\n',b'\n',b'']:break
   name,_,value=line.decode('ascii',errors='replace').partition(':');headers[name.lower()]=value.strip()
  if first.startswith('CONNECT '):
   self.server.connects.append(first.split()[1]);self.server.auth.append(headers.get('proxy-authorization',''))
   if self.server.deny:self.wfile.write(b'HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n');return
   self.wfile.write(b'HTTP/1.1 200 Connection established\r\n\r\n');self.wfile.flush()
   raw=self.rfile.readline(4096)
   # Negative TLS checks: no plaintext HTTP may be sent after CONNECT.
   if not raw.startswith((b'GET ',b'HEAD ')):return
   first=raw.decode().strip();headers={}
   while True:
    line=self.rfile.readline(4096)
    if line in [b'\r\n',b'\n',b'']:break
    name,_,value=line.decode().partition(':');headers[name.lower()]=value.strip()
  self.server.seen.append((first,headers))
  if self.server.deny:self.wfile.write(b'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');return
  if self.server.redirect:
   self.wfile.write(('HTTP/1.1 302 Found\r\nLocation: '+self.server.redirect+'\r\nContent-Length: 0\r\nConnection: close\r\n\r\n').encode());return
  self.wfile.write(b'HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\n')
  if not first.startswith('HEAD '):self.wfile.write(b'TEST')
@contextmanager
def server():
 s=Server(Handler);t=threading.Thread(target=s.serve_forever,daemon=True);t.start()
 try:yield s
 finally:s.shutdown();s.server_close();t.join()
def wire(mode=0,host='',port=0,user='',password=''):
 return f'CIE-NETWORK-1\n{mode}\n{host}\n{port}\n{user}\n{password}\n'.encode()
def run(url,config,public=False,head=False,environment=None):
 r=subprocess.run([CLIENT,url,'1' if public else '0','1' if head else '0'],input=config,capture_output=True,timeout=10,env=environment)
 if r.returncode:return r,None,None
 line,_,body=r.stdout.partition(b'\n');return r,json.loads(line),body
def check(value,name):
 global checks
 assert value,name;checks+=1
with server() as origin,server() as proxy:
 url=f'http://127.0.0.1:{origin.server_address[1]}/test';config=wire(1,'127.0.0.1',proxy.server_address[1],'test-user','test-pass')
 env=os.environ.copy();env.update(HTTP_PROXY=f'http://127.0.0.1:{proxy.server_address[1]}',ALL_PROXY=f'http://127.0.0.1:{proxy.server_address[1]}',NO_PROXY='*')
 _,r,body=run(url,wire(),environment=env);check(r['transportCode']==0 and body==b'TEST','direct request');check(len(proxy.seen)==0,'direct ignores inherited proxy')
 _,r,body=run(url,config,environment=env);check(r['transportCode']==0 and body==b'TEST','manual proxy GET');check(len(proxy.seen)==1,'manual proxy overrides NO_PROXY');check(proxy.seen[-1][0].startswith('GET http://127.0.0.1:'),'ordinary HTTP forwarded through explicit proxy');check(proxy.seen[-1][1].get('proxy-authorization')=='Basic '+base64.b64encode(b'test-user:test-pass').decode(),'proxy authentication')
 _,r,body=run(url,config,head=True);check(r['transportCode']==0 and r['bytes']==0 and body==b'','HEAD probe has no document payload');check(proxy.seen[-1][0].startswith('HEAD '),'HEAD method')
 before=len(proxy.seen);_,r,_=run(url,wire(2,'127.0.0.1',proxy.server_address[1],'test-user','test-pass'));check(r['transportCode']!=0,'HTTPS proxy requires TLS');check(len(proxy.seen)==before,'HTTPS proxy failure never sends cleartext HTTP credentials')
 before=len(proxy.seen);_,r,_=run(url,config,public=True);check(r['transportCode']!=0,'private CRL target blocked');check(len(proxy.seen)==before and not proxy.connects,'private target never reaches proxy')
 public='http://93.184.216.34/crl';_,r,body=run(public,config,public=True);check(r['transportCode']==0 and body==b'TEST','protected proxy CRL GET');check(proxy.connects[-1]=='93.184.216.34:80','CONNECT uses checked numeric address');check(proxy.seen[-1][1].get('host')=='93.184.216.34','origin host retained');check('proxy-authorization' not in proxy.seen[-1][1],'proxy credentials do not enter target tunnel')
 proxy.redirect='http://127.0.0.1/private';before=len(origin.seen);_,r,_=run(public,config,public=True);check(r['transportCode']!=0,'private redirect blocked');check(len(origin.seen)==before,'redirect never reaches local origin');proxy.redirect=None
 proxy.deny=True;before=len(origin.seen);_,r,_=run(url,config);check(r['transportCode']!=0,'proxy error reported');check(len(origin.seen)==before,'no direct fallback after proxy failure');proxy.deny=False
 before=len(proxy.seen);_,r,_=run('https://93.184.216.34/crl',config,public=True);check(r['transportCode']!=0,'invalid TLS tunnel rejected');check(len(proxy.seen)==before,'TLS failure sends no HTTP request or credentials to target')
 if len(sys.argv)==5:
  java,classpath,fetcher=sys.argv[2:5];before=len(proxy.connects)
  result=subprocess.run([java,'-Xmx256m','-cp',classpath,'it.cieid.ltv.NetworkTransportTest',fetcher,str(proxy.server_address[1])],capture_output=True,timeout=12,env=env)
  check(result.returncode==0,'Java private pipe proxy transport: '+result.stderr.decode(errors='replace')[-500:]);check(len(proxy.connects)==before+1,'Java worker never bypasses proxy');check(proxy.auth[-1]=='Basic '+base64.b64encode(b'test-user:test-pass').decode(),'Java helper proxy authentication preserved')
 for bad in [wire(1,'user@proxy',80),wire(1,'proxy/path',80),wire(1,'[:::]',80),wire(1,'proxy',0),wire(1,'proxy',65536),wire(0,'proxy',80),wire(1,'proxy',80,'u:v','p'),wire(1,'proxy',80,'','p'),wire(3,'proxy',80),wire(1,'proxy',80,'u','p\nextra'),wire()+b'extra',b'bad']:
  response,_,_=run(url,bad);check(response.returncode==2,'invalid config rejected')
print(json.dumps({'passed':True,'checks':checks,'loopbackOnly':True,'cardOperations':0,'systemProxyChanges':0,'credentialsOnlySynthetic':True}))
