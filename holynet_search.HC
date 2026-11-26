/* ============================================================================
 * holynet_search.HC — Полнотекстовый P2P-поисковик по сайтам Холинета
 * Регистронезависимый поиск (UTF-8 Кириллица + ASCII) по заголовкам, доменам,
 * подзаголовкам H1–H3, тексту страниц, блокам кода и ID узлов-владельцев.
 * ============================================================================ */

#define HOLY_SCOPE_ALL    0
#define HOLY_SCOPE_TITLE  1
#define HOLY_SCOPE_DOMAIN 2
#define HOLY_SCOPE_BODY   3

U0 HolyEscapeHtml(U8 *src, U8 *dst, I64 cap)
{
  I64 o = 0;
  if (src == NULL || cap <= 0) {
    if (cap > 0) dst[0] = 0;
    return;
  }
  for (I64 i = 0; src[i] != 0 && o + 8 < cap; i++) {
    U8 c = src[i];
    if (c == '<')      { MemCpy(dst + o, "&lt;", 4);   o += 4; }
    else if (c == '>') { MemCpy(dst + o, "&gt;", 4);   o += 4; }
    else if (c == '&') { MemCpy(dst + o, "&amp;", 5);  o += 5; }
    else if (c == '"') { MemCpy(dst + o, "&quot;", 6); o += 6; }
    else               { dst[o++] = c; }
  }
  dst[o] = 0;
}

I32 HexDigitVal(U8 c)
{
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

/* URL-кодирование UTF-8 строки для безопасной передачи запросов в ?q=... */
U0 UrlEncodeUtf8(U8 *src, U8 *dst, I64 cap)
{
  U8 *hex = "0123456789ABCDEF";
  I64 o = 0;
  if (src == NULL || cap <= 0) {
    if (cap > 0) dst[0] = 0;
    return;
  }
  for (I64 i = 0; src[i] && o + 4 < cap; i++) {
    U8 c = src[i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') {
      dst[o++] = c;
    } else if (c == ' ') {
      dst[o++] = '+';
    } else {
      dst[o++] = '%';
      dst[o++] = hex[(c >> 4) & 0x0F];
      dst[o++] = hex[c & 0x0F];
    }
  }
  dst[o] = 0;
}

/* URL-декодирование (%XX и '+' -> пробел) обратно в чистый UTF-8 */
U0 UrlDecodeUtf8(U8 *src, U8 *dst, I64 cap)
{
  I64 o = 0;
  if (src == NULL || cap <= 0) {
    if (cap > 0) dst[0] = 0;
    return;
  }
  I64 i = 0;
  while (src[i] && o + 1 < cap) {
    if (src[i] == '+') {
      dst[o++] = ' ';
      i++;
    } else if (src[i] == '%' && src[i + 1] && src[i + 2]) {
      I32 hi = HexDigitVal(src[i + 1]);
      I32 lo = HexDigitVal(src[i + 2]);
      if (hi >= 0 && lo >= 0) {
        dst[o++] = (hi << 4) | lo;
        i += 3;
      } else {
        dst[o++] = src[i++];
      }
    } else {
      dst[o++] = src[i++];
    }
  }
  dst[o] = 0;
}

/* Utf8LowerFold определена в layout_render.HC */

/* Подсчёт числа вхождений подстроки needle в haystack */
I32 CountSubstrOccurrences(U8 *haystack, U8 *needle)
{
  if (haystack == NULL || needle == NULL || needle[0] == 0) return 0;
  I64 nlen = StrLen(needle);
  I32 cnt = 0;
  U8 *p = haystack;
  while (TRUE) {
    U8 *hit = strstr(p, needle);
    if (hit == NULL) break;
    cnt++;
    p = hit + nlen;
    if (cnt >= 10) break;
  }
  return cnt;
}

/* Извлечение подзаголовков (H1-H3) и чистого видимого текста из HTML для поискового индекса */
U0 HolyExtractHtmlText(U8 *html, U8 *headings_out, I64 h_cap, U8 *body_out, I64 b_cap)
{
  if (h_cap > 0) headings_out[0] = 0;
  if (b_cap > 0) body_out[0] = 0;
  if (html == NULL) return;

  I64 hi = 0;
  I64 bi = 0;
  Bool in_heading = FALSE;
  Bool last_space_b = TRUE;
  Bool last_space_h = TRUE;

  I64 i = 0;
  while (html[i]) {
    if (html[i] == '<') {
      /* Пропускаем <script> и <style> */
      if (StrCaseEqLen(html + i, "<script", 7)) {
        while (html[i] && !StrCaseEqLen(html + i, "</script", 8)) i++;
      } else if (StrCaseEqLen(html + i, "<style", 6)) {
        while (html[i] && !StrCaseEqLen(html + i, "</style", 7)) i++;
      } else if (StrCaseEqLen(html + i, "<title", 6)) {
        while (html[i] && !StrCaseEqLen(html + i, "</title", 7)) i++;
      } else if (StrCaseEqLen(html + i, "<h1", 3) ||
                 StrCaseEqLen(html + i, "<h2", 3) ||
                 StrCaseEqLen(html + i, "<h3", 3)) {
        in_heading = TRUE;
      } else if (StrCaseEqLen(html + i, "</h1", 4) ||
                 StrCaseEqLen(html + i, "</h2", 4) ||
                 StrCaseEqLen(html + i, "</h3", 4)) {
        in_heading = FALSE;
        if (!last_space_h && hi + 3 < h_cap) {
          headings_out[hi++] = ' ';
          last_space_h = TRUE;
        }
      }
      while (html[i] && html[i] != '>') i++;
      if (html[i] == '>') i++;
      if (!last_space_b && bi + 2 < b_cap) {
        body_out[bi++] = ' ';
        last_space_b = TRUE;
      }
      continue;
    }

    /* Простейшее декодирование популярных сущностей для чистоты сниппета и поиска */
    U8 emit[8];
    I32 elen = 0;
    if (html[i] == '&') {
      if (StrNCmp(html + i, "&laquo;", 7) == 0)      { SafeCopy(emit, "«", 8); elen = StrLen(emit); i += 7; }
      else if (StrNCmp(html + i, "&raquo;", 7) == 0) { SafeCopy(emit, "»", 8); elen = StrLen(emit); i += 7; }
      else if (StrNCmp(html + i, "&mdash;", 7) == 0) { SafeCopy(emit, "—", 8); elen = StrLen(emit); i += 7; }
      else if (StrNCmp(html + i, "&ndash;", 7) == 0) { SafeCopy(emit, "-", 8); elen = 1; i += 7; }
      else if (StrNCmp(html + i, "&nbsp;", 6) == 0)  { SafeCopy(emit, " ", 8); elen = 1; i += 6; }
      else if (StrNCmp(html + i, "&quot;", 6) == 0)  { SafeCopy(emit, "\"", 8); elen = 1; i += 6; }
      else if (StrNCmp(html + i, "&amp;", 5) == 0)   { SafeCopy(emit, "&", 8); elen = 1; i += 5; }
      else if (StrNCmp(html + i, "&lt;", 4) == 0)    { SafeCopy(emit, "<", 8); elen = 1; i += 4; }
      else if (StrNCmp(html + i, "&gt;", 4) == 0)    { SafeCopy(emit, ">", 8); elen = 1; i += 4; }
      else if (StrNCmp(html + i, "&larr;", 6) == 0 || StrNCmp(html + i, "&rarr;", 6) == 0) {
        SafeCopy(emit, " ", 8); elen = 1; i += 6;
      } else {
        emit[0] = html[i++];
        elen = 1;
      }
    } else {
      emit[0] = html[i++];
      elen = 1;
    }

    if (elen == 1 && IsSpace(emit[0])) {
      if (!last_space_b && bi + 2 < b_cap) {
        body_out[bi++] = ' ';
        last_space_b = TRUE;
      }
      if (in_heading && !last_space_h && hi + 2 < h_cap) {
        headings_out[hi++] = ' ';
        last_space_h = TRUE;
      }
    } else {
      for (I32 k = 0; k < elen; k++) {
        if (bi + 2 < b_cap) body_out[bi++] = emit[k];
        if (in_heading && hi + 2 < h_cap) headings_out[hi++] = emit[k];
      }
      last_space_b = FALSE;
      if (in_heading) last_space_h = FALSE;
    }
  }
  headings_out[hi] = 0;
  body_out[bi] = 0;
}

/* Построение аккуратного UTF-8 сниппета текста вокруг первого найденного слова */
U0 HolyBuildContextSnippet(U8 *plain_body, U8 *body_lower, U8 *needle_lower,
                           U8 *out_escaped, I64 out_cap)
{
  out_escaped[0] = 0;
  if (plain_body == NULL || plain_body[0] == 0) return;

  I64 total = StrLen(plain_body);
  I64 start = 0;

  if (needle_lower != NULL && needle_lower[0] != 0 && body_lower != NULL) {
    U8 *hit = strstr(body_lower, needle_lower);
    if (hit != NULL) {
      /* Так как Utf8LowerFold сохраняет побайтовую длину UTF-8 для RU/EN, смещение совпадает! */
      I64 offset = hit - body_lower;
      if (offset > 65 && offset < total) {
        start = offset - 65;
        /* Выравниваем по началу UTF-8 символа (не продолжению 10xxxxxx) */
        while (start > 0 && ((plain_body[start] & 0xC0) == 0x80)) start--;
        /* Сдвигаем до ближайшего пробела для красоты слова */
        I64 sp = start;
        while (sp < offset && plain_body[sp] != ' ' && (sp - start) < 20) sp++;
        if (plain_body[sp] == ' ') start = sp + 1;
      }
    }
  }

  I64 max_bytes = 200;
  I64 end = start + max_bytes;
  if (end >= total) {
    end = total;
  } else {
    while (end > start && ((plain_body[end] & 0xC0) == 0x80)) end--;
    I64 back_sp = end;
    while (back_sp > start + 80 && plain_body[back_sp] != ' ') back_sp--;
    if (plain_body[back_sp] == ' ') end = back_sp;
  }

  U8 raw_slice[260];
  I64 slen = end - start;
  if (slen < 0) slen = 0;
  if (slen > 240) slen = 240;
  MemCpy(raw_slice, plain_body + start, slen);
  raw_slice[slen] = 0;

  U8 esc_slice[520];
  HolyEscapeHtml(raw_slice, esc_slice, sizeof(esc_slice));

  U8 *prefix = "";
  U8 *suffix = "";
  if (start > 0) prefix = "... ";
  if (end < total) suffix = " ...";

  snprintf(out_escaped, out_cap, "%s%s%s", prefix, esc_slice, suffix);
}

class HolySearchHit
{
  I32 site_idx;
  I32 score;
  Bool match_title;
  Bool match_domain;
  Bool match_heading;
  Bool match_body;
  Bool match_owner;
  U8  snippet[560];
};

/* Разбор параметров q=...&scope=... из query-строки поиска */
U0 HolyParseSearchParams(U8 *query_str, U8 *out_q, I64 q_cap, I32 *out_scope)
{
  out_q[0] = 0;
  *out_scope = HOLY_SCOPE_ALL;
  if (query_str == NULL || query_str[0] == 0) return;

  U8 *p = query_str;
  while (*p) {
    U8 *amp = strchr(p, '&');
    I64 seg_len = StrLen(p);
    if (amp != NULL) seg_len = amp - p;

    U8 seg[512];
    SafeCopyLen(seg, p, seg_len, sizeof(seg));

    if (StrNCmp(seg, "q=", 2) == 0) {
      UrlDecodeUtf8(seg + 2, out_q, q_cap);
    } else if (StrNCmp(seg, "scope=", 6) == 0) {
      U8 *sv = seg + 6;
      if (StrCmp(sv, "title") == 0)       *out_scope = HOLY_SCOPE_TITLE;
      else if (StrCmp(sv, "domain") == 0) *out_scope = HOLY_SCOPE_DOMAIN;
      else if (StrCmp(sv, "body") == 0)   *out_scope = HOLY_SCOPE_BODY;
      else                                *out_scope = HOLY_SCOPE_ALL;
    }

    if (amp == NULL) break;
    p = amp + 1;
  }
}

/* Разбивка поискового запроса на отдельные слова (до 8 токенов) */
I32 HolyTokenizeQuery(U8 *lower_q, U8 tok_out[8][96])
{
  I32 cnt = 0;
  U8 *p = lower_q;
  while (*p && cnt < 8) {
    while (*p && IsSpace(*p)) p++;
    if (*p == 0) break;
    I64 k = 0;
    while (*p && !IsSpace(*p) && k < 94) {
      tok_out[cnt][k++] = *p++;
    }
    tok_out[cnt][k] = 0;
    if (k > 0) cnt++;
  }
  return cnt;
}

/* Генерация HTML-страницы Поиска по сайтам Холинета */
U8 *HolyBuildSearchHtml(U8 *raw_query_param, I64 *out_len)
{
  F64 t_start = HolyNowMs();

  U8 query_text[256];
  I32 scope = HOLY_SCOPE_ALL;
  HolyParseSearchParams(raw_query_param, query_text, sizeof(query_text), &scope);

  /* Убираем крайние пробелы */
  U8 *qp = query_text;
  while (*qp && IsSpace(*qp)) qp++;
  U8 clean_q[256];
  SafeCopy(clean_q, qp, sizeof(clean_q));
  I64 qlen = StrLen(clean_q);
  while (qlen > 0 && IsSpace(clean_q[qlen - 1])) {
    clean_q[--qlen] = 0;
  }

  /* Синхронизируемся со всеми живыми P2P-узлами перед поиском! */
  HolySyncNetwork();

  U8 lower_q[256];
  Utf8LowerFold(clean_q, lower_q, sizeof(lower_q));
  U8 tokens[8][96];
  I32 ntok = HolyTokenizeQuery(lower_q, tokens);

  HolySearchHit *hits = CAlloc(HOLY_MAX_SITES * sizeof(HolySearchHit));
  I32 hit_count = 0;

  U8 *headings_buf = MAlloc(4096);
  U8 *headings_low = MAlloc(4096);
  U8 *body_buf     = MAlloc(16384);
  U8 *body_low     = MAlloc(16384);

  HolyLock();
  I32 total_sites = g_holy.site_count;
  I32 online_peers = 0;
  for (I32 pi = 0; pi < g_holy.peer_count; pi++) {
    if (g_holy.peers[pi].used && g_holy.peers[pi].online) online_peers++;
  }

  /* Проход 1: строгий поиск (требуется совпадение всех слов запроса в выбранной области).
   * Если запрос из нескольких слов дал 0 строгих совпадений — проход 2 с мягким ИЛИ! */
  for (I32 pass = 0; pass < 2; pass++) {
    Bool require_all = (pass == 0);
    if (pass == 1 && (hit_count > 0 || ntok <= 1)) break;

    for (I32 i = 0; i < g_holy.site_count; i++) {
      HolySite *s = &g_holy.sites[i];
      if (!s->used) continue;

      HolyExtractHtmlText(s->html, headings_buf, 4096, body_buf, 16384);

      if (ntok == 0) {
        /* Пустой запрос — выводим полный обзорный индекс всех сайтов сети */
        HolySearchHit *h = &hits[hit_count++];
        h->site_idx = i;
        h->score = 10 + s->hits * 5;
        HolyBuildContextSnippet(body_buf, NULL, NULL, h->snippet, sizeof(h->snippet));
        continue;
      }

      U8 title_low[256];
      U8 dom_low[160];
      U8 own_low[96];
      Utf8LowerFold(s->title, title_low, sizeof(title_low));
      Utf8LowerFold(s->domain, dom_low, sizeof(dom_low));
      Utf8LowerFold(s->owner_node, own_low, sizeof(own_low));
      Utf8LowerFold(headings_buf, headings_low, 4096);
      Utf8LowerFold(body_buf, body_low, 16384);

      I32 score = 0;
      I32 matched_tokens = 0;
      Bool m_title = FALSE;
      Bool m_dom   = FALSE;
      Bool m_head  = FALSE;
      Bool m_body  = FALSE;
      Bool m_own   = FALSE;
      U8 *best_body_tok = NULL;

      /* Бонус за точное вхождение всей фразы целиком */
      if ((scope == HOLY_SCOPE_ALL || scope == HOLY_SCOPE_TITLE) && strstr(title_low, lower_q) != NULL) {
        score += 150;
        m_title = TRUE;
      }
      if ((scope == HOLY_SCOPE_ALL || scope == HOLY_SCOPE_DOMAIN) && strstr(dom_low, lower_q) != NULL) {
        score += 120;
        m_dom = TRUE;
      }

      for (I32 t = 0; t < ntok; t++) {
        U8 *tk = tokens[t];
        Bool tok_ok = FALSE;

        if (scope == HOLY_SCOPE_ALL || scope == HOLY_SCOPE_TITLE) {
          I32 tc = CountSubstrOccurrences(title_low, tk);
          if (tc > 0) { score += 85 + tc * 10; m_title = TRUE; tok_ok = TRUE; }

          I32 hc = CountSubstrOccurrences(headings_low, tk);
          if (hc > 0) { score += 55 + hc * 8; m_head = TRUE; tok_ok = TRUE; }
        }

        if (scope == HOLY_SCOPE_ALL || scope == HOLY_SCOPE_DOMAIN) {
          if (strstr(dom_low, tk) != NULL) {
            score += 95;
            if (StrCmp(dom_low, tk) == 0) score += 60;
            m_dom = TRUE;
            tok_ok = TRUE;
          }
        }

        if (scope == HOLY_SCOPE_ALL || scope == HOLY_SCOPE_BODY) {
          I32 bc = CountSubstrOccurrences(body_low, tk);
          if (bc > 0) {
            score += 30 + bc * 6;
            m_body = TRUE;
            tok_ok = TRUE;
            if (best_body_tok == NULL) best_body_tok = tk;
          }
        }

        if (scope == HOLY_SCOPE_ALL) {
          if (strstr(own_low, tk) != NULL) {
            score += 25;
            m_own = TRUE;
            tok_ok = TRUE;
          }
        }

        if (tok_ok) matched_tokens++;
      }

      if ((require_all && matched_tokens == ntok) || (!require_all && matched_tokens > 0)) {
        HolySearchHit *h = &hits[hit_count++];
        h->site_idx = i;
        h->score = score + s->hits * 2;
        h->match_title   = m_title;
        h->match_domain  = m_dom;
        h->match_heading = m_head;
        h->match_body    = m_body;
        h->match_owner   = m_own;
        HolyBuildContextSnippet(body_buf, body_low, best_body_tok, h->snippet, sizeof(h->snippet));
      }
    }
  }

  /* Сортируем результаты по убыванию релевантности (score) */
  for (I32 a = 0; a < hit_count; a++) {
    for (I32 b = a + 1; b < hit_count; b++) {
      if (hits[b].score > hits[a].score) {
        HolySearchHit tmp;
        MemCpy(&tmp, &hits[a], sizeof(HolySearchHit));
        MemCpy(&hits[a], &hits[b], sizeof(HolySearchHit));
        MemCpy(&hits[b], &tmp, sizeof(HolySearchHit));
      }
    }
  }

  F64 elapsed_ms = HolyNowMs() - t_start;

  U8 q_esc[512];
  U8 q_enc[768];
  HolyEscapeHtml(clean_q, q_esc, sizeof(q_esc));
  UrlEncodeUtf8(clean_q, q_enc, sizeof(q_enc));

  I64 cap = 65536;
  U8 *out = MAlloc(cap);
  I64 pos = 0;

  if (ntok > 0) {
    pos += snprintf(out + pos, cap - pos,
      "<!DOCTYPE html><html><head><title>Поиск Холинета: %s</title></head><body>"
      "<h1>Поиск в Холинете: &laquo;%s&raquo;</h1>",
      q_esc, q_esc
    );
  } else {
    pos += snprintf(out + pos, cap - pos,
      "<!DOCTYPE html><html><head><title>Поиск сайтов в P2P-сети Холинет</title></head><body>"
      "<h1>Поисковая система P2P-сети ХОЛИНЕТ</h1>"
    );
  }

  /* Панель переключения области поиска (Везде / По заголовкам / По доменам / По тексту) */
  U8 *s0 = "Везде";
  U8 *s1 = "Только по заголовкам";
  U8 *s2 = "Только по доменам";
  U8 *s3 = "По тексту страниц";
  if (scope == HOLY_SCOPE_ALL)    s0 = "[ ВЕЗДЕ ]";
  if (scope == HOLY_SCOPE_TITLE)  s1 = "[ ТОЛЬКО ПО ЗАГОЛОВКАМ ]";
  if (scope == HOLY_SCOPE_DOMAIN) s2 = "[ ТОЛЬКО ПО ДОМЕНАМ ]";
  if (scope == HOLY_SCOPE_BODY)   s3 = "[ ПО ТЕКСТУ СТРАНИЦ ]";

  pos += snprintf(out + pos, cap - pos,
    "<blockquote>"
    "<b>Индекс P2P-сети:</b> просканировано <b>%d</b> сайтов (онлайн-пиров: <b>%d</b>) за <b>%.2f мс</b>.<br>"
    "Подсказка: вводите любой запрос прямо в адресную строку без <code>holy://</code>! "
    "Кнопка <b>[В Холинете / В Интернете]</b> на верхней панели мгновенно переключает поиск между сетями."
    "</blockquote>"
    "<p><b>Область поиска:</b> "
    "<a href=\"holy://search?q=%s&scope=all\">%s</a> | "
    "<a href=\"holy://search?q=%s&scope=title\">%s</a> | "
    "<a href=\"holy://search?q=%s&scope=domain\">%s</a> | "
    "<a href=\"holy://search?q=%s&scope=body\">%s</a></p>",
    total_sites, online_peers, elapsed_ms,
    q_enc, s0, q_enc, s1, q_enc, s2, q_enc, s3
  );

  /* Быстрые поисковые теги в 1 клик */
  pos += snprintf(out + pos, cap - pos,
    "<p><b>Примеры поиска в 1 клик:</b> "
    "<a href=\"holy://search?q=%s\">энциклопедия</a> | "
    "<a href=\"holy://search?q=%s\">квас</a> | "
    "<a href=\"holy://search?q=%s\">береста</a> | "
    "<a href=\"holy://search?q=%s\">видеохостинг</a> | "
    "<a href=\"holy://search?q=HolyC\">HolyC</a> | "
    "<a href=\"holy://search?q=wikipedia\">wikipedia</a></p><hr>",
    "%D1%8D%D0%BD%D1%86%D0%B8%D0%BA%D0%BB%D0%BE%D0%BF%D0%B5%D0%B4%D0%B8%D1%8F",
    "%D0%BA%D0%B2%D0%B0%D1%81",
    "%D0%B1%D0%B5%D1%80%D0%B5%D1%81%D1%82%D0%B0",
    "%D0%B2%D0%B8%D0%B4%D0%B5%D0%BE%D1%85%D0%BE%D1%81%D1%82%D0%B8%D0%BD%D0%B3"
  );

  if (ntok > 0) {
    pos += snprintf(out + pos, cap - pos,
      "<h2>Найдено сайтов: %d</h2>", hit_count);
  } else {
    pos += snprintf(out + pos, cap - pos,
      "<h2>Все проиндексированные сайты P2P-сети (%d):</h2>", hit_count);
  }

  if (hit_count == 0) {
    pos += snprintf(out + pos, cap - pos,
      "<p>По запросу <b>&laquo;%s&raquo;</b> в выбранной области пока не найдено ни одного P2P-сайта.</p>"
      "<ul>"
      "<li><a href=\"holy://search?q=%s&scope=all\">Попробовать искать везде (включая текст и код всех страниц)</a></li>"
      "<li><a href=\"holy://builder\"><b>[ Создать первый сайт на эту тему во встроенном Конструкторе! ]</b></a></li>"
      "</ul>",
      q_esc, q_enc
    );
  } else {
    pos += snprintf(out + pos, cap - pos, "<ol>");
    for (I32 r = 0; r < hit_count; r++) {
      HolySearchHit *h = &hits[r];
      HolySite *s = &g_holy.sites[h->site_idx];

      if (pos + 2048 >= cap) {
        cap *= 2;
        out = ReAlloc(out, cap);
      }

      U8 t_esc[256];
      HolyEscapeHtml(s->title, t_esc, sizeof(t_esc));

      /* Собираем понятные метки: где именно нашлось совпадение */
      U8 badges[200];
      badges[0] = 0;
      if (ntok > 0) {
        I64 bp = snprintf(badges, sizeof(badges), "Совпадение: ");
        if (h->match_title)   bp += snprintf(badges + bp, sizeof(badges) - bp, "[Заголовок] ");
        if (h->match_domain)  bp += snprintf(badges + bp, sizeof(badges) - bp, "[Домен] ");
        if (h->match_heading) bp += snprintf(badges + bp, sizeof(badges) - bp, "[Подзаголовок H1-H3] ");
        if (h->match_body)    bp += snprintf(badges + bp, sizeof(badges) - bp, "[Текст страницы] ");
        if (h->match_owner)   bp += snprintf(badges + bp, sizeof(badges) - bp, "[Узел] ");
      }

      pos += snprintf(out + pos, cap - pos,
        "<li><a href=\"holy://%s\"><b>%s</b></a> &mdash; <code>%s</code>",
        s->domain, t_esc, s->domain
      );
      if (ntok > 0) {
        pos += snprintf(out + pos, cap - pos,
          " <i>(вес: %d)</i><br><code>%s</code>", h->score, badges);
      }
      if (h->snippet[0] != 0) {
        pos += snprintf(out + pos, cap - pos, "<br>%s", h->snippet);
      }
      pos += snprintf(out + pos, cap - pos,
        "<br><i>Узел: %s | Пинг: %.2f мс | Версия v%d | Просмотров: %d</i></li>",
        s->owner_node, s->last_ping_ms, s->version, s->hits
      );
    }
    pos += snprintf(out + pos, cap - pos, "</ol>");
  }

  HolyUnlock();
  Free(hits);
  Free(headings_buf);
  Free(headings_low);
  Free(body_buf);
  Free(body_low);

  pos += snprintf(out + pos, cap - pos,
    "<hr><p><a href=\"holy://home\">На главную Холинета</a> | "
    "<a href=\"holy://builder\">Конструктор сайтов</a> | "
    "<a href=\"holy://monitor?sync=1\">Мониторинг P2P-узлов</a></p>"
    "</body></html>"
  );
  *out_len = pos;
  return out;
}

/* Умное определение: является ли введённая пользователем строка поисковым запросом
 * (чтобы никогда не требовалось вводить holy:// или вручную формировать URL поисковика!) */
Bool IsLikelySearchInput(U8 *raw, U8 *out_query, I64 q_cap)
{
  out_query[0] = 0;
  if (raw == NULL) return FALSE;

  U8 *p = raw;
  while (*p && IsSpace(*p)) p++;
  if (*p == 0) return FALSE;

  /* Явные префиксы поиска: "?запрос", "search: запрос", "поиск: запрос" */
  if (*p == '?') {
    p++;
    while (*p && IsSpace(*p)) p++;
    SafeCopy(out_query, p, q_cap);
    return TRUE;
  }
  if (StrCaseEqLen(p, "search:", 7)) {
    p += 7;
    while (*p && IsSpace(*p)) p++;
    SafeCopy(out_query, p, q_cap);
    return TRUE;
  }
  /* UTF-8 "поиск:" = D0 BF D0 BE D0 B8 D1 81 D0 BA 3A (11 байт) */
  if (StrNCmp(p, "поиск:", 11) == 0 || StrNCmp(p, "ПОИСК:", 11) == 0 || StrNCmp(p, "Поиск:", 11) == 0) {
    p += 11;
    while (*p && IsSpace(*p)) p++;
    SafeCopy(out_query, p, q_cap);
    return TRUE;
  }

  /* Если явно указана схема (https://, http://, holy://, temple://, file://) или локальный путь */
  if (strstr(p, "://") != NULL || p[0] == '/' || (p[0] == '.' && p[1] == '/')) {
    return FALSE;
  }

  /* Внутренние системные страницы без точки */
  if (StrCmp(p, "home") == 0 || StrCmp(p, "builder") == 0 ||
      StrCmp(p, "monitor") == 0 || StrCmp(p, "search") == 0 ||
      StrCmp(p, "about") == 0 || StrCaseEqLen(p, "localhost", 9)) {
    return FALSE;
  }

  /* Проверяем пробелы, точки и не-ASCII символы (кириллицу) */
  Bool has_space = FALSE;
  Bool has_dot   = FALSE;
  Bool has_utf8  = FALSE;
  for (I64 i = 0; p[i]; i++) {
    if (IsSpace(p[i])) has_space = TRUE;
    if (p[i] == '.') has_dot = TRUE;
    if (p[i] >= 128) has_utf8 = TRUE;
  }

  /* Любая фраза с пробелами или слово без точки (например "квас", "береста", "holyc") — это Поиск! */
  if (has_space || !has_dot) {
    SafeCopy(out_query, p, q_cap);
    return TRUE;
  }

  /* Кириллическая фраза даже со случайной точкой без доменной зоны (.рф) */
  if (has_utf8 && strstr(p, ".рф") == NULL) {
    SafeCopy(out_query, p, q_cap);
    return TRUE;
  }

  return FALSE;
}
