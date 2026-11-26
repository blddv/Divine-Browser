/* QuickJS page lifecycle. Only network URLs reach the resource fetcher. */
I32 JsFetchResource(U8 *url, U8 **body, I64 *length, I32 *status)
{
  *body = NULL; *length = 0; *status = 0;
  if (!StartsWithIgnoreCase(url, "http://") && !StartsWithIgnoreCase(url, "https://")) return 0;
  HttpResponse r;
  Bool ok = FetchUrlFast(url, &r, 2);
  if (ok && r.body != NULL && r.body_len >= 0 && r.body_len <= 1536 * 1024) {
    *body = QjsAllocBuf(r.body_len + 1);
    if (*body != NULL) {
      MemCpy(*body, r.body, r.body_len);
      (*body)[r.body_len] = 0;
      *length = r.body_len;
      *status = r.status_code;
    }
  }
  HttpResponseFree(&r);
  return *body != NULL;
}

Bool JsPageNeeded(U8 *html)
{
  if (html == NULL) return FALSE;
  return StrContainsIgnoreCase(html, "<script") || StrContainsIgnoreCase(html, "onclick=") ||
         StrContainsIgnoreCase(html, "javascript:");
}
