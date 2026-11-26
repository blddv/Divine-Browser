#ifndef QJS_BRIDGE_H
#define QJS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QjsPage QjsPage;

/* Callback into HolyC HTTP/HTTPS/HolyNet fetcher:
 * Returns 1 on success (caller frees *out_body with free() if malloc'd via QjsAllocBuf), 0 on error. */
typedef int32_t (*QjsFetchFn)(const char *url, char **out_body, int64_t *out_len, int32_t *out_status);

void     QjsSetFetchCallback(QjsFetchFn fn);
char    *QjsAllocBuf(int64_t size);

QjsPage *QjsPageCreate(void);
void     QjsPageDestroy(QjsPage *page);

/* Load HTML into QuickJS DOM, execute inline & external <script> tags, fire DOMContentLoaded + load.
 * Returns newly malloc'd UTF-8 HTML string after JS execution (free with QjsFreeStr), or NULL on error. */
char    *QjsPageLoadHtml(QjsPage *page, const char *html, int64_t html_len,
                         const char *page_url, int64_t *out_html_len);

/* Dispatch click on an element with data-qjs-id == qjs_id.
 * Returns 1 if DOM changed or redirect was requested, 0 otherwise. */
int32_t  QjsPageClickId(QjsPage *page, int32_t qjs_id);

/* Evaluate a javascript:... URL or inline snippet in the current page context.
 * Returns 1 if DOM changed or redirect was requested, 0 otherwise. */
int32_t  QjsPageEvalUrl(QjsPage *page, const char *js_code);

/* Advance setTimeout / setInterval timers.
 * Returns 1 if any timer fired and mutated DOM or requested redirect, 0 otherwise. */
int32_t  QjsPageTickTimers(QjsPage *page);

/* Returns 1 if active timers (setTimeout / setInterval) are pending on this page. */
int32_t  QjsPageHasActiveTimers(QjsPage *page);

/* Serialize current live DOM back to malloc'd UTF-8 HTML (free with QjsFreeStr). */
char    *QjsPageSerializeHtml(QjsPage *page, int64_t *out_html_len);

/* If JS set window.location.href / location.replace(...), returns redirect URL ("" if none) and clears it. */
int32_t  QjsPagePopRedirect(QjsPage *page, char *out_url, int64_t out_cap);

int32_t  QjsPageGetScriptCount(QjsPage *page);
void     QjsFreeStr(char *s);

#ifdef __cplusplus
}
#endif

#endif
