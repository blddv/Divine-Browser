Bool StrContainsIgnoreCase(U8 *s, U8 *needle)
{
  I64 n = StrLen(needle);
  while (*s) { if (StrCaseEqLen(s, needle, n)) return TRUE; s++; }
  return n == 0;
}

/* ============================================================================
 * css_legacy.HC — Компактный парсер упрощённого Legacy CSS 2.1 на HolyC
 * Без избыточных CSS3-конструкций: только скалярные значения, классические
 * селекторы (tag, .class, #id, потомок), каскад специфичности и style="...".
 * ============================================================================ */

#define CSS_MAX_RULES     384
#define CSS_ALIGN_INHERIT 0
#define CSS_ALIGN_LEFT    1
#define CSS_ALIGN_CENTER  2
#define CSS_ALIGN_RIGHT   3

class CssProps
{
  Bool has_display;
  Bool display_none;
  Bool display_block;
  Bool has_fg;
  U32  fg_rgb;
  Bool has_bg;
  U32  bg_rgb;
  Bool has_border;
  U32  border_rgb;
  I32  border_px;
  I32  font_px;        /* 0 = наследуется */
  I32  bold_mode;      /* 0 = наследуется, 1 = bold, -1 = normal */
  I32  italic_mode;    /* 0 = наследуется, 1 = italic, -1 = normal */
  I32  underline_mode; /* 0 = наследуется, 1 = underline, -1 = none */
  Bool mono;
  I32  text_align;     /* CSS_ALIGN_* */
  I32  margin_top;     /* -1 = не задано */
  I32  margin_bottom;
  I32  margin_left;
  I32  pad_x;          /* -1 = не задано */
  I32  pad_y;
};

class CssSimpleSel
{
  U8 tag[24];
  U8 id[48];
  U8 cls[48];
};

class CssRule
{
  Bool         has_anc;
  CssSimpleSel anc;
  CssSimpleSel target;
  I32          specificity;
  CssProps     props;
};

class CssSheet
{
  CssRule rules[CSS_MAX_RULES];
  I32     rule_count;
};

class CssElemCtx
{
  U8 tag[24];
  U8 id[48];
  U8 cls[128];
};

U0 CssPropsInit(CssProps *p)
{
  MemSet(p, 0, sizeof(CssProps));
  p->margin_top = -1;
  p->margin_bottom = -1;
  p->margin_left = -1;
  p->pad_x = -1;
  p->pad_y = -1;
}

U0 CssPropsMerge(CssProps *dst, CssProps *src)
{
  if (src->has_display) { dst->has_display = TRUE; dst->display_none = src->display_none; dst->display_block = src->display_block; }
  if (src->has_fg)        { dst->has_fg = TRUE; dst->fg_rgb = src->fg_rgb; }
  if (src->has_bg)        { dst->has_bg = TRUE; dst->bg_rgb = src->bg_rgb; }
  if (src->has_border)    { dst->has_border = TRUE; dst->border_rgb = src->border_rgb; dst->border_px = src->border_px; }
  if (src->font_px > 0)   dst->font_px = src->font_px;
  if (src->bold_mode != 0)      dst->bold_mode = src->bold_mode;
  if (src->italic_mode != 0)    dst->italic_mode = src->italic_mode;
  if (src->underline_mode != 0) dst->underline_mode = src->underline_mode;
  if (src->mono)          dst->mono = TRUE;
  if (src->text_align != 0)     dst->text_align = src->text_align;
  if (src->margin_top >= 0)     dst->margin_top = src->margin_top;
  if (src->margin_bottom >= 0)  dst->margin_bottom = src->margin_bottom;
  if (src->margin_left >= 0)    dst->margin_left = src->margin_left;
  if (src->pad_x >= 0)          dst->pad_x = src->pad_x;
  if (src->pad_y >= 0)          dst->pad_y = src->pad_y;
}

/* Разбор цветов CSS 2.1: #hex, rgb(r,g,b), базовые именованные цвета */
Bool CssParseColor(U8 *raw, U32 *out_rgb)
{
  if (raw == NULL) return FALSE;
  U8 buf[64];
  I32 bi = 0;
  while (*raw && IsSpace(*raw)) raw++;
  while (raw[bi] && bi < 63 && !IsSpace(raw[bi]) && raw[bi] != ';' && raw[bi] != '!') {
    buf[bi] = ToLower(raw[bi]);
    bi++;
  }
  buf[bi] = 0;
  if (buf[0] == 0 || StrCmp(buf, "transparent") == 0 || StrCmp(buf, "inherit") == 0 ||
      StrCmp(buf, "none") == 0 || StrCmp(buf, "initial") == 0) return FALSE;

  if (buf[0] == '#') {
    I32 d[6], n = 0;
    while (n < 6) {
      U8 c = buf[1 + n];
      if (c >= '0' && c <= '9') d[n] = c - '0';
      else if (c >= 'a' && c <= 'f') d[n] = c - 'a' + 10;
      else break;
      n++;
    }
    if (n == 6) { *out_rgb = (((d[0]<<4)|d[1])<<16) | (((d[2]<<4)|d[3])<<8) | ((d[4]<<4)|d[5]); return TRUE; }
    if (n == 3) { *out_rgb = (((d[0]<<4)|d[0])<<16) | (((d[1]<<4)|d[1])<<8) | ((d[2]<<4)|d[2]); return TRUE; }
    return FALSE;
  }

  if (StrCaseEqLen(raw, "rgb", 3)) {
    U8 *lp = strchr(raw, '(');
    if (lp == NULL) return FALSE;
    lp++;
    I32 r = Atoi(lp);
    U8 *c1 = strchr(lp, ','); if (c1 == NULL) return FALSE;
    I32 g = Atoi(c1 + 1);
    U8 *c2 = strchr(c1 + 1, ','); if (c2 == NULL) return FALSE;
    I32 b = Atoi(c2 + 1);
    U8 *c3 = strchr(c2 + 1, ',');
    if (c3 != NULL) {
      U8 *ap = c3 + 1;
      while (*ap && IsSpace(*ap)) ap++;
      if (ap[0] == '0' && ap[1] != '.') return FALSE; /* rgba(..., 0) прозрачен */
    }
    if (r < 0) r = 0; if (r > 255) r = 255;
    if (g < 0) g = 0; if (g > 255) g = 255;
    if (b < 0) b = 0; if (b > 255) b = 255;
    *out_rgb = ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
    return TRUE;
  }

  if (StrCmp(buf, "black") == 0)   { *out_rgb = 0x000000; return TRUE; }
  if (StrCmp(buf, "white") == 0)   { *out_rgb = 0xFFFFFF; return TRUE; }
  if (StrCmp(buf, "red") == 0)     { *out_rgb = 0xFF0000; return TRUE; }
  if (StrCmp(buf, "green") == 0)   { *out_rgb = 0x008000; return TRUE; }
  if (StrCmp(buf, "lime") == 0)    { *out_rgb = 0x00FF00; return TRUE; }
  if (StrCmp(buf, "blue") == 0)    { *out_rgb = 0x0000FF; return TRUE; }
  if (StrCmp(buf, "yellow") == 0)  { *out_rgb = 0xFFFF00; return TRUE; }
  if (StrCmp(buf, "navy") == 0)    { *out_rgb = 0x000080; return TRUE; }
  if (StrCmp(buf, "maroon") == 0)  { *out_rgb = 0x800000; return TRUE; }
  if (StrCmp(buf, "purple") == 0)  { *out_rgb = 0x800080; return TRUE; }
  if (StrCmp(buf, "teal") == 0)    { *out_rgb = 0x008080; return TRUE; }
  if (StrCmp(buf, "olive") == 0)   { *out_rgb = 0x808000; return TRUE; }
  if (StrCmp(buf, "silver") == 0)  { *out_rgb = 0xC0C0C0; return TRUE; }
  if (StrCmp(buf, "gray") == 0 || StrCmp(buf, "grey") == 0) { *out_rgb = 0x808080; return TRUE; }
  if (StrCmp(buf, "lightgray") == 0 || StrCmp(buf, "lightgrey") == 0) { *out_rgb = 0xE0E0E0; return TRUE; }
  if (StrCmp(buf, "darkgray") == 0 || StrCmp(buf, "darkgrey") == 0)   { *out_rgb = 0x555555; return TRUE; }
  if (StrCmp(buf, "whitesmoke") == 0 || StrCmp(buf, "aliceblue") == 0){ *out_rgb = 0xF5F7FA; return TRUE; }
  if (StrCmp(buf, "ivory") == 0 || StrCmp(buf, "beige") == 0)         { *out_rgb = 0xFAF8EE; return TRUE; }
  if (StrCmp(buf, "orange") == 0)  { *out_rgb = 0xE67E00; return TRUE; }
  if (StrCmp(buf, "gold") == 0)    { *out_rgb = 0xD4A017; return TRUE; }
  if (StrCmp(buf, "brown") == 0)   { *out_rgb = 0x8B4513; return TRUE; }
  if (StrCmp(buf, "aqua") == 0 || StrCmp(buf, "cyan") == 0)     { *out_rgb = 0x00AAAA; return TRUE; }
  if (StrCmp(buf, "fuchsia") == 0 || StrCmp(buf, "magenta") == 0){ *out_rgb = 0xAA00AA; return TRUE; }
  return FALSE;
}

/* Скалярная длина CSS 2.1 (px, pt, em, %) -> пиксели (без calc/var) */
I32 CssParsePx(U8 *v, I32 base_px)
{
  if (v == NULL) return -1;
  while (*v && IsSpace(*v)) v++;
  if (StrCaseEqLen(v, "small", 5))   return 13;
  if (StrCaseEqLen(v, "medium", 6))  return 16;
  if (StrCaseEqLen(v, "large", 5))   return 19;
  if (StrCaseEqLen(v, "x-large", 7)) return 24;
  if ((*v < '0' || *v > '9') && *v != '.') return -1;

  I32 whole = 0, frac = 0;
  while (*v >= '0' && *v <= '9') { whole = whole * 10 + (*v - '0'); v++; }
  if (*v == '.') {
    v++;
    if (*v >= '0' && *v <= '9') { frac = *v - '0'; v++; }
    while (*v >= '0' && *v <= '9') v++;
  }
  I32 px = whole;
  if (StrCaseEqLen(v, "em", 2) || StrCaseEqLen(v, "rem", 3)) {
    px = (whole * base_px) + ((frac * base_px) / 10);
  } else if (StrCaseEqLen(v, "pt", 2)) {
    px = (whole * 4) / 3;
  } else if (*v == '%') {
    px = (whole * base_px) / 100;
  }
  if (px < 0) px = 0;
  if (px > 120) px = 120;
  return px;
}

/* Разбор списка деклараций: "color: #123; padding: 8px 12px; display: none" */
U0 CssParseDecls(U8 *s, I64 len, CssProps *p)
{
  I64 i = 0;
  while (i < len) {
    while (i < len && (IsSpace(s[i]) || s[i] == ';')) i++;
    if (i >= len) break;

    I64 ks = i;
    while (i < len && s[i] != ':' && s[i] != ';') i++;
    if (i >= len || s[i] != ':') { while (i < len && s[i] != ';') i++; continue; }
    I64 ke = i;
    while (ke > ks && IsSpace(s[ke - 1])) ke--;
    i++; /* ':' */

    I64 vs = i;
    Bool in_q = FALSE; U8 qc = 0;
    while (i < len) {
      if (in_q) { if (s[i] == qc) in_q = FALSE; }
      else if (s[i] == '"' || s[i] == '\'') { in_q = TRUE; qc = s[i]; }
      else if (s[i] == ';') break;
      i++;
    }
    I64 ve = i;
    while (vs < ve && IsSpace(s[vs])) vs++;
    while (ve > vs && IsSpace(s[ve - 1])) ve--;

    U8 key[48], val[160];
    I64 klen = ke - ks; if (klen > 47) klen = 47;
    for (I64 k = 0; k < klen; k++) key[k] = ToLower(s[ks + k]);
    key[klen] = 0;

    I64 vlen = ve - vs; if (vlen > 159) vlen = 159;
    MemCpy(val, s + vs, vlen); val[vlen] = 0;
    /* Отрезаем !important и пропускаем сложные CSS3-значения var()/calc() */
    U8 *imp = strstr(val, "!important"); if (imp != NULL) *imp = 0;
    if (strstr(val, "var(") != NULL || strstr(val, "calc(") != NULL) continue;

    U32 rgb = 0;
    if (StrCmp(key, "display") == 0) {
      p->has_display = TRUE;
      if (StrCaseEqLen(val, "none", 4)) { p->display_none = TRUE; p->display_block = FALSE; }
      else { p->display_none = FALSE; p->display_block = StrCaseEqLen(val, "block", 5); }
    } else if (StrCmp(key, "visibility") == 0) {
      if (StrCaseEqLen(val, "hidden", 6)) { p->has_display = TRUE; p->display_none = TRUE; }
    } else if (StrCmp(key, "color") == 0) {
      if (CssParseColor(val, &rgb)) { p->has_fg = TRUE; p->fg_rgb = rgb; }
    } else if (StrCmp(key, "background-color") == 0 || StrCmp(key, "background") == 0) {
      if (strstr(val, "gradient") == NULL && strstr(val, "url(") == NULL) {
        U8 * vp = val;
        while (*vp) {
          if (CssParseColor(vp, &rgb)) { p->has_bg = TRUE; p->bg_rgb = rgb; break; }
          while (*vp && !IsSpace(*vp)) vp++;
          while (*vp && IsSpace(*vp)) vp++;
        }
      } else if (!p->has_bg && strstr(val, "gradient") != NULL) {
        /* No gradient engine: use its first simple hex color as a readable fallback. */
        U8 *fallback = strchr(val, '#');
        if (fallback != NULL && CssParseColor(fallback, &rgb)) { p->has_bg = TRUE; p->bg_rgb = rgb; }
      }
    } else if (StrCmp(key, "font-size") == 0) {
      I32 fpx = CssParsePx(val, 16);
      if (fpx >= 9 && fpx <= 56) p->font_px = fpx;
    } else if (StrCmp(key, "font-weight") == 0) {
      if (StrCaseEqLen(val, "bold", 4) || (val[0] >= '6' && val[0] <= '9')) p->bold_mode = 1;
      else if (StrCaseEqLen(val, "normal", 6) || (val[0] >= '1' && val[0] <= '4')) p->bold_mode = -1;
    } else if (StrCmp(key, "font-style") == 0) {
      if (StrCaseEqLen(val, "italic", 6) || StrCaseEqLen(val, "oblique", 7)) p->italic_mode = 1;
      else if (StrCaseEqLen(val, "normal", 6)) p->italic_mode = -1;
    } else if (StrCmp(key, "text-decoration") == 0) {
      if (strstr(val, "underline") != NULL) p->underline_mode = 1;
      else if (StrCaseEqLen(val, "none", 4)) p->underline_mode = -1;
    } else if (StrCmp(key, "font-family") == 0) {
      if (StrContainsIgnoreCase(val, "mono") || StrContainsIgnoreCase(val, "courier") ||
          StrContainsIgnoreCase(val, "consolas")) p->mono = TRUE;
    } else if (StrCmp(key, "text-align") == 0) {
      if (StrCaseEqLen(val, "center", 6)) p->text_align = CSS_ALIGN_CENTER;
      else if (StrCaseEqLen(val, "right", 5)) p->text_align = CSS_ALIGN_RIGHT;
      else if (StrCaseEqLen(val, "left", 4))  p->text_align = CSS_ALIGN_LEFT;
    } else if (StrCmp(key, "margin-top") == 0) {
      p->margin_top = CssParsePx(val, 16);
    } else if (StrCmp(key, "margin-bottom") == 0) {
      p->margin_bottom = CssParsePx(val, 16);
    } else if (StrCmp(key, "margin-left") == 0) {
      p->margin_left = CssParsePx(val, 16);
    } else if (StrCmp(key, "margin") == 0) {
      I32 m1 = CssParsePx(val, 16);
      if (m1 >= 0) { p->margin_top = m1; p->margin_bottom = m1; }
    } else if (StrCmp(key, "padding-left") == 0) {
      p->pad_x = CssParsePx(val, 16);
    } else if (StrCmp(key, "padding-top") == 0 || StrCmp(key, "padding-bottom") == 0) {
      p->pad_y = CssParsePx(val, 16);
    } else if (StrCmp(key, "padding") == 0) {
      I32 py = CssParsePx(val, 16);
      if (py >= 0) {
        p->pad_y = py; p->pad_x = py;
        U8 *nx = val; while (*nx && !IsSpace(*nx)) nx++; while (*nx && IsSpace(*nx)) nx++;
        I32 px2 = CssParsePx(nx, 16);
        if (px2 >= 0) p->pad_x = px2;
      }
    } else if (StrCmp(key, "border") == 0 || StrCmp(key, "border-left") == 0 || StrCmp(key, "border-bottom") == 0) {
      if (StrCaseEqLen(val, "none", 4) || (val[0] == '0' && (val[1] == 0 || IsSpace(val[1]) || val[1] == 'p'))) {
        p->has_border = FALSE;
      } else {
        I32 bpx = CssParsePx(val, 16);
        if (bpx <= 0) bpx = 1;
        p->has_border = TRUE; p->border_px = bpx; p->border_rgb = 0x888888;
        U8 *vp = val;
        while (*vp) {
          if (CssParseColor(vp, &rgb)) { p->border_rgb = rgb; break; }
          while (*vp && !IsSpace(*vp)) vp++; while (*vp && IsSpace(*vp)) vp++;
        }
      }
    } else if (StrCmp(key, "border-color") == 0) {
      if (CssParseColor(val, &rgb)) { p->has_border = TRUE; p->border_rgb = rgb; if (p->border_px <= 0) p->border_px = 1; }
    }
  }
}

Bool CssParseSimpleSel(U8 *tok, CssSimpleSel *out, I32 *io_spec)
{
  MemSet(out, 0, sizeof(CssSimpleSel));
  /* Пропускаем :hover / ::before / ::after и атрибутные селекторы */
  if (strstr(tok, ":hover") != NULL || strstr(tok, ":focus") != NULL ||
      strstr(tok, "::") != NULL || strstr(tok, ":before") != NULL ||
      strstr(tok, ":after") != NULL || strchr(tok, '[') != NULL) return FALSE;

  I32 i = 0;
  if (tok[i] == '*') i++;
  else {
    I32 ti = 0;
    while (tok[i] && tok[i] != '.' && tok[i] != '#' && tok[i] != ':' && ti < 23) {
      out->tag[ti++] = ToLower(tok[i++]);
    }
    out->tag[ti] = 0;
    if (ti > 0) *io_spec += 1;
  }

  while (tok[i]) {
    if (tok[i] == '#') {
      i++; I32 ii = 0;
      while (tok[i] && tok[i] != '.' && tok[i] != '#' && tok[i] != ':' && ii < 47) out->id[ii++] = tok[i++];
      out->id[ii] = 0;
      if (ii > 0) *io_spec += 100;
    } else if (tok[i] == '.') {
      i++; I32 ci = 0;
      while (tok[i] && tok[i] != '.' && tok[i] != '#' && tok[i] != ':' && ci < 47) out->cls[ci++] = tok[i++];
      out->cls[ci] = 0;
      if (ci > 0) *io_spec += 10;
    } else if (tok[i] == ':') {
      /* :link / :visited трактуем как базовый элемент */
      while (tok[i] && tok[i] != '.' && tok[i] != '#') i++;
    } else i++;
  }
  return (out->tag[0] != 0 || out->id[0] != 0 || out->cls[0] != 0 || tok[0] == '*');
}

U0 CssParseStylesheet(CssSheet *sheet, U8 *css, I64 len)
{
  if (sheet == NULL || css == NULL || len <= 0) return;
  /* Предварительно удаляем комментарии в буфере-копии. */
  U8 *clean = MAlloc(len + 2);
  I64 o = 0, i = 0;
  while (i < len) {
    if (i + 1 < len && css[i] == '/' && css[i + 1] == '*') {
      i += 2;
      while (i + 1 < len && !(css[i] == '*' && css[i + 1] == '/')) i++;
      if (i + 1 < len) i += 2; else i = len;
      clean[o++] = ' ';
    } else {
      clean[o++] = css[i++];
    }
  }
  clean[o] = 0;

  I64 p = 0;
  while (p < o && sheet->rule_count < CSS_MAX_RULES) {
    while (p < o && (IsSpace(clean[p]) || clean[p] == '}')) p++;
    if (p >= o) break;

    /* Обработка @-правил CSS 2.1 */
    if (clean[p] == '@') {
      I64 at_start = p;
      while (p < o && clean[p] != '{' && clean[p] != ';') p++;
      U8 save = clean[p]; clean[p] = 0;
      Bool allow_inner = (StrCaseEqLen(clean + at_start, "@media", 6) &&
                          !StrContainsIgnoreCase(clean + at_start, "print"));
      clean[p] = save;
      if (p < o && clean[p] == ';') { p++; continue; }
      if (p < o && clean[p] == '{') {
        p++;
        if (allow_inner) continue; /* Разворачиваем правила внутри @media screen/all */
        I32 depth = 1;
        while (p < o && depth > 0) {
          if (clean[p] == '{') depth++;
          else if (clean[p] == '}') depth--;
          p++;
        }
      }
      continue;
    }

    I64 sel_s = p;
    while (p < o && clean[p] != '{') p++;
    if (p >= o) break;
    I64 sel_e = p;
    p++; /* '{' */

    I64 body_s = p;
    I32 bdepth = 1;
    while (p < o && bdepth > 0) {
      if (clean[p] == '{') bdepth++;
      else if (clean[p] == '}') bdepth--;
      p++;
    }
    I64 body_e = p - 1;
    if (body_e < body_s) continue;

    CssProps parsed_props;
    CssPropsInit(&parsed_props);
    CssParseDecls(clean + body_s, body_e - body_s, &parsed_props);

    /* Разбиваем группу селекторов через запятую: h1, .title, #main p */
    I64 gs = sel_s;
    while (gs < sel_e && sheet->rule_count < CSS_MAX_RULES) {
      I64 ge = gs;
      while (ge < sel_e && clean[ge] != ',') ge++;
      I64 ts = gs, te = ge;
      while (ts < te && IsSpace(clean[ts])) ts++;
      while (te > ts && IsSpace(clean[te - 1])) te--;
      gs = ge + 1;
      if (te <= ts || te - ts > 120) continue;

      /* Берём до 2 значимых частей селектора (предок + цель), игнорируя '>' / '+' */
      U8 toks[4][64];
      I32 tc = 0;
      I64 k = ts;
      while (k < te && tc < 4) {
        while (k < te && (IsSpace(clean[k]) || clean[k] == '>' || clean[k] == '+')) k++;
        if (k >= te) break;
        I32 ti = 0;
        while (k < te && !IsSpace(clean[k]) && clean[k] != '>' && clean[k] != '+' && ti < 63)
          toks[tc][ti++] = clean[k++];
        toks[tc][ti] = 0;
        if (ti > 0) tc++;
      }
      if (tc == 0) continue;

      CssRule *r = &sheet->rules[sheet->rule_count];
      MemSet(r, 0, sizeof(CssRule));
      I32 spec = 0;
      if (!CssParseSimpleSel(toks[tc - 1], &r->target, &spec)) continue;
      if (tc >= 2) {
        if (!CssParseSimpleSel(toks[tc - 2], &r->anc, &spec)) continue;
        r->has_anc = TRUE;
      }
      r->specificity = spec;
      MemCpy(&r->props, &parsed_props, sizeof(CssProps));
      sheet->rule_count++;
    }
  }
  Free(clean);
}

Bool CssClassListHas(U8 *cls_list, U8 *want)
{
  if (want == NULL || want[0] == 0) return TRUE;
  if (cls_list == NULL || cls_list[0] == 0) return FALSE;
  I64 wlen = StrLen(want), i = 0;
  while (cls_list[i]) {
    while (cls_list[i] && IsSpace(cls_list[i])) i++;
    I64 s = i;
    while (cls_list[i] && !IsSpace(cls_list[i])) i++;
    if (i - s == wlen && StrNCmp(cls_list + s, want, wlen) == 0) return TRUE;
  }
  return FALSE;
}

Bool CssMatchSimple(CssSimpleSel *sel, CssElemCtx *el)
{
  if (sel->tag[0] != 0 && StrCmp(sel->tag, el->tag) != 0) return FALSE;
  if (sel->id[0] != 0  && StrCmp(sel->id, el->id) != 0)   return FALSE;
  if (sel->cls[0] != 0 && !CssClassListHas(el->cls, sel->cls)) return FALSE;
  return TRUE;
}

U0 CssComputeForElement(CssSheet *sheet, CssElemCtx *anc_stack, I32 anc_depth,
                        CssElemCtx *cur, U8 *inline_style, CssProps *out)
{
  CssPropsInit(out);
  if (sheet != NULL && sheet->rule_count > 0) {
    /* Простой каскад в 3 прохода по возрастанию специфичности (tag -> class -> id) */
    for (I32 i = 0; i < sheet->rule_count; i++) {
        CssRule *r = &sheet->rules[i];
        if (!CssMatchSimple(&r->target, cur)) continue;
        if (r->has_anc) {
          Bool anc_ok = FALSE;
          for (I32 a = anc_depth - 1; a >= 0; a--) {
            if (CssMatchSimple(&r->anc, &anc_stack[a])) { anc_ok = TRUE; break; }
          }
          if (!anc_ok) continue;
        }
        CssPropsMerge(out, &r->props);
    }
  }
  if (inline_style != NULL && inline_style[0] != 0) {
    CssParseDecls(inline_style, StrLen(inline_style), out);
  }
}
