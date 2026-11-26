/* ============================================================================
 * image_loader.HC — Декодер растровых/векторных изображений и параллельная
 * многопоточная догрузка картинок (для WWW и P2P-сети Holynet / Холинет)
 * ============================================================================ */

U0 *DecodeBytesToCairoSurface(U8 *bytes, I64 len, I32 *out_w, I32 *out_h)
{
  *out_w = 0;
  *out_h = 0;
  if (bytes == NULL || len <= 4 || len > 8 * 1024 * 1024) return NULL;

  U8 tmp_path[128];
  SafeCopy(tmp_path, "/tmp/divineweb_img_XXXXXX", sizeof(tmp_path));
  I32 fd = mkstemp(tmp_path); /* exclusive, random filename and 0600 */
  if (fd < 0) return NULL;
  I64 wr = write(fd, bytes, len);
  close(fd);
  if (wr != len) {
    unlink(tmp_path);
    return NULL;
  }

  U0 *gerr = NULL;
  U0 *pixbuf = gdk_pixbuf_new_from_file(tmp_path, &gerr);
  unlink(tmp_path);
  if (pixbuf == NULL) return NULL;

  I32 w = gdk_pixbuf_get_width(pixbuf);
  I32 h = gdk_pixbuf_get_height(pixbuf);
  I32 src_stride = gdk_pixbuf_get_rowstride(pixbuf);
  I32 n_chan = gdk_pixbuf_get_n_channels(pixbuf);
  U8 *src_px = gdk_pixbuf_get_pixels(pixbuf);

  if (w <= 0 || h <= 0 || w > 4096 || h > 4096 || src_px == NULL || (n_chan != 3 && n_chan != 4)) {
    g_object_unref(pixbuf);
    return NULL;
  }

  U0 *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  if (surf == NULL) {
    g_object_unref(pixbuf);
    return NULL;
  }

  cairo_surface_flush(surf);
  U8 *dst_base = cairo_image_surface_get_data(surf);
  I32 dst_stride = cairo_image_surface_get_stride(surf);

  if (dst_base != NULL) {
    for (I32 y = 0; y < h; y++) {
      U8  *srow = src_px + y * src_stride;
      U32 *drow = (dst_base + y * dst_stride)(U32 *);
      for (I32 x = 0; x < w; x++) {
        U32 r = srow[x * n_chan + 0];
        U32 g = srow[x * n_chan + 1];
        U32 b = srow[x * n_chan + 2];
        U32 a = 255;
        if (n_chan == 4) a = srow[x * 4 + 3];

        /* Премультипликация альфа-канала для CAIRO_FORMAT_ARGB32 (BGRA в памяти x86_64) */
        if (a == 0) {
          drow[x] = 0;
        } else if (a == 255) {
          drow[x] = (0xFF000000) | (r << 16) | (g << 8) | b;
        } else {
          U32 rp = (r * a + 127) / 255;
          U32 gp = (g * a + 127) / 255;
          U32 bp = (b * a + 127) / 255;
          drow[x] = (a << 24) | (rp << 16) | (gp << 8) | bp;
        }
      }
    }
    cairo_surface_mark_dirty(surf);
  }

  g_object_unref(pixbuf);
  *out_w = w;
  *out_h = h;
  return surf;
}

/* Простая %XX декодировка для data:image/svg+xml,... URI */
I64 DecodePercentUriBytes(U8 *src, U8 *dst, I64 cap)
{
  I64 o = 0;
  I64 i = 0;
  while (src[i] && o + 1 < cap) {
    if (src[i] == '%' && src[i + 1] && src[i + 2]) {
      U8 c1 = src[i + 1];
      U8 c2 = src[i + 2];
      I32 hi = -1;
      I32 lo = -1;
      if (c1 >= '0' && c1 <= '9') hi = c1 - '0';
      else if (c1 >= 'a' && c1 <= 'f') hi = c1 - 'a' + 10;
      else if (c1 >= 'A' && c1 <= 'F') hi = c1 - 'A' + 10;
      if (c2 >= '0' && c2 <= '9') lo = c2 - '0';
      else if (c2 >= 'a' && c2 <= 'f') lo = c2 - 'a' + 10;
      else if (c2 >= 'A' && c2 <= 'F') lo = c2 - 'A' + 10;
      if (hi >= 0 && lo >= 0) {
        dst[o++] = (hi << 4) | lo;
        i += 3;
        continue;
      }
    }
    dst[o++] = src[i++];
  }
  dst[o] = 0;
  return o;
}

/* Декодирование Base64 (для встроенных картинок data:image/png;base64,... в HTML Холинета) */
I32 Base64Val(U8 c)
{
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

I64 DecodeBase64Bytes(U8 *src, U8 *dst, I64 cap)
{
  I64 o = 0;
  I32 acc = 0;
  I32 bits = 0;
  for (I64 i = 0; src[i] != 0 && o + 4 < cap; i++) {
    if (src[i] == '=') break;
    I32 v = Base64Val(src[i]);
    if (v < 0) continue;
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      dst[o++] = (acc >> bits) & 0xFF;
    }
  }
  return o;
}

/* Фильтр рекламных счётчиков и 1x1 пикселей слежения, тормозящих загрузку страниц */
Bool IsTrackerBeaconUrl(U8 *url)
{
  if (url == NULL) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "mc.yandex.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "an.yandex.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "counter.yadro.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "top-fwz1.mail.ru")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "top100.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "rambler.ru/top100")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "vk.com/rtrg")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "tns-counter.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "google-analytics.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "googletagmanager.")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "doubleclick.net")) return TRUE;
  if (ContainsIgnoreCaseAscii(url, "adriver.ru")) return TRUE;
  return FALSE;
}

/* Загрузка локального изображения (data:image/* или file://) без сетевых задержек */
/* Holynet embeds may contain images, but must not let SVG/XML refer to local
 * files or network resources through librsvg. This is a conservative filter,
 * not a replacement for a sandbox. */
Bool SafeHolynetEmbeddedImage(U8 *src)
{
  if (!StartsWithIgnoreCase(src, "data:image/")) return FALSE;
  U8 *comma = strchr(src, ',');
  if (comma == NULL) return FALSE;
  I64 hdr_len = comma - src;
  Bool b64 = FALSE;
  for (I64 k = 0; k + 7 <= hdr_len; k++) if (StrCaseEqLen(src + k, ";base64", 7)) b64 = TRUE;
  I64 n = StrLen(comma + 1);
  if (n <= 0 || n > 4 * 1024 * 1024) return FALSE;
  U8 *data = MAlloc(n + 8);
  I64 len = 0;
  if (b64) len = DecodeBase64Bytes(comma + 1, data, n + 4);
  else len = DecodePercentUriBytes(comma + 1, data, n + 4);
  data[len] = 0;
  Bool safe = FALSE;
  if (len >= 8 && data[0] == 0x89 && StrNCmp(data + 1, "PNG", 3) == 0) safe = TRUE;
  if (len >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff) safe = TRUE;
  if (len >= 6 && (StrNCmp(data, "GIF87a", 6) == 0 || StrNCmp(data, "GIF89a", 6) == 0)) safe = TRUE;
  if (len >= 12 && StrNCmp(data, "RIFF", 4) == 0 && StrNCmp(data + 8, "WEBP", 4) == 0) safe = TRUE;
  I64 p = 0;
  while (p < len && IsSpace(data[p])) p++;
  if (p + 4 < len && StrCaseEqLen(data + p, "<svg", 4)) {
    safe = TRUE;
    for (I64 j = p; j < len; j++) {
      if (data[j] == 0 || data[j] == '&' ||
          (j + 2 <= len && StrCaseEqLen(data + j, "<!", 2)) ||
          (j + 2 <= len && StrCaseEqLen(data + j, "<?", 2)) ||
          (j + 4 <= len && StrCaseEqLen(data + j, "href", 4)) ||
          (j + 4 <= len && StrCaseEqLen(data + j, "url(", 4)) ||
          (j + 6 <= len && StrCaseEqLen(data + j, "<image", 6)) ||
          (j + 4 <= len && StrCaseEqLen(data + j, "<use", 4)) ||
          (j + 6 <= len && StrCaseEqLen(data + j, "<style", 6)) ||
          (j + 7 <= len && StrCaseEqLen(data + j, "<script", 7)) ||
          (j + 14 <= len && StrCaseEqLen(data + j, "<foreignobject", 14))) { safe = FALSE; break; }
    }
  }
  Free(data);
  return safe;
}

U0 *LoadLocalImageSurfaceForSrc(U8 *resolved_src, I32 *out_w, I32 *out_h)
{
  *out_w = 0;
  *out_h = 0;
  if (resolved_src == NULL || resolved_src[0] == 0) return NULL;

  if (StartsWithIgnoreCase(resolved_src, "data:image/")) {
    U8 *comma = strchr(resolved_src, ',');
    if (comma != NULL) {
      I64 hdr_len = comma - resolved_src;
      Bool is_b64 = FALSE;
      for (I64 k = 0; k + 7 <= hdr_len; k++) {
        if (StrCaseEqLen(resolved_src + k, ";base64", 7)) {
          is_b64 = TRUE;
          break;
        }
      }
      U8 *payload = comma + 1;
      I64 max_len = StrLen(payload) + 16;
      U8 *decoded = MAlloc(max_len);
      I64 dlen = 0;
      if (is_b64) dlen = DecodeBase64Bytes(payload, decoded, max_len);
      else dlen = DecodePercentUriBytes(payload, decoded, max_len);
      U0 *surf = DecodeBytesToCairoSurface(decoded, dlen, out_w, out_h);
      Free(decoded);
      return surf;
    }
  }

  if (StartsWithIgnoreCase(resolved_src, "file://")) {
    HttpResponse fresp;
    if (FetchUrlFast(resolved_src, &fresp, TRUE) && fresp.body != NULL && fresp.body_len > 0) {
      U0 *surf = DecodeBytesToCairoSurface(fresp.body, fresp.body_len, out_w, out_h);
      HttpResponseFree(&fresp);
      return surf;
    }
    HttpResponseFree(&fresp);
  }

  return NULL;
}

/* Одиночная загрузка изображения (совместимая обёртка) */
U0 *LoadImageSurfaceForSrc(U8 *resolved_src, Bool holynet_mode, I32 *out_w, I32 *out_h)
{
  U0 *local_surf = LoadLocalImageSurfaceForSrc(resolved_src, out_w, out_h);
  if (local_surf != NULL) return local_surf;
  if (holynet_mode) return NULL;

  if ((StartsWithIgnoreCase(resolved_src, "http://") ||
       StartsWithIgnoreCase(resolved_src, "https://")) &&
      !IsTrackerBeaconUrl(resolved_src)) {
    HttpResponse iresp;
    Bool ok = FetchUrlFast(resolved_src, &iresp, TRUE);
    U0 *surf = NULL;
    if (ok && iresp.status_code == 200 && iresp.body != NULL && iresp.body_len > 0) {
      surf = DecodeBytesToCairoSurface(iresp.body, iresp.body_len, out_w, out_h);
    }
    HttpResponseFree(&iresp);
    return surf;
  }
  return NULL;
}

/* Задача параллельного фонового воркера скачивания HTTP/HTTPS-картинки */
class ParallelImgJob
{
  Bool         spawned;
  U8          *url;
  pthread_t   *thread;
  HttpResponse resp;
  Bool         ok;
};

U0 *ImgDownloadWorkerFn(U0 *arg)
{
  ParallelImgJob *job = arg(ParallelImgJob *);
  job->ok = FetchUrlFast(job->url, &job->resp, TRUE);
  return NULL;
}
