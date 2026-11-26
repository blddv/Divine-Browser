/* Holynet-only Tor transport. No resolver, proxy override or direct fallback. Linux. */
#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <ftw.h>
#include <limits.h>

static pthread_once_t once = PTHREAD_ONCE_INIT;
static char root[] = "/tmp/divine-tor-XXXXXXXXXXXX";
static char sockpath[sizeof(((struct sockaddr_un*)0)->sun_path)];
static pid_t tor_pid = -1;
static int remove_entry(const char *p,const struct stat *s,int f,struct FTW *w) { (void)s;(void)f;(void)w; return remove(p); }
static void cleanup(void) {
  if (tor_pid > 0) { kill(tor_pid,SIGTERM); waitpid(tor_pid, NULL, 0); tor_pid = -1; }
  if (sockpath[0]) nftw(root,remove_entry,32,FTW_DEPTH|FTW_PHYS);
}
static void start_tor(void) {
  char executable[PATH_MAX], tor[PATH_MAX], data[PATH_MAX], socksarg[160];
  ssize_t n=readlink("/proc/self/exe",executable,sizeof(executable)-1);
  if(n<=0 || n >= (ssize_t)sizeof(executable)-1) return;
  executable[n]=0; char *slash=strrchr(executable,'/'); if(!slash) return; *slash=0;
  if(snprintf(tor,sizeof tor,"%s/vendor/tor/tor",executable) >= (int)sizeof tor || access(tor,X_OK)) {
    fprintf(stderr,"Holynet: встроенный Tor отсутствует; соединение заблокировано.\n"); return;
  }
  if(!mkdtemp(root)) return;
  snprintf(sockpath,sizeof sockpath,"%s/socks",root);
  snprintf(data,sizeof data,"%s/data",root);
  snprintf(socksarg,sizeof socksarg,"unix:%s",sockpath);
  pid_t parent=getpid(); tor_pid=fork();
  if(tor_pid==0) {
    prctl(PR_SET_PDEATHSIG,SIGTERM); if(getppid()!=parent) _exit(126);
    execl(tor,tor,"--ignore-missing-torrc","-f","/dev/null","--SocksPort",socksarg,
      "--DataDirectory",data,"--ClientOnly","1","--AvoidDiskWrites","1",
      "--Log","warn stderr",(char*)NULL);
    _exit(127);
  }
  if(tor_pid<0) { cleanup(); return; }
  atexit(cleanup);
}
static int rw_all(int fd,void *p,size_t n,int wr) {
  size_t done=0; while(done<n) { ssize_t k=wr ? send(fd,(char*)p+done,n-done,MSG_NOSIGNAL) : recv(fd,(char*)p+done,n-done,0); if(k<0 && errno==EINTR) continue; if(k<=0) return 0; done+=(size_t)k; } return 1;
}
int HolyTorConnect(const char *host,int port) {
  if(!host || !*host || strlen(host)>255 || port<1 || port>65535) return -1;
  pthread_once(&once,start_tor); if(tor_pid<=0 || !sockpath[0]) return -1;
  struct sockaddr_un addr={.sun_family=AF_UNIX}; strcpy(addr.sun_path,sockpath);
  int fd=-1;
  for(int i=0;i<100;i++) {
    fd=socket(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0); if(fd<0) return -1;
    if(connect(fd,(struct sockaddr*)&addr,sizeof addr)==0) break;
    close(fd); fd=-1;
    if(kill(tor_pid,0)<0) return -1;
    usleep(100000);
  }
  if(fd<0) return -1;
  struct ucred cred; socklen_t clen=sizeof cred;
  if(getsockopt(fd,SOL_SOCKET,SO_PEERCRED,&cred,&clen) || cred.pid!=tor_pid || cred.uid!=getuid()) { close(fd); return -1; }
  struct timeval tv={.tv_sec=60}; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof tv); setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof tv);
  unsigned char hello[]={5,1,0}, answer[4], req[262]; size_t len=strlen(host);
  if(!rw_all(fd,hello,3,1) || !rw_all(fd,answer,2,0) || answer[0]!=5 || answer[1]!=0) goto fail;
  req[0]=5; req[1]=1; req[2]=0; req[3]=3; req[4]=(unsigned char)len; memcpy(req+5,host,len); req[5+len]=(unsigned char)(port>>8); req[6+len]=(unsigned char)port;
  if(!rw_all(fd,req,len+7,1) || !rw_all(fd,answer,4,0) || answer[0]!=5 || answer[1]!=0 || answer[2]!=0) goto fail;
  size_t tail; if(answer[3]==1) tail=4; else if(answer[3]==4) tail=16; else if(answer[3]==3) { if(!rw_all(fd,answer,1,0)) goto fail; tail=answer[0]; } else goto fail;
  unsigned char discard[257]; if(!rw_all(fd,discard,tail+2,0)) goto fail;
  tv.tv_sec=10; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof tv); setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof tv);
  return fd;
fail: close(fd); return -1;
}
