/* ============================================================================
 * layout_render.HC — 2D Layout Engine v2.0 (таблицы, картинки, зум, вкладки,
 * панель закладок, поиск на странице Ctrl+F) на Cairo + HolyC
 * ============================================================================ */

#define TABS_H          28
#define NAVBAR_H        44
#define BOOKMARKS_H     26
#define TOOLBAR_H       98   /* TABS_H + NAVBAR_H + BOOKMARKS_H */
#define STATUSBAR_H     26
#define SCROLLBAR_W     14

#define THEME_TEMPLE    0
#define THEME_MODERN    1
#define THEME_HOLYNET   2
#define THEME_DAVIS     3   /* «Одобрение Дэвиса» — строго 16 цветов VGA, моноширинный шрифт, без сглаживания! */

#define RITEM_TEXT       1
#define RITEM_PRE_BG     2
#define RITEM_CODE_BG    3
#define RITEM_QUOTE_BAR  4
#define RITEM_HR         5
#define RITEM_H1_LINE    6
#define RITEM_IMAGE      7
#define RITEM_MARK_BG    8
#define RITEM_TBL_HDR_BG 9
#define RITEM_TBL_ROW_BG 10
#define RITEM_TBL_BORDER 11
#define RITEM_ANIM_CANVAS 12
#define RITEM_MARQUEE     13

/* Идентификаторы кнопок интерфейса */
#define BTN_NONE          0
#define BTN_BACK          1
#define BTN_FWD           2
#define BTN_RELOAD        3
#define BTN_HOME          4
#define BTN_GO            5
#define BTN_THEME         6
#define BTN_ADDRBAR       7
#define BTN_HOLY_TOGGLE   8
#define BTN_BUILDER       9
#define BTN_MONITOR       10
#define BTN_SEARCH        11
#define BTN_BOOKMARK_STAR 12
#define BTN_ZOOM_OUT      13
#define BTN_ZOOM_IN       14
#define BTN_FIND_TOGGLE   15
#define BTN_NEW_TAB       16
#define BTN_FIND_PREV     17
#define BTN_FIND_NEXT     18
#define BTN_FIND_CLOSE    19
#define BTN_FIND_INPUT    20

/* Диапазоны индексов для кликов по вкладкам, крестикам вкладок и закладкам */
#define BTN_TAB_BASE       100  /* 100..107 */
#define BTN_TAB_CLOSE_BASE 120  /* 120..127 */
#define BTN_BMARK_BASE     200  /* 200..215 */

#define MAX_TABS        8
#define MAX_BOOKMARKS   10

class ColorRGB
{
  F64 r, g, b;
};

class ThemePalette
{
  ColorRGB tabbar_bg;
  ColorRGB tab_active_bg;
  ColorRGB tab_inactive_bg;
  ColorRGB toolbar_bg;
  ColorRGB toolbar_border;
  ColorRGB bmark_bg;
  ColorRGB btn_bg;
  ColorRGB btn_hover;
  ColorRGB btn_fg;
  ColorRGB addr_bg;
  ColorRGB addr_fg;
  ColorRGB addr_border;
  ColorRGB addr_focus;
  ColorRGB page_bg;
  ColorRGB text_fg;
  ColorRGB heading_fg;
  ColorRGB link_fg;
  ColorRGB link_hover;
  ColorRGB quote_bar;
  ColorRGB quote_fg;
  ColorRGB pre_bg;
  ColorRGB pre_fg;
  ColorRGB pre_border;
  ColorRGB code_bg;
  ColorRGB code_fg;
  ColorRGB tbl_hdr_bg;
  ColorRGB tbl_zebra_bg;
  ColorRGB tbl_border;
  ColorRGB hr_fg;
  ColorRGB status_bg;
  ColorRGB status_fg;
  ColorRGB scroll_track;
  ColorRGB scroll_thumb;
};

class RenderItem
{
  I32  kind;
  F64  x, y, w, h;
  F64  font_size;
  I32  link_id;
  I32  img_id;
  I32  anim_kind;
  I32  heading;
  Bool bold;
  Bool italic;
  Bool underline;
  Bool strike;
  Bool mono;
  Bool in_quote;
  Bool in_pre;
  Bool has_fg_color;
  U32  fg_rgb;
  U8  *text;
};

class PageLayout
{
  RenderItem *items;
  I64         count;
  I64         cap;
  F64         content_height;
  I32         viewport_w;
};

class BookmarkEntry
{
  Bool used;
  U8   title[64];
  U8   url[512];
};

class TabStripItem
{
  U8   title[256];
  Bool holy_mode;
};

class ChromeUiState
{
  TabStripItem  tabs[MAX_TABS];
  I32           tab_count;
  I32           active_tab;
  BookmarkEntry bookmarks[MAX_BOOKMARKS];
  I32           bookmark_count;
  Bool          current_is_bookmarked;
  F64           zoom;

  /* Панель поиска на странице (Ctrl+F) */
  Bool          find_active;
  Bool          find_focused;
  U8            find_query[128];
  U8            find_query_low[128];
  I32           find_total;
  I32           find_current;      /* 0-based индекс текущего совпадения */
  I64           find_active_item;  /* индекс RenderItem для подсветки оранжевым */
};

U0 SetRGB(ColorRGB *c, F64 r, F64 g, F64 b)
{
  c->r = r; c->g = g; c->b = b;
}

U0 ApplyColor(U0 *cr, ColorRGB *c)
{
  cairo_set_source_rgb(cr, c->r, c->g, c->b);
}

/* ============================================================================
 * Подсистема темы «Одобрение Дэвиса» (Заветы Терри А. Дэвиса / TempleOS):
 *   1. Строго 16 канонических цветов EGA/VGA (0x00, 0x55, 0xAA, 0xFF) везде!
 *   2. Единый моноширинный шрифт без сглаживания (CAIRO_ANTIALIAS_NONE)!
 *   3. Упорядоченный дизеринг Байера 4x4 всех картинок <img> в 16 цветов VGA!
 *   4. Аппаратный контроль кадра: ни одного 17-го цвета ни на одном пикселе!
 * ============================================================================ */

Bool g_davis_mono_mode = FALSE;
Bool g_davis_vga_ready = FALSE;
U8   g_davis_r[16];
U8   g_davis_g[16];
U8   g_davis_b[16];
I32  g_bayer4x4[16];

U0 SetDavisEntry(I32 idx, U8 r, U8 g, U8 b)
{
  g_davis_r[idx] = r;
  g_davis_g[idx] = g;
  g_davis_b[idx] = b;
}

U0 EnsureDavisVgaTable()
{
  if (g_davis_vga_ready) return;
  SetDavisEntry(0,  0x00, 0x00, 0x00); /* 0  BLACK    */
  SetDavisEntry(1,  0x00, 0x00, 0xAA); /* 1  BLUE     */
  SetDavisEntry(2,  0x00, 0xAA, 0x00); /* 2  GREEN    */
  SetDavisEntry(3,  0x00, 0xAA, 0xAA); /* 3  CYAN     */
  SetDavisEntry(4,  0xAA, 0x00, 0x00); /* 4  RED      */
  SetDavisEntry(5,  0xAA, 0x00, 0xAA); /* 5  PURPLE   */
  SetDavisEntry(6,  0xAA, 0x55, 0x00); /* 6  BROWN    */
  SetDavisEntry(7,  0xAA, 0xAA, 0xAA); /* 7  LTGRAY   */
  SetDavisEntry(8,  0x55, 0x55, 0x55); /* 8  DKGRAY   */
  SetDavisEntry(9,  0x55, 0x55, 0xFF); /* 9  LTBLUE   */
  SetDavisEntry(10, 0x55, 0xFF, 0x55); /* 10 LTGREEN  */
  SetDavisEntry(11, 0x55, 0xFF, 0xFF); /* 11 LTCYAN   */
  SetDavisEntry(12, 0xFF, 0x55, 0x55); /* 12 LTRED    */
  SetDavisEntry(13, 0xFF, 0x55, 0xFF); /* 13 LTPURPLE */
  SetDavisEntry(14, 0xFF, 0xFF, 0x55); /* 14 YELLOW   */
  SetDavisEntry(15, 0xFF, 0xFF, 0xFF); /* 15 WHITE    */

  /* Классическая матрица дизеринга Байера 4x4 (0..15) */
  g_bayer4x4[0]  =  0; g_bayer4x4[1]  =  8; g_bayer4x4[2]  =  2; g_bayer4x4[3]  = 10;
  g_bayer4x4[4]  = 12; g_bayer4x4[5]  =  4; g_bayer4x4[6]  = 14; g_bayer4x4[7]  =  6;
  g_bayer4x4[8]  =  3; g_bayer4x4[9]  = 11; g_bayer4x4[10] =  1; g_bayer4x4[11] =  9;
  g_bayer4x4[12] = 15; g_bayer4x4[13] =  7; g_bayer4x4[14] = 13; g_bayer4x4[15] =  5;

  g_davis_vga_ready = TRUE;
}

I32 NearestDavisVgaIdx(I32 r, I32 g, I32 b, Bool forbid_bright_on_white)
{
  EnsureDavisVgaTable();
  if (r < 0) r = 0;
  if (r > 255) r = 255;
  if (g < 0) g = 0;
  if (g > 255) g = 255;
  if (b < 0) b = 0;
  if (b > 255) b = 255;

  I32 best_idx = 0;
  I32 best_dist = 100000000;
  for (I32 i = 0; i < 16; i++) {
    /* На белом листе DolDoc текст не должен становиться белым или бледно-жёлтым */
    if (forbid_bright_on_white && (i == 15 || i == 14 || i == 11 || i == 10 || i == 7)) {
      continue;
    }
    I32 dr = r - g_davis_r[i];
    I32 dg = g - g_davis_g[i];
    I32 db = b - g_davis_b[i];
    I32 dist = dr * dr + dg * dg + db * db;
    if (dist < best_dist) {
      best_dist = dist;
      best_idx = i;
    }
  }
  return best_idx;
}

U0 SetDavisColorIdx(ColorRGB *c, I32 idx)
{
  EnsureDavisVgaTable();
  c->r = g_davis_r[idx] / 255.0;
  c->g = g_davis_g[idx] / 255.0;
  c->b = g_davis_b[idx] / 255.0;
}

U0 ApplyDavisColorIdx(U0 *cr, I32 idx)
{
  EnsureDavisVgaTable();
  cairo_set_source_rgb(cr, g_davis_r[idx] / 255.0, g_davis_g[idx] / 255.0, g_davis_b[idx] / 255.0);
}

/* Переключение контекста Cairo между строгим битовым режимом Дэвиса и обычным режимом */
U0 SetCairoDavisMode(U0 *cr, Bool davis_on)
{
  g_davis_mono_mode = davis_on;
  if (cr == NULL) return;
  U0 *fopt = cairo_font_options_create();
  if (davis_on) {
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_NONE);
    cairo_font_options_set_antialias(fopt, CAIRO_ANTIALIAS_NONE);
  } else {
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_DEFAULT);
    cairo_font_options_set_antialias(fopt, CAIRO_ANTIALIAS_DEFAULT);
  }
  cairo_set_font_options(cr, fopt);
  cairo_font_options_destroy(fopt);
}

/* Создание 16-цветной дизеризованной (Bayer 4x4) поверхности для картинки <img> */
U0 *GetOrBuildDavis16ImageSurface(DocImage *im)
{
  if (im == NULL || !im->loaded || im->surface == NULL) return NULL;
  if (im->davis_surface != NULL) return im->davis_surface;

  EnsureDavisVgaTable();
  I32 w = im->nat_w;
  I32 h = im->nat_h;
  if (w <= 0 || h <= 0) return im->surface;

  cairo_surface_flush(im->surface);
  U8 *src_data = cairo_image_surface_get_data(im->surface);
  I32 src_stride = cairo_image_surface_get_stride(im->surface);

  U0 *dsurf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  U8 *dst_data = cairo_image_surface_get_data(dsurf);
  I32 dst_stride = cairo_image_surface_get_stride(dsurf);

  for (I32 y = 0; y < h; y++) {
    U8 *srow = src_data + y * src_stride;
    U8 *drow = dst_data + y * dst_stride;
    I32 by = (y & 3) * 4;
    for (I32 x = 0; x < w; x++) {
      U8 b = srow[x * 4 + 0];
      U8 g = srow[x * 4 + 1];
      U8 r = srow[x * 4 + 2];
      U8 a = srow[x * 4 + 3];

      /* 1-битная прозрачность спрайта в стиле TempleOS */
      if (a < 96) {
        drow[x * 4 + 0] = 0;
        drow[x * 4 + 1] = 0;
        drow[x * 4 + 2] = 0;
        drow[x * 4 + 3] = 0;
      } else {
        /* Восстанавливаем непремультиплицированный RGB */
        I32 ur = (r * 255) / a;
        I32 ug = (g * 255) / a;
        I32 ub = (b * 255) / a;

        /* Смещение порога по матрице Байера 4x4 (-30 .. +30) */
        I32 dither = (g_bayer4x4[by + (x & 3)] - 8) * 4;
        I32 idx = NearestDavisVgaIdx(ur + dither, ug + dither, ub + dither, FALSE);

        drow[x * 4 + 0] = g_davis_b[idx];
        drow[x * 4 + 1] = g_davis_g[idx];
        drow[x * 4 + 2] = g_davis_r[idx];
        drow[x * 4 + 3] = 255;
      }
    }
  }

  cairo_surface_mark_dirty(dsurf);
  im->davis_surface = dsurf;
  return dsurf;
}

/* Жёсткий финальный проход по буферу кадра: гарантирует <= 16 цветов VGA на всём экране! */
U0 EnforceDavis16Surface(U0 *surf)
{
  if (surf == NULL) return;
  EnsureDavisVgaTable();
  cairo_surface_flush(surf);

  I32 w = cairo_image_surface_get_width(surf);
  I32 h = cairo_image_surface_get_height(surf);
  U8 *data = cairo_image_surface_get_data(surf);
  I32 stride = cairo_image_surface_get_stride(surf);

  for (I32 y = 0; y < h; y++) {
    U8 *row = data + y * stride;
    for (I32 x = 0; x < w; x++) {
      U8 b = row[x * 4 + 0];
      U8 g = row[x * 4 + 1];
      U8 r = row[x * 4 + 2];

      /* Быстрый выход, если пиксель уже кратен сетке 0x00/0x55/0xAA/0xFF */
      I32 idx = NearestDavisVgaIdx(r, g, b, FALSE);
      row[x * 4 + 0] = g_davis_b[idx];
      row[x * 4 + 1] = g_davis_g[idx];
      row[x * 4 + 2] = g_davis_r[idx];
      row[x * 4 + 3] = 255;
    }
  }
  cairo_surface_mark_dirty(surf);
}

/* Приведение UTF-8 строки (русская кириллица А-Я, Ё/ё + латиница A-Z) к нижнему регистру */
U0 Utf8LowerFold(U8 *src, U8 *dst, I64 cap)
{
  I64 o = 0;
  if (src == NULL || cap <= 0) {
    if (cap > 0) dst[0] = 0;
    return;
  }
  I64 i = 0;
  while (src[i] && o + 3 < cap) {
    U8 b0 = src[i];
    U8 b1 = src[i + 1];
    if (b0 >= 'A' && b0 <= 'Z') {
      dst[o++] = b0 + 32;
      i++;
    } else if (b0 == 0xD0 && b1 == 0x81) {
      dst[o++] = 0xD0; dst[o++] = 0xB5; i += 2;
    } else if (b0 == 0xD1 && b1 == 0x91) {
      dst[o++] = 0xD0; dst[o++] = 0xB5; i += 2;
    } else if (b0 == 0xD0 && b1 >= 0x90 && b1 <= 0x9F) {
      dst[o++] = 0xD0; dst[o++] = b1 + 0x20; i += 2;
    } else if (b0 == 0xD0 && b1 >= 0xA0 && b1 <= 0xAF) {
      dst[o++] = 0xD1; dst[o++] = b1 - 0x20; i += 2;
    } else {
      dst[o++] = b0;
      i++;
    }
  }
  dst[o] = 0;
}

U0 GetThemePalette(I32 theme_id, ThemePalette *p)
{
  if (theme_id == THEME_TEMPLE) {
    SetRGB(&p->tabbar_bg,       0.00, 0.00, 0.42);
    SetRGB(&p->tab_active_bg,   0.00, 0.00, 0.67);
    SetRGB(&p->tab_inactive_bg, 0.00, 0.14, 0.48);
    SetRGB(&p->toolbar_bg,      0.00, 0.00, 0.67);
    SetRGB(&p->toolbar_border,  0.00, 0.67, 0.67);
    SetRGB(&p->bmark_bg,        0.00, 0.12, 0.54);
    SetRGB(&p->btn_bg,          0.00, 0.33, 0.67);
    SetRGB(&p->btn_hover,       0.00, 0.67, 0.67);
    SetRGB(&p->btn_fg,          1.00, 1.00, 0.33);
    SetRGB(&p->addr_bg,         1.00, 1.00, 1.00);
    SetRGB(&p->addr_fg,         0.00, 0.00, 0.00);
    SetRGB(&p->addr_border,     0.67, 0.67, 0.67);
    SetRGB(&p->addr_focus,      1.00, 1.00, 0.33);
    SetRGB(&p->page_bg,         0.97, 0.99, 1.00);
    SetRGB(&p->text_fg,         0.05, 0.05, 0.12);
    SetRGB(&p->heading_fg,      0.00, 0.00, 0.67);
    SetRGB(&p->link_fg,         0.67, 0.00, 0.00);
    SetRGB(&p->link_hover,      0.85, 0.00, 0.67);
    SetRGB(&p->quote_bar,       0.00, 0.67, 0.67);
    SetRGB(&p->quote_fg,        0.00, 0.35, 0.35);
    SetRGB(&p->pre_bg,          0.00, 0.05, 0.32);
    SetRGB(&p->pre_fg,          0.33, 1.00, 1.00);
    SetRGB(&p->pre_border,      0.00, 0.67, 0.67);
    SetRGB(&p->code_bg,         0.86, 0.95, 0.98);
    SetRGB(&p->code_fg,         0.00, 0.25, 0.55);
    SetRGB(&p->tbl_hdr_bg,      0.84, 0.92, 0.99);
    SetRGB(&p->tbl_zebra_bg,    0.93, 0.97, 1.00);
    SetRGB(&p->tbl_border,      0.62, 0.78, 0.90);
    SetRGB(&p->hr_fg,           0.00, 0.67, 0.67);
    SetRGB(&p->status_bg,       0.00, 0.00, 0.50);
    SetRGB(&p->status_fg,       0.33, 1.00, 1.00);
    SetRGB(&p->scroll_track,    0.85, 0.90, 0.96);
    SetRGB(&p->scroll_thumb,    0.00, 0.42, 0.72);
  } else if (theme_id == THEME_HOLYNET) {
    SetRGB(&p->tabbar_bg,       0.03, 0.18, 0.12);
    SetRGB(&p->tab_active_bg,   0.05, 0.28, 0.19);
    SetRGB(&p->tab_inactive_bg, 0.04, 0.22, 0.15);
    SetRGB(&p->toolbar_bg,      0.05, 0.28, 0.19);
    SetRGB(&p->toolbar_border,  0.85, 0.68, 0.25);
    SetRGB(&p->bmark_bg,        0.04, 0.23, 0.16);
    SetRGB(&p->btn_bg,          0.08, 0.38, 0.26);
    SetRGB(&p->btn_hover,       0.12, 0.50, 0.34);
    SetRGB(&p->btn_fg,          0.99, 0.92, 0.62);
    SetRGB(&p->addr_bg,         1.00, 0.99, 0.96);
    SetRGB(&p->addr_fg,         0.06, 0.14, 0.10);
    SetRGB(&p->addr_border,     0.65, 0.72, 0.65);
    SetRGB(&p->addr_focus,      0.95, 0.75, 0.22);
    SetRGB(&p->page_bg,         0.99, 0.98, 0.95);
    SetRGB(&p->text_fg,         0.10, 0.14, 0.11);
    SetRGB(&p->heading_fg,      0.06, 0.32, 0.21);
    SetRGB(&p->link_fg,         0.72, 0.14, 0.14);
    SetRGB(&p->link_hover,      0.07, 0.48, 0.30);
    SetRGB(&p->quote_bar,       0.82, 0.58, 0.14);
    SetRGB(&p->quote_fg,        0.26, 0.22, 0.12);
    SetRGB(&p->pre_bg,          0.06, 0.20, 0.14);
    SetRGB(&p->pre_fg,          0.72, 0.98, 0.80);
    SetRGB(&p->pre_border,      0.25, 0.58, 0.40);
    SetRGB(&p->code_bg,         0.91, 0.95, 0.91);
    SetRGB(&p->code_fg,         0.06, 0.35, 0.22);
    SetRGB(&p->tbl_hdr_bg,      0.85, 0.93, 0.86);
    SetRGB(&p->tbl_zebra_bg,    0.95, 0.96, 0.91);
    SetRGB(&p->tbl_border,      0.70, 0.78, 0.68);
    SetRGB(&p->hr_fg,           0.78, 0.74, 0.64);
    SetRGB(&p->status_bg,       0.04, 0.22, 0.15);
    SetRGB(&p->status_fg,       0.98, 0.90, 0.60);
    SetRGB(&p->scroll_track,    0.91, 0.92, 0.88);
    SetRGB(&p->scroll_thumb,    0.12, 0.45, 0.31);
  } else if (theme_id == THEME_DAVIS) {
    /* «Одобрение Дэвиса» — строго из 16 канонических цветов VGA (индексы 0..15)! */
    EnsureDavisVgaTable();
    SetDavisColorIdx(&p->tabbar_bg,       0);  /* BLACK   #000000 */
    SetDavisColorIdx(&p->tab_active_bg,   1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->tab_inactive_bg, 8);  /* DKGRAY  #555555 */
    SetDavisColorIdx(&p->toolbar_bg,      1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->toolbar_border,  11); /* LTCYAN  #55FFFF */
    SetDavisColorIdx(&p->bmark_bg,        3);  /* CYAN    #00AAAA */
    SetDavisColorIdx(&p->btn_bg,          1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->btn_hover,       5);  /* PURPLE  #AA00AA */
    SetDavisColorIdx(&p->btn_fg,          14); /* YELLOW  #FFFF55 */
    SetDavisColorIdx(&p->addr_bg,         15); /* WHITE   #FFFFFF */
    SetDavisColorIdx(&p->addr_fg,         0);  /* BLACK   #000000 */
    SetDavisColorIdx(&p->addr_border,     11); /* LTCYAN  #55FFFF */
    SetDavisColorIdx(&p->addr_focus,      14); /* YELLOW  #FFFF55 */
    SetDavisColorIdx(&p->page_bg,         15); /* WHITE   #FFFFFF (DolDoc лист!) */
    SetDavisColorIdx(&p->text_fg,         0);  /* BLACK   #000000 */
    SetDavisColorIdx(&p->heading_fg,      1);  /* BLUE    #0000AA ($FG,BLUE$) */
    SetDavisColorIdx(&p->link_fg,         4);  /* RED     #AA0000 ($LK,"...",A="..."$) */
    SetDavisColorIdx(&p->link_hover,      5);  /* PURPLE  #AA00AA */
    SetDavisColorIdx(&p->quote_bar,       2);  /* GREEN   #00AA00 */
    SetDavisColorIdx(&p->quote_fg,        2);  /* GREEN   #00AA00 */
    SetDavisColorIdx(&p->pre_bg,          0);  /* BLACK   #000000 */
    SetDavisColorIdx(&p->pre_fg,          11); /* LTCYAN  #55FFFF */
    SetDavisColorIdx(&p->pre_border,      1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->code_bg,         7);  /* LTGRAY  #AAAAAA */
    SetDavisColorIdx(&p->code_fg,         1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->tbl_hdr_bg,      11); /* LTCYAN  #55FFFF */
    SetDavisColorIdx(&p->tbl_zebra_bg,    15); /* WHITE   #FFFFFF */
    SetDavisColorIdx(&p->tbl_border,      1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->hr_fg,           6);  /* BROWN   #AA5500 */
    SetDavisColorIdx(&p->status_bg,       1);  /* BLUE    #0000AA */
    SetDavisColorIdx(&p->status_fg,       14); /* YELLOW  #FFFF55 */
    SetDavisColorIdx(&p->scroll_track,    7);  /* LTGRAY  #AAAAAA */
    SetDavisColorIdx(&p->scroll_thumb,    1);  /* BLUE    #0000AA */
  } else {
    SetRGB(&p->tabbar_bg,       0.85, 0.88, 0.93);
    SetRGB(&p->tab_active_bg,   0.95, 0.97, 0.99);
    SetRGB(&p->tab_inactive_bg, 0.89, 0.92, 0.96);
    SetRGB(&p->toolbar_bg,      0.95, 0.97, 0.99);
    SetRGB(&p->toolbar_border,  0.78, 0.82, 0.88);
    SetRGB(&p->bmark_bg,        0.92, 0.94, 0.98);
    SetRGB(&p->btn_bg,          1.00, 1.00, 1.00);
    SetRGB(&p->btn_hover,       0.88, 0.92, 0.98);
    SetRGB(&p->btn_fg,          0.15, 0.20, 0.30);
    SetRGB(&p->addr_bg,         1.00, 1.00, 1.00);
    SetRGB(&p->addr_fg,         0.08, 0.12, 0.20);
    SetRGB(&p->addr_border,     0.76, 0.81, 0.88);
    SetRGB(&p->addr_focus,      0.15, 0.39, 0.92);
    SetRGB(&p->page_bg,         1.00, 1.00, 1.00);
    SetRGB(&p->text_fg,         0.12, 0.16, 0.23);
    SetRGB(&p->heading_fg,      0.06, 0.09, 0.16);
    SetRGB(&p->link_fg,         0.15, 0.39, 0.92);
    SetRGB(&p->link_hover,      0.11, 0.25, 0.69);
    SetRGB(&p->quote_bar,       0.39, 0.40, 0.95);
    SetRGB(&p->quote_fg,        0.28, 0.33, 0.42);
    SetRGB(&p->pre_bg,          0.95, 0.96, 0.98);
    SetRGB(&p->pre_fg,          0.12, 0.18, 0.28);
    SetRGB(&p->pre_border,      0.82, 0.86, 0.91);
    SetRGB(&p->code_bg,         0.93, 0.95, 0.98);
    SetRGB(&p->code_fg,         0.75, 0.15, 0.35);
    SetRGB(&p->tbl_hdr_bg,      0.91, 0.94, 0.99);
    SetRGB(&p->tbl_zebra_bg,    0.97, 0.98, 1.00);
    SetRGB(&p->tbl_border,      0.82, 0.86, 0.92);
    SetRGB(&p->hr_fg,           0.84, 0.87, 0.92);
    SetRGB(&p->status_bg,       0.94, 0.96, 0.98);
    SetRGB(&p->status_fg,       0.28, 0.34, 0.43);
    SetRGB(&p->scroll_track,    0.94, 0.95, 0.97);
    SetRGB(&p->scroll_thumb,    0.64, 0.70, 0.78);
  }
}

U0 LayoutInit(PageLayout *lyt)
{
  MemSet(lyt, 0, sizeof(PageLayout));
  lyt->cap = 512;
  lyt->items = CAlloc(lyt->cap * sizeof(RenderItem));
}

U0 LayoutFree(PageLayout *lyt)
{
  if (lyt->items != NULL) {
    for (I64 i = 0; i < lyt->count; i++) {
      if (lyt->items[i].text != NULL) Free(lyt->items[i].text);
    }
    Free(lyt->items);
    lyt->items = NULL;
  }
  lyt->count = 0;
  lyt->content_height = 0;
}

RenderItem *LayoutPush(PageLayout *lyt, I32 kind)
{
  if (lyt->count >= lyt->cap) {
    lyt->cap *= 2;
    lyt->items = ReAlloc(lyt->items, lyt->cap * sizeof(RenderItem));
  }
  RenderItem *it = &lyt->items[lyt->count];
  MemSet(it, 0, sizeof(RenderItem));
  it->kind = kind;
  it->link_id = -1;
  it->img_id = -1;
  lyt->count++;
  return it;
}

U0 SelectNodeFont(U0 *cr, Bool mono, Bool italic, Bool bold, F64 size)
{
  if (g_davis_mono_mode) {
    /* Завет Дэвиса: ТОЛЬКО один чёткий моноширинный шрифт без курсивного размытия! */
    I32 dweight = CAIRO_FONT_WEIGHT_NORMAL;
    if (bold) dweight = CAIRO_FONT_WEIGHT_BOLD;
    cairo_select_font_face(cr, "DejaVu Sans Mono", CAIRO_FONT_SLANT_NORMAL, dweight);
    cairo_set_font_size(cr, size);
    return;
  }
  U8 *family = "DejaVu Sans";
  if (mono) family = "DejaVu Sans Mono";
  I32 slant = CAIRO_FONT_SLANT_NORMAL;
  if (italic) slant = CAIRO_FONT_SLANT_ITALIC;
  I32 weight = CAIRO_FONT_WEIGHT_NORMAL;
  if (bold) weight = CAIRO_FONT_WEIGHT_BOLD;
  cairo_select_font_face(cr, family, slant, weight);
  cairo_set_font_size(cr, size);
}

F64 FontSizeForHeading(I32 heading, Bool mono, F64 zoom)
{
  F64 base = 15.5;
  if (heading == 1) base = 26.0;
  else if (heading == 2) base = 21.0;
  else if (heading == 3) base = 18.0;
  else if (heading == 4) base = 16.0;
  else if (mono) base = 14.0;
  return base * zoom;
}

F64 MeasureTextAdvance(U0 *cr, U8 *s)
{
  if (s == NULL || s[0] == 0) return 0.0;
  CairoTextExtents ext;
  cairo_text_extents(cr, s, &ext);
  return ext.x_advance;
}

/* Вёрстка одного текстового узла с переносом слов в заданных границах [left_x .. right_x] */
U0 EmitWrappedTextNode(U0 *cr, PageLayout *lyt, DocNode *n, F64 zoom,
                       F64 left_x, F64 right_x,
                       F64 *io_cur_x, F64 *io_cur_y, F64 *io_line_h, Bool *io_has_content)
{
  F64 fsize = FontSizeForHeading(n->heading, n->mono, zoom);
  if (n->css_font_px > 0) fsize = n->css_font_px * zoom;
  F64 lh = fsize * 1.46;
  if (n->in_pre) lh = fsize * 1.38;
  if (lh > *io_line_h) *io_line_h = lh;
  SelectNodeFont(cr, n->mono, n->italic, n->bold, fsize);

  if (n->in_pre) {
    F64 adv = MeasureTextAdvance(cr, n->text);
    RenderItem *ti = LayoutPush(lyt, RITEM_TEXT);
    ti->x = *io_cur_x;
    ti->y = *io_cur_y;
    ti->w = adv;
    ti->h = lh;
    ti->font_size = fsize;
    ti->mono = TRUE;
    ti->in_pre = TRUE;
    ti->link_id = n->link_id;
    ti->has_fg_color = n->has_fg_color;
    ti->fg_rgb = n->fg_rgb;
    ti->text = StrNew(n->text);
    *io_cur_x += adv;
    *io_has_content = TRUE;
    return;
  }

  U8 *s = n->text;
  I64 slen = StrLen(s);
  I64 wpos = 0;

  while (wpos < slen) {
    I64 wstart = wpos;
    while (wpos < slen && s[wpos] == ' ') wpos++;
    while (wpos < slen && s[wpos] != ' ') wpos++;

    I64 tok_len = wpos - wstart;
    if (tok_len <= 0) break;

    if (!(*io_has_content) && *io_cur_x <= left_x + 0.5) {
      while (tok_len > 0 && s[wstart] == ' ') {
        wstart++;
        tok_len--;
      }
      if (tok_len <= 0) continue;
    }

    U8 word_buf[512];
    SafeCopyLen(word_buf, s + wstart, tok_len, sizeof(word_buf));
    F64 w_adv = MeasureTextAdvance(cr, word_buf);
    U8 *emit_str = word_buf;

    if (*io_has_content && (*io_cur_x + w_adv > right_x)) {
      *io_cur_y += *io_line_h;
      *io_cur_x = left_x;
      *io_line_h = lh;
      *io_has_content = FALSE;

      while (*emit_str == ' ') emit_str++;
      if (*emit_str == 0) continue;
      w_adv = MeasureTextAdvance(cr, emit_str);
    }

    if (n->in_mark) {
      RenderItem *mb = LayoutPush(lyt, RITEM_MARK_BG);
      mb->x = *io_cur_x;
      mb->y = *io_cur_y + 2.0;
      mb->w = w_adv;
      mb->h = lh - 3.0;
    } else if (n->mono) {
      RenderItem *cb = LayoutPush(lyt, RITEM_CODE_BG);
      cb->x = *io_cur_x;
      cb->y = *io_cur_y + 2.0;
      cb->w = w_adv;
      cb->h = lh - 3.0;
    }

    RenderItem *ti = LayoutPush(lyt, RITEM_TEXT);
    ti->x = *io_cur_x;
    ti->y = *io_cur_y;
    ti->w = w_adv;
    ti->h = lh;
    ti->font_size = fsize;
    ti->heading = n->heading;
    ti->bold = n->bold;
    ti->italic = n->italic;
    ti->underline = n->underline;
    ti->strike = n->strike;
    ti->mono = n->mono;
    ti->in_quote = n->in_quote;
    ti->link_id = n->link_id;
    ti->has_fg_color = n->has_fg_color;
    ti->fg_rgb = n->fg_rgb;
    ti->text = StrNew(emit_str);

    *io_cur_x += w_adv;
    *io_has_content = TRUE;
  }
}

/* --- Настоящая 2D вёрстка таблиц <table> / <tr> / <th> / <td> --- */
#define MAX_TBL_ROWS 64
#define MAX_TBL_COLS 8

class TblCellSpan
{
  I64  start_node;
  I64  end_node;
  Bool is_th;
  Bool present;
};

I64 LayoutHtmlTable(U0 *cr, HtmlDocument *doc, PageLayout *lyt,
                    I64 start_idx, F64 pad_left, F64 max_w, F64 zoom, F64 *io_y)
{
  TblCellSpan *grid = CAlloc(MAX_TBL_ROWS * MAX_TBL_COLS * sizeof(TblCellSpan));
  I32 row_cnt = 0;
  I32 col_cnt = 0;
  I32 cur_r = -1;
  I32 cur_c = -1;
  Bool has_th = FALSE;

  I64 idx = start_idx + 1;
  while (idx < doc->node_count && doc->nodes[idx].type != NODE_TABLE_END) {
    DocNode *nd = &doc->nodes[idx];
    if (nd->type == NODE_TABLE_ROW) {
      if (cur_r >= 0 && cur_c >= 0) {
        grid[cur_r * MAX_TBL_COLS + cur_c].end_node = idx;
      }
      if (row_cnt < MAX_TBL_ROWS) {
        cur_r = row_cnt++;
        cur_c = -1;
      } else {
        cur_r = -1;
      }
    } else if (nd->type == NODE_TABLE_CELL) {
      if (cur_r < 0 && row_cnt < MAX_TBL_ROWS) {
        cur_r = row_cnt++;
        cur_c = -1;
      }
      if (cur_r >= 0 && cur_c >= 0) {
        grid[cur_r * MAX_TBL_COLS + cur_c].end_node = idx;
      }
      if (cur_r >= 0 && cur_c + 1 < MAX_TBL_COLS) {
        cur_c++;
        if (cur_c + 1 > col_cnt) col_cnt = cur_c + 1;
        TblCellSpan *cs = &grid[cur_r * MAX_TBL_COLS + cur_c];
        cs->present = TRUE;
        cs->is_th = nd->is_th;
        cs->start_node = idx + 1;
        cs->end_node = idx + 1;
        if (nd->is_th) has_th = TRUE;
      }
    }
    idx++;
  }
  if (cur_r >= 0 && cur_c >= 0) {
    grid[cur_r * MAX_TBL_COLS + cur_c].end_node = idx;
  }

  if (row_cnt <= 0 || col_cnt <= 0) {
    Free(grid);
    return idx;
  }

  /* 1. Оцениваем естественную ширину каждой колонки */
  F64 col_nat[MAX_TBL_COLS];
  F64 col_w[MAX_TBL_COLS];
  F64 col_x[MAX_TBL_COLS];
  for (I32 c = 0; c < col_cnt; c++) col_nat[c] = 36.0 * zoom;

  for (I32 r = 0; r < row_cnt; r++) {
    for (I32 c = 0; c < col_cnt; c++) {
      TblCellSpan *cs = &grid[r * MAX_TBL_COLS + c];
      if (!cs->present) continue;
      F64 cw_sum = 18.0 * zoom;
      for (I64 k = cs->start_node; k < cs->end_node; k++) {
        DocNode *tn = &doc->nodes[k];
        if (tn->type == NODE_TEXT && tn->text != NULL) {
          SelectNodeFont(cr, tn->mono, tn->italic, tn->bold, FontSizeForHeading(tn->heading, tn->mono, zoom));
          cw_sum += MeasureTextAdvance(cr, tn->text);
        } else if (tn->type == NODE_LINE_BREAK) {
          if (cw_sum > col_nat[c]) col_nat[c] = cw_sum;
          cw_sum = 18.0 * zoom;
        }
      }
      if (cw_sum > col_nat[c]) col_nat[c] = cw_sum;
      if (col_nat[c] > 480.0 * zoom) col_nat[c] = 480.0 * zoom;
    }
  }

  F64 sum_nat = 0.0;
  for (I32 c = 0; c < col_cnt; c++) sum_nat += col_nat[c];
  if (sum_nat < 1.0) sum_nat = 1.0;

  F64 tbl_w = max_w;
  if (!has_th && sum_nat < max_w) {
    /* Компактная таблица без растягивания на весь экран, если контент узкий */
    tbl_w = sum_nat + 16.0;
    if (tbl_w > max_w) tbl_w = max_w;
  }

  F64 run_x = pad_left;
  for (I32 c = 0; c < col_cnt; c++) {
    col_x[c] = run_x;
    col_w[c] = (col_nat[c] / sum_nat) * tbl_w;
    if (col_w[c] < 34.0 * zoom && tbl_w > col_cnt * 40.0 * zoom) col_w[c] = 34.0 * zoom;
    run_x += col_w[c];
  }
  /* Подгоняем последнюю колонку под правый край */
  if (col_cnt > 0 && run_x > pad_left + max_w) {
    F64 scale_fix = max_w / (run_x - pad_left);
    run_x = pad_left;
    for (I32 c = 0; c < col_cnt; c++) {
      col_x[c] = run_x;
      col_w[c] *= scale_fix;
      run_x += col_w[c];
    }
  }
  F64 actual_tbl_w = run_x - pad_left;

  Bool draw_grid = (has_th || col_cnt >= 3);
  *io_y += 8.0 * zoom;

  /* 2. Верстаем строки таблицы по очереди */
  for (I32 r = 0; r < row_cnt; r++) {
    F64 row_top = *io_y;
    Bool row_is_header = FALSE;
    for (I32 c = 0; c < col_cnt; c++) {
      if (grid[r * MAX_TBL_COLS + c].present && grid[r * MAX_TBL_COLS + c].is_th)
        row_is_header = TRUE;
    }

    I64 bg_item_idx = -1;
    if (draw_grid) {
      if (row_is_header) {
        RenderItem *hb = LayoutPush(lyt, RITEM_TBL_HDR_BG);
        hb->x = pad_left; hb->y = row_top; hb->w = actual_tbl_w; hb->h = 26.0;
        bg_item_idx = lyt->count - 1;
      } else if ((r % 2) == 1) {
        RenderItem *zb = LayoutPush(lyt, RITEM_TBL_ROW_BG);
        zb->x = pad_left; zb->y = row_top; zb->w = actual_tbl_w; zb->h = 26.0;
        bg_item_idx = lyt->count - 1;
      }
    }

    F64 cell_pad_x = 7.0 * zoom;
    F64 cell_pad_y = 6.0 * zoom;
    if (!draw_grid) { cell_pad_x = 4.0 * zoom; cell_pad_y = 3.0 * zoom; }

    F64 max_row_bottom = row_top + 24.0 * zoom;

    for (I32 c = 0; c < col_cnt; c++) {
      TblCellSpan *cs = &grid[r * MAX_TBL_COLS + c];
      if (!cs->present) continue;

      F64 cx_left = col_x[c] + cell_pad_x;
      F64 cx_right = col_x[c] + col_w[c] - cell_pad_x;
      if (cx_right < cx_left + 16.0) cx_right = cx_left + 16.0;

      F64 cx = cx_left;
      F64 cy = row_top + cell_pad_y;
      F64 clh = 20.0 * zoom;
      Bool chas = FALSE;

      for (I64 k = cs->start_node; k < cs->end_node; k++) {
        DocNode *cn = &doc->nodes[k];
        if (cn->type == NODE_LINE_BREAK) {
          cy += clh;
          cx = cx_left;
          chas = FALSE;
        } else if (cn->type == NODE_TEXT && cn->text != NULL) {
          EmitWrappedTextNode(cr, lyt, cn, zoom, cx_left, cx_right, &cx, &cy, &clh, &chas);
        }
      }
      if (chas) cy += clh;
      if (cy + cell_pad_y > max_row_bottom) max_row_bottom = cy + cell_pad_y;
    }

    F64 row_h = max_row_bottom - row_top;
    if (bg_item_idx >= 0) lyt->items[bg_item_idx].h = row_h;

    if (draw_grid) {
      RenderItem *rb = LayoutPush(lyt, RITEM_TBL_BORDER);
      rb->x = pad_left; rb->y = row_top; rb->w = actual_tbl_w; rb->h = row_h;
      for (I32 c = 1; c < col_cnt; c++) {
        RenderItem *vb = LayoutPush(lyt, RITEM_TBL_BORDER);
        vb->x = col_x[c]; vb->y = row_top; vb->w = 0.0; vb->h = row_h;
      }
    }

    *io_y = max_row_bottom;
  }

  *io_y += 8.0 * zoom;
  Free(grid);
  return idx;
}

/* --- Построение 2D раскладки документа с масштабом zoom --- */
U0 BuildPageLayoutZoom(U0 *cr, HtmlDocument *doc, I32 win_w, F64 zoom, PageLayout *lyt)
{
  if (zoom < 0.65) zoom = 0.65;
  if (zoom > 2.00) zoom = 2.00;

  LayoutFree(lyt);
  LayoutInit(lyt);
  lyt->viewport_w = win_w;

  F64 pad_left = 32.0;
  F64 pad_right = 32.0 + SCROLLBAR_W;
  F64 max_content_w = win_w - pad_left - pad_right;
  if (max_content_w < 180.0) max_content_w = 180.0;
  if (max_content_w > 960.0 * zoom) max_content_w = 960.0 * zoom;
  if (max_content_w > win_w - pad_left - pad_right)
    max_content_w = win_w - pad_left - pad_right;

  F64 cur_y = 20.0;
  F64 line_start_x = pad_left;
  F64 cur_x = pad_left;
  F64 cur_line_h = 23.0 * zoom;
  Bool line_has_content = FALSE;

  I64 active_pre_bg_idx = -1;
  F64 pre_start_y = 0.0;

  I64 active_quote_idx = -1;
  F64 quote_start_y = 0.0;
  Bool prev_in_quote = FALSE;

  for (I64 i = 0; i < doc->node_count; i++) {
    DocNode *n = &doc->nodes[i];

    if (active_pre_bg_idx >= 0 && !(n->type == NODE_TEXT && n->in_pre) &&
        !(n->type == NODE_LINE_BREAK && i > 0 && doc->nodes[i - 1].in_pre)) {
      if (line_has_content) {
        cur_y += cur_line_h;
        line_has_content = FALSE;
      }
      lyt->items[active_pre_bg_idx].h = (cur_y - pre_start_y) + 12.0 * zoom;
      cur_y += 12.0 * zoom;
      active_pre_bg_idx = -1;
    }

    /* Вёрстка 2D таблицы */
    if (n->type == NODE_TABLE_START) {
      if (line_has_content) {
        cur_y += cur_line_h;
        line_has_content = FALSE;
      }
      i = LayoutHtmlTable(cr, doc, lyt, i, pad_left, max_content_w, zoom, &cur_y);
      cur_x = line_start_x;
      continue;
    }

    /* Вёрстка растрового или векторного изображения <img> */
    if (n->type == NODE_IMAGE && n->img_id >= 0 && n->img_id < doc->image_count) {
      DocImage *im = &doc->images[n->img_id];
      if (im->loaded && im->surface != NULL && im->nat_w > 0 && im->nat_h > 0) {
        F64 dw = im->nat_w;
        F64 dh = im->nat_h;
        if (im->attr_w > 0 && im->attr_h > 0) {
          dw = im->attr_w;
          dh = im->attr_h;
        } else if (im->attr_w > 0) {
          dw = im->attr_w;
          dh = dw * (im->nat_h * 1.0 / im->nat_w);
        } else if (im->attr_h > 0) {
          dh = im->attr_h;
          dw = dh * (im->nat_w * 1.0 / im->nat_h);
        }
        dw *= zoom;
        dh *= zoom;

        F64 avail_w = max_content_w - (line_start_x - pad_left);
        if (dw > avail_w && avail_w > 40.0) {
          F64 ratio = avail_w / dw;
          dw = avail_w;
          dh *= ratio;
        }

        if (dh <= 28.0 * zoom) {
          /* Маленькая иконка в строку с текстом */
          if (line_has_content && cur_x + dw > pad_left + max_content_w) {
            cur_y += cur_line_h;
            cur_x = line_start_x;
            line_has_content = FALSE;
          }
          RenderItem *ri = LayoutPush(lyt, RITEM_IMAGE);
          ri->x = cur_x;
          ri->y = cur_y + 2.0;
          ri->w = dw;
          ri->h = dh;
          ri->img_id = n->img_id;
          ri->link_id = n->link_id;
          cur_x += dw + 6.0 * zoom;
          if (dh + 4.0 > cur_line_h) cur_line_h = dh + 4.0;
          line_has_content = TRUE;
        } else {
          /* Полноценная иллюстрация / баннер отдельным блоком */
          if (line_has_content) {
            cur_y += cur_line_h;
            line_has_content = FALSE;
          }
          cur_y += 8.0 * zoom;
          RenderItem *ri = LayoutPush(lyt, RITEM_IMAGE);
          ri->x = line_start_x;
          ri->y = cur_y;
          ri->w = dw;
          ri->h = dh;
          ri->img_id = n->img_id;
          ri->link_id = n->link_id;
          cur_y += dh + 10.0 * zoom;
          cur_x = line_start_x;
        }
      } else if (im->alt != NULL && im->alt[0] != 0) {
        DocNode alt_node;
        MemSet(&alt_node, 0, sizeof(DocNode));
        alt_node.type = NODE_TEXT;
        alt_node.italic = TRUE;
        alt_node.link_id = n->link_id;
        U8 alt_lbl[300];
        snprintf(alt_lbl, sizeof(alt_lbl), "[Рис: %s] ", im->alt);
        alt_node.text = alt_lbl;
        EmitWrappedTextNode(cr, lyt, &alt_node, zoom, line_start_x, pad_left + max_content_w,
                            &cur_x, &cur_y, &cur_line_h, &line_has_content);
      }
      continue;
    }

    if (n->type == NODE_BLOCK_START) {
      if (line_has_content) {
        cur_y += cur_line_h;
        line_has_content = FALSE;
      }

      if (prev_in_quote && !n->in_quote && active_quote_idx >= 0) {
        lyt->items[active_quote_idx].h = cur_y - quote_start_y;
        active_quote_idx = -1;
      }

      if (n->block_kind == BLK_H1) cur_y += 15.0 * zoom;
      else if (n->block_kind == BLK_H2) cur_y += 13.0 * zoom;
      else if (n->block_kind == BLK_H3) cur_y += 9.0 * zoom;
      else if (n->block_kind == BLK_LIST_ITEM) cur_y += 5.0 * zoom;
      else cur_y += 8.0 * zoom;

      line_start_x = pad_left + (n->indent * 24.0 * zoom);
      if (n->in_quote) {
        if (!prev_in_quote) {
          quote_start_y = cur_y;
          RenderItem *qb = LayoutPush(lyt, RITEM_QUOTE_BAR);
          qb->x = line_start_x + 4.0;
          qb->y = quote_start_y;
          qb->w = 4.0;
          qb->h = 24.0;
          active_quote_idx = lyt->count - 1;
        }
        line_start_x += 18.0 * zoom;
      }
      prev_in_quote = n->in_quote;

      if (n->block_kind == BLK_PRE) {
        pre_start_y = cur_y;
        RenderItem *pb = LayoutPush(lyt, RITEM_PRE_BG);
        pb->x = line_start_x;
        pb->y = pre_start_y;
        pb->w = max_content_w - (line_start_x - pad_left);
        pb->h = 30.0;
        active_pre_bg_idx = lyt->count - 1;
        cur_y += 10.0 * zoom;
        line_start_x += 14.0 * zoom;
      }

      cur_x = line_start_x;
      I32 h_lvl = 0;
      if (n->block_kind <= 4) h_lvl = n->block_kind;
      F64 bsize = FontSizeForHeading(h_lvl, n->in_pre, zoom);
      cur_line_h = bsize * 1.45;

      if (n->block_kind == BLK_LIST_ITEM) {
        U8 bullet[32];
        if (n->list_index > 0)
          snprintf(bullet, sizeof(bullet), "%d.", n->list_index);
        else
          SafeCopy(bullet, "\xE2\x80\xA2", sizeof(bullet));

        F64 bfz = 15.5 * zoom;
        SelectNodeFont(cr, FALSE, FALSE, TRUE, bfz);
        RenderItem *bi = LayoutPush(lyt, RITEM_TEXT);
        F64 bx_off = 18.0 * zoom;
        if (n->list_index > 0) bx_off = 25.0 * zoom;
        bi->x = line_start_x - bx_off;
        bi->y = cur_y;
        bi->w = 22.0 * zoom;
        bi->h = cur_line_h;
        bi->font_size = bfz;
        bi->bold = TRUE;
        bi->text = StrNew(bullet);
      }
      continue;
    }

    if (n->type == NODE_LINE_BREAK) {
      cur_y += cur_line_h;
      cur_x = line_start_x;
      line_has_content = FALSE;
      continue;
    }

    if (n->type == NODE_HR) {
      if (line_has_content) {
        cur_y += cur_line_h;
        line_has_content = FALSE;
      }
      cur_y += 10.0 * zoom;
      RenderItem *hr = LayoutPush(lyt, RITEM_HR);
      hr->x = pad_left;
      hr->y = cur_y;
      hr->w = max_content_w;
      hr->h = 2.0;
      cur_y += 12.0 * zoom;
      cur_x = line_start_x;
      continue;
    }

    if (n->type == NODE_MARQUEE && n->text != NULL) {
      if (line_has_content) {
        cur_y += cur_line_h;
        line_has_content = FALSE;
      }
      cur_y += 6.0 * zoom;
      RenderItem *mq = LayoutPush(lyt, RITEM_MARQUEE);
      mq->x = pad_left;
      mq->y = cur_y;
      mq->w = max_content_w;
      mq->h = 34.0 * zoom;
      mq->font_size = 15.0 * zoom;
      mq->bold = TRUE;
      mq->link_id = n->link_id;
      mq->text = StrNew(n->text);
      cur_y += mq->h + 10.0 * zoom;
      cur_x = line_start_x;
      continue;
    }

    if (n->type == NODE_ANIM_CANVAS) {
      if (line_has_content) {
        cur_y += cur_line_h;
        line_has_content = FALSE;
      }
      cur_y += 8.0 * zoom;
      F64 cw = n->anim_w * zoom;
      F64 ch = n->anim_h * zoom;
      if (cw > max_content_w) {
        F64 sc = max_content_w / cw;
        cw = max_content_w;
        ch = ch * sc;
      }
      RenderItem *ac = LayoutPush(lyt, RITEM_ANIM_CANVAS);
      ac->x = pad_left;
      ac->y = cur_y;
      ac->w = cw;
      ac->h = ch;
      ac->anim_kind = n->anim_kind;
      cur_y += ch + 12.0 * zoom;
      cur_x = line_start_x;
      continue;
    }

    if (n->type == NODE_TEXT && n->text != NULL) {
      EmitWrappedTextNode(cr, lyt, n, zoom, line_start_x, pad_left + max_content_w,
                          &cur_x, &cur_y, &cur_line_h, &line_has_content);

      if (n->heading == 1 && (i + 1 >= doc->node_count || doc->nodes[i + 1].heading != 1)) {
        cur_y += cur_line_h + 4.0 * zoom;
        RenderItem *hl = LayoutPush(lyt, RITEM_H1_LINE);
        hl->x = line_start_x;
        hl->y = cur_y;
        hl->w = max_content_w - (line_start_x - pad_left);
        hl->h = 2.0;
        cur_y += 6.0 * zoom;
        cur_x = line_start_x;
        line_has_content = FALSE;
      }
    }
  }

  if (line_has_content) cur_y += cur_line_h;
  if (active_pre_bg_idx >= 0) {
    lyt->items[active_pre_bg_idx].h = (cur_y - pre_start_y) + 12.0 * zoom;
    cur_y += 12.0 * zoom;
  }
  if (active_quote_idx >= 0) {
    lyt->items[active_quote_idx].h = cur_y - quote_start_y;
  }

  lyt->content_height = cur_y + 36.0;
}

U0 BuildPageLayout(U0 *cr, HtmlDocument *doc, I32 win_w, PageLayout *lyt)
{
  BuildPageLayoutZoom(cr, doc, win_w, 1.0, lyt);
}

/* --- Проверка попадания мыши в ссылку (текстовую или картинку-ссылку!) --- */
I32 HitTestPageLink(PageLayout *lyt, I32 mx, I32 my, F64 scroll_y, I32 win_w, I32 win_h)
{
  if (my < TOOLBAR_H || my > win_h - STATUSBAR_H) return -1;
  if (mx > win_w - SCROLLBAR_W) return -1;

  F64 doc_x = mx;
  F64 doc_y = (my - TOOLBAR_H) + scroll_y;

  for (I64 i = 0; i < lyt->count; i++) {
    RenderItem *it = &lyt->items[i];
    if ((it->kind == RITEM_TEXT || it->kind == RITEM_IMAGE) && it->link_id >= 0) {
      if (doc_x >= it->x && doc_x <= it->x + it->w &&
          doc_y >= it->y && doc_y <= it->y + it->h) {
        return it->link_id;
      }
    }
  }
  return -1;
}

/* Расчёт ширины одной вкладки на панели вкладок */
F64 ComputeTabWidth(I32 win_w, I32 tab_count)
{
  if (tab_count <= 0) tab_count = 1;
  F64 avail = win_w - 50.0;
  F64 tw = avail / tab_count;
  if (tw > 210.0) tw = 210.0;
  if (tw < 80.0) tw = 80.0;
  return tw;
}

class NavbarGeom
{
  Bool compact;
  I32  back_x, back_w;
  I32  fwd_x,  fwd_w;
  I32  rel_x,  rel_w;
  I32  home_x, home_w;
  I32  addr_x, addr_w;
  I32  star_x, star_w;
  I32  go_x,   go_w;
  I32  srch_x, srch_w;
  I32  cheb_x, cheb_w;
  I32  bld_x,  bld_w;
  I32  mon_x,  mon_w;
  I32  zout_x, zout_w;
  I32  zin_x,  zin_w;
  I32  find_x, find_w;
  I32  theme_x, theme_w;
};

U0 ComputeNavbarGeom(I32 win_w, NavbarGeom *g)
{
  if (win_w < 920) {
    /* Компактная геометрия под каноническое разрешение Дэвиса 640x480! */
    g->compact = TRUE;
    g->back_x = 4;   g->back_w = 22;
    g->fwd_x  = 28;  g->fwd_w  = 22;
    g->rel_x  = 52;  g->rel_w  = 22;
    g->home_x = 76;  g->home_w = 22;
    g->addr_x = 102;

    g->theme_w = 72;
    g->find_w  = 30;
    g->zin_w   = 20;
    g->zout_w  = 20;
    g->mon_w   = 38;
    g->bld_w   = 42;
    g->cheb_w  = 68;
    g->srch_w  = 26;
    g->go_w    = 28;
    g->star_w  = 24;

    g->theme_x = win_w - g->theme_w - 4;
    g->find_x  = g->theme_x - g->find_w - 2;
    g->zin_x   = g->find_x - g->zin_w - 2;
    g->zout_x  = g->zin_x - g->zout_w - 2;
    g->mon_x   = g->zout_x - g->mon_w - 2;
    g->bld_x   = g->mon_x - g->bld_w - 2;
    g->cheb_x  = g->bld_x - g->cheb_w - 2;
    g->srch_x  = g->cheb_x - g->srch_w - 2;
    g->go_x    = g->srch_x - g->go_w - 2;
    g->star_x  = g->go_x - g->star_w - 2;
    g->addr_w  = g->star_x - g->addr_x - 3;
    if (g->addr_w < 60) g->addr_w = 60;
  } else {
    g->compact = FALSE;
    g->back_x = 8;   g->back_w = 28;
    g->fwd_x  = 40;  g->fwd_w  = 28;
    g->rel_x  = 72;  g->rel_w  = 28;
    g->home_x = 104; g->home_w = 28;
    g->addr_x = 138;

    g->theme_w = 82;
    g->find_w  = 44;
    g->zin_w   = 26;
    g->zout_w  = 26;
    g->mon_w   = 68;
    g->bld_w   = 62;
    g->cheb_w  = 124;
    g->srch_w  = 56;
    g->go_w    = 38;
    g->star_w  = 30;

    g->theme_x = win_w - g->theme_w - 6;
    g->find_x  = g->theme_x - g->find_w - 4;
    g->zin_x   = g->find_x - g->zin_w - 3;
    g->zout_x  = g->zin_x - g->zout_w - 3;
    g->mon_x   = g->zout_x - g->mon_w - 4;
    g->bld_x   = g->mon_x - g->bld_w - 4;
    g->cheb_x  = g->bld_x - g->cheb_w - 4;
    g->srch_x  = g->cheb_x - g->srch_w - 4;
    g->go_x    = g->srch_x - g->go_w - 4;
    g->star_x  = g->go_x - g->star_w - 4;
    g->addr_w  = g->star_x - g->addr_x - 4;
    if (g->addr_w < 80) g->addr_w = 80;
  }
}

/* --- Хит-тест всех элементов верхней панели (Вкладки, Навбар, Закладки) и панели Ctrl+F --- */
I32 HitTestChrome(I32 mx, I32 my, I32 win_w, I32 win_h, ChromeUiState *ui)
{
  /* 0. Всплывающая панель поиска на странице (Ctrl+F) над статус-баром */
  if (ui != NULL && ui->find_active) {
    F64 fb_w = 390.0;
    F64 fb_h = 34.0;
    F64 fb_x = win_w - SCROLLBAR_W - fb_w - 10.0;
    F64 fb_y = win_h - STATUSBAR_H - fb_h - 8.0;
    if (mx >= fb_x && mx <= fb_x + fb_w && my >= fb_y && my <= fb_y + fb_h) {
      if (mx >= fb_x + 112.0 && mx <= fb_x + 258.0) return BTN_FIND_INPUT;
      if (mx >= fb_x + 304.0 && mx <= fb_x + 330.0) return BTN_FIND_PREV;
      if (mx >= fb_x + 333.0 && mx <= fb_x + 359.0) return BTN_FIND_NEXT;
      if (mx >= fb_x + 362.0 && mx <= fb_x + 386.0) return BTN_FIND_CLOSE;
      return BTN_FIND_INPUT;
    }
  }

  /* 1. Полоса вкладок (0 .. TABS_H) */
  if (my >= 2 && my < TABS_H && ui != NULL) {
    F64 tw = ComputeTabWidth(win_w, ui->tab_count);
    F64 tx = 6.0;
    for (I32 t = 0; t < ui->tab_count; t++) {
      if (mx >= tx && mx <= tx + tw - 2.0) {
        if (ui->tab_count > 1 && mx >= tx + tw - 22.0) {
          return BTN_TAB_CLOSE_BASE + t;
        }
        return BTN_TAB_BASE + t;
      }
      tx += tw;
    }
    if (ui->tab_count < MAX_TABS && mx >= tx + 2.0 && mx <= tx + 30.0) {
      return BTN_NEW_TAB;
    }
    return BTN_NONE;
  }

  /* 2. Полоса навигации и омнибокса (TABS_H .. TABS_H + NAVBAR_H) */
  if (my >= TABS_H + 5 && my <= TABS_H + NAVBAR_H - 5) {
    NavbarGeom ng;
    ComputeNavbarGeom(win_w, &ng);

    if (mx >= ng.back_x && mx <= ng.back_x + ng.back_w) return BTN_BACK;
    if (mx >= ng.fwd_x  && mx <= ng.fwd_x  + ng.fwd_w)  return BTN_FWD;
    if (mx >= ng.rel_x  && mx <= ng.rel_x  + ng.rel_w)  return BTN_RELOAD;
    if (mx >= ng.home_x && mx <= ng.home_x + ng.home_w) return BTN_HOME;
    if (mx >= ng.addr_x && mx <= ng.addr_x + ng.addr_w) return BTN_ADDRBAR;
    if (mx >= ng.star_x && mx <= ng.star_x + ng.star_w) return BTN_BOOKMARK_STAR;
    if (mx >= ng.go_x   && mx <= ng.go_x   + ng.go_w)   return BTN_GO;
    if (mx >= ng.srch_x && mx <= ng.srch_x + ng.srch_w) return BTN_SEARCH;
    if (mx >= ng.cheb_x && mx <= ng.cheb_x + ng.cheb_w) return BTN_HOLY_TOGGLE;
    if (mx >= ng.bld_x  && mx <= ng.bld_x  + ng.bld_w)  return BTN_BUILDER;
    if (mx >= ng.mon_x  && mx <= ng.mon_x  + ng.mon_w)  return BTN_MONITOR;
    if (mx >= ng.zout_x && mx <= ng.zout_x + ng.zout_w) return BTN_ZOOM_OUT;
    if (mx >= ng.zin_x  && mx <= ng.zin_x  + ng.zin_w)  return BTN_ZOOM_IN;
    if (mx >= ng.find_x && mx <= ng.find_x + ng.find_w) return BTN_FIND_TOGGLE;
    if (mx >= ng.theme_x && mx <= ng.theme_x + ng.theme_w) return BTN_THEME;
    return BTN_NONE;
  }

  /* 3. Полоса закладок (TABS_H + NAVBAR_H .. TOOLBAR_H) */
  if (my >= TABS_H + NAVBAR_H + 2 && my < TOOLBAR_H - 2 && ui != NULL) {
    F64 bx = 92.0;
    for (I32 b = 0; b < ui->bookmark_count; b++) {
      if (!ui->bookmarks[b].used) continue;
      F64 bw = StrLen(ui->bookmarks[b].title) * 6.2 + 22.0;
      if (bw < 68.0) bw = 68.0;
      if (bw > 155.0) bw = 155.0;
      if (bx + bw > win_w - 8.0) break;
      if (mx >= bx && mx <= bx + bw) return BTN_BMARK_BASE + b;
      bx += bw + 6.0;
    }
  }

  return BTN_NONE;
}

U0 DrawButtonBox(U0 *cr, F64 x, F64 y, F64 w, F64 h, U8 *label,
                 Bool hovered, Bool enabled, ThemePalette *pal)
{
  if (hovered && enabled) ApplyColor(cr, &pal->btn_hover);
  else ApplyColor(cr, &pal->btn_bg);
  cairo_rectangle(cr, x, y, w, h);
  cairo_fill(cr);

  ApplyColor(cr, &pal->toolbar_border);
  cairo_set_line_width(cr, 1.1);
  cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1.0, h - 1.0);
  cairo_stroke(cr);

  if (enabled) ApplyColor(cr, &pal->btn_fg);
  else if (g_davis_mono_mode) ApplyDavisColorIdx(cr, 7); /* LTGRAY #AAAAAA без полупрозрачности! */
  else cairo_set_source_rgba(cr, pal->btn_fg.r, pal->btn_fg.g, pal->btn_fg.b, 0.40);

  SelectNodeFont(cr, FALSE, FALSE, TRUE, 12.2);
  CairoTextExtents ext;
  cairo_text_extents(cr, label, &ext);
  F64 tx = x + (w - ext.width) * 0.5 - ext.x_bearing;
  F64 ty = y + (h - ext.height) * 0.5 - ext.y_bearing;
  cairo_move_to(cr, tx, ty);
  cairo_show_text(cr, label);
}

/* Проверка, содержит ли текстовый блок искомое слово Ctrl+F (UTF-8 lower) */
Bool ItemMatchesFind(RenderItem *it, ChromeUiState *ui)
{
  if (ui == NULL || !ui->find_active || ui->find_query_low[0] == 0) return FALSE;
  if (it->kind != RITEM_TEXT || it->text == NULL) return FALSE;
  U8 low_buf[512];
  Utf8LowerFold(it->text, low_buf, sizeof(low_buf));
  return strstr(low_buf, ui->find_query_low) != NULL;
}

/* --- Полная отрисовка кадра браузера в поверхность Cairo --- */
/* --- Глобальный таймер 30 FPS анимаций для <marquee> и <canvas> --- */
F64  g_anim_t0_sec = 0.0;
Bool g_anim_override = FALSE;
F64  g_anim_override_sec = 0.0;

F64 GetBrowserAnimTimeSec()
{
  if (g_anim_override) return g_anim_override_sec;
  LinuxTimeval tv;
  gettimeofday((&tv)(timeval *), NULL);
  F64 now_s = tv.tv_sec * 1.0 + tv.tv_usec / 1000000.0;
  if (g_anim_t0_sec <= 0.0) g_anim_t0_sec = now_s;
  return now_s - g_anim_t0_sec;
}

/* Живая бегущая строка <marquee> (30 FPS) */
U0 PaintAnimatedMarquee(U0 *cr, RenderItem *it, F64 sy, F64 t_sec, Bool is_davis)
{
  cairo_save(cr);
  if (is_davis) {
    ApplyDavisColorIdx(cr, 1); /* BLUE */
    cairo_rectangle(cr, it->x, sy, it->w, it->h);
    cairo_fill(cr);
    ApplyDavisColorIdx(cr, 14); /* YELLOW */
    cairo_set_line_width(cr, 1.0);
    cairo_rectangle(cr, it->x + 0.5, sy + 0.5, it->w - 1.0, it->h - 1.0);
    cairo_stroke(cr);
  } else {
    cairo_set_source_rgb(cr, 0.05, 0.24, 0.17);
    cairo_rectangle(cr, it->x, sy, it->w, it->h);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.88, 0.70, 0.24);
    cairo_set_line_width(cr, 1.5);
    cairo_rectangle(cr, it->x + 0.75, sy + 0.75, it->w - 1.5, it->h - 1.5);
    cairo_stroke(cr);
  }

  cairo_rectangle(cr, it->x + 4.0, sy + 2.0, it->w - 8.0, it->h - 4.0);
  cairo_clip(cr);

  SelectNodeFont(cr, TRUE, FALSE, TRUE, it->font_size);
  CairoTextExtents ext;
  MemSet(&ext, 0, sizeof(CairoTextExtents));
  cairo_text_extents(cr, it->text, &ext);
  F64 tw = ext.x_advance;
  if (tw < 80.0) tw = 320.0;

  F64 span = it->w + tw + 40.0;
  F64 dist = t_sec * 105.0;
  I64 cyc = dist / span;
  F64 rem = dist - cyc * span;
  F64 tx = (it->x + it->w + 16.0) - rem;

  if (is_davis) ApplyDavisColorIdx(cr, 14);
  else          cairo_set_source_rgb(cr, 1.00, 0.94, 0.58);

  cairo_move_to(cr, tx, sy + it->h * 0.68);
  cairo_show_text(cr, it->text);
  cairo_restore(cr);
}

/* Живой процедурный 2D/3D-холст <canvas data-anim="cosmos"> (30 FPS Cairo) */
U0 PaintAnimatedCanvas(U0 *cr, RenderItem *it, F64 sy, F64 t_sec, Bool is_davis)
{
  cairo_save(cr);
  cairo_rectangle(cr, it->x, sy, it->w, it->h);
  cairo_clip(cr);

  /* 1. Космический фон + двойная рамка */
  if (is_davis) ApplyDavisColorIdx(cr, 0); /* BLACK */
  else          cairo_set_source_rgb(cr, 0.03, 0.07, 0.13);
  cairo_rectangle(cr, it->x, sy, it->w, it->h);
  cairo_fill(cr);

  if (is_davis) ApplyDavisColorIdx(cr, 11); /* LTCYAN */
  else          cairo_set_source_rgb(cr, 0.22, 0.85, 0.62);
  cairo_set_line_width(cr, 2.0);
  cairo_rectangle(cr, it->x + 1.0, sy + 1.0, it->w - 2.0, it->h - 2.0);
  cairo_stroke(cr);

  /* 2. Мерцающее звёздное поле */
  for (I32 si = 0; si < 42; si++) {
    F64 fx = ((si * 173 + 29) % 997) / 997.0;
    F64 fy = ((si * 311 + 71) % 887) / 887.0;
    F64 sx = it->x + 12.0 + fx * (it->w - 24.0);
    F64 sy_star = sy + 12.0 + fy * (it->h - 56.0);
    F64 twk = 0.45 + 0.55 * sin(t_sec * 3.2 + si * 1.7);
    if (is_davis) {
      if (twk > 0.65) ApplyDavisColorIdx(cr, 15);
      else            ApplyDavisColorIdx(cr, 7);
      cairo_rectangle(cr, sx, sy_star, 2.0, 2.0);
      cairo_fill(cr);
    } else {
      cairo_set_source_rgba(cr, 0.82, 0.94, 1.0, twk);
      cairo_arc(cr, sx, sy_star, 1.1 + (si % 2) * 0.7, 0.0, 6.2831853);
      cairo_fill(cr);
    }
  }

  /* 3. Орбитальная P2P-система (левая часть сцены) */
  F64 sun_x = it->x + it->w * 0.31;
  F64 sun_y = sy + it->h * 0.44;
  F64 scale = it->h / 300.0;

  /* Орбитальные кольца */
  F64 r1 = 44.0 * scale;
  F64 r2 = 78.0 * scale;
  F64 r3 = 114.0 * scale;
  cairo_set_line_width(cr, 1.0);
  if (is_davis) ApplyDavisColorIdx(cr, 8); /* DKGRAY */
  else          cairo_set_source_rgba(cr, 0.24, 0.48, 0.65, 0.45);
  cairo_arc(cr, sun_x, sun_y, r1, 0.0, 6.2831853); cairo_stroke(cr);
  cairo_arc(cr, sun_x, sun_y, r2, 0.0, 6.2831853); cairo_stroke(cr);
  cairo_arc(cr, sun_x, sun_y, r3, 0.0, 6.2831853); cairo_stroke(cr);

  /* Пульсирующее золотое Солнце (Ядро Холинета) */
  F64 pulse = 1.0 + 0.12 * sin(t_sec * 4.2);
  if (!is_davis) {
    cairo_set_source_rgba(cr, 1.0, 0.75, 0.15, 0.24);
    cairo_arc(cr, sun_x, sun_y, 26.0 * scale * pulse, 0.0, 6.2831853);
    cairo_fill(cr);
  }
  if (is_davis) ApplyDavisColorIdx(cr, 14); /* YELLOW */
  else          cairo_set_source_rgb(cr, 1.0, 0.86, 0.22);
  cairo_arc(cr, sun_x, sun_y, 16.5 * scale * pulse, 0.0, 6.2831853);
  cairo_fill(cr);

  /* Планета 1 (быстрая внутренняя) */
  F64 a1 = t_sec * 1.85;
  F64 p1x = sun_x + cos(a1) * r1;
  F64 p1y = sun_y + sin(a1) * r1;
  if (is_davis) ApplyDavisColorIdx(cr, 12); /* LTRED */
  else          cairo_set_source_rgb(cr, 1.0, 0.48, 0.34);
  cairo_arc(cr, p1x, p1y, 5.2 * scale, 0.0, 6.2831853);
  cairo_fill(cr);

  /* Планета 2 (Терра-HolyC со своим вращающимся спутником!) */
  F64 a2 = t_sec * 1.05 + 1.2;
  F64 p2x = sun_x + cos(a2) * r2;
  F64 p2y = sun_y + sin(a2) * r2;
  if (is_davis) ApplyDavisColorIdx(cr, 10); /* LTGREEN */
  else          cairo_set_source_rgb(cr, 0.22, 0.92, 0.62);
  cairo_arc(cr, p2x, p2y, 7.8 * scale, 0.0, 6.2831853);
  cairo_fill(cr);

  F64 ma = t_sec * 4.4;
  F64 mx = p2x + cos(ma) * (15.0 * scale);
  F64 my = p2y + sin(ma) * (15.0 * scale);
  if (is_davis) ApplyDavisColorIdx(cr, 15); /* WHITE */
  else          cairo_set_source_rgb(cr, 0.92, 0.96, 1.0);
  cairo_arc(cr, mx, my, 2.6 * scale, 0.0, 6.2831853);
  cairo_fill(cr);

  /* Планета 3 (Сатурн-P2P с кольцом!) */
  F64 a3 = t_sec * 0.62 + 3.4;
  F64 p3x = sun_x + cos(a3) * r3;
  F64 p3y = sun_y + sin(a3) * r3;
  if (is_davis) ApplyDavisColorIdx(cr, 11); /* LTCYAN */
  else          cairo_set_source_rgb(cr, 0.38, 0.76, 1.0);
  cairo_arc(cr, p3x, p3y, 9.0 * scale, 0.0, 6.2831853);
  cairo_fill(cr);

  if (is_davis) ApplyDavisColorIdx(cr, 14);
  else          cairo_set_source_rgb(cr, 0.98, 0.82, 0.38);
  cairo_set_line_width(cr, 2.0);
  cairo_move_to(cr, p3x - 15.0 * scale, p3y + 5.0 * scale);
  cairo_line_to(cr, p3x + 15.0 * scale, p3y - 5.0 * scale);
  cairo_stroke(cr);

  /* 4. Вращающийся 3D каркасный гиперкуб HolyC (правая часть сцены) */
  F64 cx3 = it->x + it->w * 0.76;
  F64 cy3 = sy + it->h * 0.43;
  F64 csz = 54.0 * scale;
  F64 ay = t_sec * 1.15;
  F64 ax = t_sec * 0.74;
  F64 cay = cos(ay); F64 say = sin(ay);
  F64 cax = cos(ax); F64 sax = sin(ax);

  F64 px[8];
  F64 py[8];
  for (I32 vi = 0; vi < 8; vi++) {
    F64 vx = -1.0; if (vi & 1) vx = 1.0;
    F64 vy = -1.0; if (vi & 2) vy = 1.0;
    F64 vz = -1.0; if (vi & 4) vz = 1.0;

    /* Поворот вокруг оси Y, затем X */
    F64 rx1 = vx * cay - vz * say;
    F64 rz1 = vx * say + vz * cay;
    F64 ry2 = vy * cax - rz1 * sax;
    F64 rz2 = vy * sax + rz1 * cax;

    F64 persp = 3.4 / (3.4 + rz2 * 0.55);
    px[vi] = cx3 + rx1 * csz * persp;
    py[vi] = cy3 + ry2 * csz * persp;
  }

  I32 eA[12]; I32 eB[12];
  eA[0]=0; eB[0]=1;  eA[1]=2; eB[1]=3;  eA[2]=4; eB[2]=5;  eA[3]=6; eB[3]=7;
  eA[4]=0; eB[4]=2;  eA[5]=1; eB[5]=3;  eA[6]=4; eB[6]=6;  eA[7]=5; eB[7]=7;
  eA[8]=0; eB[8]=4;  eA[9]=1; eB[9]=5;  eA[10]=2;eB[10]=6; eA[11]=3;eB[11]=7;

  if (is_davis) ApplyDavisColorIdx(cr, 11); /* LTCYAN */
  else          cairo_set_source_rgb(cr, 0.30, 0.96, 0.88);
  cairo_set_line_width(cr, 2.0);
  for (I32 ei = 0; ei < 12; ei++) {
    cairo_move_to(cr, px[eA[ei]], py[eA[ei]]);
    cairo_line_to(cr, px[eB[ei]], py[eB[ei]]);
    cairo_stroke(cr);
  }

  if (is_davis) ApplyDavisColorIdx(cr, 14); /* YELLOW */
  else          cairo_set_source_rgb(cr, 1.0, 0.90, 0.36);
  for (I32 vi = 0; vi < 8; vi++) {
    cairo_arc(cr, px[vi], py[vi], 3.4 * scale, 0.0, 6.2831853);
    cairo_fill(cr);
  }

  /* 5. Бегущая гармоническая осциллограмма P2P-сигнала внизу холста */
  F64 wave_y = sy + it->h - 26.0 * scale;
  if (is_davis) ApplyDavisColorIdx(cr, 10); /* LTGREEN */
  else          cairo_set_source_rgb(cr, 0.35, 1.00, 0.56);
  cairo_set_line_width(cr, 1.8);
  Bool first_pt = TRUE;
  for (I32 wx = 14; wx < it->w - 14; wx += 5) {
    F64 wy = wave_y + sin(wx * 0.045 - t_sec * 5.2) * (8.5 * scale)
                    + cos(wx * 0.095 + t_sec * 3.1) * (4.0 * scale);
    if (first_pt) {
      cairo_move_to(cr, it->x + wx, wy);
      first_pt = FALSE;
    } else {
      cairo_line_to(cr, it->x + wx, wy);
    }
  }
  cairo_stroke(cr);

  /* 6. Живая телеметрия HUD в углу холста */
  U8 hud[128];
  snprintf(hud, sizeof(hud), "[LIVE 30 FPS :: HOLYC + CAIRO 2D/3D]  T = %.2f c", t_sec);
  SelectNodeFont(cr, TRUE, FALSE, TRUE, 12.0 * scale);
  if (is_davis) ApplyDavisColorIdx(cr, 14);
  else          cairo_set_source_rgb(cr, 0.76, 0.98, 0.86);
  cairo_move_to(cr, it->x + 14.0, sy + 20.0 * scale);
  cairo_show_text(cr, hud);

  cairo_restore(cr);
}

U0 RenderBrowserFrame(U0 *cr, HtmlDocument *doc, PageLayout *lyt,
                      I32 win_w, I32 win_h, F64 scroll_y,
                      U8 *addr_buf, Bool addr_focused,
                      I32 hover_btn, I32 hover_link_id,
                      Bool can_back, Bool can_fwd,
                      I32 theme_id, Bool holy_mode, U8 *status_msg,
                      ChromeUiState *ui)
{
  Bool is_davis = (theme_id == THEME_DAVIS);
  SetCairoDavisMode(cr, is_davis);

  ThemePalette pal;
  GetThemePalette(theme_id, &pal);

  /* 1. Фон документа */
  ApplyColor(cr, &pal.page_bg);
  if (doc->has_css_bg) {
    I32 r = (doc->css_bg_rgb >> 16) & 255;
    I32 g = (doc->css_bg_rgb >> 8) & 255;
    I32 b = doc->css_bg_rgb & 255;
    if (is_davis) ApplyDavisColorIdx(cr, NearestDavisVgaIdx(r, g, b, FALSE));
    else cairo_set_source_rgb(cr, r / 255.0, g / 255.0, b / 255.0);
  }
  cairo_rectangle(cr, 0.0, 0.0, win_w, win_h);
  cairo_fill(cr);

  /* 2. Содержимое веб-страницы */
  F64 view_top = TOOLBAR_H;
  F64 view_h = win_h - TOOLBAR_H - STATUSBAR_H;
  if (view_h < 20.0) view_h = 20.0;

  if (is_davis) {
    /* Каноническая двойная рамка окна DolDoc из TempleOS (BLUE + LTCYAN, строго 1px!) */
    ApplyDavisColorIdx(cr, 1); /* BLUE #0000AA */
    cairo_set_line_width(cr, 2.0);
    cairo_rectangle(cr, 2.0, view_top + 2.0, win_w - SCROLLBAR_W - 4.0, view_h - 4.0);
    cairo_stroke(cr);
    ApplyDavisColorIdx(cr, 11); /* LTCYAN #55FFFF */
    cairo_set_line_width(cr, 1.0);
    cairo_rectangle(cr, 5.5, view_top + 5.5, win_w - SCROLLBAR_W - 11.0, view_h - 11.0);
    cairo_stroke(cr);
  } else if (theme_id == THEME_TEMPLE || theme_id == THEME_HOLYNET) {
    ApplyColor(cr, &pal.toolbar_border);
    cairo_set_line_width(cr, 1.8);
    cairo_rectangle(cr, 3.0, view_top + 3.0, win_w - SCROLLBAR_W - 6.0, view_h - 6.0);
    cairo_stroke(cr);
  }

  cairo_save(cr);
  cairo_rectangle(cr, 7.0, view_top + 7.0, win_w - SCROLLBAR_W - 14.0, view_h - 14.0);
  cairo_clip(cr);

  for (I64 i = 0; i < lyt->count; i++) {
    RenderItem *it = &lyt->items[i];
    F64 sy = view_top + it->y - scroll_y;
    if (sy + it->h < view_top - 12.0 || sy > view_top + view_h + 12.0)
      continue;

    if (it->kind == RITEM_PRE_BG) {
      ApplyColor(cr, &pal.pre_bg);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
      ApplyColor(cr, &pal.pre_border);
      cairo_set_line_width(cr, 1.0);
      cairo_rectangle(cr, it->x + 0.5, sy + 0.5, it->w - 1.0, it->h - 1.0);
      cairo_stroke(cr);
    } else if (it->kind == RITEM_CODE_BG) {
      ApplyColor(cr, &pal.code_bg);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
    } else if (it->kind == RITEM_MARK_BG) {
      if (is_davis) ApplyDavisColorIdx(cr, 14); /* YELLOW #FFFF55 */
      else cairo_set_source_rgb(cr, 1.00, 0.93, 0.42);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
    } else if (it->kind == RITEM_TBL_HDR_BG) {
      ApplyColor(cr, &pal.tbl_hdr_bg);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
    } else if (it->kind == RITEM_TBL_ROW_BG) {
      ApplyColor(cr, &pal.tbl_zebra_bg);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
    } else if (it->kind == RITEM_TBL_BORDER) {
      ApplyColor(cr, &pal.tbl_border);
      cairo_set_line_width(cr, 1.0);
      if (it->w <= 0.5) {
        cairo_move_to(cr, it->x + 0.5, sy);
        cairo_line_to(cr, it->x + 0.5, sy + it->h);
        cairo_stroke(cr);
      } else {
        cairo_rectangle(cr, it->x + 0.5, sy + 0.5, it->w - 1.0, it->h - 1.0);
        cairo_stroke(cr);
      }
    } else if (it->kind == RITEM_QUOTE_BAR) {
      ApplyColor(cr, &pal.quote_bar);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
    } else if (it->kind == RITEM_HR || it->kind == RITEM_H1_LINE) {
      ApplyColor(cr, &pal.hr_fg);
      cairo_rectangle(cr, it->x, sy, it->w, it->h);
      cairo_fill(cr);
    } else if (it->kind == RITEM_MARQUEE && it->text != NULL) {
      PaintAnimatedMarquee(cr, it, sy, GetBrowserAnimTimeSec(), is_davis);
    } else if (it->kind == RITEM_ANIM_CANVAS) {
      PaintAnimatedCanvas(cr, it, sy, GetBrowserAnimTimeSec(), is_davis);
    } else if (it->kind == RITEM_IMAGE && it->img_id >= 0 && it->img_id < doc->image_count) {
      DocImage *im = &doc->images[it->img_id];
      if (im->loaded && im->surface != NULL && im->nat_w > 0 && im->nat_h > 0) {
        U0 *draw_surf = im->surface;
        if (is_davis) {
          draw_surf = GetOrBuildDavis16ImageSurface(im);
        }
        cairo_save(cr);
        cairo_translate(cr, it->x, sy);
        cairo_scale(cr, it->w / im->nat_w, it->h / im->nat_h);
        cairo_set_source_surface(cr, draw_surf, 0.0, 0.0);
        if (is_davis) {
          /* Пиксельное масштабирование без размытия в духе спрайтов TempleOS! */
          cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
        }
        cairo_paint(cr);
        cairo_restore(cr);

        if (is_davis) {
          /* Чёткая рамка вокруг графического спрайта DolDoc */
          ApplyDavisColorIdx(cr, 1); /* BLUE #0000AA */
          cairo_set_line_width(cr, 1.0);
          cairo_rectangle(cr, it->x - 0.5, sy - 0.5, it->w + 1.0, it->h + 1.0);
          cairo_stroke(cr);
        }

        if (it->link_id >= 0 && it->link_id == hover_link_id) {
          ApplyColor(cr, &pal.link_hover);
          cairo_set_line_width(cr, 2.0);
          cairo_rectangle(cr, it->x - 1.0, sy - 1.0, it->w + 2.0, it->h + 2.0);
          cairo_stroke(cr);
        }
      }
    } else if (it->kind == RITEM_TEXT && it->text != NULL) {
      /* Подсветка совпадений поиска Ctrl+F (строго в 16 цветах VGA при активной теме Дэвиса!) */
      if (ItemMatchesFind(it, ui)) {
        if (is_davis) {
          if (ui->find_active_item == i) ApplyDavisColorIdx(cr, 11); /* LTCYAN #55FFFF */
          else ApplyDavisColorIdx(cr, 14); /* YELLOW #FFFF55 */
        } else {
          if (ui->find_active_item == i) cairo_set_source_rgb(cr, 1.00, 0.62, 0.16);
          else cairo_set_source_rgb(cr, 1.00, 0.94, 0.30);
        }
        cairo_rectangle(cr, it->x - 1.0, sy + 1.0, it->w + 2.0, it->h - 2.0);
        cairo_fill(cr);
      } else if (is_davis && it->link_id >= 0 && it->link_id == hover_link_id) {
        /* В TempleOS наведение на $LK$ ссылку подсвечивает её жёлтым маркером! */
        ApplyDavisColorIdx(cr, 14); /* YELLOW #FFFF55 */
        cairo_rectangle(cr, it->x - 1.0, sy + 1.0, it->w + 2.0, it->h - 2.0);
        cairo_fill(cr);
      }

      SelectNodeFont(cr, it->mono, it->italic, it->bold, it->font_size);

      if (it->link_id >= 0) {
        if (it->link_id == hover_link_id) ApplyColor(cr, &pal.link_hover);
        else ApplyColor(cr, &pal.link_fg);
      } else if (it->has_fg_color) {
        I32 r8 = (it->fg_rgb >> 16) & 0xFF;
        I32 g8 = (it->fg_rgb >> 8) & 0xFF;
        I32 b8 = it->fg_rgb & 0xFF;
        if (is_davis) {
          /* Квантуем любой цвет с веб-сайта в ближайший контрастный из 16 цветов Дэвиса! */
          I32 vga_idx = NearestDavisVgaIdx(r8, g8, b8, TRUE);
          ApplyDavisColorIdx(cr, vga_idx);
        } else {
          cairo_set_source_rgb(cr, r8 / 255.0, g8 / 255.0, b8 / 255.0);
        }
      } else if (it->in_pre) {
        ApplyColor(cr, &pal.pre_fg);
      } else if (it->mono) {
        ApplyColor(cr, &pal.code_fg);
      } else if (it->heading > 0) {
        ApplyColor(cr, &pal.heading_fg);
      } else if (it->in_quote) {
        ApplyColor(cr, &pal.quote_fg);
      } else {
        ApplyColor(cr, &pal.text_fg);
      }

      F64 baseline_y = sy + it->font_size * 1.06;
      cairo_move_to(cr, it->x, baseline_y);
      cairo_show_text(cr, it->text);

      if (it->underline || it->link_id >= 0) {
        F64 uw = 1.0;
        if (it->link_id == hover_link_id) uw = 1.8;
        cairo_set_line_width(cr, uw);
        cairo_move_to(cr, it->x, baseline_y + 2.5);
        cairo_line_to(cr, it->x + it->w, baseline_y + 2.5);
        cairo_stroke(cr);
      }
      if (it->strike) {
        cairo_set_line_width(cr, 1.2);
        cairo_move_to(cr, it->x, baseline_y - it->font_size * 0.32);
        cairo_line_to(cr, it->x + it->w, baseline_y - it->font_size * 0.32);
        cairo_stroke(cr);
      }
    }
  }

  cairo_restore(cr);

  /* 3. Правый скроллбар */
  F64 sb_x = win_w - SCROLLBAR_W;
  ApplyColor(cr, &pal.scroll_track);
  cairo_rectangle(cr, sb_x, view_top, SCROLLBAR_W, view_h);
  cairo_fill(cr);

  F64 total_h = lyt->content_height;
  if (total_h < view_h) total_h = view_h;
  F64 thumb_h = (view_h / total_h) * view_h;
  if (thumb_h < 28.0) thumb_h = 28.0;
  if (thumb_h > view_h) thumb_h = view_h;

  F64 max_scroll = total_h - view_h;
  F64 thumb_y = view_top;
  if (max_scroll > 0.0) {
    thumb_y = view_top + (scroll_y / max_scroll) * (view_h - thumb_h);
  }
  ApplyColor(cr, &pal.scroll_thumb);
  cairo_rectangle(cr, sb_x + 2.0, thumb_y + 1.0, SCROLLBAR_W - 4.0, thumb_h - 2.0);
  cairo_fill(cr);

  /* 4A. Полоса вкладок (Tabs Bar) */
  ApplyColor(cr, &pal.tabbar_bg);
  cairo_rectangle(cr, 0.0, 0.0, win_w, TABS_H);
  cairo_fill(cr);

  if (ui != NULL) {
    F64 tw = ComputeTabWidth(win_w, ui->tab_count);
    F64 tx = 6.0;
    for (I32 t = 0; t < ui->tab_count; t++) {
      Bool is_act = (t == ui->active_tab);
      if (is_act) ApplyColor(cr, &pal.tab_active_bg);
      else if (hover_btn == BTN_TAB_BASE + t) ApplyColor(cr, &pal.btn_hover);
      else ApplyColor(cr, &pal.tab_inactive_bg);

      cairo_rectangle(cr, tx, 3.0, tw - 3.0, TABS_H - 3.0);
      cairo_fill(cr);

      ApplyColor(cr, &pal.toolbar_border);
      cairo_set_line_width(cr, 1.0);
      cairo_rectangle(cr, tx + 0.5, 3.5, tw - 4.0, TABS_H - 3.0);
      cairo_stroke(cr);

      /* Индикатор сети на корешке вкладки (в режиме Дэвиса строго LTGREEN / LTCYAN) */
      if (is_davis) {
        if (ui->tabs[t].holy_mode) ApplyDavisColorIdx(cr, 10); /* LTGREEN #55FF55 */
        else ApplyDavisColorIdx(cr, 11); /* LTCYAN #55FFFF */
      } else {
        if (ui->tabs[t].holy_mode) cairo_set_source_rgb(cr, 0.25, 0.92, 0.48);
        else cairo_set_source_rgb(cr, 0.45, 0.72, 1.00);
      }
      cairo_rectangle(cr, tx + 6.0, 11.0, 7.0, 7.0);
      cairo_fill(cr);

      cairo_save(cr);
      F64 clip_tw = tw - 38.0;
      if (ui->tab_count <= 1) clip_tw = tw - 22.0;
      cairo_rectangle(cr, tx + 17.0, 4.0, clip_tw, TABS_H - 6.0);
      cairo_clip(cr);

      ApplyColor(cr, &pal.btn_fg);
      SelectNodeFont(cr, FALSE, FALSE, is_act, 12.0);
      cairo_move_to(cr, tx + 18.0, 20.0);
      cairo_show_text(cr, ui->tabs[t].title);
      cairo_restore(cr);

      if (ui->tab_count > 1) {
        if (hover_btn == BTN_TAB_CLOSE_BASE + t) {
          if (is_davis) ApplyDavisColorIdx(cr, 12); /* LTRED #FF5555 */
          else cairo_set_source_rgb(cr, 1.0, 0.45, 0.45);
        } else {
          ApplyColor(cr, &pal.btn_fg);
        }
        SelectNodeFont(cr, FALSE, FALSE, TRUE, 12.5);
        cairo_move_to(cr, tx + tw - 17.0, 20.0);
        cairo_show_text(cr, "x");
      }

      tx += tw;
    }

    if (ui->tab_count < MAX_TABS) {
      DrawButtonBox(cr, tx + 2.0, 4.0, 26.0, TABS_H - 6.0, "+",
                    hover_btn == BTN_NEW_TAB, TRUE, &pal);
    }
  }

  /* 4B. Полоса навигации и омнибокса */
  ApplyColor(cr, &pal.toolbar_bg);
  cairo_rectangle(cr, 0.0, TABS_H, win_w, NAVBAR_H);
  cairo_fill(cr);

  NavbarGeom ng;
  ComputeNavbarGeom(win_w, &ng);

  F64 ny = TABS_H + 6.0;
  DrawButtonBox(cr, ng.back_x, ny, ng.back_w, 32.0, "<", hover_btn == BTN_BACK,   can_back, &pal);
  DrawButtonBox(cr, ng.fwd_x,  ny, ng.fwd_w,  32.0, ">", hover_btn == BTN_FWD,    can_fwd,  &pal);
  DrawButtonBox(cr, ng.rel_x,  ny, ng.rel_w,  32.0, "R", hover_btn == BTN_RELOAD, TRUE,     &pal);
  DrawButtonBox(cr, ng.home_x, ny, ng.home_w, 32.0, "H", hover_btn == BTN_HOME,   TRUE,     &pal);

  I32 addr_x = ng.addr_x;
  I32 addr_w = ng.addr_w;

  ApplyColor(cr, &pal.addr_bg);
  cairo_rectangle(cr, addr_x, ny, addr_w, 32.0);
  cairo_fill(cr);

  if (addr_focused) {
    ApplyColor(cr, &pal.addr_focus);
    cairo_set_line_width(cr, 2.0);
  } else {
    ApplyColor(cr, &pal.addr_border);
    cairo_set_line_width(cr, 1.2);
  }
  cairo_rectangle(cr, addr_x + 0.5, ny + 0.5, addr_w - 1.0, 31.0);
  cairo_stroke(cr);

  cairo_save(cr);
  cairo_rectangle(cr, addr_x + 6.0, ny + 1.0, addr_w - 12.0, 30.0);
  cairo_clip(cr);

  if (addr_buf[0] == 0 && !addr_focused) {
    if (is_davis) ApplyDavisColorIdx(cr, 8); /* DKGRAY #555555 без полупрозрачности! */
    else cairo_set_source_rgba(cr, pal.addr_fg.r, pal.addr_fg.g, pal.addr_fg.b, 0.45);
    SelectNodeFont(cr, FALSE, TRUE, FALSE, 12.5);
    cairo_move_to(cr, addr_x + 7.0, ny + 21.0);
    if (ng.compact) cairo_show_text(cr, "URL / запрос...");
    else cairo_show_text(cr, "Введите домен или поисковый запрос...");
  } else {
    ApplyColor(cr, &pal.addr_fg);
    SelectNodeFont(cr, FALSE, FALSE, FALSE, 13.0);
    F64 url_adv = MeasureTextAdvance(cr, addr_buf);
    F64 text_x = addr_x + 7.0;
    if (addr_focused && url_adv > (addr_w - 20.0)) {
      text_x = (addr_x + addr_w - 10.0) - url_adv;
    }
    cairo_move_to(cr, text_x, ny + 21.0);
    cairo_show_text(cr, addr_buf);

    if (addr_focused) {
      ApplyColor(cr, &pal.link_fg);
      cairo_rectangle(cr, text_x + url_adv + 1.0, ny + 6.0, 2.0, 20.0);
      cairo_fill(cr);
    }
  }
  cairo_restore(cr);

  /* Кнопка избранного ★ / ☆ */
  U8 *star_lbl = "\xE2\x98\x86"; /* ☆ */
  if (ui != NULL && ui->current_is_bookmarked) star_lbl = "\xE2\x98\x85"; /* ★ */
  U8 *srch_lbl = "Найти";
  if (ng.compact) srch_lbl = "?";
  DrawButtonBox(cr, ng.star_x, ny, ng.star_w, 32.0, star_lbl, hover_btn == BTN_BOOKMARK_STAR, TRUE, &pal);
  DrawButtonBox(cr, ng.go_x,   ny, ng.go_w,   32.0, "Go",     hover_btn == BTN_GO,            TRUE, &pal);
  DrawButtonBox(cr, ng.srch_x, ny, ng.srch_w, 32.0, srch_lbl, hover_btn == BTN_SEARCH,        TRUE, &pal);

  /* Тумблер сети [■ В Холинете] / [■ В Интернете] */
  if (is_davis) {
    if (holy_mode) {
      if (hover_btn == BTN_HOLY_TOGGLE) ApplyDavisColorIdx(cr, 5);
      else ApplyDavisColorIdx(cr, 2); /* GREEN #00AA00 */
    } else {
      if (hover_btn == BTN_HOLY_TOGGLE) ApplyDavisColorIdx(cr, 5);
      else ApplyDavisColorIdx(cr, 1); /* BLUE #0000AA */
    }
  } else if (holy_mode) {
    if (hover_btn == BTN_HOLY_TOGGLE) cairo_set_source_rgb(cr, 0.14, 0.56, 0.36);
    else cairo_set_source_rgb(cr, 0.10, 0.46, 0.29);
  } else {
    if (hover_btn == BTN_HOLY_TOGGLE) ApplyColor(cr, &pal.btn_hover);
    else ApplyColor(cr, &pal.btn_bg);
  }
  cairo_rectangle(cr, ng.cheb_x, ny, ng.cheb_w, 32.0);
  cairo_fill(cr);

  if (is_davis) {
    if (holy_mode) ApplyDavisColorIdx(cr, 14);
    else ApplyDavisColorIdx(cr, 11);
  } else if (holy_mode) {
    cairo_set_source_rgb(cr, 0.96, 0.80, 0.28);
  } else {
    ApplyColor(cr, &pal.toolbar_border);
  }
  cairo_set_line_width(cr, 1.3);
  cairo_rectangle(cr, ng.cheb_x + 0.5, ny + 0.5, ng.cheb_w - 1.0, 31.0);
  cairo_stroke(cr);

  if (is_davis) {
    if (holy_mode) ApplyDavisColorIdx(cr, 10); /* LTGREEN */
    else ApplyDavisColorIdx(cr, 11); /* LTCYAN */
  } else if (holy_mode) {
    cairo_set_source_rgb(cr, 0.35, 1.00, 0.52);
  } else {
    cairo_set_source_rgb(cr, 0.55, 0.65, 0.78);
  }
  cairo_rectangle(cr, ng.cheb_x + 6.0, ny + 11.5, 8.0, 8.0);
  cairo_fill(cr);

  if (is_davis) ApplyDavisColorIdx(cr, 14);
  else if (holy_mode) cairo_set_source_rgb(cr, 1.00, 0.96, 0.72);
  else ApplyColor(cr, &pal.btn_fg);

  SelectNodeFont(cr, FALSE, FALSE, TRUE, 11.8);
  U8 *holy_lbl = "В Интернете";
  if (holy_mode) holy_lbl = "В Холинете";
  if (ng.compact) {
    if (holy_mode) holy_lbl = "Холи";
    else holy_lbl = "Инет";
  }
  cairo_move_to(cr, ng.cheb_x + 17.0, ny + 21.0);
  cairo_show_text(cr, holy_lbl);

  U8 *bld_lbl = "Констр";
  U8 *mon_lbl = "Монитор";
  U8 *fnd_lbl = "Стр?";
  if (ng.compact) {
    bld_lbl = "Кнст";
    mon_lbl = "Мон";
    fnd_lbl = "F?";
  }
  DrawButtonBox(cr, ng.bld_x,  ny, ng.bld_w,  32.0, bld_lbl, hover_btn == BTN_BUILDER,     TRUE, &pal);
  DrawButtonBox(cr, ng.mon_x,  ny, ng.mon_w,  32.0, mon_lbl, hover_btn == BTN_MONITOR,     TRUE, &pal);
  DrawButtonBox(cr, ng.zout_x, ny, ng.zout_w, 32.0, "-",     hover_btn == BTN_ZOOM_OUT,    TRUE, &pal);
  DrawButtonBox(cr, ng.zin_x,  ny, ng.zin_w,  32.0, "+",     hover_btn == BTN_ZOOM_IN,     TRUE, &pal);
  DrawButtonBox(cr, ng.find_x, ny, ng.find_w, 32.0, fnd_lbl, hover_btn == BTN_FIND_TOGGLE, TRUE, &pal);

  U8 *tlabel = "Modern";
  if (theme_id == THEME_TEMPLE) tlabel = "Temple";
  if (theme_id == THEME_HOLYNET) tlabel = "Холинет";
  if (theme_id == THEME_DAVIS) {
    if (ng.compact) tlabel = "Дэвис16";
    else tlabel = "Дэвис 16c";
  }
  DrawButtonBox(cr, ng.theme_x, ny, ng.theme_w, 32.0, tlabel, hover_btn == BTN_THEME, TRUE, &pal);

  /* 4C. Полоса закладок (Bookmarks Bar) */
  F64 bmy = TABS_H + NAVBAR_H;
  ApplyColor(cr, &pal.bmark_bg);
  cairo_rectangle(cr, 0.0, bmy, win_w, BOOKMARKS_H);
  cairo_fill(cr);

  ApplyColor(cr, &pal.toolbar_border);
  cairo_set_line_width(cr, 1.3);
  cairo_move_to(cr, 0.0, TOOLBAR_H - 0.5);
  cairo_line_to(cr, win_w, TOOLBAR_H - 0.5);
  cairo_stroke(cr);

  ApplyColor(cr, &pal.btn_fg);
  SelectNodeFont(cr, FALSE, FALSE, TRUE, 11.5);
  cairo_move_to(cr, 10.0, bmy + 17.0);
  cairo_show_text(cr, "\xE2\x98\x85 Закладки:");

  if (ui != NULL) {
    F64 right_guard = win_w - 8.0;
    if (is_davis && win_w >= 640) right_guard = win_w - 196.0;

    F64 bx = 92.0;
    if (ng.compact) bx = 96.0;
    for (I32 b = 0; b < ui->bookmark_count; b++) {
      if (!ui->bookmarks[b].used) continue;
      F64 bw = StrLen(ui->bookmarks[b].title) * 6.4 + 22.0;
      if (bw < 68.0) bw = 68.0;
      if (bw > 155.0) bw = 155.0;
      if (bx + bw > right_guard) break;

      if (hover_btn == BTN_BMARK_BASE + b) ApplyColor(cr, &pal.btn_hover);
      else ApplyColor(cr, &pal.btn_bg);
      cairo_rectangle(cr, bx, bmy + 3.0, bw, BOOKMARKS_H - 6.0);
      cairo_fill(cr);

      ApplyColor(cr, &pal.toolbar_border);
      cairo_set_line_width(cr, 0.9);
      cairo_rectangle(cr, bx + 0.5, bmy + 3.5, bw - 1.0, BOOKMARKS_H - 7.0);
      cairo_stroke(cr);

      cairo_save(cr);
      cairo_rectangle(cr, bx + 5.0, bmy + 3.0, bw - 10.0, BOOKMARKS_H - 6.0);
      cairo_clip(cr);
      ApplyColor(cr, &pal.btn_fg);
      SelectNodeFont(cr, FALSE, FALSE, FALSE, 11.5);
      cairo_move_to(cr, bx + 7.0, bmy + 17.0);
      cairo_show_text(cr, ui->bookmarks[b].title);
      cairo_restore(cr);

      bx += bw + 6.0;
    }
  }

  /* В теме «Одобрение Дэвиса» рисуем контрольную шкалу всех 16 цветов VGA + подсказку F7! */
  if (is_davis && win_w >= 640) {
    F64 sw_start = win_w - 186.0;
    ApplyDavisColorIdx(cr, 0); /* BLACK подложка под 16 квадратов палитры */
    cairo_rectangle(cr, sw_start - 2.0, bmy + 4.0, 180.0, 18.0);
    cairo_fill(cr);

    ApplyDavisColorIdx(cr, 15); /* WHITE */
    SelectNodeFont(cr, TRUE, FALSE, TRUE, 10.5);
    cairo_move_to(cr, sw_start + 3.0, bmy + 16.5);
    cairo_show_text(cr, "16c:");

    F64 sx = sw_start + 34.0;
    for (I32 ci = 0; ci < 16; ci++) {
      ApplyDavisColorIdx(cr, ci);
      cairo_rectangle(cr, sx + ci * 9.0, bmy + 6.0, 8.0, 14.0);
      cairo_fill(cr);
    }
  }

  /* 4D. Всплывающая панель поиска на странице (Ctrl+F) */
  if (ui != NULL && ui->find_active) {
    F64 fb_w = 390.0;
    F64 fb_h = 34.0;
    F64 fb_x = win_w - SCROLLBAR_W - fb_w - 10.0;
    F64 fb_y = win_h - STATUSBAR_H - fb_h - 8.0;

    ApplyColor(cr, &pal.toolbar_bg);
    cairo_rectangle(cr, fb_x, fb_y, fb_w, fb_h);
    cairo_fill(cr);

    ApplyColor(cr, &pal.toolbar_border);
    cairo_set_line_width(cr, 1.5);
    cairo_rectangle(cr, fb_x + 0.5, fb_y + 0.5, fb_w - 1.0, fb_h - 1.0);
    cairo_stroke(cr);

    ApplyColor(cr, &pal.btn_fg);
    SelectNodeFont(cr, FALSE, FALSE, TRUE, 12.0);
    cairo_move_to(cr, fb_x + 8.0, fb_y + 21.0);
    cairo_show_text(cr, "На странице:");

    ApplyColor(cr, &pal.addr_bg);
    cairo_rectangle(cr, fb_x + 104.0, fb_y + 5.0, 148.0, 24.0);
    cairo_fill(cr);
    if (ui->find_focused) ApplyColor(cr, &pal.addr_focus);
    else ApplyColor(cr, &pal.addr_border);
    cairo_set_line_width(cr, 1.4);
    cairo_rectangle(cr, fb_x + 104.5, fb_y + 5.5, 147.0, 23.0);
    cairo_stroke(cr);

    cairo_save(cr);
    cairo_rectangle(cr, fb_x + 108.0, fb_y + 6.0, 140.0, 22.0);
    cairo_clip(cr);
    ApplyColor(cr, &pal.addr_fg);
    SelectNodeFont(cr, FALSE, FALSE, FALSE, 12.5);
    cairo_move_to(cr, fb_x + 109.0, fb_y + 21.0);
    cairo_show_text(cr, ui->find_query);
    if (ui->find_focused) {
      F64 fa = MeasureTextAdvance(cr, ui->find_query);
      ApplyColor(cr, &pal.link_fg);
      cairo_rectangle(cr, fb_x + 110.0 + fa, fb_y + 8.0, 2.0, 16.0);
      cairo_fill(cr);
    }
    cairo_restore(cr);

    U8 cnt_lbl[32];
    if (ui->find_total > 0)
      snprintf(cnt_lbl, sizeof(cnt_lbl), "%d/%d", ui->find_current + 1, ui->find_total);
    else
      SafeCopy(cnt_lbl, "0/0", sizeof(cnt_lbl));

    ApplyColor(cr, &pal.btn_fg);
    SelectNodeFont(cr, TRUE, FALSE, FALSE, 11.5);
    cairo_move_to(cr, fb_x + 258.0, fb_y + 21.0);
    cairo_show_text(cr, cnt_lbl);

    DrawButtonBox(cr, fb_x + 304.0, fb_y + 5.0, 26.0, 24.0, "^", hover_btn == BTN_FIND_PREV,   TRUE, &pal);
    DrawButtonBox(cr, fb_x + 333.0, fb_y + 5.0, 26.0, 24.0, "v", hover_btn == BTN_FIND_NEXT,   TRUE, &pal);
    DrawButtonBox(cr, fb_x + 362.0, fb_y + 5.0, 24.0, 24.0, "x", hover_btn == BTN_FIND_CLOSE, TRUE, &pal);
  }

  /* 5. Нижний статус-бар + индикатор масштаба */
  F64 sb_y = win_h - STATUSBAR_H;
  ApplyColor(cr, &pal.status_bg);
  cairo_rectangle(cr, 0.0, sb_y, win_w, STATUSBAR_H);
  cairo_fill(cr);

  ApplyColor(cr, &pal.toolbar_border);
  cairo_set_line_width(cr, 1.0);
  cairo_move_to(cr, 0.0, sb_y + 0.5);
  cairo_line_to(cr, win_w, sb_y + 0.5);
  cairo_stroke(cr);

  ApplyColor(cr, &pal.status_fg);
  SelectNodeFont(cr, FALSE, FALSE, FALSE, 12.2);
  U8 bar_line[1150];
  if (hover_link_id >= 0 && hover_link_id < doc->link_count) {
    U8 *hl = doc->links[hover_link_id];
    if (is_davis) {
      snprintf(bar_line, sizeof(bar_line), "$LK,\"ПЕРЕХОД\",A=\"%s\"$  [16 ЦВЕТОВ VGA | F7: Оракул Дэвиса]", hl);
    } else if (StartsWithIgnoreCase(hl, "holy://")) {
      snprintf(bar_line, sizeof(bar_line), "Перейти в Холинете (Holynet): %s", hl + 7);
    } else {
      snprintf(bar_line, sizeof(bar_line), "Перейти по ссылке: %s", hl);
    }
  } else {
    SafeCopy(bar_line, status_msg, sizeof(bar_line));
  }
  cairo_save(cr);
  cairo_rectangle(cr, 8.0, sb_y + 2.0, win_w - 148.0, STATUSBAR_H - 4.0);
  cairo_clip(cr);
  cairo_move_to(cr, 12.0, sb_y + 17.5);
  cairo_show_text(cr, bar_line);
  cairo_restore(cr);

  if (ui != NULL) {
    U8 zoom_txt[48];
    I32 zp = (ui->zoom * 100.0 + 0.5);
    if (is_davis) snprintf(zoom_txt, sizeof(zoom_txt), "16VGA %d%%", zp);
    else snprintf(zoom_txt, sizeof(zoom_txt), "Масштаб: %d%%", zp);
    SelectNodeFont(cr, TRUE, FALSE, TRUE, 11.5);
    F64 zw = MeasureTextAdvance(cr, zoom_txt);
    cairo_move_to(cr, win_w - zw - 12.0, sb_y + 17.5);
    cairo_show_text(cr, zoom_txt);
  }
}
