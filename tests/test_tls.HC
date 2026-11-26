#include "../bindings.HH"
#include "../url_http.HC"
I32 Main(I32 argc, U8 **argv)
{
  if (argc < 2) return 2;
  HttpResponse r;
  Bool ok = FetchUrl(argv[1], &r);
  printf("TLS_STATUS=%d OK=%d\n", r.status_code, ok);
  HttpResponseFree(&r);
  return 0;
}
