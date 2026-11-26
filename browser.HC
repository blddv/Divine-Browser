/* ============================================================================
 * browser.HC — Главный модуль 2D-браузера DivineWeb v2.0 на HolyC
 * Возможности:
 *   - Многовкладочный интерфейс (Tabs: Ctrl+T, Ctrl+W, Ctrl+Tab, мышь)
 *   - Панель Избранного / Закладок (Bookmarks Bar + bookmarks.conf, Ctrl+D)
 *   - Реальная графика <img> (PNG, JPEG, SVG, GIF, WebP) и 2D-таблицы <table>
 *   - Поиск на странице с подсветкой (Ctrl+F) и Масштабирование (Zoom +/-)
 *   - Переключаемая P2P-сеть «ХОЛИНЕТ» (WAN PEX + LPD), Поиск сайтов,
 *     2D Конструктор сайтов с сохранением на диск и Мониторинг узлов
 * ============================================================================ */

#include "bindings.HH"
#include "url_http.HC"
#include "image_loader.HC"
#include "css_legacy.HC"
#include "js_engine.HC"
#include "html_dom.HC"
#include "layout_render.HC"
#include "holynet_p2p.HC"
#include "holynet_builder.HC"

#define HISTORY_MAX 48

class BrowserTab
{
  Bool             used;
  Bool             holynet_mode;
  U0              *js_page;
  Bool             js_disabled;
  Bool             js_holynet_enabled;
  F64              zoom;
  F64              scroll_y;
  HtmlDocument     doc;
  PageLayout       layout;
  SiteBuilderState builder;
  U8               current_url[1024];
  U8               addr_buf[1024];
  U8               status_msg[512];
  I32              last_status_code;
  U8              *history[HISTORY_MAX];
  I32              hist_count;
  I32              hist_pos;
};

class BrowserApp
{
  /* Окно X11 и поверхности Cairo */
  U0  *dpy;
  I32  screen;
  U64  win;
  U64  wm_delete;
  U64  cur_arrow;
  U64  cur_hand;
  U64  cur_ibeam;
  I32  active_cursor;

  U0  *xlib_surf;
  U0  *back_surf;
  U0  *back_cr;

  I32  win_w;
  I32  win_h;
  I32  theme_id;
  I32  p2p_port_pref;

  /* Вкладки браузера */
  BrowserTab    tabs[MAX_TABS];
  I32           tab_count;
  I32           active_tab;

  /* Состояние панелей интерфейса (вкладки, закладки, Ctrl+F) */
  ChromeUiState ui;

  Bool addr_focused;
  I32  hover_btn;
  I32  hover_link_id;
  Bool dragging_scroll;
};

BrowserTab *CurTab(BrowserApp *app)
{
  return &app->tabs[app->active_tab];
}

U0 EnsureHolynetNode(BrowserApp *app)
{
  if (!g_holy.initialized) {
    if (HolyStartNode(app->p2p_port_pref)) {
      HolySeedPresetSites(0);
    }
  }
}

/* --- Управление панелью Избранного / Закладок (bookmarks.conf) --- */
U0 SaveBookmarksConf(BrowserApp *app)
{
  I32 fd = open("bookmarks.conf", O_WRONLY | O_CREAT | O_TRUNC, 0x1A4);
  if (fd < 0) return;
  for (I32 i = 0; i < app->ui.bookmark_count; i++) {
    BookmarkEntry *bm = &app->ui.bookmarks[i];
    if (!bm->used) continue;
    U8 line[620];
    I64 n = snprintf(line, sizeof(line), "%s|%s\n", bm->title, bm->url);
    write(fd, line, n);
  }
  close(fd);
}

U0 AddBookmarkInternal(BrowserApp *app, U8 *title, U8 *url)
{
  if (app->ui.bookmark_count >= MAX_BOOKMARKS) return;
  for (I32 i = 0; i < app->ui.bookmark_count; i++) {
    if (app->ui.bookmarks[i].used && StrCmp(app->ui.bookmarks[i].url, url) == 0)
      return;
  }
  BookmarkEntry *bm = &app->ui.bookmarks[app->ui.bookmark_count++];
  bm->used = TRUE;
  SafeCopy(bm->title, title, sizeof(bm->title));
  SafeCopy(bm->url, url, sizeof(bm->url));
}

U0 InitBookmarks(BrowserApp *app)
{
  app->ui.bookmark_count = 0;
  I32 fd = open("bookmarks.conf", O_RDONLY, 0);
  if (fd >= 0) {
    U8 buf[4096];
    I64 n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n > 0) {
      buf[n] = 0;
      U8 *line = buf;
      while (*line) {
        U8 *nl = strchr(line, '\n');
        if (nl != NULL) *nl = 0;
        U8 *bar = strchr(line, '|');
        if (bar != NULL) {
          *bar = 0;
          if (line[0] != 0 && bar[1] != 0) {
            U8 *btitle = line;
            U8 migrated_url[512];
            if (StrCmp(btitle, "Чебурнет") == 0) btitle = "Холинет";
            if (StartsWithIgnoreCase(bar + 1, "cheb://")) {
              snprintf(migrated_url, sizeof(migrated_url), "holy://%s", bar + 8);
              AddBookmarkInternal(app, btitle, migrated_url);
            } else {
              AddBookmarkInternal(app, btitle, bar + 1);
            }
          }
        }
        if (nl == NULL) break;
        line = nl + 1;
      }
    }
  }

  if (app->ui.bookmark_count == 0) {
    AddBookmarkInternal(app, "Холинет",    "holy://home");
    AddBookmarkInternal(app, "Поиск P2P",   "holy://search");
    AddBookmarkInternal(app, "Конструктор", "holy://builder");
    AddBookmarkInternal(app, "Мониторинг",  "holy://monitor?sync=1");
    AddBookmarkInternal(app, "HolyC Lang",  "https://holyc-lang.com");
    AddBookmarkInternal(app, "Kernel.org",  "https://www.kernel.org");
    AddBookmarkInternal(app, "TempleOS",    "https://en.wikipedia.org/wiki/TempleOS");
  }
}

Bool IsUrlBookmarked(BrowserApp *app, U8 *url)
{
  if (url == NULL || url[0] == 0) return FALSE;
  for (I32 i = 0; i < app->ui.bookmark_count; i++) {
    if (app->ui.bookmarks[i].used && StrCmp(app->ui.bookmarks[i].url, url) == 0)
      return TRUE;
  }
  return FALSE;
}

U0 ToggleCurrentBookmark(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  if (t->current_url[0] == 0) return;

  for (I32 i = 0; i < app->ui.bookmark_count; i++) {
    if (app->ui.bookmarks[i].used && StrCmp(app->ui.bookmarks[i].url, t->current_url) == 0) {
      for (I32 j = i + 1; j < app->ui.bookmark_count; j++) {
        MemCpy(&app->ui.bookmarks[j - 1], &app->ui.bookmarks[j], sizeof(BookmarkEntry));
      }
      app->ui.bookmark_count--;
      SaveBookmarksConf(app);
      SafeCopy(t->status_msg, "Удалено из закладок (bookmarks.conf обновлён)", sizeof(t->status_msg));
      return;
    }
  }

  if (app->ui.bookmark_count >= MAX_BOOKMARKS) {
    SafeCopy(t->status_msg, "Панель закладок заполнена (макс. 10)", sizeof(t->status_msg));
    return;
  }

  U8 short_t[64];
  if (t->builder.active) SafeCopy(short_t, "Конструктор", sizeof(short_t));
  else SafeCopy(short_t, t->doc.title, sizeof(short_t));

  /* Обрезаем слишком длинный заголовок на границах UTF-8 до ~22 байт */
  I64 sl = StrLen(short_t);
  if (sl > 22) {
    I64 cut = 22;
    while (cut > 0 && ((short_t[cut] & 0xC0) == 0x80)) cut--;
    short_t[cut] = 0;
  }
  for (I64 k = 0; short_t[k]; k++) {
    if (short_t[k] == '|' || short_t[k] == '\n') short_t[k] = ' ';
  }

  AddBookmarkInternal(app, short_t, t->current_url);
  SaveBookmarksConf(app);
  SafeCopy(t->status_msg, "Сайт добавлен на панель закладок ★ (bookmarks.conf)", sizeof(t->status_msg));
}

/* Форматирование чистого текста для омнибокса (без навязчивого holy://) */
U0 FormatCleanAddressBar(U8 *final_url, U8 *out_addr, I64 cap)
{
  out_addr[0] = 0;
  if (final_url == NULL || final_url[0] == 0) return;

  if (StartsWithIgnoreCase(final_url, "holy://search")) {
    U8 *qm = strchr(final_url, '?');
    if (qm != NULL) {
      I32 dummy_sc = 0;
      HolyParseSearchParams(qm + 1, out_addr, cap, &dummy_sc);
    }
    return;
  }

  if (StartsWithIgnoreCase(final_url, "https://lite.duckduckgo.com/lite/")) {
    U8 *qm = strchr(final_url, '?');
    if (qm != NULL) {
      I32 dummy_sc = 0;
      HolyParseSearchParams(qm + 1, out_addr, cap, &dummy_sc);
    }
    return;
  }

  if (StrCmp(final_url, "holy://home") == 0 || StrCmp(final_url, "temple://home") == 0) {
    out_addr[0] = 0;
    return;
  }

  if (StartsWithIgnoreCase(final_url, "holy://")) {
    SafeCopy(out_addr, final_url + 7, cap);
    return;
  }

  SafeCopy(out_addr, final_url, cap);
}

U0 ClampScroll(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  F64 view_h = app->win_h - TOOLBAR_H - STATUSBAR_H;
  if (view_h < 20.0) view_h = 20.0;
  F64 max_s = t->layout.content_height - view_h;
  if (max_s < 0.0) max_s = 0.0;
  if (t->scroll_y > max_s) t->scroll_y = max_s;
  if (t->scroll_y < 0.0) t->scroll_y = 0.0;
}

/* --- Поиск на открытой странице (Ctrl+F) и автоскролл к совпадению --- */
U0 RecomputeFindMatches(BrowserApp *app, Bool jump_to_active)
{
  BrowserTab *t = CurTab(app);
  Utf8LowerFold(app->ui.find_query, app->ui.find_query_low, sizeof(app->ui.find_query_low));
  app->ui.find_total = 0;
  app->ui.find_active_item = -1;

  if (!app->ui.find_active || app->ui.find_query_low[0] == 0 || t->builder.active) {
    return;
  }

  for (I64 i = 0; i < t->layout.count; i++) {
    if (ItemMatchesFind(&t->layout.items[i], &app->ui)) {
      app->ui.find_total++;
    }
  }

  if (app->ui.find_total <= 0) {
    app->ui.find_current = 0;
    return;
  }

  if (app->ui.find_current < 0) app->ui.find_current = app->ui.find_total - 1;
  if (app->ui.find_current >= app->ui.find_total) app->ui.find_current = 0;

  I32 seen = 0;
  for (I64 i = 0; i < t->layout.count; i++) {
    if (ItemMatchesFind(&t->layout.items[i], &app->ui)) {
      if (seen == app->ui.find_current) {
        app->ui.find_active_item = i;
        if (jump_to_active) {
          F64 view_h = app->win_h - TOOLBAR_H - STATUSBAR_H;
          t->scroll_y = t->layout.items[i].y - view_h * 0.35;
          ClampScroll(app);
        }
        break;
      }
      seen++;
    }
  }
}

U0 SyncChromeState(BrowserApp *app)
{
  app->ui.tab_count = app->tab_count;
  app->ui.active_tab = app->active_tab;
  for (I32 i = 0; i < app->tab_count; i++) {
    BrowserTab *tb = &app->tabs[i];
    app->ui.tabs[i].holy_mode = tb->holynet_mode;
    if (tb->builder.active) {
      SafeCopy(app->ui.tabs[i].title, "Конструктор P2P", sizeof(app->ui.tabs[i].title));
    } else if (tb->doc.title[0] != 0) {
      SafeCopy(app->ui.tabs[i].title, tb->doc.title, sizeof(app->ui.tabs[i].title));
    } else {
      SafeCopy(app->ui.tabs[i].title, "Новая вкладка", sizeof(app->ui.tabs[i].title));
    }
  }
  BrowserTab *cur = CurTab(app);
  app->ui.zoom = cur->zoom;
  app->ui.current_is_bookmarked = IsUrlBookmarked(app, cur->current_url);
}

U0 PushTabHistory(BrowserTab *t, U8 *url)
{
  for (I32 i = t->hist_pos + 1; i < t->hist_count; i++) {
    if (t->history[i] != NULL) {
      Free(t->history[i]);
      t->history[i] = NULL;
    }
  }
  t->hist_count = t->hist_pos + 1;

  if (t->hist_pos >= 0 && t->history[t->hist_pos] != NULL &&
      StrCmp(t->history[t->hist_pos], url) == 0) {
    return;
  }

  if (t->hist_count >= HISTORY_MAX) {
    Free(t->history[0]);
    for (I32 i = 1; i < HISTORY_MAX; i++)
      t->history[i - 1] = t->history[i];
    t->hist_count = HISTORY_MAX - 1;
  }

  t->history[t->hist_count] = StrNew(url);
  t->hist_pos = t->hist_count;
  t->hist_count++;
}

U0 UpdateWindowTitle(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  if (app->dpy != NULL && app->win != 0) {
    U8 wtitle[340];
    if (t->builder.active) {
      snprintf(wtitle, sizeof(wtitle), "Конструктор сайтов Холинета [%s] — DivineWeb", g_holy.node_id);
    } else if (t->holynet_mode) {
      snprintf(wtitle, sizeof(wtitle), "[В Холинете] %s — DivineWeb v2.0", t->doc.title);
    } else {
      snprintf(wtitle, sizeof(wtitle), "[В Интернете] %s — DivineWeb v2.0 (HolyC)", t->doc.title);
    }
    XStoreName(app->dpy, app->win, wtitle);
  }
}

/* «Божий Оракул Дэвиса» (клавиша F7 из TempleOS — энтропия микросекунд таймера!) */
U0 DavisInvokeOracle(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  F64 ms = HolyNowMs();
  I64 entropy = ((ms * 1000.0)(I64)) ^ (getpid() * 7919);
  if (entropy < 0) entropy = -entropy;

  U8 *words[16];
  words[0]  = "ПРОСТОТА — ВЫСШАЯ МИЛОСТЬ КОМПИЛЯТОРА.";
  words[1]  = "16 ЦВЕТОВ И 640x480 — ЗАВЕТ ХРАМА КОДА.";
  words[2]  = "ИДИОТ ВОСХИЩАЕТСЯ СЛОЖНОСТЬЮ, ГЕНИЙ — ПРОСТОТОЙ.";
  words[3]  = "СВЕТ ИСТИНЫ В КОЛЬЦЕ НУЛЕВОГО ПРИВИЛЕГИЯ RING-0.";
  words[4]  = "ЧИСТЫЙ HOLYC СИЯЕТ БЕЗ ЧУЖИХ ПРОСЛОЕК.";
  words[5]  = "КАЖДЫЙ ПИКСЕЛЬ ЧЕСТЕН, КОГДА СГЛАЖИВАНИЕ ОТКЛЮЧЕНО.";
  words[6]  = "ХРАМ ПОСТРОЕН В МАШИННЫХ КОДАХ X86_64.";
  words[7]  = "МОНОШИРИННАЯ БУКВА ТВЕРДА, КАК КАМЕННАЯ СКРИЖАЛЬ.";
  words[8]  = "НЕ УМНОЖАЙ ПАЛИТРУ СВЕРХ ШЕСТНАДЦАТИ ЦВЕТОВ.";
  words[9]  = "УЗЕЛ РАВЕН УЗЛУ — P2P НЕ ЗНАЕТ ХОЗЯЕВ.";
  words[10] = "ПРЯМОЙ ДОСТУП К БУФЕРУ КАДРА ЕСТЬ РАДОСТЬ ДУХА.";
  words[11] = "КОД ДОЛЖЕН БЫТЬ ЯСЕН, КАК ЧЕРТЁЖ КОРАБЛЯ.";
  words[12] = "ВЗГЛЯНИ В ИСХОДНИК — ТАМ НЕТ СКРЫТЫХ ТАЙН.";
  words[13] = "СЛОН БОЖИЙ ШАГАЕТ ПО 16-ЦВЕТНОМУ ПОЛОТНУ.";
  words[14] = "ОДИН ШРИФТ, ОДНО ЯДРО, ЧИСТАЯ МЫСЛЬ.";
  words[15] = "ОДОБРЕНИЕ ДЭВИСА ПОЛУЧЕНО: ЦВЕТОВ РОВНО 16!";

  I32 pick = entropy % 16;
  snprintf(t->status_msg, sizeof(t->status_msg),
           "[Оракул Дэвиса F7]: %s", words[pick]);
}

U0 RepaintWindow(BrowserApp *app)
{
  SyncChromeState(app);
  BrowserTab *t = CurTab(app);
  U8 safety_status[768];
  U8 *shown_status = t->status_msg;
  if (t->holynet_mode) {
    U8 *js_state = "ВЫКЛ";
    if (t->js_holynet_enabled) js_state = "ВКЛ";
    snprintf(safety_status, sizeof(safety_status), "[TOR + TLS | САЙТ НЕ ПРОВЕРЕН | JS %s] %s", js_state, t->status_msg);
    shown_status = safety_status;
  }

  RenderBrowserFrame(
    app->back_cr,
    &t->doc,
    &t->layout,
    app->win_w,
    app->win_h,
    t->scroll_y,
    t->addr_buf,
    app->addr_focused,
    app->hover_btn,
    app->hover_link_id,
    t->hist_pos > 0,
    t->hist_pos + 1 < t->hist_count,
    app->theme_id,
    t->holynet_mode,
    shown_status,
    &app->ui
  );

  if (t->builder.active) {
    RenderBuilderCanvas(app->back_cr, &t->builder, app->win_w, app->win_h);
  }

  /* В теме «Одобрение Дэвиса» принудительно сводим ВЕСЬ буфер кадра к 16 цветам VGA! */
  if (app->theme_id == THEME_DAVIS) {
    EnforceDavis16Surface(app->back_surf);
  }

  cairo_surface_flush(app->back_surf);

  if (app->xlib_surf != NULL && app->dpy != NULL) {
    U0 *wcr = cairo_create(app->xlib_surf);
    cairo_set_source_surface(wcr, app->back_surf, 0.0, 0.0);
    cairo_paint(wcr);
    cairo_destroy(wcr);
    cairo_surface_flush(app->xlib_surf);
    XFlush(app->dpy);
  }
}

U0 RebuildCurrentTabLayout(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  if (!t->builder.active) {
    SetCairoDavisMode(app->back_cr, app->theme_id == THEME_DAVIS);
    BuildPageLayoutZoom(app->back_cr, &t->doc, app->win_w, t->zoom, &t->layout);
    ClampScroll(app);
    RecomputeFindMatches(app, FALSE);
  }
}

I32 g_js_redirect_depth = 0;

U0 ParseTabResponse(BrowserTab *t, HttpResponse *resp)
{
  if (t->js_page != NULL) { QjsPageDestroy(t->js_page); t->js_page = NULL; }
  U8 *render_html = NULL;
  I64 render_len = 0;
  if (((!t->holynet_mode && !t->js_disabled) || (t->holynet_mode && t->js_holynet_enabled)) && resp->body != NULL && resp->body_len > 0 && resp->body_len < 2 * 1024 * 1024 && JsPageNeeded(resp->body)) {
    QjsSetFetchCallback(&JsFetchResource);
    t->js_page = QjsPageCreate();
    if (t->js_page != NULL)
      render_html = QjsPageLoadHtml(t->js_page, resp->body, resp->body_len, resp->final_url, &render_len);
  }
  DocFree(&t->doc);
  if (render_html != NULL && render_len > 0) ParseHtmlDocument(render_html, render_len, resp->final_url, &t->doc);
  else ParseHtmlDocument(resp->body, resp->body_len, resp->final_url, &t->doc);
  if (render_html != NULL) QjsFreeStr(render_html);
}

U0 NavigateTo(BrowserApp *app, U8 *target_url, Bool record_history)
{
  BrowserTab *t = CurTab(app);

  if (StartsWithIgnoreCase(target_url, "holy://") ||
      StartsWithIgnoreCase(target_url, "cheb://")) {
    if (!t->holynet_mode) {
      t->holynet_mode = TRUE;
      if (app->theme_id != THEME_DAVIS) app->theme_id = THEME_HOLYNET;
    }
  } else if (StartsWithIgnoreCase(target_url, "http://") ||
             StartsWithIgnoreCase(target_url, "https://") ||
             StartsWithIgnoreCase(target_url, "temple://")) {
    if (StartsWithIgnoreCase(target_url, "temple://") && t->holynet_mode) {
      t->holynet_mode = FALSE;
      if (app->theme_id == THEME_HOLYNET) app->theme_id = THEME_TEMPLE;
    }
  }

  if (t->holynet_mode) {
    EnsureHolynetNode(app);
    U8 claim_dom[128];
    claim_dom[0] = 0;

    HttpResponse cresp;
    I32 mode_rc = HolyFetchUrl(target_url, &cresp, claim_dom, sizeof(claim_dom));
    t->last_status_code = cresp.status_code;

    SafeCopy(t->current_url, cresp.final_url, sizeof(t->current_url));
    FormatCleanAddressBar(cresp.final_url, t->addr_buf, sizeof(t->addr_buf));

    if (record_history) PushTabHistory(t, cresp.final_url);

    if (mode_rc == 2) {
      t->builder.active = TRUE;
      if (claim_dom[0] != 0) {
        SafeCopy(t->builder.domain_buf, claim_dom, sizeof(t->builder.domain_buf));
        snprintf(t->builder.feedback_msg, sizeof(t->builder.feedback_msg),
                 "Создание публикации '%s' на узле %s. Владелец не проверяется!", claim_dom, g_holy.node_id);
      }
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ХОЛИНЕТ | Узел %s | профиль %d] %s",
               g_holy.node_id, g_holy.profile_number, t->builder.feedback_msg);
      HttpResponseFree(&cresp);
      SyncChromeState(app);
      UpdateWindowTitle(app);
      return;
    }

    t->builder.active = FALSE;
    ParseTabResponse(t, &cresp);
    LoadDocumentImages(&t->doc, TRUE);
    SetCairoDavisMode(app->back_cr, app->theme_id == THEME_DAVIS);
    BuildPageLayoutZoom(app->back_cr, &t->doc, app->win_w, t->zoom, &t->layout);
    t->scroll_y = 0.0;
    app->hover_link_id = -1;
    RecomputeFindMatches(app, FALSE);

    if (app->theme_id == THEME_DAVIS) {
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ОДОБРЕНИЕ ДЭВИСА: 16 ЦВЕТОВ VGA | БЕЗ СГЛАЖИВАНИЯ | F7: Оракул] Холинет %s (%d сайтов)",
               g_holy.node_id, g_holy.site_count);
    } else if (cresp.status_code == 200) {
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ХОЛИНЕТ | %s | профиль %d] %d сайтов в текущем каталоге",
               g_holy.node_id, g_holy.profile_number, g_holy.site_count);
    } else {
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ХОЛИНЕТ | %s | профиль %d] ДОМЕН НЕ НАЙДЕН — статус не подтверждён.",
               g_holy.node_id, g_holy.profile_number);
    }

    HttpResponseFree(&cresp);
    SyncChromeState(app);
    UpdateWindowTitle(app);
    U8 js_redirect[1024];
    if (t->js_page != NULL && g_js_redirect_depth < 5 &&
        QjsPagePopRedirect(t->js_page, js_redirect, sizeof(js_redirect)) && !t->holynet_mode &&
        (StartsWithIgnoreCase(js_redirect, "http://") || StartsWithIgnoreCase(js_redirect, "https://") ||
         StartsWithIgnoreCase(js_redirect, "holy://"))) {
      g_js_redirect_depth++;
      NavigateTo(app, js_redirect, TRUE);
      g_js_redirect_depth--;
    }
    return;
  }

  /* Классический режим глобального Интернета (WWW) — быстрая двухфазная отрисовка */
  t->builder.active = FALSE;
  F64 nav_t0 = HolyNowMs();
  snprintf(t->status_msg, sizeof(t->status_msg), "Загрузка из Интернета: %s ...", target_url);
  if (app->dpy != NULL) {
    RepaintWindow(app);
  }

  HttpResponse resp;
  Bool ok = FetchUrl(target_url, &resp);

  SafeCopy(t->current_url, resp.final_url, sizeof(t->current_url));
  FormatCleanAddressBar(resp.final_url, t->addr_buf, sizeof(t->addr_buf));

  ParseTabResponse(t, &resp);
  t->scroll_y = 0.0;
  app->hover_link_id = -1;

  Bool has_remote_imgs = FALSE;
  LoadLocalDocumentImagesOnly(&t->doc, &has_remote_imgs);

  /* В живом окне X11 мгновенно показываем текст и таблицы страницы ДО скачивания внешних картинок! */
  if (app->dpy != NULL && has_remote_imgs) {
    SetCairoDavisMode(app->back_cr, app->theme_id == THEME_DAVIS);
    BuildPageLayoutZoom(app->back_cr, &t->doc, app->win_w, t->zoom, &t->layout);
    RecomputeFindMatches(app, FALSE);
    snprintf(t->status_msg, sizeof(t->status_msg),
             "[ИНТЕРНЕТ WWW] Текст открыт — параллельная догрузка иллюстраций...");
    UpdateWindowTitle(app);
    RepaintWindow(app);
  }

  if (has_remote_imgs) {
    LoadDocumentImages(&t->doc, FALSE);
  }

  SetCairoDavisMode(app->back_cr, app->theme_id == THEME_DAVIS);
  BuildPageLayoutZoom(app->back_cr, &t->doc, app->win_w, t->zoom, &t->layout);
  RecomputeFindMatches(app, FALSE);

  if (record_history) PushTabHistory(t, resp.final_url);

  I64 elapsed_ms = (HolyNowMs() - nav_t0)(I64);
  if (elapsed_ms < 1) elapsed_ms = 1;

  if (ok) {
    I32 loaded_imgs = 0;
    for (I32 im = 0; im < t->doc.image_count; im++) {
      if (t->doc.images[im].loaded) loaded_imgs++;
    }
    if (app->theme_id == THEME_DAVIS) {
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ОДОБРЕНИЕ ДЭВИСА: 16 ЦВЕТОВ VGA | МОНОШРИФТ | F7: Оракул] HTTP %d за %ld мс | %d ссылок | %d спрайтов",
               resp.status_code, elapsed_ms, t->doc.link_count, loaded_imgs);
    } else {
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ИНТЕРНЕТ WWW] HTTP %d за %ld мс | %d Б | %d ссылок | %d картинок | Ctrl+T: вкладка",
               resp.status_code, elapsed_ms, resp.body_len, t->doc.link_count, loaded_imgs);
    }
  } else {
    snprintf(t->status_msg, sizeof(t->status_msg),
             "[ИНТЕРНЕТ WWW] Ошибка (%d): %s", resp.status_code, resp.error);
  }

  HttpResponseFree(&resp);
  SyncChromeState(app);
  UpdateWindowTitle(app);
    U8 js_redirect[1024];
    if (t->js_page != NULL && g_js_redirect_depth < 5 &&
        QjsPagePopRedirect(t->js_page, js_redirect, sizeof(js_redirect)) && !t->holynet_mode &&
        (StartsWithIgnoreCase(js_redirect, "http://") || StartsWithIgnoreCase(js_redirect, "https://") ||
         StartsWithIgnoreCase(js_redirect, "holy://"))) {
      g_js_redirect_depth++;
      NavigateTo(app, js_redirect, TRUE);
      g_js_redirect_depth--;
    }
}

/* Re-render the live DOM after a JS event without resetting scroll. */
U0 RefreshJsPage(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  if (t->js_page == NULL) return;
  U8 redirect[1024];
  if (QjsPagePopRedirect(t->js_page, redirect, sizeof(redirect)) && !t->holynet_mode &&
      (StartsWithIgnoreCase(redirect, "http://") || StartsWithIgnoreCase(redirect, "https://") ||
       StartsWithIgnoreCase(redirect, "holy://"))) {
    NavigateTo(app, redirect, TRUE);
    return;
  }
  I64 len = 0;
  U8 *html = QjsPageSerializeHtml(t->js_page, &len);
  if (html != NULL && len > 0) {
    DocFree(&t->doc);
    ParseHtmlDocument(html, len, t->current_url, &t->doc);
    LoadDocumentImages(&t->doc, t->holynet_mode);
    RebuildCurrentTabLayout(app);
  }
  if (html != NULL) QjsFreeStr(html);
}

U0 RunJsLink(BrowserApp *app, U8 *url)
{
  BrowserTab *t = CurTab(app);
  if (t->js_page == NULL) return;
  I32 changed;
  if (StartsWithIgnoreCase(url, "javascript:__qjs_click("))
    changed = QjsPageClickId(t->js_page, Atoi(url + 23));
  else changed = QjsPageEvalUrl(t->js_page, url);
  if (changed) RefreshJsPage(app);
}

/* Поисковый запрос в текущей активной сети вкладки */
U0 ExecuteSearchQuery(BrowserApp *app, U8 *raw_query, U8 *scope_opt, Bool record_history)
{
  BrowserTab *t = CurTab(app);
  U8 *p = raw_query;
  if (p == NULL) p = "";
  while (*p && IsSpace(*p)) p++;

  U8 clean_q[256];
  SafeCopy(clean_q, p, sizeof(clean_q));
  I64 ql = StrLen(clean_q);
  while (ql > 0 && IsSpace(clean_q[ql - 1])) clean_q[--ql] = 0;

  U8 enc_q[768];
  UrlEncodeUtf8(clean_q, enc_q, sizeof(enc_q));

  U8 search_url[1024];
  if (t->holynet_mode) {
    if (clean_q[0] == 0) {
      SafeCopy(search_url, "holy://search", sizeof(search_url));
    } else if (scope_opt != NULL && scope_opt[0] != 0) {
      snprintf(search_url, sizeof(search_url), "holy://search?q=%s&scope=%s", enc_q, scope_opt);
    } else {
      snprintf(search_url, sizeof(search_url), "holy://search?q=%s", enc_q);
    }
  } else {
    if (clean_q[0] == 0) {
      SafeCopy(search_url, "https://lite.duckduckgo.com/lite/", sizeof(search_url));
    } else {
      snprintf(search_url, sizeof(search_url), "https://lite.duckduckgo.com/lite/?q=%s", enc_q);
    }
  }

  NavigateTo(app, search_url, record_history);
}

U0 SubmitOmniboxInput(BrowserApp *app, U8 *raw_input, Bool force_search)
{
  BrowserTab *t = CurTab(app);
  if (force_search) {
    ExecuteSearchQuery(app, raw_input, NULL, TRUE);
    return;
  }

  U8 *p = raw_input;
  while (*p && IsSpace(*p)) p++;
  if (*p == 0) {
    if (t->holynet_mode) NavigateTo(app, "holy://home", TRUE);
    else NavigateTo(app, "temple://home", TRUE);
    return;
  }

  U8 *upload_arg = NULL;
  if (StrCaseEqLen(p, "upload ", 7)) upload_arg = p + 7;
  else if (StrCaseEqLen(p, "publish ", 8)) upload_arg = p + 8;
  else if (StrNCmp(p, "загрузить ", 19) == 0 || StrNCmp(p, "ЗАГРУЗИТЬ ", 19) == 0) upload_arg = p + 19;

  if (upload_arg != NULL) {
    while (*upload_arg && IsSpace(*upload_arg)) upload_arg++;
    U8 *sp = strchr(upload_arg, ' ');
    if (sp != NULL) {
      U8 udom[128];
      SafeCopyLen(udom, upload_arg, sp - upload_arg, sizeof(udom));
      U8 *upath = sp + 1;
      while (*upath && IsSpace(*upath)) upath++;
      if (udom[0] != 0 && *upath != 0) {
        if (!t->holynet_mode) {
          t->holynet_mode = TRUE;
          app->theme_id = THEME_HOLYNET;
        }
        EnsureHolynetNode(app);
        U8 uerr[256];
        if (HolyPublishHtmlFile(udom, upath, uerr, sizeof(uerr))) {
          NavigateTo(app, udom, TRUE);
          snprintf(t->status_msg, sizeof(t->status_msg),
                   "[HTML ОПУБЛИКОВАН В ХОЛИНЕТ!] '%s' -> домен '%s' (сохранён в holynet_sites/)",
                   upath, udom);
        } else {
          snprintf(t->status_msg, sizeof(t->status_msg), "[ОШИБКА ЗАГРУЗКИ HTML] %s", uerr);
        }
        return;
      }
    }
  }

  U8 *peer_arg = NULL;
  if (StrCaseEqLen(p, "peer ", 5)) peer_arg = p + 5;
  else if (StrNCmp(p, "пир ", 7) == 0 || StrNCmp(p, "ПИР ", 7) == 0) peer_arg = p + 7;

  if (peer_arg != NULL) {
    SafeCopy(t->status_msg, "Прямые пиры отключены: Холинет использует Tor + TLS; провайдер видит Tor.", sizeof(t->status_msg));
    return;
  }

  U8 detected_query[256];
  if (IsLikelySearchInput(p, detected_query, sizeof(detected_query))) {
    ExecuteSearchQuery(app, detected_query, NULL, TRUE);
  } else {
    NavigateTo(app, p, TRUE);
  }
}

/* Переключение тумблера [■ В Холинете] <-> [■ В Интернете] на текущей вкладке */
U0 ToggleHolynetMode(BrowserApp *app)
{
  BrowserTab *t = CurTab(app);
  Bool was_search = FALSE;
  U8   saved_query[256];
  saved_query[0] = 0;

  if (StartsWithIgnoreCase(t->current_url, "holy://search") ||
      StartsWithIgnoreCase(t->current_url, "https://lite.duckduckgo.com/lite/")) {
    was_search = TRUE;
    SafeCopy(saved_query, t->addr_buf, sizeof(saved_query));
  }

  U8 saved_input[512];
  SafeCopy(saved_input, t->addr_buf, sizeof(saved_input));
  Bool had_typed = (app->addr_focused && saved_input[0] != 0);

  t->holynet_mode = !t->holynet_mode;
  if (t->holynet_mode) {
    if (app->theme_id != THEME_DAVIS) app->theme_id = THEME_HOLYNET;
    EnsureHolynetNode(app);
  } else {
    t->builder.active = FALSE;
    if (app->theme_id == THEME_HOLYNET) app->theme_id = THEME_TEMPLE;
  }

  if (had_typed) {
    app->addr_focused = FALSE;
    SubmitOmniboxInput(app, saved_input, FALSE);
    return;
  }
  if (was_search && saved_query[0] != 0) {
    ExecuteSearchQuery(app, saved_query, NULL, TRUE);
    return;
  }
  if (!t->builder.active && saved_input[0] != 0 &&
      !StartsWithIgnoreCase(t->current_url, "temple://") &&
      !StartsWithIgnoreCase(t->current_url, "file://")) {
    ParsedUrl pu;
    UrlParse(t->current_url, &pu);
    if (pu.host[0] != 0 && !HolyIsSystemDomain(pu.host)) {
      NavigateTo(app, pu.host, TRUE);
      return;
    }
  }

  if (t->holynet_mode) NavigateTo(app, "holy://home", TRUE);
  else NavigateTo(app, "temple://home", TRUE);
}

/* --- Управление вкладками браузера (открытие, переключение, закрытие) --- */
U0 InitSingleTabStruct(BrowserTab *tb, Bool cheb)
{
  MemSet(tb, 0, sizeof(BrowserTab));
  tb->used = TRUE;
  tb->holynet_mode = cheb;
  tb->zoom = 1.0;
  tb->hist_pos = -1;
  BuilderInit(&tb->builder);
}

U0 FreeSingleTabStruct(BrowserTab *tb)
{
  if (tb->js_page != NULL) { QjsPageDestroy(tb->js_page); tb->js_page = NULL; }
  DocFree(&tb->doc);
  LayoutFree(&tb->layout);
  for (I32 i = 0; i < tb->hist_count; i++) {
    if (tb->history[i] != NULL) Free(tb->history[i]);
    tb->history[i] = NULL;
  }
  tb->used = FALSE;
}

U0 SwitchToTab(BrowserApp *app, I32 idx)
{
  if (idx < 0 || idx >= app->tab_count) return;
  app->active_tab = idx;
  app->addr_focused = FALSE;
  app->hover_link_id = -1;
  BrowserTab *t = CurTab(app);
  if (app->theme_id != THEME_DAVIS) {
    if (t->holynet_mode) app->theme_id = THEME_HOLYNET;
    else if (app->theme_id == THEME_HOLYNET) app->theme_id = THEME_TEMPLE;
  }
  RebuildCurrentTabLayout(app);
  SyncChromeState(app);
  UpdateWindowTitle(app);
}

U0 OpenNewTab(BrowserApp *app, U8 *start_input, Bool cheb)
{
  if (app->tab_count >= MAX_TABS) return;
  I32 tid = app->tab_count++;
  InitSingleTabStruct(&app->tabs[tid], cheb);
  app->active_tab = tid;
  if (cheb && app->theme_id != THEME_DAVIS) app->theme_id = THEME_HOLYNET;
  if (start_input != NULL && start_input[0] != 0) {
    SubmitOmniboxInput(app, start_input, FALSE);
  } else {
    if (cheb) NavigateTo(app, "holy://home", TRUE);
    else NavigateTo(app, "temple://home", TRUE);
  }
}

U0 CloseTabAt(BrowserApp *app, I32 idx)
{
  if (app->tab_count <= 1 || idx < 0 || idx >= app->tab_count) return;
  FreeSingleTabStruct(&app->tabs[idx]);
  for (I32 j = idx + 1; j < app->tab_count; j++) {
    MemCpy(&app->tabs[j - 1], &app->tabs[j], sizeof(BrowserTab));
  }
  MemSet(&app->tabs[app->tab_count - 1], 0, sizeof(BrowserTab));
  app->tab_count--;
  if (app->active_tab >= app->tab_count) app->active_tab = app->tab_count - 1;
  SwitchToTab(app, app->active_tab);
}

U0 AdjustZoom(BrowserApp *app, F64 delta)
{
  BrowserTab *t = CurTab(app);
  if (delta == 0.0) t->zoom = 1.0;
  else t->zoom += delta;
  if (t->zoom < 0.70) t->zoom = 0.70;
  if (t->zoom > 1.80) t->zoom = 1.80;
  RebuildCurrentTabLayout(app);
  SyncChromeState(app);
}

U0 RecreateBackbuffer(BrowserApp *app, I32 new_w, I32 new_h)
{
  if (new_w < 540) new_w = 540;
  if (new_h < 380) new_h = 380;
  app->win_w = new_w;
  app->win_h = new_h;

  if (app->back_cr != NULL) cairo_destroy(app->back_cr);
  if (app->back_surf != NULL) cairo_surface_destroy(app->back_surf);

  app->back_surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, app->win_w, app->win_h);
  app->back_cr = cairo_create(app->back_surf);

  if (app->xlib_surf != NULL) {
    cairo_xlib_surface_set_size(app->xlib_surf, app->win_w, app->win_h);
  }
}

U0 UpdateCursorShape(BrowserApp *app, I32 shape)
{
  if (app->dpy == NULL || app->active_cursor == shape) return;
  app->active_cursor = shape;
  if (shape == 1) XDefineCursor(app->dpy, app->win, app->cur_hand);
  else if (shape == 2) XDefineCursor(app->dpy, app->win, app->cur_ibeam);
  else XDefineCursor(app->dpy, app->win, app->cur_arrow);
}

U0 ScrollToMouseY(BrowserApp *app, I32 my)
{
  BrowserTab *t = CurTab(app);
  F64 view_h = app->win_h - TOOLBAR_H - STATUSBAR_H;
  if (view_h <= 20.0) return;
  F64 ratio = (my - TOOLBAR_H) / view_h;
  if (ratio < 0.0) ratio = 0.0;
  if (ratio > 1.0) ratio = 1.0;
  F64 max_s = t->layout.content_height - view_h;
  if (max_s < 0.0) max_s = 0.0;
  t->scroll_y = ratio * max_s;
  ClampScroll(app);
}

U0 EraseLastUtf8Char(U8 *s)
{
  I64 len = StrLen(s);
  if (len <= 0) return;
  len--;
  while (len > 0 && ((s[len] & 0xC0) == 0x80)) len--;
  s[len] = 0;
}

U8 *GetBuilderActiveBuffer(SiteBuilderState *st, I64 *out_cap)
{
  if (st->focused_field == BWID_FIELD_DOMAIN)   { *out_cap = sizeof(st->domain_buf);   return st->domain_buf; }
  if (st->focused_field == BWID_FIELD_TITLE)    { *out_cap = sizeof(st->title_buf);    return st->title_buf; }
  if (st->focused_field == BWID_FIELD_SUBTITLE) { *out_cap = sizeof(st->subtitle_buf); return st->subtitle_buf; }
  if (st->focused_field == BWID_FIELD_BLKTEXT)  { *out_cap = sizeof(st->block_input);  return st->block_input; }
  if (st->focused_field == BWID_FIELD_LINKURL)  { *out_cap = sizeof(st->link_input);   return st->link_input; }
  if (st->focused_field == BWID_FIELD_HTMLFILE) { *out_cap = sizeof(st->html_file_buf); return st->html_file_buf; }
  *out_cap = 0;
  return NULL;
}

U0 HandleBuilderWidgetClick(BrowserApp *app, I32 wid)
{
  BrowserTab *t = CurTab(app);
  SiteBuilderState *st = &t->builder;
  if (wid >= BWID_FIELD_DOMAIN && wid <= BWID_FIELD_HTMLFILE) {
    st->focused_field = wid;
    return;
  }

  if (wid == BWID_EXIT_HOME) {
    NavigateTo(app, "holy://home", TRUE);
    return;
  }

  if (wid >= BWID_TPL_CARD && wid <= BWID_TPL_BLOG) {
    BuilderApplyTemplate(st, wid);
    snprintf(t->status_msg, sizeof(t->status_msg), "[Конструктор] %s", st->feedback_msg);
    return;
  }

  if (wid == BWID_ADD_H2 && st->block_input[0] != 0) {
    BuilderPushBlock(st, BBLK_H2, st->block_input, "");
  } else if (wid == BWID_ADD_TEXT && st->block_input[0] != 0) {
    BuilderPushBlock(st, BBLK_TEXT, st->block_input, "");
  } else if (wid == BWID_ADD_QUOTE && st->block_input[0] != 0) {
    BuilderPushBlock(st, BBLK_QUOTE, st->block_input, "");
  } else if (wid == BWID_ADD_CODE && st->block_input[0] != 0) {
    BuilderPushBlock(st, BBLK_CODE, st->block_input, "");
  } else if (wid == BWID_ADD_LI && st->block_input[0] != 0) {
    BuilderPushBlock(st, BBLK_LI, st->block_input, "");
  } else if (wid == BWID_ADD_LINK && st->block_input[0] != 0) {
    BuilderPushBlock(st, BBLK_LINK, st->block_input, st->link_input);
  } else if (wid == BWID_DEL_LAST) {
    if (st->block_count > 0) st->block_count--;
  } else if (wid == BWID_CLEAR_ALL) {
    st->block_count = 0;
  } else if (wid == BWID_PUBLISH_HTML) {
    U8 err[256];
    if (HolyPublishHtmlFile(st->domain_buf, st->html_file_buf, err, sizeof(err))) {
      NavigateTo(app, st->domain_buf, TRUE);
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[HTML ЗАГРУЖЕН В P2P + СОХРАНЁН!] Файл '%s' опубликован на домене %s!",
               st->html_file_buf, st->domain_buf);
    } else {
      SafeCopy(st->feedback_msg, err, sizeof(st->feedback_msg));
      st->feedback_error = TRUE;
      snprintf(t->status_msg, sizeof(t->status_msg), "[ОШИБКА ЗАГРУЗКИ HTML] %s", err);
    }
  } else if (wid == BWID_PUBLISH) {
    U8 *compiled = BuilderCompileHtml(st);
    U8 err[256];
    if (HolyPublishSite(st->domain_buf, st->title_buf, compiled, err, sizeof(err))) {
      HolySaveUserSiteToDisk(st->domain_buf, st->title_buf, compiled);
      Free(compiled);
      NavigateTo(app, st->domain_buf, TRUE);
      snprintf(t->status_msg, sizeof(t->status_msg),
               "[ОПУБЛИКОВАНО В P2P + СОХРАНЕНО!] Домен %s закреплён за вашим узлом!",
               st->domain_buf);
    } else {
      Free(compiled);
      SafeCopy(st->feedback_msg, err, sizeof(st->feedback_msg));
      st->feedback_error = TRUE;
      snprintf(t->status_msg, sizeof(t->status_msg), "[ОШИБКА ДОМЕНА] %s", err);
    }
  }
}

U0 AppCleanup(BrowserApp *app)
{
  if (g_holy.initialized) {
    g_holy.running = FALSE;
    if (g_holy.listen_fd >= 0) close(g_holy.listen_fd);
    if (g_holy.identity_lock_fd >= 0) close(g_holy.identity_lock_fd);
  }
  for (I32 i = 0; i < app->tab_count; i++) {
    FreeSingleTabStruct(&app->tabs[i]);
  }
  if (app->back_cr != NULL) cairo_destroy(app->back_cr);
  if (app->back_surf != NULL) cairo_surface_destroy(app->back_surf);
  if (app->xlib_surf != NULL) cairo_surface_destroy(app->xlib_surf);
  if (app->dpy != NULL) {
    XFreeCursor(app->dpy, app->cur_arrow);
    XFreeCursor(app->dpy, app->cur_hand);
    XFreeCursor(app->dpy, app->cur_ibeam);
    XCloseDisplay(app->dpy);
  }
}

U0 AddCliPeerString(U8 *hp)
{
  U8 host[128];
  U8 *colon = strchr(hp, ':');
  if (colon == NULL) return;
  SafeCopyLen(host, hp, colon - hp, sizeof(host));
  I32 port = Atoi(colon + 1);
  if (port > 0) HolyAddPeerCandidate(host, port);
}

/* --- Режим рендеринга PNG без X-сервера --- */
I32 RunHeadlessScreenshot(U8 *out_png, U8 *start_url, U8 *cli_search_q, U8 *cli_scope,
                          U8 **extra_tabs, I32 extra_tab_cnt, U8 *find_str, F64 init_zoom,
                          I32 theme_id, I32 req_w, I32 req_h, F64 init_scroll, Bool holy_mode,
                          I32 p2p_port, U8 *claim_dom, U8 *claim_title)
{
  BrowserApp *app = MAlloc(sizeof(BrowserApp));
  MemSet(app, 0, sizeof(BrowserApp));
  app->hover_link_id = -1;
  app->theme_id = theme_id;
  app->p2p_port_pref = p2p_port;
  InitBookmarks(app);

  if (holy_mode) {
    if (theme_id != THEME_DAVIS) app->theme_id = THEME_HOLYNET;
    EnsureHolynetNode(app);
    /* Первый запуск встроенного Tor может занять десятки секунд. В headless
     * режиме дождаться сети, иначе снимок делается до загрузки каталога. */
    for (I32 tw = 0; tw < 900 && !g_holy.mesh_initial_done && g_holy.running; tw++) usleep(50000);
    HolySyncNetwork();
  }

  RecreateBackbuffer(app, req_w, req_h);

  /* Открываем первую основную вкладку */
  app->tab_count = 1;
  app->active_tab = 0;
  InitSingleTabStruct(&app->tabs[0], holy_mode);
  if (init_zoom > 0.1) app->tabs[0].zoom = init_zoom;

  if (claim_dom != NULL && claim_dom[0] != 0) {
    EnsureHolynetNode(app);
    SafeCopy(app->tabs[0].builder.domain_buf, claim_dom, sizeof(app->tabs[0].builder.domain_buf));
    if (claim_title != NULL && claim_title[0] != 0) {
      SafeCopy(app->tabs[0].builder.title_buf, claim_title, sizeof(app->tabs[0].builder.title_buf));
    }
    U8 *html = BuilderCompileHtml(&app->tabs[0].builder);
    U8 err[256];
    HolyPublishSite(app->tabs[0].builder.domain_buf, app->tabs[0].builder.title_buf, html, err, sizeof(err));
    Free(html);
  }

  /* Открываем фоновые дополнительные вкладки, если переданы --tab <URL> */
  for (I32 et = 0; et < extra_tab_cnt; et++) {
    Bool tab_holy = StartsWithIgnoreCase(extra_tabs[et], "holy://") || holy_mode;
    if (StartsWithIgnoreCase(extra_tabs[et], "http://") ||
        StartsWithIgnoreCase(extra_tabs[et], "https://")) {
      tab_holy = FALSE;
    }
    OpenNewTab(app, extra_tabs[et], tab_holy);
  }

  /* Возвращаем фокус на первую основную вкладку и открываем целевой URL */
  SwitchToTab(app, 0);
  app->tabs[0].holynet_mode = holy_mode;
  if (theme_id == THEME_DAVIS) app->theme_id = THEME_DAVIS;
  else if (holy_mode) app->theme_id = THEME_HOLYNET;
  else app->theme_id = theme_id;

  if (cli_search_q != NULL) {
    ExecuteSearchQuery(app, cli_search_q, cli_scope, TRUE);
  } else {
    SubmitOmniboxInput(app, start_url, FALSE);
  }

  if (find_str != NULL && find_str[0] != 0) {
    app->ui.find_active = TRUE;
    app->ui.find_focused = TRUE;
    SafeCopy(app->ui.find_query, find_str, sizeof(app->ui.find_query));
    RecomputeFindMatches(app, TRUE);
  }

  if (init_scroll > 0.0) {
    app->tabs[0].scroll_y = init_scroll;
    ClampScroll(app);
  }
  RepaintWindow(app);

  I32 rc = cairo_surface_write_to_png(app->back_surf, out_png);
  if (rc == 0) {
    "[DivineWeb v2.0] Скриншот '%s' (вкладок=%d) -> '%s'\n",
      app->tabs[0].current_url, app->tab_count, out_png;
  } else {
    "[DivineWeb v2.0] Ошибка записи PNG в '%s' (код %d)\n", out_png, rc;
  }
  AppCleanup(app);
  Free(app);
  return rc;
}

I32 Main(I32 argc, U8 **argv)
{
  signal(13, 1(U0 *)); /* SIGPIPE / SIG_IGN */
  U8  *initial_url = "temple://home";
  Bool url_explicit = FALSE;
  U8  *cli_search = NULL;
  U8  *cli_scope = NULL;
  U8  *cli_find = NULL;
  U8  *extra_tabs[MAX_TABS];
  I32  extra_tab_cnt = 0;
  U8  *screenshot_out = NULL;
  I32  start_theme = THEME_TEMPLE;
  I32  req_win_w = 1080;
  I32  req_win_h = 760;
  F64  init_scroll = 0.0;
  F64  init_zoom = 1.0;
  Bool start_holy = FALSE;
  Bool daemon_mode = FALSE;
  I32  p2p_port = HOLY_DEFAULT_PORT;
  I32  seed_preset = 0;
  I32  daemon_seconds = 120;
  U8  *cli_peers[16];
  I32  cli_peer_cnt = 0;
  U8  *claim_dom = NULL;
  U8  *claim_title = NULL;
  U8  *pub_html_dom = NULL;
  U8  *pub_html_path = NULL;

  for (I32 i = 1; i < argc; i++) {
    if (StrCmp(argv[i], "--modern") == 0) {
      start_theme = THEME_MODERN;
    } else if (StrCmp(argv[i], "--temple") == 0) {
      start_theme = THEME_TEMPLE;
    } else if (StrCmp(argv[i], "--davis") == 0) {
      start_theme = THEME_DAVIS;
    } else if (StrCmp(argv[i], "--davis-640") == 0 || StrCmp(argv[i], "--640x480") == 0) {
      start_theme = THEME_DAVIS;
      req_win_w = 640;
      req_win_h = 480;
    } else if (StrCmp(argv[i], "--holynet") == 0 || StrCmp(argv[i], "--cheburnet") == 0) {
      start_holy = TRUE;
      if (start_theme != THEME_DAVIS) start_theme = THEME_HOLYNET;
    } else if (StrCmp(argv[i], "--search") == 0 && i + 1 < argc) {
      cli_search = argv[++i];
    } else if (StrCmp(argv[i], "--scope") == 0 && i + 1 < argc) {
      cli_scope = argv[++i];
    } else if (StrCmp(argv[i], "--find") == 0 && i + 1 < argc) {
      cli_find = argv[++i];
    } else if (StrCmp(argv[i], "--zoom") == 0 && i + 1 < argc) {
      init_zoom = Atoi(argv[++i]) / 100.0;
    } else if (StrCmp(argv[i], "--tab") == 0 && i + 1 < argc) {
      if (extra_tab_cnt < MAX_TABS - 1) extra_tabs[extra_tab_cnt++] = argv[++i];
    } else if (StrCmp(argv[i], "--p2p-port") == 0 && i + 1 < argc) {
      p2p_port = Atoi(argv[++i]);
    } else if (StrCmp(argv[i], "--peer") == 0 && i + 1 < argc) {
      if (cli_peer_cnt < 16) cli_peers[cli_peer_cnt++] = argv[++i];
    } else if (StrCmp(argv[i], "--p2p-daemon") == 0) {
      daemon_mode = TRUE;
      start_holy = TRUE;
    } else if (StrCmp(argv[i], "--seed-preset") == 0 && i + 1 < argc) {
      seed_preset = Atoi(argv[++i]);
    } else if (StrCmp(argv[i], "--daemon-sec") == 0 && i + 1 < argc) {
      daemon_seconds = Atoi(argv[++i]);
    } else if (StrCmp(argv[i], "--claim-publish") == 0 && i + 2 < argc) {
      claim_dom = argv[++i];
      claim_title = argv[++i];
    } else if (StrCmp(argv[i], "--publish-html") == 0 && i + 2 < argc) {
      pub_html_dom = argv[++i];
      pub_html_path = argv[++i];
      start_holy = TRUE;
      start_theme = THEME_HOLYNET;
    } else if (StrCmp(argv[i], "--screenshot") == 0 && i + 1 < argc) {
      screenshot_out = argv[++i];
    } else if (StrCmp(argv[i], "--scroll") == 0 && i + 1 < argc) {
      init_scroll = Atoi(argv[++i]);
    } else if (StrCmp(argv[i], "--anim-ms") == 0 && i + 1 < argc) {
      g_anim_override = TRUE;
      g_anim_override_sec = Atoi(argv[++i]) / 1000.0;
    } else if (StrCmp(argv[i], "--help") == 0 || StrCmp(argv[i], "-h") == 0) {
      "DivineWeb v2.0 — 2D-браузер на HolyC (вкладки, закладки, картинки, таблицы, P2P Holynet / Холинет)\n";
      "Использование:\n";
      "  ./holy-browser [URL или запрос] [--holynet] [--davis] [--tab <URL>] [--find <слово>] [--zoom <%%>]\n";
      "  ./holy-browser --p2p-daemon --p2p-port 19401 --seed-preset 1  (профиль; TCP-порт не открывается)\n";
      "  ./holy-browser --screenshot <out.png> [URL/запрос] [--holynet] [--scroll <px>]\n";
      return 0;
    } else {
      initial_url = argv[i];
      url_explicit = TRUE;
    }
  }

  if (cli_peer_cnt > 0) {
    "Прямые пиры --peer отключены для защиты IP; используйте TLS-ретранслятор.\n";
    return 2;
  }

  if (start_holy && !url_explicit) {
    if (pub_html_dom != NULL) initial_url = pub_html_dom;
    else initial_url = "holy://home";
  }

  if (daemon_mode) {
    if (!HolyStartNode(p2p_port)) {
      "[P2P Узел] Не удалось занять порт %d\n", p2p_port;
      return 1;
    }
    for (I32 k = 0; k < cli_peer_cnt; k++) AddCliPeerString(cli_peers[k]);
    HolySeedPresetSites(seed_preset);
    if (pub_html_dom != NULL && pub_html_path != NULL) {
      U8 perr[256];
      if (HolyPublishHtmlFile(pub_html_dom, pub_html_path, perr, sizeof(perr))) {
        "[P2P Узел] HTML '%s' опубликован на домене '%s'\n", pub_html_path, pub_html_dom;
      } else {
        "[P2P Узел] Ошибка публикации HTML: %s\n", perr;
      }
    }
    HolySyncNetwork();
    "[Узел Холинета %s] Tor + TLS-реле; прямых входящих соединений нет (сайтов: %d). Провайдер видит Tor.\n",
      g_holy.node_id, g_holy.site_count;
    for (I32 s = 0; s < daemon_seconds * 10; s++) {
      usleep(100000);
    }
    g_holy.running = FALSE;
    if (g_holy.listen_fd >= 0) close(g_holy.listen_fd);
    if (g_holy.identity_lock_fd >= 0) close(g_holy.identity_lock_fd);
    return 0;
  }

  if (screenshot_out != NULL) {
    if (start_holy || StartsWithIgnoreCase(initial_url, "holy://") ||
        StartsWithIgnoreCase(initial_url, "cheb://")) {
      HolyStartNode(p2p_port);
      HolySeedPresetSites(0);
      for (I32 k = 0; k < cli_peer_cnt; k++) AddCliPeerString(cli_peers[k]);
      if (pub_html_dom != NULL && pub_html_path != NULL) {
        U8 perr[256];
        HolyPublishHtmlFile(pub_html_dom, pub_html_path, perr, sizeof(perr));
      }
      start_holy = TRUE;
    }
    return RunHeadlessScreenshot(screenshot_out, initial_url, cli_search, cli_scope,
                                 extra_tabs, extra_tab_cnt, cli_find, init_zoom,
                                 start_theme, req_win_w, req_win_h, init_scroll, start_holy,
                                 p2p_port, claim_dom, claim_title);
  }

  BrowserApp *app = MAlloc(sizeof(BrowserApp));
  MemSet(app, 0, sizeof(BrowserApp));
  app->hover_link_id = -1;
  app->theme_id = start_theme;
  app->p2p_port_pref = p2p_port;
  InitBookmarks(app);

  if (start_holy) {
    EnsureHolynetNode(app);
    for (I32 k = 0; k < cli_peer_cnt; k++) AddCliPeerString(cli_peers[k]);
    if (pub_html_dom != NULL && pub_html_path != NULL) {
      U8 perr[256];
      HolyPublishHtmlFile(pub_html_dom, pub_html_path, perr, sizeof(perr));
    }
  }

  app->dpy = XOpenDisplay(NULL);
  if (app->dpy == NULL) {
    "Ошибка: дисплей X11 не найден ($DISPLAY пуст).\n";
    "Используйте --screenshot out.png [URL/запрос] --holynet или --p2p-daemon.\n";
    return 1;
  }

  app->screen = XDefaultScreen(app->dpy);
  app->win_w = req_win_w;
  app->win_h = req_win_h;

  U64 root = XRootWindow(app->dpy, app->screen);
  app->win = XCreateSimpleWindow(
    app->dpy, root, 40, 28, app->win_w, app->win_h, 0,
    XBlackPixel(app->dpy, app->screen),
    XWhitePixel(app->dpy, app->screen)
  );

  I64 mask = X11_ExposureMask | X11_KeyPressMask |
             X11_ButtonPressMask | X11_ButtonReleaseMask |
             X11_PointerMotionMask | X11_StructureNotifyMask;
  XSelectInput(app->dpy, app->win, mask);

  app->wm_delete = XInternAtom(app->dpy, "WM_DELETE_WINDOW", FALSE);
  XSetWMProtocols(app->dpy, app->win, &app->wm_delete, 1);

  app->cur_arrow = XCreateFontCursor(app->dpy, XC_left_ptr);
  app->cur_hand  = XCreateFontCursor(app->dpy, XC_hand2);
  app->cur_ibeam = XCreateFontCursor(app->dpy, XC_xterm);
  XDefineCursor(app->dpy, app->win, app->cur_arrow);

  U0 *visual = XDefaultVisual(app->dpy, app->screen);
  app->xlib_surf = cairo_xlib_surface_create(app->dpy, app->win, visual, app->win_w, app->win_h);
  RecreateBackbuffer(app, app->win_w, app->win_h);

  app->tab_count = 1;
  app->active_tab = 0;
  InitSingleTabStruct(&app->tabs[0], start_holy);
  if (init_zoom > 0.1) app->tabs[0].zoom = init_zoom;

  XMapWindow(app->dpy, app->win);
  if (cli_search != NULL) {
    ExecuteSearchQuery(app, cli_search, cli_scope, TRUE);
  } else {
    SubmitOmniboxInput(app, initial_url, FALSE);
  }
  for (I32 et = 0; et < extra_tab_cnt; et++) {
    OpenNewTab(app, extra_tabs[et], start_holy);
  }
  if (extra_tab_cnt > 0) SwitchToTab(app, 0);

  RepaintWindow(app);

  I64 seen_mesh_seq = g_holy.mesh_catalog_seq;
  Bool running = TRUE;
  while (running) {
    BrowserTab *idle_t = CurTab(app);
    if (XPending(app->dpy) == 0 && (idle_t->doc.has_animations || idle_t->holynet_mode ||
        (idle_t->js_page != NULL && QjsPageHasActiveTimers(idle_t->js_page)))) {
      I32 wait_ms = 250;
      if (idle_t->doc.has_animations || (idle_t->js_page != NULL && QjsPageHasActiveTimers(idle_t->js_page))) wait_ms = 33;
      LinuxPollFd xfd;
      xfd.fd = XConnectionNumber(app->dpy);
      xfd.events = LINUX_POLLIN;
      xfd.revents = 0;
      I32 prc = poll(&xfd, 1, wait_ms);

      /* Живое автообновление без перезагрузки и без F5, когда из P2P прилетел новый сайт! */
      if (g_holy.mesh_catalog_seq != seen_mesh_seq) {
        seen_mesh_seq = g_holy.mesh_catalog_seq;
        if (idle_t->holynet_mode && !idle_t->builder.active && !app->addr_focused) {
          if (StrCmp(idle_t->current_url, "holy://home") == 0 ||
              StartsWithIgnoreCase(idle_t->current_url, "holy://monitor") ||
              idle_t->last_status_code == 404) {
            F64 keep_scroll = idle_t->scroll_y;
            NavigateTo(app, idle_t->current_url, FALSE);
            if (idle_t->last_status_code == 200 &&
                (StrCmp(idle_t->current_url, "holy://home") == 0 ||
                 StartsWithIgnoreCase(idle_t->current_url, "holy://monitor"))) {
              idle_t->scroll_y = keep_scroll;
              ClampScroll(app);
            }
            RepaintWindow(app);
            continue;
          }
        }
      }

      if (prc == 0) {
        Bool js_updated = FALSE;
        if (idle_t->js_page != NULL && QjsPageTickTimers(idle_t->js_page)) { RefreshJsPage(app); js_updated = TRUE; }
        if (idle_t->doc.has_animations || js_updated) RepaintWindow(app);
        continue;
      }
    }

    XEventHC ev;
    XNextEvent(app->dpy, &ev);
    Bool need_redraw = FALSE;
    BrowserTab *t = CurTab(app);

    if (ev.type == X11_Expose) {
      need_redraw = TRUE;
    } else if (ev.type == X11_ClientMessage) {
      if (ev.xclient.data_l[0] == app->wm_delete) running = FALSE;
    } else if (ev.type == X11_ConfigureNotify) {
      I32 nw = ev.xconfigure.width;
      I32 nh = ev.xconfigure.height;
      if (nw != app->win_w || nh != app->win_h) {
        RecreateBackbuffer(app, nw, nh);
        RebuildCurrentTabLayout(app);
        need_redraw = TRUE;
      }
    } else if (ev.type == X11_MotionNotify) {
      I32 mx = ev.xmotion.x;
      I32 my = ev.xmotion.y;

      if (app->dragging_scroll && !t->builder.active) {
        ScrollToMouseY(app, my);
        need_redraw = TRUE;
      } else {
        SyncChromeState(app);
        I32 b = HitTestChrome(mx, my, app->win_w, app->win_h, &app->ui);
        if (b != app->hover_btn) {
          app->hover_btn = b;
          need_redraw = TRUE;
        }

        if (b == BTN_ADDRBAR || b == BTN_FIND_INPUT) {
          UpdateCursorShape(app, 2);
        } else if (b != BTN_NONE) {
          UpdateCursorShape(app, 1);
        } else if (t->builder.active && my >= TOOLBAR_H) {
          I32 bw = HitTestBuilder(mx, my, app->win_w, app->win_h);
          if (bw != t->builder.hover_widget) {
            t->builder.hover_widget = bw;
            need_redraw = TRUE;
          }
          if (bw >= BWID_FIELD_DOMAIN && bw <= BWID_FIELD_HTMLFILE) UpdateCursorShape(app, 2);
          else if (bw >= BWID_TPL_CARD) UpdateCursorShape(app, 1);
          else UpdateCursorShape(app, 0);
        } else {
          I32 lnk = HitTestPageLink(&t->layout, mx, my, t->scroll_y, app->win_w, app->win_h);
          if (lnk != app->hover_link_id) {
            app->hover_link_id = lnk;
            need_redraw = TRUE;
          }
          if (lnk >= 0) UpdateCursorShape(app, 1);
          else UpdateCursorShape(app, 0);
        }
      }
    } else if (ev.type == X11_ButtonRelease) {
      if (ev.xbutton.button == 1) app->dragging_scroll = FALSE;
    } else if (ev.type == X11_ButtonPress) {
      I32 btn = ev.xbutton.button;
      I32 mx = ev.xbutton.x;
      I32 my = ev.xbutton.y;
      Bool ctrl_held = (ev.xbutton.state & X11_ControlMask) != 0;

      if (btn == 4 && !t->builder.active) {
        if (ctrl_held) AdjustZoom(app, 0.10);
        else { t->scroll_y -= 56.0; ClampScroll(app); }
        need_redraw = TRUE;
      } else if (btn == 5 && !t->builder.active) {
        if (ctrl_held) AdjustZoom(app, -0.10);
        else { t->scroll_y += 56.0; ClampScroll(app); }
        need_redraw = TRUE;
      } else if (btn == 1) {
        SyncChromeState(app);
        I32 tb = HitTestChrome(mx, my, app->win_w, app->win_h, &app->ui);
        if (tb == BTN_ADDRBAR) {
          app->addr_focused = TRUE;
          app->ui.find_focused = FALSE;
          t->builder.focused_field = BWID_NONE;
          need_redraw = TRUE;
        } else if (tb == BTN_FIND_INPUT) {
          app->addr_focused = FALSE;
          app->ui.find_focused = TRUE;
          need_redraw = TRUE;
        } else if (tb == BTN_FIND_PREV) {
          app->ui.find_current--;
          RecomputeFindMatches(app, TRUE);
          need_redraw = TRUE;
        } else if (tb == BTN_FIND_NEXT) {
          app->ui.find_current++;
          RecomputeFindMatches(app, TRUE);
          need_redraw = TRUE;
        } else if (tb == BTN_FIND_CLOSE) {
          app->ui.find_active = FALSE;
          app->ui.find_focused = FALSE;
          need_redraw = TRUE;
        } else if (tb >= BTN_TAB_BASE && tb < BTN_TAB_BASE + MAX_TABS) {
          SwitchToTab(app, tb - BTN_TAB_BASE);
          need_redraw = TRUE;
        } else if (tb >= BTN_TAB_CLOSE_BASE && tb < BTN_TAB_CLOSE_BASE + MAX_TABS) {
          CloseTabAt(app, tb - BTN_TAB_CLOSE_BASE);
          need_redraw = TRUE;
        } else if (tb == BTN_NEW_TAB) {
          OpenNewTab(app, NULL, t->holynet_mode);
          need_redraw = TRUE;
        } else if (tb >= BTN_BMARK_BASE && tb < BTN_BMARK_BASE + MAX_BOOKMARKS) {
          I32 bidx = tb - BTN_BMARK_BASE;
          if (bidx < app->ui.bookmark_count && app->ui.bookmarks[bidx].used) {
            U8 bm_url[512];
            SafeCopy(bm_url, app->ui.bookmarks[bidx].url, sizeof(bm_url));
            if (StartsWithIgnoreCase(bm_url, "http://") || StartsWithIgnoreCase(bm_url, "https://")) {
              t->holynet_mode = FALSE;
              if (app->theme_id == THEME_HOLYNET) app->theme_id = THEME_TEMPLE;
            }
            NavigateTo(app, bm_url, TRUE);
            need_redraw = TRUE;
          }
        } else if (tb != BTN_NONE) {
          if (tb == BTN_HOLY_TOGGLE) {
            ToggleHolynetMode(app);
            need_redraw = TRUE;
          } else {
            app->addr_focused = FALSE;
            app->ui.find_focused = FALSE;
            if (tb == BTN_BACK && t->hist_pos > 0) {
              t->hist_pos--;
              NavigateTo(app, t->history[t->hist_pos], FALSE);
            } else if (tb == BTN_FWD && t->hist_pos + 1 < t->hist_count) {
              t->hist_pos++;
              NavigateTo(app, t->history[t->hist_pos], FALSE);
            } else if (tb == BTN_RELOAD) {
              NavigateTo(app, t->current_url, FALSE);
            } else if (tb == BTN_HOME) {
              if (t->holynet_mode) NavigateTo(app, "holy://home", TRUE);
              else NavigateTo(app, "temple://home", TRUE);
            } else if (tb == BTN_BOOKMARK_STAR) {
              ToggleCurrentBookmark(app);
            } else if (tb == BTN_GO) {
              SubmitOmniboxInput(app, t->addr_buf, FALSE);
            } else if (tb == BTN_SEARCH) {
              SubmitOmniboxInput(app, t->addr_buf, TRUE);
            } else if (tb == BTN_BUILDER) {
              if (!t->holynet_mode) {
                t->holynet_mode = TRUE;
                if (app->theme_id != THEME_DAVIS) app->theme_id = THEME_HOLYNET;
              }
              NavigateTo(app, "holy://builder", TRUE);
            } else if (tb == BTN_MONITOR) {
              if (!t->holynet_mode) {
                t->holynet_mode = TRUE;
                if (app->theme_id != THEME_DAVIS) app->theme_id = THEME_HOLYNET;
              }
              NavigateTo(app, "holy://monitor?sync=1", TRUE);
            } else if (tb == BTN_ZOOM_OUT) {
              AdjustZoom(app, -0.10);
            } else if (tb == BTN_ZOOM_IN) {
              AdjustZoom(app, 0.10);
            } else if (tb == BTN_FIND_TOGGLE) {
              app->ui.find_active = !app->ui.find_active;
              app->ui.find_focused = app->ui.find_active;
              RecomputeFindMatches(app, TRUE);
            } else if (tb == BTN_THEME) {
              app->theme_id = (app->theme_id + 1) % 4;
              RebuildCurrentTabLayout(app);
              if (app->theme_id == THEME_DAVIS) {
                DavisInvokeOracle(app);
              }
            }
            need_redraw = TRUE;
          }
        } else if (t->builder.active) {
          app->addr_focused = FALSE;
          app->ui.find_focused = FALSE;
          I32 bw = HitTestBuilder(mx, my, app->win_w, app->win_h);
          HandleBuilderWidgetClick(app, bw);
          need_redraw = TRUE;
        } else {
          app->addr_focused = FALSE;
          app->ui.find_focused = FALSE;
          if (mx >= app->win_w - SCROLLBAR_W && my >= TOOLBAR_H && my <= app->win_h - STATUSBAR_H) {
            app->dragging_scroll = TRUE;
            ScrollToMouseY(app, my);
            need_redraw = TRUE;
          } else {
            I32 clicked_link = HitTestPageLink(&t->layout, mx, my, t->scroll_y, app->win_w, app->win_h);
            if (clicked_link >= 0 && clicked_link < t->doc.link_count) {
              U8 target_copy[1024];
              SafeCopy(target_copy, t->doc.links[clicked_link], sizeof(target_copy));
              /* Средний или Ctrl+клик открывает ссылку в новой вкладке! */
              if (t->holynet_mode && (StartsWithIgnoreCase(target_copy, "file:") ||
                  StartsWithIgnoreCase(target_copy, "http:") || StartsWithIgnoreCase(target_copy, "https:"))) {
                SafeCopy(t->status_msg, "Переход из Холинета к локальному файлу или в Интернет заблокирован; введите адрес вручную.", sizeof(t->status_msg));
              } else if (StartsWithIgnoreCase(target_copy, "javascript:")) {
                RunJsLink(app, target_copy);
              } else if (ctrl_held && app->tab_count < MAX_TABS) {
                OpenNewTab(app, target_copy, t->holynet_mode);
              } else {
                NavigateTo(app, target_copy, TRUE);
              }
            }
            need_redraw = TRUE;
          }
        }
      } else if (btn == 2 && !t->builder.active) {
        /* Колёсико (средняя кнопка мыши) по ссылке — открыть в новой вкладке! */
        I32 clicked_link = HitTestPageLink(&t->layout, mx, my, t->scroll_y, app->win_w, app->win_h);
        if (clicked_link >= 0 && clicked_link < t->doc.link_count) {
          U8 target_copy[1024];
          SafeCopy(target_copy, t->doc.links[clicked_link], sizeof(target_copy));
          if (!StartsWithIgnoreCase(target_copy, "javascript:") &&
              !(t->holynet_mode && (StartsWithIgnoreCase(target_copy, "file:") ||
                StartsWithIgnoreCase(target_copy, "http:") || StartsWithIgnoreCase(target_copy, "https:"))))
            OpenNewTab(app, target_copy, t->holynet_mode);
          need_redraw = TRUE;
        }
      }
    } else if (ev.type == X11_KeyPress) {
      U8 kbuf[32];
      U64 ksym = 0;
      MemSet(kbuf, 0, sizeof(kbuf));
      I32 nbytes = XLookupString(&ev.xkey, kbuf, sizeof(kbuf) - 1, &ksym, NULL);
      Bool ctrl = (ev.xkey.state & X11_ControlMask) != 0;

      if (ctrl && (ksym == 'j' || ksym == 'J' || kbuf[0] == 10)) {
        if (t->holynet_mode) t->js_holynet_enabled = !t->js_holynet_enabled;
        else t->js_disabled = !t->js_disabled;
        U8 js_reload_url[1024];
        SafeCopy(js_reload_url, t->current_url, sizeof(js_reload_url));
        NavigateTo(app, js_reload_url, FALSE);
        if (t->holynet_mode) {
          if (t->js_holynet_enabled) SafeCopy(t->status_msg, "Холинет: JS включён. САЙТЫ НЕ ПРОВЕРЕНЫ (Ctrl+J)", sizeof(t->status_msg));
          else SafeCopy(t->status_msg, "Холинет: JS выключен. САЙТЫ НЕ ПРОВЕРЕНЫ (Ctrl+J)", sizeof(t->status_msg));
        } else if (t->js_disabled) SafeCopy(t->status_msg, "JavaScript выключен (Ctrl+J)", sizeof(t->status_msg));
        else SafeCopy(t->status_msg, "JavaScript включён (Ctrl+J)", sizeof(t->status_msg));
        need_redraw = TRUE;
      } else if (ctrl && (kbuf[0] == 12 || ksym == 'l' || ksym == 'L' || ksym == 'k' || ksym == 'K')) {
        app->addr_focused = TRUE;
        app->ui.find_focused = FALSE;
        t->addr_buf[0] = 0;
        need_redraw = TRUE;
      } else if (ctrl && (kbuf[0] == 20 || ksym == 't' || ksym == 'T')) {
        OpenNewTab(app, NULL, t->holynet_mode);
        need_redraw = TRUE;
      } else if (ctrl && (kbuf[0] == 23 || ksym == 'w' || ksym == 'W')) {
        if (app->tab_count > 1) CloseTabAt(app, app->active_tab);
        need_redraw = TRUE;
      } else if (ctrl && ksym == XK_Tab) {
        SwitchToTab(app, (app->active_tab + 1) % app->tab_count);
        need_redraw = TRUE;
      } else if (ctrl && (kbuf[0] == 4 || ksym == 'd' || ksym == 'D')) {
        ToggleCurrentBookmark(app);
        need_redraw = TRUE;
      } else if (ctrl && (kbuf[0] == 6 || ksym == 'f' || ksym == 'F')) {
        app->ui.find_active = TRUE;
        app->ui.find_focused = TRUE;
        app->addr_focused = FALSE;
        RecomputeFindMatches(app, TRUE);
        need_redraw = TRUE;
      } else if (ctrl && (ksym == '=' || ksym == '+')) {
        AdjustZoom(app, 0.10);
        need_redraw = TRUE;
      } else if (ctrl && ksym == '-') {
        AdjustZoom(app, -0.10);
        need_redraw = TRUE;
      } else if (ctrl && ksym == '0') {
        AdjustZoom(app, 0.0);
        need_redraw = TRUE;
      } else if (ctrl && (kbuf[0] == 17 || ksym == 'q' || ksym == 'Q')) {
        running = FALSE;
      } else if (ksym == XK_F5) {
        NavigateTo(app, t->current_url, FALSE);
        need_redraw = TRUE;
      } else if (ksym == XK_F7) {
        DavisInvokeOracle(app);
        need_redraw = TRUE;
      } else if (ksym == XK_F12) {
        cairo_surface_write_to_png(app->back_surf, "screenshot.png");
        SafeCopy(t->status_msg, "Скриншот сохранён в файл screenshot.png", sizeof(t->status_msg));
        need_redraw = TRUE;
      } else if (app->ui.find_active && app->ui.find_focused) {
        if (ksym == XK_Return || ksym == XK_KP_Enter) {
          app->ui.find_current++;
          RecomputeFindMatches(app, TRUE);
          need_redraw = TRUE;
        } else if (ksym == XK_Escape) {
          app->ui.find_active = FALSE;
          app->ui.find_focused = FALSE;
          need_redraw = TRUE;
        } else if (ksym == XK_BackSpace || ksym == XK_Delete) {
          EraseLastUtf8Char(app->ui.find_query);
          app->ui.find_current = 0;
          RecomputeFindMatches(app, TRUE);
          need_redraw = TRUE;
        } else if (nbytes > 0 && kbuf[0] >= 32 && !ctrl) {
          I64 fl = StrLen(app->ui.find_query);
          if (fl + nbytes < sizeof(app->ui.find_query) - 1) {
            MemCpy(app->ui.find_query + fl, kbuf, nbytes);
            app->ui.find_query[fl + nbytes] = 0;
            app->ui.find_current = 0;
            RecomputeFindMatches(app, TRUE);
            need_redraw = TRUE;
          }
        }
      } else if (app->addr_focused) {
        if (ksym == XK_Return || ksym == XK_KP_Enter) {
          app->addr_focused = FALSE;
          SubmitOmniboxInput(app, t->addr_buf, FALSE);
          need_redraw = TRUE;
        } else if (ksym == XK_Escape) {
          app->addr_focused = FALSE;
          FormatCleanAddressBar(t->current_url, t->addr_buf, sizeof(t->addr_buf));
          need_redraw = TRUE;
        } else if (ksym == XK_BackSpace || ksym == XK_Delete) {
          EraseLastUtf8Char(t->addr_buf);
          need_redraw = TRUE;
        } else if (ctrl && (kbuf[0] == 21 || ksym == 'u' || ksym == 'U')) {
          t->addr_buf[0] = 0;
          need_redraw = TRUE;
        } else if (nbytes > 0 && kbuf[0] >= 32 && !ctrl) {
          I64 alen = StrLen(t->addr_buf);
          if (alen + nbytes < sizeof(t->addr_buf) - 1) {
            MemCpy(t->addr_buf + alen, kbuf, nbytes);
            t->addr_buf[alen + nbytes] = 0;
            need_redraw = TRUE;
          }
        }
      } else if (t->builder.active && t->builder.focused_field != BWID_NONE) {
        I64 fcap = 0;
        U8 *fbuf = GetBuilderActiveBuffer(&t->builder, &fcap);
        if (ksym == XK_Tab) {
          t->builder.focused_field++;
          if (t->builder.focused_field > BWID_FIELD_HTMLFILE)
            t->builder.focused_field = BWID_FIELD_DOMAIN;
          need_redraw = TRUE;
        } else if (ksym == XK_Escape) {
          t->builder.focused_field = BWID_NONE;
          need_redraw = TRUE;
        } else if ((ksym == XK_BackSpace || ksym == XK_Delete) && fbuf != NULL) {
          EraseLastUtf8Char(fbuf);
          need_redraw = TRUE;
        } else if (ctrl && (kbuf[0] == 21 || ksym == 'u' || ksym == 'U') && fbuf != NULL) {
          fbuf[0] = 0;
          need_redraw = TRUE;
        } else if (fbuf != NULL && nbytes > 0 && kbuf[0] >= 32 && !ctrl) {
          I64 flen = StrLen(fbuf);
          if (flen + nbytes < fcap - 1) {
            MemCpy(fbuf + flen, kbuf, nbytes);
            fbuf[flen + nbytes] = 0;
            need_redraw = TRUE;
          }
        }
      } else if (!t->builder.active) {
        F64 page_step = (app->win_h - TOOLBAR_H - STATUSBAR_H) * 0.85;
        if (ksym == XK_Down || ksym == 'j') {
          t->scroll_y += 42.0; ClampScroll(app); need_redraw = TRUE;
        } else if (ksym == XK_Up || ksym == 'k') {
          t->scroll_y -= 42.0; ClampScroll(app); need_redraw = TRUE;
        } else if (ksym == XK_Page_Down || ksym == ' ') {
          t->scroll_y += page_step; ClampScroll(app); need_redraw = TRUE;
        } else if (ksym == XK_Page_Up) {
          t->scroll_y -= page_step; ClampScroll(app); need_redraw = TRUE;
        } else if (ksym == XK_Home) {
          t->scroll_y = 0.0; ClampScroll(app); need_redraw = TRUE;
        } else if (ksym == XK_End) {
          t->scroll_y = t->layout.content_height; ClampScroll(app); need_redraw = TRUE;
        }
      }
    }

    if (need_redraw && XPending(app->dpy) == 0) {
      RepaintWindow(app);
    }
  }

  AppCleanup(app);
  Free(app);
  return 0;
}
