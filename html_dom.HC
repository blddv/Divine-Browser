/* ============================================================================
 * html_dom.HC — Потоковый HTML-парсер, декодер UTF-8 сущностей и модель документа
 * Браузер DivineWeb на языке HolyC (holyc-lang)
 * ============================================================================ */

#define NODE_TEXT         1
#define NODE_BLOCK_START  2
#define NODE_LINE_BREAK   3
#define NODE_HR           4
#define NODE_IMAGE        5
#define NODE_TABLE_START  6
#define NODE_TABLE_ROW    7
#define NODE_TABLE_CELL   8
#define NODE_TABLE_END    9
#define NODE_ANIM_CANVAS  10
#define NODE_MARQUEE      11

#define BLK_PARAGRAPH     0
#define BLK_H1            1
#define BLK_H2            2
#define BLK_H3            3
#define BLK_H4            4
#define BLK_QUOTE         5
#define BLK_PRE           6
#define BLK_LIST_ITEM     7

#define MAX_DOC_IMAGES    16

class DocImage
{
  U8  *src;
  U8  *alt;
  I32  attr_w;
  I32  attr_h;
  U0  *surface;
  U0  *davis_surface;  /* 16-цветный дизеринг Байера 4x4 для темы «Одобрение Дэвиса» */
  I32  nat_w;
  I32  nat_h;
  Bool loaded;
};

class DocNode
{
  I32  type;
  I32  block_kind;
  I32  heading;
  I32  indent;
  I32  list_index;     /* 0 = маркер •, >0 = нумерованный список 1., 2., ... */
  I32  link_id;        /* -1 если обычный текст, иначе индекс в doc->links */
  I32  img_id;         /* индекс в doc->images для NODE_IMAGE */
  I32  anim_kind;      /* 1 = cosmos, 2 = cube, 3 = waves */
  I32  anim_w;
  I32  anim_h;
  Bool is_th;          /* TRUE для ячейки шапки <th> */
  Bool bold;
  Bool italic;
  Bool underline;
  Bool strike;
  Bool in_mark;
  Bool mono;
  Bool in_quote;
  Bool in_pre;
  Bool has_fg_color;
  U32  fg_rgb;
  I32  css_font_px;
  U8  *text;
};

class HtmlDocument
{
  U8       title[256];
  U8       base_url[1024];
  DocNode *nodes;
  I64      node_count;
  I64      node_cap;
  U8     **links;
  I64      link_count;
  I64      link_cap;
  DocImage images[MAX_DOC_IMAGES];
  I32      image_count;
  Bool     has_animations;
  Bool     has_css_bg;
  U32      css_bg_rgb;
};

U0 DocInit(HtmlDocument *doc, U8 *base_url)
{
  MemSet(doc, 0, sizeof(HtmlDocument));
  SafeCopy(doc->title, "DivineWeb — Страница", sizeof(doc->title));
  SafeCopy(doc->base_url, base_url, sizeof(doc->base_url));
  doc->node_cap = 256;
  doc->nodes = CAlloc(doc->node_cap * sizeof(DocNode));
  doc->link_cap = 64;
  doc->links = CAlloc(doc->link_cap * sizeof(U8 *));
}

U0 DocFree(HtmlDocument *doc)
{
  if (doc->nodes != NULL) {
    for (I64 i = 0; i < doc->node_count; i++) {
      if (doc->nodes[i].text != NULL) Free(doc->nodes[i].text);
    }
    Free(doc->nodes);
    doc->nodes = NULL;
  }
  if (doc->links != NULL) {
    for (I64 i = 0; i < doc->link_count; i++) {
      if (doc->links[i] != NULL) Free(doc->links[i]);
    }
    Free(doc->links);
    doc->links = NULL;
  }
  for (I32 im = 0; im < doc->image_count; im++) {
    if (doc->images[im].src != NULL) Free(doc->images[im].src);
    if (doc->images[im].alt != NULL) Free(doc->images[im].alt);
    if (doc->images[im].surface != NULL) cairo_surface_destroy(doc->images[im].surface);
    if (doc->images[im].davis_surface != NULL) cairo_surface_destroy(doc->images[im].davis_surface);
    MemSet(&doc->images[im], 0, sizeof(DocImage));
  }
  doc->node_count = 0;
  doc->link_count = 0;
  doc->image_count = 0;
}

I32 DocAddLink(HtmlDocument *doc, U8 *raw_href)
{
  U8 resolved[1024];
  UrlResolve(doc->base_url, raw_href, resolved, sizeof(resolved));
  if (doc->link_count >= doc->link_cap) {
    doc->link_cap *= 2;
    doc->links = ReAlloc(doc->links, doc->link_cap * sizeof(U8 *));
  }
  I32 id = doc->link_count;
  doc->links[id] = StrNew(resolved);
  doc->link_count++;
  return id;
}

DocNode *DocPushNode(HtmlDocument *doc, I32 type)
{
  if (doc->node_count >= doc->node_cap) {
    doc->node_cap *= 2;
    doc->nodes = ReAlloc(doc->nodes, doc->node_cap * sizeof(DocNode));
  }
  DocNode *n = &doc->nodes[doc->node_count];
  MemSet(n, 0, sizeof(DocNode));
  n->type = type;
  n->link_id = -1;
  doc->node_count++;
  return n;
}

/* Кодирование Unicode codepoint в UTF-8 */
I64 EncodeUtf8Codepoint(U32 cp, U8 *out)
{
  if (cp < 0x80) {
    out[0] = cp;
    return 1;
  } else if (cp < 0x800) {
    out[0] = 0xC0 | (cp >> 6);
    out[1] = 0x80 | (cp & 0x3F);
    return 2;
  } else if (cp < 0x10000) {
    out[0] = 0xE0 | (cp >> 12);
    out[1] = 0x80 | ((cp >> 6) & 0x3F);
    out[2] = 0x80 | (cp & 0x3F);
    return 3;
  } else if (cp <= 0x10FFFF) {
    out[0] = 0xF0 | (cp >> 18);
    out[1] = 0x80 | ((cp >> 12) & 0x3F);
    out[2] = 0x80 | ((cp >> 6) & 0x3F);
    out[3] = 0x80 | (cp & 0x3F);
    return 4;
  }
  out[0] = '?';
  return 1;
}

/* Декодирование HTML-сущностей (&amp;, &laquo;, &#1046;, &#x2192;, ...) */
I64 DecodeHtmlEntity(U8 *ent, I64 len, U8 *out)
{
  if (len <= 0) {
    out[0] = '&';
    return 1;
  }
  if (ent[0] == '#') {
    U32 cp = 0;
    if (len > 2 && (ent[1] == 'x' || ent[1] == 'X')) {
      for (I64 i = 2; i < len; i++) {
        U8 c = ent[i];
        if (c >= '0' && c <= '9') cp = (cp << 4) | (c - '0');
        else if (c >= 'a' && c <= 'f') cp = (cp << 4) | (10 + c - 'a');
        else if (c >= 'A' && c <= 'F') cp = (cp << 4) | (10 + c - 'A');
      }
    } else {
      for (I64 i = 1; i < len; i++) {
        if (ent[i] >= '0' && ent[i] <= '9')
          cp = cp * 10 + (ent[i] - '0');
      }
    }
    if (cp == 160) { out[0] = ' '; return 1; }
    if (cp > 0) return EncodeUtf8Codepoint(cp, out);
  }

  if (len == 3 && StrNCmp(ent, "amp", 3) == 0)   { out[0] = '&'; return 1; }
  if (len == 2 && StrNCmp(ent, "lt", 2) == 0)    { out[0] = '<'; return 1; }
  if (len == 2 && StrNCmp(ent, "gt", 2) == 0)    { out[0] = '>'; return 1; }
  if (len == 4 && StrNCmp(ent, "quot", 4) == 0)  { out[0] = '"'; return 1; }
  if (len == 4 && StrNCmp(ent, "apos", 4) == 0)  { out[0] = '\''; return 1; }
  if (len == 4 && StrNCmp(ent, "nbsp", 4) == 0)  { out[0] = ' '; return 1; }
  if (len == 4 && StrNCmp(ent, "copy", 4) == 0)  return EncodeUtf8Codepoint(0x00A9, out);
  if (len == 3 && StrNCmp(ent, "reg", 3) == 0)   return EncodeUtf8Codepoint(0x00AE, out);
  if (len == 5 && StrNCmp(ent, "mdash", 5) == 0) return EncodeUtf8Codepoint(0x2014, out);
  if (len == 5 && StrNCmp(ent, "ndash", 5) == 0) return EncodeUtf8Codepoint(0x2013, out);
  if (len == 4 && StrNCmp(ent, "bull", 4) == 0)  return EncodeUtf8Codepoint(0x2022, out);
  if (len == 6 && StrNCmp(ent, "hellip", 6) == 0) return EncodeUtf8Codepoint(0x2026, out);
  if (len == 5 && StrNCmp(ent, "laquo", 5) == 0) return EncodeUtf8Codepoint(0x00AB, out);
  if (len == 5 && StrNCmp(ent, "raquo", 5) == 0) return EncodeUtf8Codepoint(0x00BB, out);
  if (len == 4 && StrNCmp(ent, "larr", 4) == 0)  return EncodeUtf8Codepoint(0x2190, out);
  if (len == 4 && StrNCmp(ent, "rarr", 4) == 0)  return EncodeUtf8Codepoint(0x2192, out);
  if (len == 4 && StrNCmp(ent, "uarr", 4) == 0)  return EncodeUtf8Codepoint(0x2191, out);
  if (len == 4 && StrNCmp(ent, "darr", 4) == 0)  return EncodeUtf8Codepoint(0x2193, out);
  if (len == 6 && StrNCmp(ent, "middot", 6) == 0) return EncodeUtf8Codepoint(0x00B7, out);
  if (len == 5 && StrNCmp(ent, "times", 5) == 0) return EncodeUtf8Codepoint(0x00D7, out);
  if (len == 5 && StrNCmp(ent, "starf", 5) == 0) return EncodeUtf8Codepoint(0x2605, out);
  if (len == 4 && StrNCmp(ent, "star", 4) == 0)  return EncodeUtf8Codepoint(0x2606, out);
  if (len == 5 && StrNCmp(ent, "trade", 5) == 0) return EncodeUtf8Codepoint(0x2122, out);
  if (len == 4 && StrNCmp(ent, "euro", 4) == 0)  return EncodeUtf8Codepoint(0x20AC, out);
  if (len == 6 && StrNCmp(ent, "plusmn", 6) == 0) return EncodeUtf8Codepoint(0x00B1, out);

  /* Неизвестная сущность — оставляем как есть */
  out[0] = '&';
  return 1;
}

U8 *DecodeEntitiesAlloc(U8 *raw, I64 raw_len, Bool collapse_ws)
{
  I64 cap = raw_len * 2 + 16;
  U8 *out = MAlloc(cap);
  I64 opos = 0;
  I64 i = 0;
  Bool prev_space = FALSE;

  while (i < raw_len) {
    if (opos + 8 >= cap) {
      cap *= 2;
      out = ReAlloc(out, cap);
    }

    U8 ch = raw[i];
    if (ch == '&') {
      I64 semi = -1;
      for (I64 k = i + 1; k < raw_len && k < i + 14; k++) {
        if (raw[k] == ';') { semi = k; break; }
        if (IsSpace(raw[k]) || raw[k] == '<' || raw[k] == '&') break;
      }
      if (semi > i + 1) {
        U8 utf8[8];
        I64 n = DecodeHtmlEntity(raw + i + 1, semi - (i + 1), utf8);
        if (collapse_ws && n == 1 && utf8[0] == ' ') {
          if (!prev_space) { out[opos++] = ' '; prev_space = TRUE; }
        } else {
          MemCpy(out + opos, utf8, n);
          opos += n;
          prev_space = FALSE;
        }
        i = semi + 1;
        continue;
      }
    }

    if (collapse_ws) {
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
        if (!prev_space) {
          out[opos++] = ' ';
          prev_space = TRUE;
        }
        i++;
        continue;
      }
      prev_space = FALSE;
    }

    out[opos++] = ch;
    i++;
  }

  out[opos] = 0;
  return out;
}

/* Извлечение значения атрибута (например href="..." из тега <a ...>) */
Bool ExtractAttrValue(U8 *tag_body, I64 tag_len, U8 *attr_name, U8 *out, I64 out_cap)
{
  I64 alen = StrLen(attr_name);
  I64 i = 0;
  out[0] = 0;

  while (i + alen < tag_len) {
    if (IsSpace(tag_body[i])) {
      while (i < tag_len && IsSpace(tag_body[i])) i++;
      if (i + alen <= tag_len && StrCaseEqLen(tag_body + i, attr_name, alen)) {
        I64 k = i + alen;
        while (k < tag_len && IsSpace(tag_body[k])) k++;
        if (k < tag_len && tag_body[k] == '=') {
          k++;
          while (k < tag_len && IsSpace(tag_body[k])) k++;
          if (k < tag_len && (tag_body[k] == '"' || tag_body[k] == '\'')) {
            U8 quote = tag_body[k++];
            I64 start = k;
            while (k < tag_len && tag_body[k] != quote) k++;
            U8 *decoded = DecodeEntitiesAlloc(tag_body + start, k - start, FALSE);
            SafeCopy(out, decoded, out_cap);
            Free(decoded);
            return TRUE;
          } else {
            I64 start = k;
            while (k < tag_len && !IsSpace(tag_body[k]) && tag_body[k] != '>') k++;
            U8 *decoded = DecodeEntitiesAlloc(tag_body + start, k - start, FALSE);
            SafeCopy(out, decoded, out_cap);
            Free(decoded);
            return TRUE;
          }
        }
      }
    }
    i++;
  }
  return FALSE;
}

U0 EmitBlockStart(HtmlDocument *doc, I32 kind, I32 indent, I32 list_idx, Bool in_quote, Bool in_pre)
{
  /* Избегаем дублирования пустых параграфов подряд */
  if (doc->node_count > 0 && kind != BLK_LIST_ITEM && kind != BLK_PRE) {
    DocNode *prev = &doc->nodes[doc->node_count - 1];
    if (prev->type == NODE_BLOCK_START && prev->block_kind == kind && prev->list_index == 0) {
      return;
    }
  }
  DocNode *n = DocPushNode(doc, NODE_BLOCK_START);
  n->block_kind = kind;
  n->indent = indent;
  n->list_index = list_idx;
  n->in_quote = in_quote;
  n->in_pre = in_pre;
}

/* Разбор #RRGGBB или #RGB цвета из атрибута color="..." или style="...color:#RRGGBB..." */
Bool ParseCssHexColor(U8 *s, U32 *out_rgb)
{
  if (s == NULL) return FALSE;
  U8 *hash = strchr(s, '#');
  if (hash == NULL) return FALSE;
  hash++;
  I32 d[6];
  I32 cnt = 0;
  while (cnt < 6) {
    U8 c = hash[cnt];
    if (c >= '0' && c <= '9') d[cnt] = c - '0';
    else if (c >= 'a' && c <= 'f') d[cnt] = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') d[cnt] = c - 'A' + 10;
    else break;
    cnt++;
  }
  if (cnt == 6) {
    U32 r = (d[0] << 4) | d[1];
    U32 g = (d[2] << 4) | d[3];
    U32 b = (d[4] << 4) | d[5];
    *out_rgb = (r << 16) | (g << 8) | b;
    return TRUE;
  } else if (cnt >= 3) {
    U32 r = (d[0] << 4) | d[0];
    U32 g = (d[1] << 4) | d[1];
    U32 b = (d[2] << 4) | d[2];
    *out_rgb = (r << 16) | (g << 8) | b;
    return TRUE;
  }
  return FALSE;
}

Bool ExtractInlineTextColor(U8 *tag_body, I64 tag_len, U32 *out_rgb)
{
  U8 col_attr[128];
  if (ExtractAttrValue(tag_body, tag_len, "color", col_attr, sizeof(col_attr))) {
    if (ParseCssHexColor(col_attr, out_rgb)) return TRUE;
  }
  U8 style_attr[256];
  if (ExtractAttrValue(tag_body, tag_len, "style", style_attr, sizeof(style_attr))) {
    U8 *p = style_attr;
    while (*p) {
      if (StrCaseEqLen(p, "color", 5)) {
        if (p == style_attr || *(p - 1) != '-') {
          return ParseCssHexColor(p + 5, out_rgb);
        }
      }
      p++;
    }
  }
  return FALSE;
}

/* --- Главный парсер HTML -> HtmlDocument --- */
/* Collect simple author styles before the rendering pass. */
U0 CollectLegacyCss(U8 *html, I64 len, U8 *base, CssSheet *sheet)
{
  I32 links = 0;
  for (I64 p = 0; p + 6 < len; p++) {
    if (html[p] != '<') continue;
    if (StrCaseEqLen(html + p, "<style", 6)) {
      I64 start = p + 6;
      while (start < len && html[start] != '>') start++;
      if (start >= len) break;
      start++;
      I64 end = start;
      while (end + 7 < len && !StrCaseEqLen(html + end, "</style", 7)) end++;
      if (end + 7 < len) CssParseStylesheet(sheet, html + start, end - start);
      p = end;
    } else if (links < 4 && StrCaseEqLen(html + p, "<link", 5)) {
      I64 end = p + 5;
      while (end < len && html[end] != '>') end++;
      U8 rel[128], href[1024], url[1024];
      rel[0] = 0; href[0] = 0;
      ExtractAttrValue(html + p + 1, end - p - 1, "rel", rel, sizeof(rel));
      ExtractAttrValue(html + p + 1, end - p - 1, "href", href, sizeof(href));
      if (StrContainsIgnoreCase(rel, "stylesheet") && href[0]) {
        UrlResolve(base, href, url, sizeof(url));
        if (!StartsWithIgnoreCase(base, "holy://") && !StartsWithIgnoreCase(base, "cheb://") &&
            (StartsWithIgnoreCase(url, "http://") || StartsWithIgnoreCase(url, "https://"))) {
          HttpResponse r;
          links++;
          if (FetchUrlFast(url, &r, TRUE) && r.body != NULL && r.body_len < 1024 * 1024)
            CssParseStylesheet(sheet, r.body, r.body_len);
          HttpResponseFree(&r);
        }
      }
      p = end;
    }
  }
}

Bool HtmlVoidTag(U8 *t)
{
  return StrCmp(t, "br") == 0 || StrCmp(t, "img") == 0 || StrCmp(t, "hr") == 0 ||
         StrCmp(t, "input") == 0 || StrCmp(t, "link") == 0 || StrCmp(t, "meta") == 0 ||
         StrCmp(t, "source") == 0 || StrCmp(t, "area") == 0 || StrCmp(t, "base") == 0 ||
         StrCmp(t, "embed") == 0 || StrCmp(t, "wbr") == 0;
}

U0 ParseHtmlDocument(U8 *html, I64 len, U8 *base_url, HtmlDocument *doc)
{
  DocInit(doc, base_url);
  if (html == NULL || len <= 0) return;

  CssSheet *sheet = CAlloc(sizeof(CssSheet));
  CollectLegacyCss(html, len, base_url, sheet);
  for (I32 i = 1; i < sheet->rule_count; i++) {
    CssRule r = sheet->rules[i];
    I32 j = i;
    while (j > 0 && sheet->rules[j - 1].specificity > r.specificity) {
      sheet->rules[j] = sheet->rules[j - 1]; j--;
    }
    sheet->rules[j] = r;
  }
  CssElemCtx *ctx = CAlloc(64 * sizeof(CssElemCtx));
  CssProps *styles = CAlloc(64 * sizeof(CssProps));
  I32 *links = CAlloc(64 * sizeof(I32));
  I32 depth = 0;
  I32 hidden_depth = 0;
  CssProps current_css;
  CssPropsInit(&current_css);

  I32 bold_depth = 0;
  I32 italic_depth = 0;
  I32 underline_depth = 0;
  I32 strike_depth = 0;
  I32 mark_depth = 0;
  I32 mono_depth = 0;
  I32 heading_level = 0;
  I32 quote_depth = 0;
  I32 pre_depth = 0;
  I32 table_depth = 0;
  I32 list_depth = 0;
  I32 list_ordered[16];
  I32 list_counter[16];
  MemSet(list_ordered, 0, sizeof(list_ordered));
  MemSet(list_counter, 0, sizeof(list_counter));

  Bool has_custom_color = FALSE;
  U32  active_rgb = 0;

  I32 current_link_id = -1;
  Bool in_title = FALSE;
  Bool in_marquee = FALSE;

  EmitBlockStart(doc, BLK_PARAGRAPH, 0, 0, FALSE, FALSE);

  I64 pos = 0;
  while (pos < len) {
    /* 1. Обработка HTML-комментариев <!-- ... --> */
    if (pos + 4 <= len && StrNCmp(html + pos, "<!--", 4) == 0) {
      pos += 4;
      while (pos + 3 <= len && StrNCmp(html + pos, "-->", 3) != 0) pos++;
      if (pos + 3 <= len) pos += 3;
      continue;
    }

    /* 2. Обработка тега <...> */
    if (html[pos] == '<') {
      I64 tag_start = pos + 1;
      I64 tag_end = tag_start;
      Bool in_q = FALSE;
      U8 q_ch = 0;
      while (tag_end < len) {
        U8 c = html[tag_end];
        if (in_q) {
          if (c == q_ch) in_q = FALSE;
        } else {
          if (c == '"' || c == '\'') { in_q = TRUE; q_ch = c; }
          else if (c == '>') break;
        }
        tag_end++;
      }
      if (tag_end >= len) break;

      I64 tlen = tag_end - tag_start;
      U8 *tp = html + tag_start;
      pos = tag_end + 1;

      while (tlen > 0 && IsSpace(*tp)) { tp++; tlen--; }
      if (tlen <= 0 || tp[0] == '!' || tp[0] == '?') continue;

      Bool closing = FALSE;
      if (tp[0] == '/') {
        closing = TRUE;
        tp++;
        tlen--;
        while (tlen > 0 && IsSpace(*tp)) { tp++; tlen--; }
      }

      U8 tname[32];
      I64 ni = 0;
      while (ni < tlen && ni < 31 && !IsSpace(tp[ni]) && tp[ni] != '/') {
        tname[ni] = ToLower(tp[ni]);
        ni++;
      }
      tname[ni] = 0;

      /* Пропуск содержимого <script>, <style>, <svg>, <noscript>, <select> целиком */
      if (!closing && (StrCmp(tname, "script") == 0 || StrCmp(tname, "style") == 0 ||
                       StrCmp(tname, "svg") == 0 || StrCmp(tname, "select") == 0)) {
        U8 close_pat[40];
        snprintf(close_pat, sizeof(close_pat), "</%s", tname);
        I64 clen = StrLen(close_pat);
        while (pos + clen <= len) {
          if (StrCaseEqLen(html + pos, close_pat, clen)) {
            pos += clen;
            while (pos < len && html[pos] != '>') pos++;
            if (pos < len) pos++;
            break;
          }
          pos++;
        }
        continue;
      }

      /* A bounded element stack provides inheritance, selector ancestry and
       * event target inheritance. Void elements never change stack depth. */
      Bool is_void = HtmlVoidTag(tname) || (tlen > 0 && tp[tlen - 1] == '/');
      I32 tag_link_id = current_link_id;
      if (hidden_depth > 0) {
        if (closing) hidden_depth--;
        else if (!is_void) hidden_depth++;
        continue;
      }
      if (closing) {
        I32 found = depth - 1;
        while (found >= 0 && StrCmp(ctx[found].tag, tname) != 0) found--;
        if (found >= 0) depth = found;
        CssPropsInit(&current_css);
        current_link_id = -1;
        if (depth > 0) { current_css = styles[depth - 1]; current_link_id = links[depth - 1]; }
      } else {
        CssElemCtx el;
        MemSet(&el, 0, sizeof(el));
        SafeCopy(el.tag, tname, sizeof(el.tag));
        ExtractAttrValue(tp, tlen, "id", el.id, sizeof(el.id));
        ExtractAttrValue(tp, tlen, "class", el.cls, sizeof(el.cls));
        U8 inline_css[1024]; inline_css[0] = 0;
        ExtractAttrValue(tp, tlen, "style", inline_css, sizeof(inline_css));
        CssProps own;
        CssComputeForElement(sheet, ctx, depth, &el, inline_css, &own);
        if (own.display_none) {
          if (!is_void) hidden_depth = 1;
          continue;
        }
        CssProps inherited;
        CssPropsInit(&inherited);
        if (depth > 0) {
          CssProps *parent = &styles[depth - 1];
          inherited.has_fg = parent->has_fg; inherited.fg_rgb = parent->fg_rgb;
          inherited.font_px = parent->font_px; inherited.bold_mode = parent->bold_mode;
          inherited.italic_mode = parent->italic_mode; inherited.underline_mode = parent->underline_mode;
          inherited.mono = parent->mono; inherited.text_align = parent->text_align;
        }
        CssPropsMerge(&inherited, &own);
        if (StrCmp(tname, "body") == 0 && own.has_bg) {
          doc->has_css_bg = TRUE; doc->css_bg_rgb = own.bg_rgb;
        }
        I32 el_link = current_link_id;
        U8 qid[32]; qid[0] = 0;
        if (ExtractAttrValue(tp, tlen, "data-qjs-id", qid, sizeof(qid)) && Atoi(qid) > 0) {
          U8 jsurl[64]; snprintf(jsurl, sizeof(jsurl), "javascript:__qjs_click(%d)", Atoi(qid));
          el_link = DocAddLink(doc, jsurl);
        } else if (StrCmp(tname, "a") == 0) {
          U8 href[1024]; href[0] = 0;
          if (ExtractAttrValue(tp, tlen, "href", href, sizeof(href)) && href[0]) el_link = DocAddLink(doc, href);
        }
        tag_link_id = el_link;
        if (!is_void) { current_css = inherited; current_link_id = el_link; }
        if (!is_void && depth < 64) {
          ctx[depth] = el; styles[depth] = inherited; links[depth] = el_link; depth++;
        }
      }

      if (StrCmp(tname, "title") == 0) {
        in_title = !closing;
        continue;
      }

      /* Бегущая строка <marquee>...</marquee> с живой 30 FPS анимацией */
      if (StrCmp(tname, "marquee") == 0) {
        in_marquee = !closing;
        doc->has_animations = TRUE;
        continue;
      }

      /* Анимированный холст <canvas width="..." height="..." data-anim="cosmos|cube|waves"> */
      if (StrCmp(tname, "canvas") == 0 && !closing) {
        U8 w_val[32];
        U8 h_val[32];
        U8 anim_val[64];
        w_val[0] = 0; h_val[0] = 0; anim_val[0] = 0;
        ExtractAttrValue(tp, tlen, "width", w_val, sizeof(w_val));
        ExtractAttrValue(tp, tlen, "height", h_val, sizeof(h_val));
        if (!ExtractAttrValue(tp, tlen, "data-anim", anim_val, sizeof(anim_val))) {
          ExtractAttrValue(tp, tlen, "id", anim_val, sizeof(anim_val));
        }

        I32 cw = Atoi(w_val);
        I32 ch = Atoi(h_val);
        if (cw <= 0) cw = 740;
        if (ch <= 0) ch = 300;

        for (I64 ai = 0; anim_val[ai]; ai++) anim_val[ai] = ToLower(anim_val[ai]);
        I32 akind = 1; /* cosmos */
        if (strstr(anim_val, "cube") != NULL)  akind = 2;
        if (strstr(anim_val, "wave") != NULL)  akind = 3;

        DocNode *cn = DocPushNode(doc, NODE_ANIM_CANVAS);
        cn->anim_kind = akind;
        cn->anim_w = cw;
        cn->anim_h = ch;
        doc->has_animations = TRUE;

        /* Пропускаем fallback-текст до </canvas> */
        while (pos + 8 <= len) {
          if (StrCaseEqLen(html + pos, "</canvas", 8)) {
            pos += 8;
            while (pos < len && html[pos] != '>') pos++;
            if (pos < len) pos++;
            break;
          }
          pos++;
        }
        continue;
      }

      /* Блочные теги и заголовки */
      if (StrCmp(tname, "h1") == 0 || StrCmp(tname, "h2") == 0 ||
          StrCmp(tname, "h3") == 0 || StrCmp(tname, "h4") == 0 ||
          StrCmp(tname, "h5") == 0 || StrCmp(tname, "h6") == 0) {
        I32 lvl = tname[1] - '0';
        if (lvl > 4) lvl = 4;
        if (!closing) {
          heading_level = lvl;
          EmitBlockStart(doc, lvl, list_depth, 0, quote_depth > 0, FALSE);
        } else {
          heading_level = 0;
          EmitBlockStart(doc, BLK_PARAGRAPH, list_depth, 0, quote_depth > 0, FALSE);
        }
        continue;
      }

      /* Настоящие 2D таблицы <table> / <tr> / <th> / <td> (для верхнего уровня table_depth == 1) */
      if (StrCmp(tname, "table") == 0) {
        if (!closing) {
          table_depth++;
          if (table_depth == 1) {
            DocPushNode(doc, NODE_TABLE_START);
          }
        } else {
          if (table_depth == 1) {
            DocPushNode(doc, NODE_TABLE_END);
            EmitBlockStart(doc, BLK_PARAGRAPH, list_depth, 0, quote_depth > 0, FALSE);
          }
          if (table_depth > 0) table_depth--;
        }
        continue;
      }

      if (StrCmp(tname, "tr") == 0) {
        if (!closing) {
          if (table_depth == 1) {
            DocPushNode(doc, NODE_TABLE_ROW);
          } else {
            EmitBlockStart(doc, BLK_PARAGRAPH, list_depth, 0, quote_depth > 0, FALSE);
          }
        }
        continue;
      }

      if (StrCmp(tname, "td") == 0 || StrCmp(tname, "th") == 0) {
        Bool is_h = (StrCmp(tname, "th") == 0);
        if (!closing) {
          if (is_h) bold_depth++;
          if (table_depth == 1) {
            DocNode *cn = DocPushNode(doc, NODE_TABLE_CELL);
            cn->is_th = is_h;
          }
        } else {
          if (is_h && bold_depth > 0) bold_depth--;
          if (table_depth != 1 && pre_depth == 0) {
            DocNode *sp = DocPushNode(doc, NODE_TEXT);
            sp->text = StrNew("  ");
          }
        }
        continue;
      }

      if (StrCmp(tname, "p") == 0 || StrCmp(tname, "div") == 0 ||
          StrCmp(tname, "section") == 0 || StrCmp(tname, "article") == 0 ||
          StrCmp(tname, "header") == 0 || StrCmp(tname, "footer") == 0 ||
          StrCmp(tname, "main") == 0 || StrCmp(tname, "nav") == 0 ||
          StrCmp(tname, "dl") == 0 || StrCmp(tname, "dt") == 0) {
        if (table_depth == 1) {
          DocPushNode(doc, NODE_LINE_BREAK);
        } else {
          I32 bkind = BLK_PARAGRAPH;
          if (quote_depth > 0) bkind = BLK_QUOTE;
          EmitBlockStart(doc, bkind, list_depth, 0, quote_depth > 0, pre_depth > 0);
        }
        continue;
      }

      if (StrCmp(tname, "dd") == 0) {
        I32 bkind = BLK_PARAGRAPH;
        if (quote_depth > 0) bkind = BLK_QUOTE;
        EmitBlockStart(doc, bkind, list_depth + 1, 0, quote_depth > 0, pre_depth > 0);
        continue;
      }

      if (StrCmp(tname, "blockquote") == 0) {
        if (!closing) quote_depth++;
        else if (quote_depth > 0) quote_depth--;
        I32 bkind = BLK_PARAGRAPH;
        if (quote_depth > 0) bkind = BLK_QUOTE;
        EmitBlockStart(doc, bkind, list_depth, 0, quote_depth > 0, FALSE);
        continue;
      }

      if (StrCmp(tname, "pre") == 0) {
        if (!closing) {
          pre_depth++;
          EmitBlockStart(doc, BLK_PRE, list_depth, 0, quote_depth > 0, TRUE);
        } else {
          if (pre_depth > 0) pre_depth--;
          EmitBlockStart(doc, BLK_PARAGRAPH, list_depth, 0, quote_depth > 0, FALSE);
        }
        continue;
      }

      if (StrCmp(tname, "ul") == 0 || StrCmp(tname, "ol") == 0) {
        if (!closing) {
          if (list_depth < 15) {
            list_ordered[list_depth] = (StrCmp(tname, "ol") == 0);
            list_counter[list_depth] = 0;
            list_depth++;
          }
        } else {
          if (list_depth > 0) list_depth--;
          EmitBlockStart(doc, BLK_PARAGRAPH, list_depth, 0, quote_depth > 0, FALSE);
        }
        continue;
      }

      if (StrCmp(tname, "li") == 0) {
        if (!closing) {
          I32 idx = 0;
          if (list_depth > 0 && list_ordered[list_depth - 1]) {
            list_counter[list_depth - 1]++;
            idx = list_counter[list_depth - 1];
          }
          I32 lindent = 1;
          if (list_depth > 0) lindent = list_depth;
          EmitBlockStart(doc, BLK_LIST_ITEM, lindent, idx, quote_depth > 0, FALSE);
        }
        continue;
      }

      if (StrCmp(tname, "br") == 0 && !closing) {
        DocPushNode(doc, NODE_LINE_BREAK);
        continue;
      }

      if (StrCmp(tname, "hr") == 0 && !closing) {
        DocPushNode(doc, NODE_HR);
        EmitBlockStart(doc, BLK_PARAGRAPH, list_depth, 0, quote_depth > 0, FALSE);
        continue;
      }

      /* Строчное форматирование */
      if (StrCmp(tname, "b") == 0 || StrCmp(tname, "strong") == 0) {
        if (!closing) bold_depth++;
        else if (bold_depth > 0) bold_depth--;
        continue;
      }
      if (StrCmp(tname, "i") == 0 || StrCmp(tname, "em") == 0 || StrCmp(tname, "cite") == 0) {
        if (!closing) italic_depth++;
        else if (italic_depth > 0) italic_depth--;
        continue;
      }
      if (StrCmp(tname, "u") == 0 || StrCmp(tname, "ins") == 0) {
        if (!closing) underline_depth++;
        else if (underline_depth > 0) underline_depth--;
        continue;
      }
      if (StrCmp(tname, "s") == 0 || StrCmp(tname, "del") == 0 || StrCmp(tname, "strike") == 0) {
        if (!closing) strike_depth++;
        else if (strike_depth > 0) strike_depth--;
        continue;
      }
      if (StrCmp(tname, "mark") == 0) {
        if (!closing) mark_depth++;
        else if (mark_depth > 0) mark_depth--;
        continue;
      }
      if (StrCmp(tname, "span") == 0 || StrCmp(tname, "font") == 0) {
        if (!closing) {
          U32 parsed_rgb = 0;
          if (ExtractInlineTextColor(tp, tlen, &parsed_rgb)) {
            has_custom_color = TRUE;
            active_rgb = parsed_rgb;
          }
        } else {
          has_custom_color = FALSE;
        }
        continue;
      }
      if (StrCmp(tname, "code") == 0 || StrCmp(tname, "kbd") == 0 || StrCmp(tname, "tt") == 0) {
        if (!closing) mono_depth++;
        else if (mono_depth > 0) mono_depth--;
        continue;
      }

      if (closing && StrCmp(tname, "button") == 0 && pre_depth == 0) {
        DocNode *sp = DocPushNode(doc, NODE_TEXT);
        sp->text = StrNew("  ");
        continue;
      }

      /* Ссылки и обработчики уже учтены в стеке выше. */
      if (StrCmp(tname, "a") == 0) continue;

      /* Изображения <img src="..." alt="..." width="..." height="..."> */
      if (StrCmp(tname, "img") == 0 && !closing) {
        I64 src_cap = tlen + 64;
        if (src_cap < 2048) src_cap = 2048;
        U8 *src_val = MAlloc(src_cap);
        U8 alt_val[256];
        U8 w_val[32];
        U8 h_val[32];
        src_val[0] = 0;
        alt_val[0] = 0;
        w_val[0] = 0;
        h_val[0] = 0;
        ExtractAttrValue(tp, tlen, "src", src_val, src_cap);
        if (src_val[0] == 0) {
          ExtractAttrValue(tp, tlen, "data-src", src_val, src_cap);
        }
        ExtractAttrValue(tp, tlen, "alt", alt_val, sizeof(alt_val));
        Bool has_w = ExtractAttrValue(tp, tlen, "width", w_val, sizeof(w_val));
        Bool has_h = ExtractAttrValue(tp, tlen, "height", h_val, sizeof(h_val));
        I32 parsed_w = 0;
        I32 parsed_h = 0;
        if (has_w) parsed_w = Atoi(w_val);
        if (has_h) parsed_h = Atoi(h_val);

        /* Пропускаем невидимые 1x1 / 0x0 пиксели счётчиков аналитики */
        Bool is_tiny_pixel = (has_w && has_h && parsed_w <= 2 && parsed_h <= 2);

        if (!is_tiny_pixel && src_val[0] != 0 && doc->image_count < MAX_DOC_IMAGES) {
          I32 iid = doc->image_count++;
          DocImage *im = &doc->images[iid];
          MemSet(im, 0, sizeof(DocImage));
          if (StartsWithIgnoreCase(src_val, "data:")) {
            im->src = StrNew(src_val);
          } else {
            U8 resolved_src[2048];
            UrlResolve(doc->base_url, src_val, resolved_src, sizeof(resolved_src));
            im->src = StrNew(resolved_src);
          }
          im->alt = StrNew(alt_val);
          im->attr_w = parsed_w;
          im->attr_h = parsed_h;

          DocNode *in = DocPushNode(doc, NODE_IMAGE);
          in->img_id = iid;
          in->link_id = tag_link_id;
        } else if (!is_tiny_pixel && alt_val[0] != 0) {
          U8 img_label[300];
          snprintf(img_label, sizeof(img_label), "[Изображение: %s]", alt_val);
          DocNode *in = DocPushNode(doc, NODE_TEXT);
          in->text = StrNew(img_label);
          in->italic = TRUE;
          in->link_id = tag_link_id;
        }
        Free(src_val);
        continue;
      }

      continue;
    }

    /* 3. Чтение текстового фрагмента до следующего '<' */
    I64 tstart = pos;
    while (pos < len && html[pos] != '<') pos++;
    I64 rlen = pos - tstart;
    if (rlen <= 0 || hidden_depth > 0) continue;

    if (in_title) {
      U8 *tdec = DecodeEntitiesAlloc(html + tstart, rlen, TRUE);
      U8 *trim = tdec;
      while (*trim && IsSpace(*trim)) trim++;
      if (*trim != 0) SafeCopy(doc->title, trim, sizeof(doc->title));
      Free(tdec);
      continue;
    }

    if (pre_depth > 0) {
      /* Внутри <pre> сохраняем пробелы и режем по переводам строк */
      I64 line_s = tstart;
      for (I64 k = tstart; k <= pos; k++) {
        if (k == pos || html[k] == '\n') {
          I64 seg_len = k - line_s;
          if (seg_len > 0 && html[line_s + seg_len - 1] == '\r') seg_len--;
          if (seg_len > 0) {
            U8 *dec = DecodeEntitiesAlloc(html + line_s, seg_len, FALSE);
            DocNode *n = DocPushNode(doc, NODE_TEXT);
            n->text = dec;
            n->mono = TRUE;
            n->in_pre = TRUE;
            n->in_quote = (quote_depth > 0);
            n->link_id = current_link_id;
          }
          if (k < pos && html[k] == '\n') {
            DocPushNode(doc, NODE_LINE_BREAK);
          }
          line_s = k + 1;
        }
      }
    } else {
      U8 *dec = DecodeEntitiesAlloc(html + tstart, rlen, TRUE);
      /* Пропускаем чисто пробельные куски в самом начале нового блока */
      Bool only_spaces = TRUE;
      for (I64 j = 0; dec[j]; j++) {
        if (dec[j] != ' ') { only_spaces = FALSE; break; }
      }
      if (only_spaces && doc->node_count > 0 &&
          (doc->nodes[doc->node_count - 1].type == NODE_BLOCK_START ||
           doc->nodes[doc->node_count - 1].type == NODE_LINE_BREAK)) {
        Free(dec);
        continue;
      }
      if (dec[0] != 0) {
        if (in_marquee) {
          DocNode *mn = DocPushNode(doc, NODE_MARQUEE);
          mn->text = dec;
          mn->link_id = current_link_id;
          doc->has_animations = TRUE;
          continue;
        }
        DocNode *n = DocPushNode(doc, NODE_TEXT);
        n->text = dec;
        n->bold = (bold_depth > 0) || (heading_level > 0);
        n->italic = (italic_depth > 0) || (quote_depth > 0);
        n->underline = (underline_depth > 0) || (current_link_id >= 0);
        n->strike = (strike_depth > 0);
        n->in_mark = (mark_depth > 0);
        n->mono = (mono_depth > 0);
        n->heading = heading_level;
        n->indent = list_depth;
        n->in_quote = (quote_depth > 0);
        n->link_id = current_link_id;
        n->has_fg_color = has_custom_color;
        n->fg_rgb = active_rgb;
        if (current_css.has_fg) { n->has_fg_color = TRUE; n->fg_rgb = current_css.fg_rgb; }
        if (current_css.bold_mode != 0) n->bold = current_css.bold_mode > 0;
        if (current_css.italic_mode != 0) n->italic = current_css.italic_mode > 0;
        if (current_css.underline_mode != 0) n->underline = current_css.underline_mode > 0;
        if (current_css.mono) n->mono = TRUE;
        n->css_font_px = current_css.font_px;
      } else {
        Free(dec);
      }
    }
  }
  Free(sheet); Free(ctx); Free(styles); Free(links);
}

/* Мгновенное декодирование локальных/встроенных картинок (data:image/*, file://) без сети */
Bool LoadLocalDocumentImagesOnly(HtmlDocument *doc, Bool *out_has_remote)
{
  Bool any_loaded = FALSE;
  Bool has_remote = FALSE;
  I32 max_fetch = doc->image_count;
  if (max_fetch > 10) max_fetch = 10;

  for (I32 i = 0; i < max_fetch; i++) {
    DocImage *im = &doc->images[i];
    if (im->src == NULL || im->surface != NULL) continue;
    if ((StartsWithIgnoreCase(doc->base_url, "holy://") || StartsWithIgnoreCase(doc->base_url, "cheb://")) &&
        StartsWithIgnoreCase(im->src, "data:image/") && !SafeHolynetEmbeddedImage(im->src)) continue;
    if (StartsWithIgnoreCase(im->src, "data:image/") ||
        (StartsWithIgnoreCase(im->src, "file://") && StartsWithIgnoreCase(doc->base_url, "file://"))) {
      I32 w = 0;
      I32 h = 0;
      im->surface = LoadLocalImageSurfaceForSrc(im->src, &w, &h);
      if (im->surface != NULL && w > 0 && h > 0) {
        im->nat_w = w;
        im->nat_h = h;
        im->loaded = TRUE;
        any_loaded = TRUE;
      }
    } else if ((StartsWithIgnoreCase(im->src, "http://") ||
                StartsWithIgnoreCase(im->src, "https://")) &&
               !IsTrackerBeaconUrl(im->src)) {
      has_remote = TRUE;
    }
  }
  if (out_has_remote != NULL) *out_has_remote = has_remote;
  return any_loaded;
}

/* Параллельная многопоточная загрузка изображений документа (в 5-10 раз быстрее!) */
U0 LoadDocumentImages(HtmlDocument *doc, Bool holynet_mode)
{
  Bool has_remote = FALSE;
  LoadLocalDocumentImagesOnly(doc, &has_remote);

  /* В режиме Holynet внешние HTTP/HTTPS-запросы запрещены, а при отсутствии внешних URL выходим сразу */
  if (holynet_mode || !has_remote) return;

  EnsureHttpGlobals();

  I32 max_fetch = doc->image_count;
  if (max_fetch > 10) max_fetch = 10;

  ParallelImgJob *jobs = CAlloc(MAX_DOC_IMAGES * sizeof(ParallelImgJob));
  I32 job_count = 0;

  /* Предварительно кэшируем DNS уникальных CDN-хостов, чтобы 10 потоков не ждали резолвер */
  for (I32 i = 0; i < max_fetch; i++) {
    DocImage *im = &doc->images[i];
    if (im->src == NULL || im->surface != NULL) continue;
    if (!StartsWithIgnoreCase(im->src, "http://") &&
        !StartsWithIgnoreCase(im->src, "https://")) continue;
    if (IsTrackerBeaconUrl(im->src)) continue;
    ParsedUrl iu;
    UrlParse(im->src, &iu);
    if (iu.host[0] != 0) {
      U32 dummy_ip = 0;
      ResolveHostIpv4Cached(iu.host, &dummy_ip);
    }
  }

  /* Запускаем параллельные потоки только для уникальных URL */
  for (I32 i = 0; i < max_fetch; i++) {
    DocImage *im = &doc->images[i];
    if (im->src == NULL || im->surface != NULL) continue;
    if (!StartsWithIgnoreCase(im->src, "http://") &&
        !StartsWithIgnoreCase(im->src, "https://")) continue;
    if (IsTrackerBeaconUrl(im->src)) continue;

    Bool already_queued = FALSE;
    for (I32 j = 0; j < job_count; j++) {
      if (StrCmp(jobs[j].url, im->src) == 0) {
        already_queued = TRUE;
        break;
      }
    }
    if (already_queued) continue;

    ParallelImgJob *jb = &jobs[job_count];
    jb->url = im->src;
    jb->spawned = FALSE;
    jb->ok = FALSE;
    if (pthread_create(&jb->thread, NULL, &ImgDownloadWorkerFn, jb) == 0) {
      jb->spawned = TRUE;
    } else {
      jb->ok = FetchUrlFast(jb->url, &jb->resp, TRUE);
    }
    job_count++;
  }

  /* Ждём завершения параллельной волны скачивания */
  for (I32 j = 0; j < job_count; j++) {
    if (jobs[j].spawned) {
      pthread_join(jobs[j].thread, NULL);
    }
  }

  /* Декодируем полученные байты в поверхности Cairo на основном потоке */
  for (I32 j = 0; j < job_count; j++) {
    ParallelImgJob *jb = &jobs[j];
    if (jb->ok && jb->resp.status_code == 200 &&
        jb->resp.body != NULL && jb->resp.body_len > 0) {
      for (I32 i = 0; i < max_fetch; i++) {
        DocImage *im = &doc->images[i];
        if (im->src != NULL && im->surface == NULL && StrCmp(im->src, jb->url) == 0) {
          I32 w = 0;
          I32 h = 0;
          im->surface = DecodeBytesToCairoSurface(jb->resp.body, jb->resp.body_len, &w, &h);
          if (im->surface != NULL && w > 0 && h > 0) {
            im->nat_w = w;
            im->nat_h = h;
            im->loaded = TRUE;
          }
        }
      }
    }
    HttpResponseFree(&jb->resp);
  }

  Free(jobs);
}
