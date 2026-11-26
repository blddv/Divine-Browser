/* ============================================================================
 * holynet_builder.HC — Графический 2D Конструктор сайтов Холинета на Cairo
 * Позволяет занять любой свободный домен и опубликовать сайт в P2P-сеть HOLY/1.0
 * ============================================================================ */

#define BBLK_H2     1
#define BBLK_TEXT   2
#define BBLK_QUOTE  3
#define BBLK_CODE   4
#define BBLK_LI     5
#define BBLK_LINK   6

/* Идентификаторы интерактивных виджетов Конструктора */
#define BWID_NONE           0
#define BWID_FIELD_DOMAIN   1
#define BWID_FIELD_TITLE    2
#define BWID_FIELD_SUBTITLE 3
#define BWID_FIELD_BLKTEXT  4
#define BWID_FIELD_LINKURL  5
#define BWID_FIELD_HTMLFILE 6

#define BWID_TPL_CARD       10
#define BWID_TPL_WIKI       11
#define BWID_TPL_SEARCH     12
#define BWID_TPL_BLOG       13

#define BWID_ADD_H2         20
#define BWID_ADD_TEXT       21
#define BWID_ADD_QUOTE      22
#define BWID_ADD_CODE       23
#define BWID_ADD_LI         24
#define BWID_ADD_LINK       25
#define BWID_DEL_LAST       26
#define BWID_CLEAR_ALL      27

#define BWID_PUBLISH        30
#define BWID_EXIT_HOME      31
#define BWID_PUBLISH_HTML   32

class BuilderBlock
{
  I32 kind;
  U8  text[384];
  U8  href[128];
};

class SiteBuilderState
{
  Bool active;
  I32  focused_field;
  I32  hover_widget;

  U8   domain_buf[128];
  U8   title_buf[160];
  U8   subtitle_buf[240];
  U8   block_input[384];
  U8   link_input[128];
  U8   html_file_buf[256];

  BuilderBlock blocks[24];
  I32          block_count;

  U8   feedback_msg[256];
  Bool feedback_error;
};

U0 BuilderPushBlock(SiteBuilderState *st, I32 kind, U8 *txt, U8 *href)
{
  if (st->block_count >= 24) return;
  BuilderBlock *b = &st->blocks[st->block_count++];
  b->kind = kind;
  SafeCopy(b->text, txt, sizeof(b->text));
  SafeCopy(b->href, href, sizeof(b->href));
}

U0 BuilderApplyTemplate(SiteBuilderState *st, I32 tpl_id)
{
  st->block_count = 0;
  st->feedback_error = FALSE;

  if (tpl_id == BWID_TPL_CARD) {
    SafeCopy(st->title_buf, "Мастерская системного кода в Холинете", sizeof(st->title_buf));
    SafeCopy(st->subtitle_buf, "Суверенный P2P-сайт, раздаваемый напрямую из браузера на HolyC", sizeof(st->subtitle_buf));
    BuilderPushBlock(st, BBLK_H2, "О нашем узле", "");
    BuilderPushBlock(st, BBLK_TEXT, "Этот домен занят нами в децентрализованной сети Холинет. Здесь нет облаков и посредников — страницу отдаёт сокет нашего браузера.", "");
    BuilderPushBlock(st, BBLK_CODE, "U0 HelloHolynet() { \"Привет, суверенный P2P!\\n\"; }", "");
    BuilderPushBlock(st, BBLK_LINK, "Посмотреть пульс сети в Мониторинге", "holy://monitor");
    SafeCopy(st->feedback_msg, "Загружен шаблон «Визитка узла».", sizeof(st->feedback_msg));
  } else if (tpl_id == BWID_TPL_WIKI) {
    SafeCopy(st->title_buf, "Свободная Летопись Холинета", sizeof(st->title_buf));
    SafeCopy(st->subtitle_buf, "Народная база знаний, открытая каждым узлом без цензуры корпораций", sizeof(st->subtitle_buf));
    BuilderPushBlock(st, BBLK_QUOTE, "В Холинете нет чужой Википедии — мы пишем собственную энциклопедию всем миром!", "");
    BuilderPushBlock(st, BBLK_H2, "Разделы знаний", "");
    BuilderPushBlock(st, BBLK_LI, "Архитектура компилятора HolyC и наследие TempleOS", "");
    BuilderPushBlock(st, BBLK_LI, "Устройство пирингового протокола HOLY/1.0_DIVINE_MESH", "");
    BuilderPushBlock(st, BBLK_LINK, "Перейти на соседнюю БерестаПедию", "holy://wikipedia.org");
    SafeCopy(st->feedback_msg, "Загружен шаблон «Энциклопедия».", sizeof(st->feedback_msg));
  } else if (tpl_id == BWID_TPL_SEARCH) {
    SafeCopy(st->title_buf, "Ищейка — Главный каталог доменов Холинета", sizeof(st->title_buf));
    SafeCopy(st->subtitle_buf, "Мы заняли этот мировой домен раньше всех! Навигатор по лучшим P2P-узлам сети.", sizeof(st->subtitle_buf));
    BuilderPushBlock(st, BBLK_H2, "Проверенные сайты в P2P-сети", "");
    BuilderPushBlock(st, BBLK_LINK, "БерестаПедия (бывший wikipedia.org)", "wikipedia.org");
    BuilderPushBlock(st, BBLK_LINK, "ДиафильмПроектор (бывший youtube.com)", "youtube.com");
    BuilderPushBlock(st, BBLK_LINK, "Береста.СУ — Доска объявлений", "beresta.su");
    BuilderPushBlock(st, BBLK_LINK, "КвасПром — Стратегический квас", "kvas.ru");
    SafeCopy(st->feedback_msg, "Загружен шаблон «Поисковик / Каталог».", sizeof(st->feedback_msg));
  } else if (tpl_id == BWID_TPL_BLOG) {
    SafeCopy(st->title_buf, "Бортовой журнал P2P-капитана", sizeof(st->title_buf));
    SafeCopy(st->subtitle_buf, "Заметки о программировании на HolyC, самосборных сетях и тёплом ламповом софте", sizeof(st->subtitle_buf));
    BuilderPushBlock(st, BBLK_H2, "Запись #1: Мы вышли в эфир Холинета!", "");
    BuilderPushBlock(st, BBLK_TEXT, "Сегодня поднял собственный узел браузера DivineWeb и занял этот домен за пару секунд прямо из встроенного конструктора.", "");
    BuilderPushBlock(st, BBLK_QUOTE, "Кто первый поднял сокет — того и домен!", "");
    BuilderPushBlock(st, BBLK_LINK, "Вернуться в общий каталог Холинета", "holy://home");
    SafeCopy(st->feedback_msg, "Загружен шаблон «Блог / Борда».", sizeof(st->feedback_msg));
  }
}

U0 BuilderInit(SiteBuilderState *st)
{
  MemSet(st, 0, sizeof(SiteBuilderState));
  st->focused_field = BWID_FIELD_DOMAIN;
  SafeCopy(st->domain_buf, "google.com", sizeof(st->domain_buf));
  SafeCopy(st->block_input, "Новый блок текста для вашего P2P-сайта...", sizeof(st->block_input));
  SafeCopy(st->link_input, "wikipedia.org", sizeof(st->link_input));
  SafeCopy(st->html_file_buf, "./demo.html", sizeof(st->html_file_buf));
  BuilderApplyTemplate(st, BWID_TPL_SEARCH);
  SafeCopy(st->feedback_msg, "Выберите или введите любой свободный домен и нажмите «Опубликовать в P2P»!", sizeof(st->feedback_msg));
}

U0 HtmlEscapeAppend(U8 *dst, I64 *pos, I64 cap, U8 *src)
{
  for (I64 i = 0; src[i] != 0 && *pos + 12 < cap; i++) {
    U8 c = src[i];
    if (c == '<') {
      MemCpy(dst + *pos, "&lt;", 4); *pos += 4;
    } else if (c == '>') {
      MemCpy(dst + *pos, "&gt;", 4); *pos += 4;
    } else if (c == '&') {
      MemCpy(dst + *pos, "&amp;", 5); *pos += 5;
    } else if (c == '"') {
      MemCpy(dst + *pos, "&quot;", 6); *pos += 6;
    } else {
      dst[*pos] = c;
      *pos = *pos + 1;
    }
  }
  dst[*pos] = 0;
}

/* Сборка чистого HTML из блоков Конструктора для раздачи в P2P */
U8 *BuilderCompileHtml(SiteBuilderState *st)
{
  I64 cap = 32768;
  U8 *out = MAlloc(cap);
  I64 pos = 0;

  pos += snprintf(out + pos, cap - pos, "<!DOCTYPE html><html><head><title>");
  HtmlEscapeAppend(out, &pos, cap, st->title_buf);
  pos += snprintf(out + pos, cap - pos, "</title></head><body><h1>");
  HtmlEscapeAppend(out, &pos, cap, st->title_buf);
  pos += snprintf(out + pos, cap - pos, "</h1>");

  if (st->subtitle_buf[0] != 0) {
    pos += snprintf(out + pos, cap - pos, "<blockquote><b>Домен <code>%s</code> (узел %s):</b> ",
                    st->domain_buf, g_holy.node_id);
    HtmlEscapeAppend(out, &pos, cap, st->subtitle_buf);
    pos += snprintf(out + pos, cap - pos, "</blockquote>");
  }

  Bool in_ul = FALSE;
  for (I32 i = 0; i < st->block_count; i++) {
    BuilderBlock *b = &st->blocks[i];
    if (b->kind == BBLK_LI) {
      if (!in_ul) {
        pos += snprintf(out + pos, cap - pos, "<ul>");
        in_ul = TRUE;
      }
      pos += snprintf(out + pos, cap - pos, "<li>");
      HtmlEscapeAppend(out, &pos, cap, b->text);
      pos += snprintf(out + pos, cap - pos, "</li>");
      continue;
    }

    if (in_ul) {
      pos += snprintf(out + pos, cap - pos, "</ul>");
      in_ul = FALSE;
    }

    if (b->kind == BBLK_H2) {
      pos += snprintf(out + pos, cap - pos, "<h2>");
      HtmlEscapeAppend(out, &pos, cap, b->text);
      pos += snprintf(out + pos, cap - pos, "</h2>");
    } else if (b->kind == BBLK_TEXT) {
      pos += snprintf(out + pos, cap - pos, "<p>");
      HtmlEscapeAppend(out, &pos, cap, b->text);
      pos += snprintf(out + pos, cap - pos, "</p>");
    } else if (b->kind == BBLK_QUOTE) {
      pos += snprintf(out + pos, cap - pos, "<blockquote>");
      HtmlEscapeAppend(out, &pos, cap, b->text);
      pos += snprintf(out + pos, cap - pos, "</blockquote>");
    } else if (b->kind == BBLK_CODE) {
      pos += snprintf(out + pos, cap - pos, "<pre>");
      HtmlEscapeAppend(out, &pos, cap, b->text);
      pos += snprintf(out + pos, cap - pos, "</pre>");
    } else if (b->kind == BBLK_LINK) {
      U8 target[160];
      U8 clean_disp[160];
      if (strstr(b->href, "://") != NULL) {
        SafeCopy(target, b->href, sizeof(target));
        if (StartsWithIgnoreCase(b->href, "holy://")) SafeCopy(clean_disp, b->href + 7, sizeof(clean_disp));
        else SafeCopy(clean_disp, b->href, sizeof(clean_disp));
      } else {
        snprintf(target, sizeof(target), "holy://%s", b->href);
        SafeCopy(clean_disp, b->href, sizeof(clean_disp));
      }
      pos += snprintf(out + pos, cap - pos, "<p>&rarr; <a href=\"%s\"><b>", target);
      HtmlEscapeAppend(out, &pos, cap, b->text);
      pos += snprintf(out + pos, cap - pos, "</b></a> (<code>%s</code>)</p>", clean_disp);
    }
  }

  if (in_ul) {
    pos += snprintf(out + pos, cap - pos, "</ul>");
  }

  pos += snprintf(out + pos, cap - pos,
    "<hr><p><i>Сайт собран во встроенном Конструкторе Холинета и раздаётся по P2P (%s)</i> | "
    "<a href=\"holy://builder?claim=%s\">Редактировать</a> | "
    "<a href=\"holy://monitor\">Мониторинг P2P</a> | "
    "<a href=\"holy://home\">Каталог</a></p></body></html>",
    g_holy.node_id, st->domain_buf
  );
  return out;
}

/* Вспомогательная отрисовка кнопки виджета в Конструкторе */
U0 DrawBuilderBtn(U0 *cr, F64 x, F64 y, F64 w, F64 h, U8 *label,
                  Bool hovered, Bool accent, Bool danger)
{
  if (g_davis_mono_mode) {
    if (accent) {
      if (hovered) ApplyDavisColorIdx(cr, 5);
      else ApplyDavisColorIdx(cr, 1); /* BLUE #0000AA */
    } else if (danger) {
      if (hovered) ApplyDavisColorIdx(cr, 12);
      else ApplyDavisColorIdx(cr, 4); /* RED #AA0000 */
    } else {
      if (hovered) ApplyDavisColorIdx(cr, 11); /* LTCYAN */
      else ApplyDavisColorIdx(cr, 7); /* LTGRAY */
    }
    cairo_rectangle(cr, x, y, w, h);
    cairo_fill(cr);

    if (accent || danger) ApplyDavisColorIdx(cr, 14);
    else ApplyDavisColorIdx(cr, 1);
    cairo_set_line_width(cr, 1.0);
    cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1.0, h - 1.0);
    cairo_stroke(cr);

    if (accent || danger) ApplyDavisColorIdx(cr, 14);
    else ApplyDavisColorIdx(cr, 0);
  } else {
    if (accent) {
      if (hovered) cairo_set_source_rgb(cr, 0.05, 0.45, 0.30);
      else cairo_set_source_rgb(cr, 0.06, 0.36, 0.24);
    } else if (danger) {
      if (hovered) cairo_set_source_rgb(cr, 0.78, 0.18, 0.18);
      else cairo_set_source_rgb(cr, 0.65, 0.14, 0.14);
    } else {
      if (hovered) cairo_set_source_rgb(cr, 0.85, 0.93, 0.88);
      else cairo_set_source_rgb(cr, 0.93, 0.96, 0.94);
    }
    cairo_rectangle(cr, x, y, w, h);
    cairo_fill(cr);

    if (accent || danger) cairo_set_source_rgb(cr, 0.95, 0.85, 0.45);
    else cairo_set_source_rgb(cr, 0.55, 0.68, 0.60);
    cairo_set_line_width(cr, 1.2);
    cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1.0, h - 1.0);
    cairo_stroke(cr);

    if (accent || danger) cairo_set_source_rgb(cr, 1.0, 0.97, 0.85);
    else cairo_set_source_rgb(cr, 0.08, 0.22, 0.16);
  }

  SelectNodeFont(cr, FALSE, FALSE, TRUE, 12.5);
  CairoTextExtents ext;
  cairo_text_extents(cr, label, &ext);
  F64 tx = x + (w - ext.width) * 0.5 - ext.x_bearing;
  F64 ty = y + (h - ext.height) * 0.5 - ext.y_bearing;
  cairo_move_to(cr, tx, ty);
  cairo_show_text(cr, label);
}

/* Вспомогательная отрисовка интерактивного текстового поля */
U0 DrawBuilderInput(U0 *cr, F64 x, F64 y, F64 w, F64 h, U8 *caption, U8 *val, Bool focused)
{
  cairo_set_source_rgb(cr, 0.12, 0.26, 0.20);
  SelectNodeFont(cr, FALSE, FALSE, TRUE, 12.5);
  cairo_move_to(cr, x, y - 5.0);
  cairo_show_text(cr, caption);

  cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
  cairo_rectangle(cr, x, y, w, h);
  cairo_fill(cr);

  if (focused) {
    cairo_set_source_rgb(cr, 0.07, 0.52, 0.35);
    cairo_set_line_width(cr, 2.2);
  } else {
    cairo_set_source_rgb(cr, 0.65, 0.75, 0.70);
    cairo_set_line_width(cr, 1.2);
  }
  cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1.0, h - 1.0);
  cairo_stroke(cr);

  cairo_save(cr);
  cairo_rectangle(cr, x + 6.0, y + 2.0, w - 12.0, h - 4.0);
  cairo_clip(cr);

  cairo_set_source_rgb(cr, 0.06, 0.10, 0.08);
  SelectNodeFont(cr, FALSE, FALSE, FALSE, 13.5);
  F64 adv = MeasureTextAdvance(cr, val);
  F64 tx = x + 8.0;
  if (focused && adv > (w - 22.0)) {
    tx = (x + w - 14.0) - adv;
  }
  cairo_move_to(cr, tx, y + h - 8.0);
  cairo_show_text(cr, val);

  if (focused) {
    cairo_set_source_rgb(cr, 0.80, 0.15, 0.15);
    cairo_rectangle(cr, tx + adv + 1.5, y + 5.0, 2.0, h - 10.0);
    cairo_fill(cr);
  }
  cairo_restore(cr);
}

/* Хит-тест мыши по всем виджетам Конструктора сайтов */
I32 HitTestBuilder(I32 mx, I32 my, I32 win_w, I32 win_h)
{
  F64 top = TOOLBAR_H;
  if (my < top || my > win_h - STATUSBAR_H) return BWID_NONE;

  F64 pad = 24.0;
  F64 full_w = win_w - pad * 2.0;

  /* Кнопка Назад в шапке конструктора */
  if (my >= top + 12 && my <= top + 40 && mx >= win_w - 190 && mx <= win_w - 24)
    return BWID_EXIT_HOME;

  /* Строка домена + 4 кнопки шаблонов */
  F64 r1_y = top + 68.0;
  if (my >= r1_y && my <= r1_y + 30.0) {
    if (mx >= pad && mx <= pad + 290.0) return BWID_FIELD_DOMAIN;
  }

  F64 tpl_y = top + 110.0;
  if (my >= tpl_y && my <= tpl_y + 28.0) {
    if (mx >= pad && mx <= pad + 165.0) return BWID_TPL_CARD;
    if (mx >= pad + 173.0 && mx <= pad + 355.0) return BWID_TPL_WIKI;
    if (mx >= pad + 363.0 && mx <= pad + 555.0) return BWID_TPL_SEARCH;
    if (mx >= pad + 563.0 && mx <= pad + 735.0) return BWID_TPL_BLOG;
  }

  /* Заголовок и подзаголовок */
  F64 r2_y = top + 162.0;
  F64 half_w = (full_w - 16.0) * 0.5;
  if (my >= r2_y && my <= r2_y + 30.0) {
    if (mx >= pad && mx <= pad + half_w) return BWID_FIELD_TITLE;
    if (mx >= pad + half_w + 16.0 && mx <= pad + full_w) return BWID_FIELD_SUBTITLE;
  }

  /* Поля нового блока и URL ссылки */
  F64 r3_y = top + 216.0;
  F64 blk_w = full_w - 260.0;
  if (blk_w < 200.0) blk_w = 200.0;
  if (my >= r3_y && my <= r3_y + 30.0) {
    if (mx >= pad && mx <= pad + blk_w) return BWID_FIELD_BLKTEXT;
    if (mx >= pad + blk_w + 14.0 && mx <= pad + full_w) return BWID_FIELD_LINKURL;
  }

  /* Кнопки добавления блоков */
  F64 b_y = top + 254.0;
  if (my >= b_y && my <= b_y + 28.0) {
    if (mx >= pad + 0.0   && mx <= pad + 112.0) return BWID_ADD_H2;
    if (mx >= pad + 118.0 && mx <= pad + 220.0) return BWID_ADD_TEXT;
    if (mx >= pad + 226.0 && mx <= pad + 332.0) return BWID_ADD_QUOTE;
    if (mx >= pad + 338.0 && mx <= pad + 450.0) return BWID_ADD_CODE;
    if (mx >= pad + 456.0 && mx <= pad + 566.0) return BWID_ADD_LI;
    if (mx >= pad + 572.0 && mx <= pad + 694.0) return BWID_ADD_LINK;
    if (mx >= pad + 704.0 && mx <= pad + 824.0) return BWID_DEL_LAST;
    if (mx >= pad + 830.0 && mx <= pad + 940.0) return BWID_CLEAR_ALL;
  }

  /* Поле и кнопка загрузки готового .html файла с диска */
  F64 pub_y = win_h - STATUSBAR_H - 46.0;
  F64 html_y = pub_y - 42.0;
  F64 html_in_w = full_w - 332.0;
  if (my >= html_y && my <= html_y + 30.0) {
    if (mx >= pad && mx <= pad + html_in_w) return BWID_FIELD_HTMLFILE;
    if (mx >= pad + html_in_w + 12.0 && mx <= pad + full_w) return BWID_PUBLISH_HTML;
  }

  /* Главная кнопка публикации внизу */
  if (my >= pub_y && my <= pub_y + 36.0 && mx >= pad && mx <= pad + full_w) {
    return BWID_PUBLISH;
  }

  return BWID_NONE;
}

/* Полная отрисовка интерфейса Конструктора сайтов Холинета */
U0 RenderBuilderCanvas(U0 *cr, SiteBuilderState *st, I32 win_w, I32 win_h)
{
  F64 top = TOOLBAR_H;
  F64 view_h = win_h - TOOLBAR_H - STATUSBAR_H;
  F64 pad = 24.0;
  F64 full_w = win_w - pad * 2.0;

  /* Рабочий фон и шапка Конструктора */
  if (g_davis_mono_mode) ApplyDavisColorIdx(cr, 15); /* WHITE #FFFFFF */
  else cairo_set_source_rgb(cr, 0.96, 0.98, 0.96);
  cairo_rectangle(cr, 0.0, top, win_w, view_h);
  cairo_fill(cr);

  if (g_davis_mono_mode) ApplyDavisColorIdx(cr, 1); /* BLUE #0000AA */
  else cairo_set_source_rgb(cr, 0.06, 0.30, 0.21);
  cairo_rectangle(cr, 0.0, top, win_w, 48.0);
  cairo_fill(cr);

  if (g_davis_mono_mode) ApplyDavisColorIdx(cr, 14); /* YELLOW #FFFF55 */
  else cairo_set_source_rgb(cr, 0.99, 0.92, 0.62);
  SelectNodeFont(cr, FALSE, FALSE, TRUE, 17.0);
  cairo_move_to(cr, pad, top + 30.0);
  cairo_show_text(cr, "КОНСТРУКТОР САЙТОВ ХОЛИНЕТА  (P2P-сеть браузера HOLY/1.0)");

  DrawBuilderBtn(cr, win_w - 190.0, top + 10.0, 166.0, 28.0,
                 "В каталог Холинета", st->hover_widget == BWID_EXIT_HOME, FALSE, FALSE);

  /* Строка 1: Домен + Живой статус владения в P2P-сети */
  F64 r1_y = top + 68.0;
  DrawBuilderInput(cr, pad, r1_y, 290.0, 30.0,
                   "1. Любой домен в Холинете (без ограничений):",
                   st->domain_buf, st->focused_field == BWID_FIELD_DOMAIN);

  U8 owner_id[64];
  I32 cur_ver = 0;
  I32 dom_state = HolyInspectDomainOwner(st->domain_buf, owner_id, sizeof(owner_id), &cur_ver);

  F64 badge_x = pad + 304.0;
  F64 badge_w = full_w - 304.0;
  U8 badge_txt[180];
  if (dom_state == 0) {
    cairo_set_source_rgb(cr, 0.84, 0.96, 0.87);
    cairo_rectangle(cr, badge_x, r1_y, badge_w, 30.0);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.08, 0.48, 0.22);
    snprintf(badge_txt, sizeof(badge_txt),
             "[ НЕ НАЙДЕН ] '%s' отсутствует в текущем каталоге; владельцы не проверяются.",
             st->domain_buf);
  } else if (dom_state == 1) {
    cairo_set_source_rgb(cr, 0.85, 0.92, 0.99);
    cairo_rectangle(cr, badge_x, r1_y, badge_w, 30.0);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.08, 0.30, 0.65);
    snprintf(badge_txt, sizeof(badge_txt),
             "[ ВАШ ДОМЕН ] Закреплён за вашим узлом %s (текущая версия v%d -> обновится до v%d)",
             g_holy.node_id, cur_ver, cur_ver + 1);
  } else {
    cairo_set_source_rgb(cr, 0.99, 0.87, 0.87);
    cairo_rectangle(cr, badge_x, r1_y, badge_w, 30.0);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.68, 0.12, 0.12);
    snprintf(badge_txt, sizeof(badge_txt),
             "[ ЗАНЯТ! ] Домен уже захвачен узлом %s — выберите другое имя домена!", owner_id);
  }
  SelectNodeFont(cr, FALSE, FALSE, TRUE, 12.5);
  cairo_move_to(cr, badge_x + 10.0, r1_y + 20.0);
  cairo_show_text(cr, badge_txt);

  /* Кнопки быстрых шаблонов */
  F64 tpl_y = top + 110.0;
  DrawBuilderBtn(cr, pad,         tpl_y, 165.0, 28.0, "Шаблон: Визитка",       st->hover_widget == BWID_TPL_CARD,   FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 173.0, tpl_y, 182.0, 28.0, "Шаблон: Энциклопедия",  st->hover_widget == BWID_TPL_WIKI,   FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 363.0, tpl_y, 192.0, 28.0, "Шаблон: Поисковик",     st->hover_widget == BWID_TPL_SEARCH, FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 563.0, tpl_y, 172.0, 28.0, "Шаблон: Блог / Борда",  st->hover_widget == BWID_TPL_BLOG,   FALSE, FALSE);

  /* Строка 2: Заголовок и Описание */
  F64 r2_y = top + 162.0;
  F64 half_w = (full_w - 16.0) * 0.5;
  DrawBuilderInput(cr, pad, r2_y, half_w, 30.0,
                   "2. Главный заголовок сайта (H1 / Title):",
                   st->title_buf, st->focused_field == BWID_FIELD_TITLE);
  DrawBuilderInput(cr, pad + half_w + 16.0, r2_y, half_w, 30.0,
                   "3. Подзаголовок / приветственная плашка узла:",
                   st->subtitle_buf, st->focused_field == BWID_FIELD_SUBTITLE);

  /* Строка 3: Текст нового блока + Адрес ссылки */
  F64 r3_y = top + 216.0;
  F64 blk_w = full_w - 260.0;
  DrawBuilderInput(cr, pad, r3_y, blk_w, 30.0,
                   "4. Содержимое нового блока (текст, заголовок, код или подпись ссылки):",
                   st->block_input, st->focused_field == BWID_FIELD_BLKTEXT);
  DrawBuilderInput(cr, pad + blk_w + 14.0, r3_y, 246.0, 30.0,
                   "Целевой URL (+P2P Ссылка):",
                   st->link_input, st->focused_field == BWID_FIELD_LINKURL);

  /* Кнопки добавления блоков */
  F64 b_y = top + 254.0;
  DrawBuilderBtn(cr, pad + 0.0,   b_y, 112.0, 28.0, "+ Заголовок", st->hover_widget == BWID_ADD_H2,    FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 118.0, b_y, 102.0, 28.0, "+ Абзац",     st->hover_widget == BWID_ADD_TEXT,  FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 226.0, b_y, 106.0, 28.0, "+ Цитата",    st->hover_widget == BWID_ADD_QUOTE, FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 338.0, b_y, 112.0, 28.0, "+ Код HolyC", st->hover_widget == BWID_ADD_CODE,  FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 456.0, b_y, 110.0, 28.0, "+ В список",  st->hover_widget == BWID_ADD_LI,    FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 572.0, b_y, 122.0, 28.0, "+ P2P Ссылка",st->hover_widget == BWID_ADD_LINK,  FALSE, FALSE);
  DrawBuilderBtn(cr, pad + 704.0, b_y, 120.0, 28.0, "- Удалить блок", st->hover_widget == BWID_DEL_LAST, FALSE, TRUE);
  DrawBuilderBtn(cr, pad + 830.0, b_y, 110.0, 28.0, "Очистить",    st->hover_widget == BWID_CLEAR_ALL, FALSE, TRUE);

  /* Область списка собранных блоков страницы */
  F64 list_y = top + 292.0;
  F64 pub_y = win_h - STATUSBAR_H - 46.0;
  F64 html_y = pub_y - 42.0;
  F64 list_h = html_y - list_y - 24.0;
  if (list_h < 54.0) list_h = 54.0;

  cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
  cairo_rectangle(cr, pad, list_y, full_w, list_h);
  cairo_fill(cr);
  cairo_set_source_rgb(cr, 0.70, 0.80, 0.74);
  cairo_set_line_width(cr, 1.2);
  cairo_rectangle(cr, pad + 0.5, list_y + 0.5, full_w - 1.0, list_h - 1.0);
  cairo_stroke(cr);

  cairo_save(cr);
  cairo_rectangle(cr, pad + 4.0, list_y + 4.0, full_w - 8.0, list_h - 8.0);
  cairo_clip(cr);

  U8 hdr_blocks[128];
  snprintf(hdr_blocks, sizeof(hdr_blocks), "Структура вашего сайта (%d блоков):", st->block_count);
  cairo_set_source_rgb(cr, 0.08, 0.30, 0.20);
  SelectNodeFont(cr, FALSE, FALSE, TRUE, 13.0);
  cairo_move_to(cr, pad + 12.0, list_y + 20.0);
  cairo_show_text(cr, hdr_blocks);

  F64 row_y = list_y + 28.0;
  for (I32 i = 0; i < st->block_count; i++) {
    if (row_y + 24.0 > list_y + list_h) break;
    BuilderBlock *b = &st->blocks[i];

    cairo_set_source_rgb(cr, 0.94, 0.97, 0.95);
    cairo_rectangle(cr, pad + 10.0, row_y, full_w - 20.0, 24.0);
    cairo_fill(cr);

    U8 *ktag = "TXT";
    if (b->kind == BBLK_H2)    ktag = "H2";
    if (b->kind == BBLK_QUOTE) ktag = "QUOTE";
    if (b->kind == BBLK_CODE)  ktag = "CODE";
    if (b->kind == BBLK_LI)    ktag = "LIST";
    if (b->kind == BBLK_LINK)  ktag = "LINK";

    cairo_set_source_rgb(cr, 0.08, 0.42, 0.28);
    cairo_rectangle(cr, pad + 12.0, row_y + 2.0, 58.0, 20.0);
    cairo_fill(cr);

    cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
    SelectNodeFont(cr, TRUE, FALSE, TRUE, 11.5);
    cairo_move_to(cr, pad + 17.0, row_y + 16.0);
    cairo_show_text(cr, ktag);

    U8 preview_line[520];
    if (b->kind == BBLK_LINK) {
      snprintf(preview_line, sizeof(preview_line), "%s  -->  [%s]", b->text, b->href);
    } else {
      SafeCopy(preview_line, b->text, sizeof(preview_line));
    }
    cairo_set_source_rgb(cr, 0.10, 0.16, 0.12);
    SelectNodeFont(cr, FALSE, FALSE, FALSE, 13.0);
    cairo_move_to(cr, pad + 80.0, row_y + 16.5);
    cairo_show_text(cr, preview_line);

    row_y += 27.0;
  }
  cairo_restore(cr);

  /* Строка 5: Импорт готового .html файла с диска напрямую на выбранный домен Холинета */
  F64 html_in_w = full_w - 332.0;
  DrawBuilderInput(cr, pad, html_y, html_in_w, 30.0,
                   "5. Или загрузите свой готовый .html файл с диска (таблицы, цвета, SVG/Base64 картинки):",
                   st->html_file_buf, st->focused_field == BWID_FIELD_HTMLFILE);
  DrawBuilderBtn(cr, pad + html_in_w + 12.0, html_y, 320.0, 30.0,
                 "ЗАГРУЗИТЬ .HTML ФАЙЛ В ХОЛИНЕТ!",
                 st->hover_widget == BWID_PUBLISH_HTML, TRUE, FALSE);

  /* Большая кнопка публикации из блоков Конструктора в P2P Холинет */
  U8 pub_label[220];
  snprintf(pub_label, sizeof(pub_label),
           "СОБРАТЬ ИЗ БЛОКОВ И ОПУБЛИКОВАТЬ ДОМЕН «%s» В P2P ХОЛИНЕТ!", st->domain_buf);
  DrawBuilderBtn(cr, pad, pub_y, full_w, 36.0, pub_label,
                 st->hover_widget == BWID_PUBLISH, TRUE, FALSE);
}
