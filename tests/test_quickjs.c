#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "../quickjs/qjs_bridge.h"
static int calls;
static int32_t fetcher(const char *u, char **body, int64_t *len, int32_t *status) {
  calls++;
  const char *s = "document.getElementById('out').textContent='external ok'";
  *len = strlen(s); *body = QjsAllocBuf(*len+1); memcpy(*body,s,*len+1); *status=200;
  return 1;
}
static void contains(char *s,const char *v){ if(!s || !strstr(s,v)){fprintf(stderr,"missing %s in %s\n",v,s?s:"NULL");exit(1);} }
int main(void) {
  const char *doc="<html><body><noscript>disabled</noscript><div id='out'>old</div><button id='b'>go</button><script src='/x.js'></script><script>document.getElementById('b').addEventListener('click',function(){document.getElementById('out').textContent='clicked';}); setTimeout(function(){document.getElementById('out').textContent='timer';},100); fetch('https://evil.invalid/data');</script></body></html>";
  QjsSetFetchCallback(fetcher); QjsPage *p=QjsPageCreate(); assert(p); int64_t n;
  char *s=QjsPageLoadHtml(p,doc,strlen(doc),"https://example.test/index",&n);
  contains(s,"external ok"); assert(!strstr(s,"disabled")); assert(calls==1);
  char *id=strstr(s,"data-qjs-id=\""); assert(id); id+=13; int qid=atoi(id); assert(qid>0);
  QjsFreeStr(s); assert(QjsPageClickId(p,qid)); s=QjsPageSerializeHtml(p,&n); contains(s,"clicked"); QjsFreeStr(s);
  struct timespec delay={0,150000000}; nanosleep(&delay,NULL);
  assert(QjsPageTickTimers(p)); s=QjsPageSerializeHtml(p,&n); contains(s,"timer"); QjsFreeStr(s);
  assert(!QjsPageTickTimers(p));
  assert(QjsPageEvalUrl(p,"location.href='/next'")); char redirect[256]; assert(QjsPagePopRedirect(p,redirect,sizeof(redirect))); assert(!strcmp(redirect,"https://example.test/next"));
  QjsPageEvalUrl(p,"while(true){}"); assert(QjsPageEvalUrl(p,"document.getElementById('out').textContent='recovered'"));
  s=QjsPageSerializeHtml(p,&n); contains(s,"recovered"); QjsFreeStr(s); QjsPageDestroy(p);
  puts("QuickJS load, same-origin fetch, click, timer, redirect and watchdog: OK");
  return 0;
}
