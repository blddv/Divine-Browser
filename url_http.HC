/* ============================================================================
 * url_http.HC — Парсер URL, резолвер ссылок и быстрый стек HTTP/1.1 + TLS + Gzip
 * Браузер DivineWeb на языке HolyC (holyc-lang)
 * ============================================================================ */

class ParsedUrl
{
  U8  scheme[16];
  U8  host[256];
  I32 port;
  U8  path[1024];
};

class HttpResponse
{
  I32 status_code;
  U8  final_url[1024];
  U8  content_type[128];
  U8  error[256];
  U8 *body;
  I64 body_len;
};

#define DNS_CACHE_CAP 64

class DnsCacheEntry
{
  Bool used;
  U8   host[256];
  U32  ipv4_addr;
};

class HttpFastGlobals
{
  Bool          initialized;
  U8            mtx_buf[96];
  U0           *ssl_ctx;
  DnsCacheEntry dns[DNS_CACHE_CAP];
  I32           dns_hand;
  I64           tmp_seq;
};

HttpFastGlobals g_http_fast;

U0 EnsureHttpGlobals()
{
  if (!g_http_fast.initialized) {
    MemSet(&g_http_fast, 0, sizeof(HttpFastGlobals));
    pthread_mutex_init((&g_http_fast.mtx_buf)(pthread_mutex_t *), NULL);
    g_http_fast.ssl_ctx = SSL_CTX_new(TLS_client_method());
    if (g_http_fast.ssl_ctx != NULL) {
      SSL_CTX_set_verify(g_http_fast.ssl_ctx, 1, NULL); /* SSL_VERIFY_PEER */
      if (SSL_CTX_set_default_verify_paths(g_http_fast.ssl_ctx) != 1) {
        SSL_CTX_free(g_http_fast.ssl_ctx); g_http_fast.ssl_ctx = NULL;
      }
    }
    g_http_fast.initialized = TRUE;
  }
}

/* Bind certificate validation to the requested DNS name or numeric address. */
Bool SecureTlsSetHost(U0 *ssl, U8 *host)
{
  if (ssl == NULL || host == NULL || host[0] == 0) return FALSE;
  U32 ip = 0;
  if (inet_pton(AF_INET, host, &ip) == 1)
    return X509_VERIFY_PARAM_set1_ip_asc(SSL_get0_param(ssl), host) == 1;
  SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, host);
  return SSL_set1_host(ssl, host) == 1;
}

U0 HttpFastLock()
{
  EnsureHttpGlobals();
  pthread_mutex_lock((&g_http_fast.mtx_buf)(pthread_mutex_t *));
}

U0 HttpFastUnlock()
{
  if (g_http_fast.initialized) {
    pthread_mutex_unlock((&g_http_fast.mtx_buf)(pthread_mutex_t *));
  }
}

I64 NextHttpTempSeq()
{
  HttpFastLock();
  g_http_fast.tmp_seq++;
  I64 v = g_http_fast.tmp_seq;
  HttpFastUnlock();
  return v;
}

U16 HttpHtons(I32 port)
{
  U16 p = port & 0xFFFF;
  return ((p & 0xFF) << 8) | ((p >> 8) & 0xFF);
}

U0 SafeCopy(U8 *dst, U8 *src, I64 cap)
{
  if (cap <= 0) return;
  if (src == NULL) {
    dst[0] = 0;
    return;
  }
  I64 i = 0;
  while (i < cap - 1 && src[i] != 0) {
    dst[i] = src[i];
    i++;
  }
  /* Если строка обрезалась посередине многобайтового UTF-8 символа — убираем битый хвост */
  if (src[i] != 0 && (src[i] & 0xC0) == 0x80) {
    while (i > 0 && (dst[i - 1] & 0xC0) == 0x80) i--;
    if (i > 0 && (dst[i - 1] & 0x80) != 0) i--;
  }
  dst[i] = 0;
}

U0 SafeCopyLen(U8 *dst, U8 *src, I64 len, I64 cap)
{
  if (cap <= 0) return;
  if (src == NULL || len <= 0) {
    dst[0] = 0;
    return;
  }
  I64 n = len;
  if (n > cap - 1) n = cap - 1;
  MemCpy(dst, src, n);
  dst[n] = 0;
}

Bool StrCaseEqLen(U8 *a, U8 *b, I64 len)
{
  for (I64 i = 0; i < len; i++) {
    U8 ca = a[i];
    U8 cb = b[i];
    if (ca == 0 || cb == 0) return ca == cb;
    if (ca >= 'A' && ca <= 'Z') ca += 32;
    if (cb >= 'A' && cb <= 'Z') cb += 32;
    if (ca != cb) return FALSE;
  }
  return TRUE;
}

Bool StartsWithIgnoreCase(U8 *s, U8 *prefix)
{
  if (s == NULL || prefix == NULL) return FALSE;
  I64 plen = StrLen(prefix);
  if (StrLen(s) < plen) return FALSE;
  return StrCaseEqLen(s, prefix, plen);
}

Bool ContainsIgnoreCaseAscii(U8 *hay, U8 *needle)
{
  if (hay == NULL || needle == NULL || needle[0] == 0) return FALSE;
  I64 nlen = StrLen(needle);
  I64 hlen = StrLen(hay);
  for (I64 i = 0; i + nlen <= hlen; i++) {
    if (StrCaseEqLen(hay + i, needle, nlen)) return TRUE;
  }
  return FALSE;
}

U8 *FindHeaderIgnoreCase(U8 *headers, I64 headers_len, U8 *key)
{
  I64 klen = StrLen(key);
  I64 i = 0;
  while (i + klen <= headers_len) {
    if (i == 0 || headers[i - 1] == '\n') {
      if (StrCaseEqLen(headers + i, key, klen) && headers[i + klen] == ':') {
        I64 v = i + klen + 1;
        while (v < headers_len && (headers[v] == ' ' || headers[v] == '\t'))
          v++;
        return headers + v;
      }
    }
    i++;
  }
  return NULL;
}

U0 ExtractHeaderLine(U8 *val_start, U8 *out, I64 out_cap)
{
  if (val_start == NULL) {
    out[0] = 0;
    return;
  }
  I64 i = 0;
  while (i < out_cap - 1 && val_start[i] != 0 &&
         val_start[i] != '\r' && val_start[i] != '\n') {
    out[i] = val_start[i];
    i++;
  }
  out[i] = 0;
}

U0 UrlParse(U8 *raw, ParsedUrl *u)
{
  MemSet(u, 0, sizeof(ParsedUrl));
  if (raw == NULL) {
    SafeCopy(u->scheme, "temple", 16);
    SafeCopy(u->host, "home", 256);
    SafeCopy(u->path, "/", 1024);
    return;
  }

  U8 *p = raw;
  while (*p && IsSpace(*p)) p++;
  if (*p == 0) {
    SafeCopy(u->scheme, "temple", 16);
    SafeCopy(u->host, "home", 256);
    SafeCopy(u->path, "/", 1024);
    return;
  }

  /* Локальный путь без схемы (/path/to/file.html, ~/file.html или ./demo.html) */
  if (p[0] == '~' && p[1] == '/') {
    U8 *home = getenv("HOME");
    if (home == NULL || home[0] == 0) home = "/home/user";
    SafeCopy(u->scheme, "file", 16);
    SafeCopy(u->host, "", 256);
    snprintf(u->path, 1024, "%s/%s", home, p + 2);
    return;
  }
  if (p[0] == '/' || (p[0] == '.' && p[1] == '/')) {
    SafeCopy(u->scheme, "file", 16);
    SafeCopy(u->host, "", 256);
    SafeCopy(u->path, p, 1024);
    return;
  }

  U8 *scheme_end = strstr(p, "://");
  U8 normalized[1024];
  if (scheme_end == NULL) {
    snprintf(normalized, sizeof(normalized), "https://%s", p);
    p = normalized;
    scheme_end = strstr(p, "://");
  }

  I64 slen = scheme_end - p;
  SafeCopyLen(u->scheme, p, slen, 16);
  for (I64 i = 0; u->scheme[i]; i++)
    u->scheme[i] = ToLower(u->scheme[i]);

  /* Обратная совместимость старых ссылок cheb:// -> holy:// (Holynet) */
  if (StrCmp(u->scheme, "cheb") == 0) {
    SafeCopy(u->scheme, "holy", 16);
  }

  U8 *rest = scheme_end + 3;

  if (StrCmp(u->scheme, "file") == 0) {
    SafeCopy(u->host, "", 256);
    if (rest[0] == '/') {
      SafeCopy(u->path, rest, 1024);
    } else {
      snprintf(u->path, 1024, "/%s", rest);
    }
    return;
  }

  if (StrCmp(u->scheme, "temple") == 0 || StrCmp(u->scheme, "holy") == 0) {
    U8 *slash = strchr(rest, '/');
    if (slash) {
      SafeCopyLen(u->host, rest, slash - rest, 256);
      SafeCopy(u->path, slash, 1024);
    } else {
      SafeCopy(u->host, rest, 256);
      SafeCopy(u->path, "/", 1024);
    }
    u->port = 0;
    return;
  }

  /* HTTP / HTTPS */
  u->port = 80;
  if (StrCmp(u->scheme, "https") == 0) u->port = 443;

  U8 *slash = strchr(rest, '/');
  U8 *qmark = strchr(rest, '?');
  U8 *split = slash;
  if (qmark != NULL && (split == NULL || qmark < split))
    split = qmark;

  U8 hostport[300];
  if (split != NULL) {
    SafeCopyLen(hostport, rest, split - rest, sizeof(hostport));
    if (split[0] == '?') {
      snprintf(u->path, 1024, "/%s", split);
    } else {
      SafeCopy(u->path, split, 1024);
    }
  } else {
    SafeCopy(hostport, rest, sizeof(hostport));
    SafeCopy(u->path, "/", 1024);
  }

  /* Отрезаем #fragment из пути для HTTP-запроса */
  U8 *hash = strchr(u->path, '#');
  if (hash != NULL) *hash = 0;
  if (u->path[0] == 0) SafeCopy(u->path, "/", 1024);

  U8 *colon = strchr(hostport, ':');
  if (colon != NULL) {
    SafeCopyLen(u->host, hostport, colon - hostport, 256);
    I64 parsed_port = Atoi(colon + 1);
    if (parsed_port > 0 && parsed_port < 65536) u->port = parsed_port;
  } else {
    SafeCopy(u->host, hostport, 256);
  }
}

U0 UrlFormat(ParsedUrl *u, U8 *out, I64 cap)
{
  if (StrCmp(u->scheme, "file") == 0) {
    snprintf(out, cap, "file://%s", u->path);
  } else if (StrCmp(u->scheme, "temple") == 0 || StrCmp(u->scheme, "holy") == 0) {
    if (StrCmp(u->path, "/") == 0 || u->path[0] == 0)
      snprintf(out, cap, "%s://%s", u->scheme, u->host);
    else
      snprintf(out, cap, "%s://%s%s", u->scheme, u->host, u->path);
  } else {
    Bool default_port = (StrCmp(u->scheme, "http") == 0 && u->port == 80) ||
                        (StrCmp(u->scheme, "https") == 0 && u->port == 443);
    if (default_port)
      snprintf(out, cap, "%s://%s%s", u->scheme, u->host, u->path);
    else
      snprintf(out, cap, "%s://%s:%d%s", u->scheme, u->host, u->port, u->path);
  }
}

U0 UrlResolve(U8 *base_str, U8 *href, U8 *out, I64 out_cap)
{
  if (href == NULL || href[0] == 0) {
    SafeCopy(out, base_str, out_cap);
    return;
  }
  U8 *h = href;
  while (*h && IsSpace(*h)) h++;

  if (StartsWithIgnoreCase(h, "javascript:")) {
    SafeCopy(out, h, out_cap);
    return;
  }
  /* Игнорируем mailto:, tel: */
  if (StartsWithIgnoreCase(h, "mailto:") ||
      StartsWithIgnoreCase(h, "tel:")) {
    SafeCopy(out, base_str, out_cap);
    return;
  }

  /* Уже абсолютный URL со схемой */
  if (strstr(h, "://") != NULL) {
    if (StartsWithIgnoreCase(h, "cheb://")) {
      snprintf(out, out_cap, "holy://%s", h + 7);
    } else {
      SafeCopy(out, h, out_cap);
    }
    return;
  }

  ParsedUrl base;
  UrlParse(base_str, &base);

  /* Протоколо-относительный URL: //example.com/path */
  if (h[0] == '/' && h[1] == '/') {
    if (StrCmp(base.scheme, "http") == 0)
      snprintf(out, out_cap, "http:%s", h);
    else
      snprintf(out, out_cap, "https:%s", h);
    return;
  }

  /* Якорь #section — остаёмся на текущей странице */
  if (h[0] == '#') {
    SafeCopy(out, base_str, out_cap);
    return;
  }

  /* Относительно корня хоста: /about */
  if (h[0] == '/') {
    if (StrCmp(base.scheme, "file") == 0) {
      snprintf(out, out_cap, "file://%s", h);
    } else if (StrCmp(base.scheme, "temple") == 0) {
      snprintf(out, out_cap, "temple://%s", h + 1);
    } else {
      SafeCopy(base.path, h, 1024);
      UrlFormat(&base, out, out_cap);
    }
    return;
  }

  /* Относительно текущей директории */
  U8 dir[1024];
  SafeCopy(dir, base.path, sizeof(dir));
  U8 *q = strchr(dir, '?');
  if (q) *q = 0;
  U8 *last_slash = strrchr(dir, '/');
  if (last_slash != NULL) {
    *(last_slash + 1) = 0;
  } else {
    SafeCopy(dir, "/", sizeof(dir));
  }

  U8 combined[1024];
  snprintf(combined, sizeof(combined), "%s%s", dir, h);
  SafeCopy(base.path, combined, 1024);
  UrlFormat(&base, out, out_cap);
}

/* --- Кэшированное разрешение DNS (IPv4) без повторных getaddrinfo на CDN --- */
Bool ResolveHostIpv4Cached(U8 *host, U32 *out_ipv4)
{
  if (host == NULL || host[0] == 0) return FALSE;

  HttpFastLock();
  for (I32 i = 0; i < DNS_CACHE_CAP; i++) {
    if (g_http_fast.dns[i].used &&
        StrCaseEqLen(g_http_fast.dns[i].host, host, StrLen(host) + 1)) {
      *out_ipv4 = g_http_fast.dns[i].ipv4_addr;
      HttpFastUnlock();
      return TRUE;
    }
  }
  HttpFastUnlock();

  LinuxAddrInfo hints, *servinfo = NULL, *ptr;
  MemSet(&hints, 0, sizeof(LinuxAddrInfo));
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;

  if (getaddrinfo(host, NULL, (&hints)(addrinfo *), (&servinfo)(addrinfo **)) != 0 ||
      servinfo == NULL) {
    return FALSE;
  }

  Bool found = FALSE;
  U32 resolved_ip = 0;
  for (ptr = servinfo; ptr != NULL; ptr = ptr->ai_next) {
    if (ptr->ai_addr != NULL && ptr->ai_addrlen >= sizeof(LinuxSockAddrIn)) {
      LinuxSockAddrIn *sin = (ptr->ai_addr)(LinuxSockAddrIn *);
      resolved_ip = sin->sin_addr;
      found = TRUE;
      break;
    }
  }
  freeaddrinfo(servinfo(addrinfo *));

  if (found) {
    HttpFastLock();
    I32 slot = g_http_fast.dns_hand % DNS_CACHE_CAP;
    g_http_fast.dns_hand = (g_http_fast.dns_hand + 1) % DNS_CACHE_CAP;
    g_http_fast.dns[slot].used = TRUE;
    SafeCopy(g_http_fast.dns[slot].host, host, 256);
    g_http_fast.dns[slot].ipv4_addr = resolved_ip;
    HttpFastUnlock();
    *out_ipv4 = resolved_ip;
  }
  return found;
}

U0 EvictDnsCacheHost(U8 *host)
{
  if (host == NULL || host[0] == 0) return;
  HttpFastLock();
  for (I32 i = 0; i < DNS_CACHE_CAP; i++) {
    if (g_http_fast.dns[i].used &&
        StrCaseEqLen(g_http_fast.dns[i].host, host, StrLen(host) + 1)) {
      g_http_fast.dns[i].used = FALSE;
    }
  }
  HttpFastUnlock();
}

/* --- Неблокирующий TCP connect с точным миллисекундным poll() таймаутом --- */
I32 TcpConnectFast(U8 *host, I32 port, I32 connect_ms, I32 rw_ms)
{
  U32 ipv4 = 0;
  if (!ResolveHostIpv4Cached(host, &ipv4)) {
    return -1;
  }

  I32 sockfd = socket(AF_INET, SOCK_STREAM, 0);
  if (sockfd < 0) return -1;

  I32 orig_flags = fcntl(sockfd, LINUX_F_GETFL, 0);
  if (orig_flags < 0) orig_flags = 0;
  fcntl(sockfd, LINUX_F_SETFL, orig_flags | LINUX_O_NONBLOCK);

  LinuxSockAddrIn dst;
  MemSet(&dst, 0, sizeof(LinuxSockAddrIn));
  dst.sin_family = AF_INET;
  dst.sin_port = HttpHtons(port);
  dst.sin_addr = ipv4;

  I32 rc = connect(sockfd, (&dst)(sockaddr *), sizeof(LinuxSockAddrIn));
  if (rc < 0) {
    I32 err = *__errno_location();
    if (err != LINUX_EINPROGRESS) {
      close(sockfd);
      EvictDnsCacheHost(host);
      return -1;
    }

    LinuxPollFd pfd;
    pfd.fd = sockfd;
    pfd.events = LINUX_POLLOUT;
    pfd.revents = 0;
    I32 prc = poll(&pfd, 1, connect_ms);
    if (prc <= 0) {
      close(sockfd);
      return -1;
    }

    I32 so_err = 0;
    U32 slen = sizeof(I32);
    if (getsockopt(sockfd, LINUX_SOL_SOCKET, LINUX_SO_ERROR, &so_err, &slen) < 0 ||
        so_err != 0) {
      close(sockfd);
      EvictDnsCacheHost(host);
      return -1;
    }
  }

  /* Возвращаем блокирующий режим и ставим короткие таймауты чтения/записи */
  fcntl(sockfd, LINUX_F_SETFL, orig_flags);

  LinuxTimeval tv;
  tv.tv_sec = rw_ms / 1000;
  tv.tv_usec = (rw_ms % 1000) * 1000;
  setsockopt(sockfd, LINUX_SOL_SOCKET, LINUX_SO_RCVTIMEO, &tv, sizeof(LinuxTimeval));
  setsockopt(sockfd, LINUX_SOL_SOCKET, LINUX_SO_SNDTIMEO, &tv, sizeof(LinuxTimeval));

  return sockfd;
}

I32 TcpConnectTimeout(U8 *host, I32 port)
{
  return TcpConnectFast(host, port, 3000, 3500);
}

/* Проверка: пришёл ли завершающий чанк 0\r\n\r\n в потоке Transfer-Encoding: chunked */
Bool IsChunkedStreamComplete(U8 *src, I64 src_len)
{
  I64 spos = 0;
  while (spos < src_len) {
    while (spos < src_len && (src[spos] == '\r' || src[spos] == '\n' || src[spos] == ' '))
      spos++;
    if (spos >= src_len) return FALSE;

    I64 chunk_size = 0;
    Bool has_hex = FALSE;
    while (spos < src_len) {
      U8 ch = src[spos];
      I64 digit = -1;
      if (ch >= '0' && ch <= '9') digit = ch - '0';
      else if (ch >= 'a' && ch <= 'f') digit = 10 + (ch - 'a');
      else if (ch >= 'A' && ch <= 'F') digit = 10 + (ch - 'A');
      else break;
      chunk_size = (chunk_size << 4) | digit;
      has_hex = TRUE;
      spos++;
    }
    if (!has_hex) return FALSE;

    while (spos < src_len && src[spos] != '\n') spos++;
    if (spos >= src_len) return FALSE;
    spos++; /* пропускаем '\n' после размера чанка */

    if (chunk_size == 0) {
      /* Финальный 0-чанк получен! Ждём завершающий пустой перевод строки (\r\n или \n) */
      if (spos < src_len && src[spos] == '\n') return TRUE;
      if (spos + 1 < src_len && src[spos] == '\r' && src[spos + 1] == '\n') return TRUE;
      /* Если есть trailer-заголовки — ищем \r\n\r\n */
      for (I64 t = spos; t + 3 < src_len; t++) {
        if (src[t] == '\r' && src[t + 1] == '\n' &&
            src[t + 2] == '\r' && src[t + 3] == '\n') return TRUE;
      }
      return FALSE;
    }

    if (spos + chunk_size > src_len) return FALSE;
    spos += chunk_size;

    if (spos < src_len && src[spos] == '\r') spos++;
    if (spos >= src_len) return FALSE;
    if (src[spos] == '\n') spos++;
  }
  return FALSE;
}

/* --- Декодирование HTTP Transfer-Encoding: chunked --- */
U8 *DecodeChunkedBody(U8 *src, I64 src_len, I64 *out_len)
{
  I64 cap = src_len + 16;
  U8 *dst = MAlloc(cap);
  I64 dpos = 0;
  I64 spos = 0;

  while (spos < src_len) {
    while (spos < src_len && (src[spos] == '\r' || src[spos] == '\n' || src[spos] == ' '))
      spos++;
    if (spos >= src_len) break;

    I64 chunk_size = 0;
    Bool has_hex = FALSE;
    while (spos < src_len) {
      U8 ch = src[spos];
      I64 digit = -1;
      if (ch >= '0' && ch <= '9') digit = ch - '0';
      else if (ch >= 'a' && ch <= 'f') digit = 10 + (ch - 'a');
      else if (ch >= 'A' && ch <= 'F') digit = 10 + (ch - 'A');
      else break;
      chunk_size = (chunk_size << 4) | digit;
      has_hex = TRUE;
      spos++;
    }
    if (!has_hex) break;

    while (spos < src_len && src[spos] != '\n') spos++;
    if (spos < src_len && src[spos] == '\n') spos++;

    if (chunk_size <= 0) break;
    if (spos + chunk_size > src_len) chunk_size = src_len - spos;

    if (dpos + chunk_size + 1 > cap) {
      cap = (dpos + chunk_size + 1) * 2;
      dst = ReAlloc(dst, cap);
    }
    MemCpy(dst + dpos, src + spos, chunk_size);
    dpos += chunk_size;
    spos += chunk_size;

    if (spos < src_len && src[spos] == '\r') spos++;
    if (spos < src_len && src[spos] == '\n') spos++;
  }

  dst[dpos] = 0;
  *out_len = dpos;
  return dst;
}

/* --- Мгновенная распаковка Content-Encoding: gzip через системную zlib (libz) --- */
U8 *DecompressGzipAlloc(U8 *src, I64 src_len, I64 *out_len)
{
  *out_len = 0;
  if (src == NULL || src_len <= 0) return NULL;

  U8 tmp_gz[128];
  SafeCopy(tmp_gz, "/tmp/divineweb_gz_XXXXXX", sizeof(tmp_gz));
  I32 fd = mkstemp(tmp_gz);
  if (fd < 0) return NULL;
  I64 wr = write(fd, src, src_len);
  close(fd);
  if (wr != src_len) {
    unlink(tmp_gz);
    return NULL;
  }

  U0 *gz = gzopen(tmp_gz, "rb");
  if (gz == NULL) {
    unlink(tmp_gz);
    return NULL;
  }

  I64 cap = src_len * 4 + 4096;
  if (cap < 65536) cap = 65536;
  U8 *dst = MAlloc(cap);
  I64 total = 0;

  while (TRUE) {
    if (total + 32768 + 1 > cap) {
      if (cap >= 12 * 1024 * 1024) break;
      cap *= 2;
      dst = ReAlloc(dst, cap);
    }
    I32 n = gzread(gz, dst + total, 32768);
    if (n <= 0) break;
    total += n;
  }
  gzclose(gz);
  unlink(tmp_gz);

  if (total <= 0) {
    Free(dst);
    return NULL;
  }
  dst[total] = 0;
  *out_len = total;
  return dst;
}

/* --- Быстрое сжатие буфера в Gzip (libz) для глобальной P2P-передачи сайтов --- */
U8 *CompressGzipAlloc(U8 *src, I64 src_len, I64 *out_len)
{
  *out_len = 0;
  if (src == NULL || src_len <= 0) return NULL;

  U8 tmp_gz[128];
  SafeCopy(tmp_gz, "/tmp/divineweb_cgz_XXXXXX", sizeof(tmp_gz));
  I32 tmp_fd = mkstemp(tmp_gz);
  if (tmp_fd < 0) return NULL;
  close(tmp_fd);
  U0 *gz = gzopen(tmp_gz, "wb6");
  if (gz == NULL) { unlink(tmp_gz); return NULL; }

  I64 off = 0;
  while (off < src_len) {
    I64 chunk = src_len - off;
    if (chunk > 65536) chunk = 65536;
    I32 wr = gzwrite(gz, src + off, chunk);
    if (wr <= 0) {
      gzclose(gz);
      unlink(tmp_gz);
      return NULL;
    }
    off += wr;
  }
  gzclose(gz);

  I64 fsz = 0;
  U8 *data = FileRead(tmp_gz, &fsz);
  unlink(tmp_gz);
  if (data == NULL || fsz <= 0) {
    if (data != NULL) Free(data);
    return NULL;
  }
  *out_len = fsz;
  return data;
}

I64 ParseContentLengthVal(U8 *hdr_val)
{
  if (hdr_val == NULL) return -1;
  I64 v = 0;
  Bool any = FALSE;
  I64 i = 0;
  while (hdr_val[i] >= '0' && hdr_val[i] <= '9') {
    v = v * 10 + (hdr_val[i] - '0');
    any = TRUE;
    i++;
  }
  if (!any) return -1;
  return v;
}

/* --- Генератор встроенных страниц temple:// --- */
U8 *BuildTempleBuiltinPage(U8 *page_name, I64 *out_len)
{
  U8 *html = NULL;
  if (StrCmp(page_name, "about") == 0) {
    html = StrNew(
      "<!DOCTYPE html><html><head><title>О браузере DivineWeb (HolyC)</title></head><body>"
      "<h1>О браузере DivineWeb v2.0</h1>"
      "<p><b>DivineWeb</b> — графический 2D веб-браузер, целиком написанный на языке "
      "<b>HolyC</b> (созданном Терри Дэвисом для <i>TempleOS</i>) и скомпилированный "
      "в нативный машинный код Linux x86_64 компилятором <code>hcc</code> (holyc-lang).</p>"
      "<h2>Архитектура модулей</h2>"
      "<ul>"
      "<li><b>bindings.HH</b> — прямые <code>extern \"c\"</code> привязки к X11, Cairo, GdkPixbuf, zlib и OpenSSL.</li>"
      "<li><b>url_http.HC</b> — быстрый клиент HTTP/1.1 + TLS с DNS-кэшем, <code>gzip</code>, <code>chunked</code> и точным <code>Content-Length</code>.</li>"
      "<li><b>image_loader.HC</b> — многопоточная параллельная загрузка картинок <code>&lt;img&gt;</code> без блокировки чтения страницы.</li>"
      "<li><b>html_dom.HC</b> — лексер HTML, таблицы <code>&lt;table&gt;</code>, декодер UTF-8 сущностей и модель документа.</li>"
      "<li><b>layout_render.HC</b> — 2D Layout Engine с масштабированием, 4 темами (включая 16-цветное «Одобрение Дэвиса») и вкладками.</li>"
      "<li><b>holynet_p2p.HC</b> — встроенная глобальная P2P-сеть <b>Holynet (Холинет)</b> по протоколу <code>HOLY/1.0_DIVINE_MESH</code>.</li>"
      "</ul>"
      "<blockquote>«An idiot admires complexity, a genius admires simplicity.» — Terry A. Davis</blockquote>"
      "<hr>"
      "<p><a href=\"temple://home\">&larr; Вернуться на стартовую страницу (temple://home)</a> | "
      "<a href=\"holy://home\">Войти в P2P-сеть Холинет (holy://home)</a> | "
      "<a href=\"file:///home/user/holy-browser/demo.html\">Локальное демо (demo.html)</a></p>"
      "</body></html>"
    );
  } else {
    html = StrNew(
      "<!DOCTYPE html><html><head><title>DivineWeb — Браузер на HolyC</title></head><body>"
      "<h1>DivineWeb Browser на языке HolyC</h1>"
      "<p>Добро пожаловать в <b>DivineWeb v2.0</b> — быстрый графический 2D-браузер, "
      "написанный на <b>HolyC</b> под Linux! Поддерживаются протоколы <code>https://</code>, "
      "<code>http://</code>, <code>file://</code>, внутренние страницы <code>temple://</code> "
      "и суверенная P2P-сеть <b>Holynet (Холинет, <code>holy://</code>)</b>.</p>"
      "<blockquote>«Бог сказал, что храм должен быть в разрешении 640x480 и 16 цветах!» — включите тему <b>Дэвис 16c</b> в правом верхнем углу!</blockquote>"
      "<h2>Быстрые ссылки (кликните мышью)</h2>"
      "<ul>"
      "<li><a href=\"holy://home\">Войти в P2P-сеть Holynet / Холинет (holy://home)</a></li>"
      "<li><a href=\"file:///home/user/holy-browser/demo.html\">Локальная демонстрационная страница (demo.html — все возможности HTML)</a></li>"
      "<li><a href=\"temple://about\">Архитектура браузера и горячие клавиши (temple://about)</a></li>"
      "<li><a href=\"https://example.com\">Example Domain по защищённому HTTPS (https://example.com)</a></li>"
      "<li><a href=\"https://en.wikipedia.org/wiki/TempleOS\">Статья TempleOS в Wikipedia (HTTPS + Gzip + параллельные картинки)</a></li>"
      "</ul>"
      "<h2>Пример кода на HolyC прямо в браузере</h2>"
      "<pre>"
      "U0 DivineGreeting(I64 count = 3)\n"
      "{\n"
      "  for (I64 i = 0; i &lt; count; i++) {\n"
      "    \"[%d] Слава простоте HolyC и сети Holynet!\\n\", i + 1;\n"
      "  }\n"
      "}\n"
      "DivineGreeting;"
      "</pre>"
      "</body></html>"
    );
  }
  *out_len = StrLen(html);
  return html;
}

U8 *BuildErrorPage(U8 *url, U8 *reason, I64 *out_len)
{
  U8 *buf = MAlloc(2048);
  snprintf(buf, 2048,
    "<!DOCTYPE html><html><head><title>Ошибка загрузки — DivineWeb</title></head><body>"
    "<h1>Не удалось открыть страницу</h1>"
    "<p>При обращении к адресу <code>%s</code> произошла ошибка:</p>"
    "<blockquote><b>%s</b></blockquote>"
    "<h3>Что можно проверить:</h3>"
    "<ul>"
    "<li>Проверьте правильность написания домена или пути к локальному файлу.</li>"
    "<li>Перейдите на <a href=\"temple://home\">стартовую страницу (temple://home)</a> или в <a href=\"holy://home\">P2P-сеть Холинет (holy://home)</a>.</li>"
    "<li>Откройте локальную тестовую страницу <a href=\"file:///home/user/holy-browser/demo.html\">demo.html</a>.</li>"
    "</ul>"
    "</body></html>",
    url, reason);
  *out_len = StrLen(buf);
  return buf;
}

U0 HttpResponseFree(HttpResponse *resp)
{
  if (resp->body != NULL) {
    Free(resp->body);
    resp->body = NULL;
  }
  resp->body_len = 0;
}

/* Поиск конца HTTP-заголовков (\r\n\r\n или \n\n) */
I64 FindHttpHeaderEnd(U8 *buf, I64 len, I64 *out_body_off)
{
  for (I64 i = 0; i + 3 < len; i++) {
    if (buf[i] == '\r' && buf[i + 1] == '\n' &&
        buf[i + 2] == '\r' && buf[i + 3] == '\n') {
      *out_body_off = i + 4;
      return i;
    }
  }
  for (I64 i = 0; i + 1 < len; i++) {
    if (buf[i] == '\n' && buf[i + 1] == '\n') {
      *out_body_off = i + 2;
      return i;
    }
  }
  *out_body_off = 0;
  return -1;
}

/* --- Быстрая загрузка URL (is_subresource=TRUE ставит короткие таймауты для <img>) --- */
Bool FetchUrlFast(U8 *initial_url, HttpResponse *resp, Bool is_subresource)
{
  EnsureHttpGlobals();
  MemSet(resp, 0, sizeof(HttpResponse));
  SafeCopy(resp->final_url, initial_url, sizeof(resp->final_url));
  SafeCopy(resp->content_type, "text/html", sizeof(resp->content_type));

  I32 connect_ms = 2500;
  I32 rw_ms = 3000;
  I64 max_body_limit = 8 * 1024 * 1024;
  I64 max_redirects = 6;
  if (is_subresource) {
    connect_ms = 750;
    rw_ms = 900;
    max_body_limit = 768 * 1024;
    max_redirects = 2;
  }

  U8 current_url[1024];
  SafeCopy(current_url, initial_url, sizeof(current_url));

  for (I64 redirect_hop = 0; redirect_hop < max_redirects; redirect_hop++) {
    ParsedUrl u;
    UrlParse(current_url, &u);
    UrlFormat(&u, resp->final_url, sizeof(resp->final_url));

    /* 1. Встроенные страницы temple:// */
    if (StrCmp(u.scheme, "temple") == 0) {
      resp->status_code = 200;
      resp->body = BuildTempleBuiltinPage(u.host, &resp->body_len);
      return TRUE;
    }

    /* 2. Локальные файлы file:// */
    if (StrCmp(u.scheme, "file") == 0) {
      I64 fsize = 0;
      U8 *data = FileRead(u.path, &fsize);
      if (data == NULL) {
        resp->status_code = 404;
        snprintf(resp->error, sizeof(resp->error), "Файл не найден: %s", u.path);
        if (!is_subresource) {
          resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
        }
        return FALSE;
      }
      resp->status_code = 200;
      resp->body = data;
      resp->body_len = fsize;
      return TRUE;
    }

    /* 3. Сеть: HTTP / HTTPS */
    Bool use_tls = (StrCmp(u.scheme, "https") == 0);
    if (!use_tls && StrCmp(u.scheme, "http") != 0) {
      resp->status_code = 400;
      snprintf(resp->error, sizeof(resp->error), "Неподдерживаемый протокол: %s", u.scheme);
      if (!is_subresource) {
        resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
      }
      return FALSE;
    }

    I32 sock = TcpConnectFast(u.host, u.port, connect_ms, rw_ms);
    if (sock < 0) {
      resp->status_code = 502;
      snprintf(resp->error, sizeof(resp->error),
               "Не удалось подключиться к серверу %s:%d (DNS или таймаут сети)", u.host, u.port);
      if (!is_subresource) {
        resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
      }
      return FALSE;
    }

    U0 *ssl = NULL;
    if (use_tls) {
      if (g_http_fast.ssl_ctx == NULL) {
        close(sock);
        resp->status_code = 500;
        SafeCopy(resp->error, "Ошибка контекста OpenSSL TLS", sizeof(resp->error));
        if (!is_subresource) {
          resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
        }
        return FALSE;
      }
      ssl = SSL_new(g_http_fast.ssl_ctx);
      if (ssl == NULL || SSL_set_fd(ssl, sock) != 1 || !SecureTlsSetHost(ssl, u.host) || SSL_connect(ssl) <= 0) {
        if (ssl != NULL) SSL_free(ssl);
        close(sock);
        resp->status_code = 525;
        snprintf(resp->error, sizeof(resp->error), "Ошибка рукопожатия TLS/SSL с хостом %s", u.host);
        if (!is_subresource) {
          resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
        }
        return FALSE;
      }
    }

    U8 req[2048];
    if (is_subresource) {
      snprintf(req, sizeof(req),
        "GET %s HTTP/1.1\r\n"
        "Host: %s\r\n"
        "User-Agent: Mozilla/5.0 DivineWeb/2.0 (HolyC; Linux x86_64)\r\n"
        "Accept: image/webp,image/png,image/svg+xml,image/*;q=0.9,*/*;q=0.5\r\n"
        "Accept-Encoding: identity\r\n"
        "Connection: close\r\n\r\n",
        u.path, u.host);
    } else {
      snprintf(req, sizeof(req),
        "GET %s HTTP/1.1\r\n"
        "Host: %s\r\n"
        "User-Agent: Mozilla/5.0 DivineWeb/2.0 (HolyC; Linux x86_64)\r\n"
        "Accept: text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5\r\n"
        "Accept-Encoding: gzip, identity\r\n"
        "Connection: close\r\n\r\n",
        u.path, u.host);
    }

    I64 req_len = StrLen(req);
    I64 sent = 0;
    if (use_tls) sent = SSL_write(ssl, req, req_len);
    else sent = send(sock, req, req_len, 0);

    if (sent <= 0) {
      if (use_tls) SSL_free(ssl);
      close(sock);
      resp->status_code = 502;
      SafeCopy(resp->error, "Ошибка отправки HTTP-запроса", sizeof(resp->error));
      if (!is_subresource) {
        resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
      }
      return FALSE;
    }

    I64 raw_cap = 65536;
    I64 raw_len = 0;
    U8 *raw_buf = MAlloc(raw_cap);

    Bool hdr_parsed = FALSE;
    I64  hdr_end = -1;
    I64  body_offset = 0;
    I32  parsed_status = 200;
    I64  expected_clen = -1;
    Bool is_chunked = FALSE;
    Bool is_redirect = FALSE;

    while (TRUE) {
      if (raw_len + 32768 + 1 > raw_cap) {
        if (raw_cap >= max_body_limit) break;
        raw_cap *= 2;
        raw_buf = ReAlloc(raw_buf, raw_cap);
      }
      I64 n = 0;
      if (use_tls) n = SSL_read(ssl, raw_buf + raw_len, 32768);
      else n = recv(sock, raw_buf + raw_len, 32768, 0);
      if (n <= 0) break;
      raw_len += n;
      raw_buf[raw_len] = 0;

      /* Как только прилетели заголовки — сразу узнаём длину ответа, не ждём закрытия сокета! */
      if (!hdr_parsed) {
        hdr_end = FindHttpHeaderEnd(raw_buf, raw_len, &body_offset);
        if (hdr_end >= 0) {
          hdr_parsed = TRUE;
          U8 *sp = memchr(raw_buf, ' ', hdr_end);
          if (sp != NULL) {
            while (sp < raw_buf + hdr_end && *sp == ' ') sp++;
            parsed_status = Atoi(sp);
          }
          if (parsed_status == 301 || parsed_status == 302 ||
              parsed_status == 303 || parsed_status == 307 || parsed_status == 308) {
            is_redirect = TRUE;
            break;
          }
          if (parsed_status == 204 || parsed_status == 304) {
            expected_clen = 0;
            break;
          }
          U8 *cl_hdr = FindHeaderIgnoreCase(raw_buf, hdr_end, "Content-Length");
          if (cl_hdr != NULL) {
            expected_clen = ParseContentLengthVal(cl_hdr);
          }
          U8 *te_hdr = FindHeaderIgnoreCase(raw_buf, hdr_end, "Transfer-Encoding");
          if (te_hdr != NULL) {
            U8 te_line[128];
            ExtractHeaderLine(te_hdr, te_line, sizeof(te_line));
            if (ContainsIgnoreCaseAscii(te_line, "chunked")) is_chunked = TRUE;
          }
        }
      }

      if (hdr_parsed) {
        I64 have_body = raw_len - body_offset;
        if (expected_clen >= 0 && have_body >= expected_clen) {
          break;
        }
        if (is_chunked && have_body >= 5) {
          if (IsChunkedStreamComplete(raw_buf + body_offset, have_body)) {
            break;
          }
        }
      }
    }

    if (use_tls) SSL_free(ssl);
    close(sock);

    if (raw_len == 0) {
      Free(raw_buf);
      resp->status_code = 502;
      SafeCopy(resp->error, "Сервер закрыл соединение, не прислав ответа", sizeof(resp->error));
      if (!is_subresource) {
        resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
      }
      return FALSE;
    }

    if (!hdr_parsed) {
      hdr_end = FindHttpHeaderEnd(raw_buf, raw_len, &body_offset);
    }

    if (hdr_end < 0) {
      resp->status_code = 200;
      resp->body = raw_buf;
      resp->body_len = raw_len;
      return TRUE;
    }

    resp->status_code = parsed_status;

    U8 *ct_hdr = FindHeaderIgnoreCase(raw_buf, hdr_end, "Content-Type");
    if (ct_hdr != NULL) ExtractHeaderLine(ct_hdr, resp->content_type, sizeof(resp->content_type));

    /* Мгновенный переход по HTTP-редиректу 301 / 302 / 303 / 307 / 308 */
    if (is_subresource != 2 && (is_redirect || resp->status_code == 301 || resp->status_code == 302 ||
        resp->status_code == 303 || resp->status_code == 307 || resp->status_code == 308)) {
      U8 *loc_hdr = FindHeaderIgnoreCase(raw_buf, hdr_end, "Location");
      if (loc_hdr != NULL) {
        U8 loc_val[1024];
        ExtractHeaderLine(loc_hdr, loc_val, sizeof(loc_val));
        U8 next_url[1024];
        UrlResolve(resp->final_url, loc_val, next_url, sizeof(next_url));
        SafeCopy(current_url, next_url, sizeof(current_url));
        Free(raw_buf);
        continue;
      }
    }

    /* Декодируем тело: обычное или chunked */
    I64 raw_body_len = raw_len - body_offset;
    if (expected_clen >= 0 && raw_body_len > expected_clen) {
      raw_body_len = expected_clen;
    }

    U8 *decoded_body = NULL;
    I64 decoded_len = 0;

    if (is_chunked) {
      decoded_body = DecodeChunkedBody(raw_buf + body_offset, raw_body_len, &decoded_len);
    } else {
      decoded_body = MAlloc(raw_body_len + 1);
      if (raw_body_len > 0) MemCpy(decoded_body, raw_buf + body_offset, raw_body_len);
      decoded_body[raw_body_len] = 0;
      decoded_len = raw_body_len;
    }

    /* Проверяем Content-Encoding: gzip (или сигнатуру 0x1F 0x8B) */
    U8 *ce_hdr = FindHeaderIgnoreCase(raw_buf, hdr_end, "Content-Encoding");
    U8 ce_val[64];
    ExtractHeaderLine(ce_hdr, ce_val, sizeof(ce_val));
    Free(raw_buf);

    Bool is_gzip = ContainsIgnoreCaseAscii(ce_val, "gzip");
    if (!is_gzip && decoded_len >= 2) {
      if ((decoded_body[0] & 0xFF) == 0x1F && (decoded_body[1] & 0xFF) == 0x8B) {
        is_gzip = TRUE;
      }
    }

    if (is_gzip && decoded_len > 0) {
      I64 unz_len = 0;
      U8 *unz = DecompressGzipAlloc(decoded_body, decoded_len, &unz_len);
      if (unz != NULL && unz_len > 0) {
        Free(decoded_body);
        resp->body = unz;
        resp->body_len = unz_len;
        return TRUE;
      }
    }

    resp->body = decoded_body;
    resp->body_len = decoded_len;
    return TRUE;
  }

  resp->status_code = 310;
  SafeCopy(resp->error, "Слишком много перенаправлений (HTTP Redirect Loop)", sizeof(resp->error));
  if (!is_subresource) {
    resp->body = BuildErrorPage(resp->final_url, resp->error, &resp->body_len);
  }
  return FALSE;
}

Bool FetchUrl(U8 *initial_url, HttpResponse *resp)
{
  return FetchUrlFast(initial_url, resp, FALSE);
}
