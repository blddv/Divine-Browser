/* ============================================================================
 * qjs_bridge.c — Мост движка QuickJS (ES2023) + Live DOM/BOM для DivineWeb v2.0
 * Обеспечивает базовое выполнение JavaScript на сайтах, снятие заглушек
 * "Enable JavaScript", работу querySelector/innerHTML/style/classList/fetch,
 * интерактивные клики (onclick / addEventListener) и таймеры setTimeout.
 * ============================================================================ */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include "quickjs.h"
#include "qjs_bridge.h"

struct QjsPage {
    JSRuntime *rt;
    JSContext *ctx;
    double     deadline_ms;
    int32_t    script_count;
    int32_t    ext_scripts_loaded;
    int32_t    request_count;
    char       page_url[1024];
};

static QjsFetchFn g_qjs_fetch_cb = NULL;

static double now_monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

static int qjs_interrupt_handler(JSRuntime *rt, void *opaque)
{
    (void)rt;
    QjsPage *page = (QjsPage *)opaque;
    if (!page || page->deadline_ms <= 0.0) return 0;
    return (now_monotonic_ms() > page->deadline_ms) ? 1 : 0;
}

void QjsSetFetchCallback(QjsFetchFn fn)
{
    g_qjs_fetch_cb = fn;
}

char *QjsAllocBuf(int64_t size)
{
    if (size <= 0) size = 1;
    return (char *)malloc((size_t)size);
}

void QjsFreeStr(char *s)
{
    if (s) free(s);
}

static JSValue js_native_now_ms(JSContext *ctx, JSValueConst this_val,
                                int argc, JSValueConst *argv)
{
    (void)this_val; (void)argc; (void)argv;
    return JS_NewFloat64(ctx, now_monotonic_ms());
}

static JSValue js_native_inc_script(JSContext *ctx, JSValueConst this_val,
                                    int argc, JSValueConst *argv)
{
    (void)this_val; (void)argc; (void)argv;
    QjsPage *page = (QjsPage *)JS_GetContextOpaque(ctx);
    if (page) page->script_count++;
    return JS_UNDEFINED;
}

/* Network requests are limited to the page's own HTTP(S) origin.  Local
 * files and redirects are not available through the callback. */
static int same_http_origin(const char *a, const char *b)
{
    const char *as = strstr(a, "://"), *bs = strstr(b, "://");
    if (!as || !bs || as-a != bs-b || strncasecmp(a,b,(size_t)(as-a))) return 0;
    if (!((as-a == 4 && !strncasecmp(a,"http",4)) ||
          (as-a == 5 && !strncasecmp(a,"https",5)))) return 0;
    a=as+3; b=bs+3;
    size_t al=strcspn(a,"/?#"), bl=strcspn(b,"/?#");
    return al && al==bl && !memchr(a,'@',al) && !memchr(b,'@',bl) && !strncasecmp(a,b,al);
}

static JSValue js_native_fetch_sync(JSContext *ctx, JSValueConst this_val,
                                    int argc, JSValueConst *argv)
{
    (void)this_val;
    if (argc < 1) return JS_NULL;
    const char *url = JS_ToCString(ctx, argv[0]);
    if (!url) return JS_NULL;

    int is_script = (argc >= 2 && JS_ToBool(ctx, argv[1]) > 0);
    QjsPage *page = (QjsPage *)JS_GetContextOpaque(ctx);

    if (!page || page->request_count++ >= 16 || !same_http_origin(page->page_url, url)) {
        JS_FreeCString(ctx, url);
        return JS_NULL;
    }
    if (is_script && page) {
        if (page->ext_scripts_loaded >= 8) {
            JS_FreeCString(ctx, url);
            return JS_NULL;
        }
        page->ext_scripts_loaded++;
    }

    if (!g_qjs_fetch_cb) {
        JS_FreeCString(ctx, url);
        return JS_NULL;
    }

    /* Продлеваем watchdog на время сетевого запроса */
    double saved_rem = 0.0;
    if (page && page->deadline_ms > 0.0) {
        saved_rem = page->deadline_ms - now_monotonic_ms();
        if (saved_rem < 250.0) saved_rem = 250.0;
    }

    char *body = NULL;
    int64_t body_len = 0;
    int32_t status = 0;
    int32_t ok = g_qjs_fetch_cb(url, &body, &body_len, &status);
    JS_FreeCString(ctx, url);

    if (page && saved_rem > 0.0) {
        page->deadline_ms = now_monotonic_ms() + saved_rem;
    }

    if (!ok || !body) {
        if (body) free(body);
        return JS_NULL;
    }

    /* Ограничиваем огромные бандлы 1.5 МБ, чтобы не тормозить UI */
    if (body_len > 1536 * 1024) {
        free(body);
        return JS_NULL;
    }

    JSValue obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "status", JS_NewInt32(ctx, status > 0 ? status : 200));
    JS_SetPropertyStr(ctx, obj, "body", JS_NewStringLen(ctx, body, (size_t)body_len));
    free(body);
    return obj;
}

static JSValue js_native_eval_global(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv)
{
    (void)this_val;
    if (argc < 1) return JS_UNDEFINED;
    size_t len = 0;
    const char *code = JS_ToCStringLen(ctx, &len, argv[0]);
    if (!code) return JS_UNDEFINED;
    const char *fname = "<inline-script>";
    if (argc >= 2 && JS_IsString(argv[1])) {
        fname = JS_ToCString(ctx, argv[1]);
    }
    JSValue val = JS_Eval(ctx, code, len, fname ? fname : "<script>", JS_EVAL_TYPE_GLOBAL);
    if (argc >= 2 && JS_IsString(argv[1]) && fname) {
        JS_FreeCString(ctx, fname);
    }
    JS_FreeCString(ctx, code);
    if (JS_IsException(val)) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return JS_UNDEFINED;
    }
    JS_FreeValue(ctx, val);
    return JS_UNDEFINED;
}

/* Встроенная легковесная среда браузера (DOM + BOM + Events + Timers + Fetch) */
static const char DOM_BOOTSTRAP_JS[] =
"(function(g){\n"
"  g.window = g; g.self = g; g.top = g; g.parent = g; g.frames = g;\n"
"  let __dirty = false, __redirect = '', __nextQid = 1;\n"
"  let __timers = [], __nextTid = 1, __writeBuf = null;\n"
"  const VOID_TAGS = new Set(['area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr']);\n"
"  const RAW_TAGS  = new Set(['script','style','svg','textarea','title']);\n"
"  function escAttr(s){ return String(s).replace(/&/g,'&amp;').replace(/\"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }\n"
"  function escText(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }\n"
"  function decodeEntities(s){\n"
"    const named = {amp:'&',lt:'<',gt:'>',quot:'\"',apos:String.fromCharCode(39),nbsp:' ',copy:'©',reg:'®',mdash:'—',ndash:'–',bull:'•',hellip:'…',laquo:'«',raquo:'»',larr:'←',rarr:'→',uarr:'↑',darr:'↓',middot:'·',times:'×',starf:'★',star:'☆',trade:'™',euro:'€',plusmn:'±'};\n"
"    return String(s).replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (m,k) => { if(k[0] !== '#') return named[k] === undefined ? m : named[k]; const n = k[1].toLowerCase() === 'x' ? parseInt(k.slice(2),16) : parseInt(k.slice(1),10); return n > 0 && n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : '\ufffd'; });\n"
"  }\n"
"  function camelToKebab(k){ return String(k).replace(/[A-Z]/g, m => '-' + m.toLowerCase()); }\n"
"  function kebabToCamel(k){ return String(k).replace(/-([a-z])/g, (_,c) => c.toUpperCase()); }\n"
"  function resolveUrl(base, rel){\n"
"    if(!rel) return base || '';\n"
"    rel = String(rel).trim();\n"
"    if(/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(rel)) return rel;\n"
"    const m = String(base || 'http://localhost/').match(/^([a-zA-Z]+:\\/\\/[^\\/?#]+)(\\/[^?#]*)?/);\n"
"    if(!m) return rel;\n"
"    const origin = m[1], path = m[2] || '/';\n"
"    if(rel.startsWith('//')) return origin.split('//')[0] + rel;\n"
"    if(rel.startsWith('/')) return origin + rel;\n"
"    const dir = path.slice(0, path.lastIndexOf('/') + 1);\n"
"    return origin + dir + rel;\n"
"  }\n"
"  class Event {\n"
"    constructor(type, opts){ this.type = String(type||''); this.bubbles = !!(opts&&opts.bubbles); this.cancelable = !!(opts&&opts.cancelable); this.defaultPrevented = false; this.propagationStopped = false; this.target = null; this.currentTarget = null; this.detail = opts ? opts.detail : undefined; this.key = (opts&&opts.key)||''; this.keyCode = (opts&&opts.keyCode)||0; }\n"
"    preventDefault(){ this.defaultPrevented = true; }\n"
"    stopPropagation(){ this.propagationStopped = true; }\n"
"    stopImmediatePropagation(){ this.propagationStopped = true; }\n"
"  }\n"
"  class CustomEvent extends Event { constructor(t,o){ super(t,o); } }\n"
"  g.Event = Event; g.CustomEvent = CustomEvent;\n"
"  class EventTarget {\n"
"    constructor(){ this.__ls = Object.create(null); }\n"
"    addEventListener(t, fn){ if(typeof fn !== 'function' && (!fn || typeof fn.handleEvent !== 'function')) return; t = String(t); (this.__ls[t] || (this.__ls[t] = [])).push(fn); if(t === 'click' && this.nodeType === 1) this.__ensureQid(); }\n"
"    removeEventListener(t, fn){ const a = this.__ls[String(t)]; if(!a) return; const i = a.indexOf(fn); if(i >= 0) a.splice(i, 1); }\n"
"    dispatchEvent(ev){\n"
"      if(!ev || !ev.type) return true;\n"
"      if(!ev.target) ev.target = this;\n"
"      let cur = this;\n"
"      while(cur){\n"
"        ev.currentTarget = cur;\n"
"        const prop = 'on' + ev.type;\n"
"        if(typeof cur[prop] === 'function'){ try{ if(cur[prop].call(cur, ev) === false) ev.preventDefault(); }catch(e){} }\n"
"        else if(cur.nodeType === 1 && cur.__attrs && cur.__attrs[prop]){\n"
"          try{ const fn = new Function('event', cur.__attrs[prop]); if(fn.call(cur, ev) === false) ev.preventDefault(); }catch(e){}\n"
"        }\n"
"        const a = cur.__ls && cur.__ls[ev.type];\n"
"        if(a){ for(const fn of a.slice()){ try{ if(typeof fn === 'function') fn.call(cur, ev); else if(fn && fn.handleEvent) fn.handleEvent(ev); }catch(e){} } }\n"
"        if(!ev.bubbles || ev.propagationStopped) break;\n"
"        cur = cur.parentNode;\n"
"      }\n"
"      return !ev.defaultPrevented;\n"
"    }\n"
"  }\n"
"  g.EventTarget = EventTarget;\n"
"  const __qidMap = new Map();\n"
"  class DomNode extends EventTarget {\n"
"    constructor(nt, name){ super(); this.nodeType = nt; this.nodeName = name; this.parentNode = null; this.childNodes = []; this.ownerDocument = null; }\n"
"    get parentElement(){ return (this.parentNode && this.parentNode.nodeType === 1) ? this.parentNode : null; }\n"
"    get firstChild(){ return this.childNodes[0] || null; }\n"
"    get lastChild(){ return this.childNodes[this.childNodes.length - 1] || null; }\n"
"    get nextSibling(){ if(!this.parentNode) return null; const s = this.parentNode.childNodes; const i = s.indexOf(this); return (i >= 0 && i + 1 < s.length) ? s[i+1] : null; }\n"
"    get previousSibling(){ if(!this.parentNode) return null; const s = this.parentNode.childNodes; const i = s.indexOf(this); return i > 0 ? s[i-1] : null; }\n"
"    appendChild(ch){\n"
"      if(!ch) return ch;\n"
"      if(ch.nodeType === 11){ for(const c of ch.childNodes.slice()) this.appendChild(c); return ch; }\n"
"      if(ch.parentNode) ch.parentNode.removeChild(ch);\n"
"      ch.parentNode = this; ch.ownerDocument = this.ownerDocument || (this.nodeType === 9 ? this : null);\n"
"      this.childNodes.push(ch); __dirty = true; return ch;\n"
"    }\n"
"    insertBefore(ch, ref){\n"
"      if(!ref) return this.appendChild(ch);\n"
"      if(ch.nodeType === 11){ for(const c of ch.childNodes.slice()) this.insertBefore(c, ref); return ch; }\n"
"      if(ch.parentNode) ch.parentNode.removeChild(ch);\n"
"      const i = this.childNodes.indexOf(ref);\n"
"      if(i < 0) return this.appendChild(ch);\n"
"      ch.parentNode = this; ch.ownerDocument = this.ownerDocument;\n"
"      this.childNodes.splice(i, 0, ch); __dirty = true; return ch;\n"
"    }\n"
"    removeChild(ch){ const i = this.childNodes.indexOf(ch); if(i >= 0){ this.childNodes.splice(i, 1); ch.parentNode = null; __dirty = true; } return ch; }\n"
"    replaceChild(nw, old){ this.insertBefore(nw, old); return this.removeChild(old); }\n"
"    remove(){ if(this.parentNode) this.parentNode.removeChild(this); }\n"
"    replaceWith(...nodes){ if(!this.parentNode) return; for(const n of nodes) this.parentNode.insertBefore(typeof n === 'string' ? new TextNode(n) : n, this); this.remove(); }\n"
"    append(...nodes){ for(const n of nodes) this.appendChild(typeof n === 'string' ? new TextNode(n) : n); }\n"
"    prepend(...nodes){ const f = this.firstChild; for(const n of nodes) this.insertBefore(typeof n === 'string' ? new TextNode(n) : n, f); }\n"
"    contains(other){ let c = other; while(c){ if(c === this) return true; c = c.parentNode; } return false; }\n"
"    hasChildNodes(){ return this.childNodes.length > 0; }\n"
"    cloneNode(deep){ const cp = new DomNode(this.nodeType, this.nodeName); if(deep){ for(const c of this.childNodes) cp.appendChild(c.cloneNode(true)); } return cp; }\n"
"  }\n"
"  class TextNode extends DomNode {\n"
"    constructor(t){ super(3, '#text'); this.__data = String(t == null ? '' : t); }\n"
"    get data(){ return this.__data; } set data(v){ this.__data = String(v == null ? '' : v); __dirty = true; }\n"
"    get nodeValue(){ return this.__data; } set nodeValue(v){ this.data = v; }\n"
"    get textContent(){ return this.__data; } set textContent(v){ this.data = v; }\n"
"    cloneNode(){ return new TextNode(this.__data); }\n"
"  }\n"
"  function makeStyleProxy(el){\n"
"    const parseMap = () => {\n"
"      const m = Object.create(null), raw = el.__attrs.style || '';\n"
"      for(const part of raw.split(';')){\n"
"        const idx = part.indexOf(':');\n"
"        if(idx > 0){ const k = part.slice(0, idx).trim().toLowerCase(), v = part.slice(idx + 1).trim(); if(k) m[k] = v; }\n"
"      }\n"
"      return m;\n"
"    };\n"
"    const syncMap = (m) => {\n"
"      const out = []; for(const k of Object.keys(m)){ if(m[k] !== '' && m[k] != null) out.push(k + ': ' + m[k]); }\n"
"      if(out.length) el.__attrs.style = out.join('; '); else delete el.__attrs.style;\n"
"      __dirty = true;\n"
"    };\n"
"    const target = {\n"
"      setProperty(k, v){ const m = parseMap(); if(v == null || v === '') delete m[camelToKebab(k)]; else m[camelToKebab(k)] = String(v); syncMap(m); },\n"
"      getPropertyValue(k){ return parseMap()[camelToKebab(k)] || ''; },\n"
"      removeProperty(k){ const m = parseMap(); const old = m[camelToKebab(k)] || ''; delete m[camelToKebab(k)]; syncMap(m); return old; }\n"
"    };\n"
"    return new Proxy(target, {\n"
"      get(t, p){ if(p in t) return t[p]; if(typeof p !== 'string') return undefined; if(p === 'cssText') return el.__attrs.style || ''; return parseMap()[camelToKebab(p)] || ''; },\n"
"      set(t, p, v){ if(typeof p !== 'string') return true; if(p === 'cssText'){ el.__attrs.style = String(v || ''); __dirty = true; return true; } t.setProperty(p, v); return true; }\n"
"    });\n"
"  }\n"
"  function matchSimpleSel(el, sel){\n"
"    if(!el || el.nodeType !== 1) return false;\n"
"    sel = sel.trim().replace(/:(link|visited|hover|active|focus|first-child|last-child)/g, '');\n"
"    if(!sel || sel === '*') return true;\n"
"    const attrRe = /\\[([^\\]=~|^$*]+)(?:([~|^$*]?=)['\"]?([^'\"\\]]*)['\"]?)?\\]/g;\n"
"    let m;\n"
"    while((m = attrRe.exec(sel)) !== null){\n"
"      const ak = m[1].trim().toLowerCase(), op = m[2], av = m[3] || '';\n"
"      if(!el.hasAttribute(ak)) return false;\n"
"      const cur = el.getAttribute(ak) || '';\n"
"      if(op === '=' && cur !== av) return false;\n"
"      if(op === '^=' && !cur.startsWith(av)) return false;\n"
"      if(op === '$=' && !cur.endsWith(av)) return false;\n"
"      if(op === '*=' && !cur.includes(av)) return false;\n"
"    }\n"
"    sel = sel.replace(attrRe, '');\n"
"    const idM = sel.match(/#([A-Za-z0-9_-]+)/);\n"
"    if(idM && el.id !== idM[1]) return false;\n"
"    const clsM = sel.match(/\\.[A-Za-z0-9_-]+/g);\n"
"    if(clsM){\n"
"      const list = (el.className || '').trim().split(/\\s+/);\n"
"      for(const c of clsM){ if(!list.includes(c.slice(1))) return false; }\n"
"    }\n"
"    const tagM = sel.match(/^[A-Za-z][A-Za-z0-9-]*/);\n"
"    if(tagM && el.tag !== tagM[0].toLowerCase()) return false;\n"
"    return true;\n"
"  }\n"
"  function matchSelector(el, fullSel){\n"
"    for(const group of String(fullSel || '').split(',')){\n"
"      const g2 = group.trim(); if(!g2) continue;\n"
"      const tokens = g2.replace(/\\s*>\\s*/g, ' > ').trim().split(/\\s+/);\n"
"      let cur = el, idx = tokens.length - 1, ok = true;\n"
"      if(!matchSimpleSel(cur, tokens[idx])){ continue; }\n"
"      idx--;\n"
"      while(idx >= 0){\n"
"        if(tokens[idx] === '>'){\n"
"          idx--; cur = cur.parentElement;\n"
"          if(!cur || !matchSimpleSel(cur, tokens[idx])){ ok = false; break; }\n"
"          idx--;\n"
"        } else {\n"
"          let p = cur.parentElement, found = false;\n"
"          while(p){ if(matchSimpleSel(p, tokens[idx])){ found = true; cur = p; break; } p = p.parentElement; }\n"
"          if(!found){ ok = false; break; }\n"
"          idx--;\n"
"        }\n"
"      }\n"
"      if(ok) return true;\n"
"    }\n"
"    return false;\n"
"  }\n"
"  class Element extends DomNode {\n"
"    constructor(tag){ super(1, String(tag||'div').toUpperCase()); this.tag = String(tag||'div').toLowerCase(); this.__attrs = Object.create(null); this.__style = null; this.__rawContent = null; this.__value = undefined; this.__checked = false; this.__qid = 0; }\n"
"    get tagName(){ return this.nodeName; }\n"
"    __ensureQid(){ if(!this.__qid){ this.__qid = __nextQid++; __qidMap.set(this.__qid, this); this.__attrs['data-qjs-id'] = String(this.__qid); __dirty = true; } return this.__qid; }\n"
"    get id(){ return this.__attrs.id || ''; } set id(v){ this.setAttribute('id', v); }\n"
"    get className(){ return this.__attrs['class'] || ''; } set className(v){ this.setAttribute('class', v); }\n"
"    get href(){ return this.__attrs.href ? resolveUrl(g.location.href, this.__attrs.href) : ''; } set href(v){ this.setAttribute('href', v); }\n"
"    get src(){ return this.__attrs.src ? resolveUrl(g.location.href, this.__attrs.src) : ''; } set src(v){ this.setAttribute('src', v); }\n"
"    get value(){ return this.__value !== undefined ? this.__value : (this.__attrs.value || ''); } set value(v){ this.__value = String(v == null ? '' : v); this.__attrs.value = this.__value; __dirty = true; }\n"
"    get checked(){ return !!(this.__checked || ('checked' in this.__attrs)); } set checked(v){ this.__checked = !!v; if(v) this.__attrs.checked = ''; else delete this.__attrs.checked; __dirty = true; }\n"
"    get disabled(){ return 'disabled' in this.__attrs; } set disabled(v){ if(v) this.__attrs.disabled = ''; else delete this.__attrs.disabled; __dirty = true; }\n"
"    get hidden(){ return 'hidden' in this.__attrs; } set hidden(v){ if(v){ this.__attrs.hidden = ''; this.style.display = 'none'; } else { delete this.__attrs.hidden; if(this.style.display === 'none') this.style.display = ''; } __dirty = true; }\n"
"    get style(){ return this.__style || (this.__style = makeStyleProxy(this)); } set style(v){ this.__attrs.style = String(v || ''); __dirty = true; }\n"
"    get dataset(){ const el = this; return new Proxy({}, { get(_, p){ return el.getAttribute('data-' + camelToKebab(p)); }, set(_, p, v){ el.setAttribute('data-' + camelToKebab(p), v); return true; }, deleteProperty(_, p){ el.removeAttribute('data-' + camelToKebab(p)); return true; } }); }\n"
"    get classList(){\n"
"      const el = this;\n"
"      const getArr = () => (el.className || '').trim().split(/\\s+/).filter(Boolean);\n"
"      return {\n"
"        add(...cs){ const s = new Set(getArr()); for(const c of cs) if(c) s.add(String(c)); el.className = Array.from(s).join(' '); },\n"
"        remove(...cs){ const s = new Set(getArr()); for(const c of cs) s.delete(String(c)); el.className = Array.from(s).join(' '); },\n"
"        toggle(c, force){ const s = new Set(getArr()); const has = s.has(c); const add = force !== undefined ? !!force : !has; if(add) s.add(c); else s.delete(c); el.className = Array.from(s).join(' '); return add; },\n"
"        contains(c){ return getArr().includes(String(c)); },\n"
"        replace(o, n){ const s = new Set(getArr()); if(s.has(o)){ s.delete(o); s.add(n); el.className = Array.from(s).join(' '); return true; } return false; }\n"
"      };\n"
"    }\n"
"    get onclick(){ return this.__onclick || null; } set onclick(fn){ this.__onclick = fn; if(fn) this.__ensureQid(); }\n"
"    getAttribute(k){ k = String(k).toLowerCase(); return (k in this.__attrs) ? this.__attrs[k] : null; }\n"
"    setAttribute(k, v){ k = String(k).toLowerCase(); this.__attrs[k] = String(v == null ? '' : v); if(k === 'onclick') this.__ensureQid(); __dirty = true; }\n"
"    removeAttribute(k){ delete this.__attrs[String(k).toLowerCase()]; __dirty = true; }\n"
"    hasAttribute(k){ return String(k).toLowerCase() in this.__attrs; }\n"
"    getAttributeNames(){ return Object.keys(this.__attrs); }\n"
"    get attributes(){ return Object.keys(this.__attrs).map(k => ({ name: k, value: this.__attrs[k] })); }\n"
"    get children(){ return this.childNodes.filter(c => c.nodeType === 1); }\n"
"    get childElementCount(){ return this.children.length; }\n"
"    get firstElementChild(){ return this.children[0] || null; }\n"
"    get lastElementChild(){ const c = this.children; return c[c.length - 1] || null; }\n"
"    get nextElementSibling(){ let n = this.nextSibling; while(n && n.nodeType !== 1) n = n.nextSibling; return n; }\n"
"    get previousElementSibling(){ let n = this.previousSibling; while(n && n.nodeType !== 1) n = n.previousSibling; return n; }\n"
"    get textContent(){\n"
"      if(this.__rawContent != null) return this.__rawContent;\n"
"      let s = ''; for(const c of this.childNodes) s += c.textContent || ''; return s;\n"
"    }\n"
"    set textContent(v){\n"
"      const str = String(v == null ? '' : v);\n"
"      if(RAW_TAGS.has(this.tag)){ this.__rawContent = str; this.childNodes = []; __dirty = true; return; }\n"
"      this.__rawContent = null; this.childNodes = [];\n"
"      if(str) this.appendChild(new TextNode(str));\n"
"      __dirty = true;\n"
"    }\n"
"    get innerText(){ return this.textContent; } set innerText(v){ this.textContent = v; }\n"
"    get innerHTML(){\n"
"      if(this.__rawContent != null) return this.__rawContent;\n"
"      let out = ''; for(const c of this.childNodes) out += serializeNode(c); return out;\n"
"    }\n"
"    set innerHTML(html){\n"
"      this.__rawContent = null; this.childNodes = [];\n"
"      const frag = parseHtmlFragment(String(html == null ? '' : html), this.ownerDocument);\n"
"      this.appendChild(frag); __dirty = true;\n"
"    }\n"
"    get outerHTML(){ return serializeNode(this); }\n"
"    insertAdjacentHTML(pos, html){\n"
"      const frag = parseHtmlFragment(String(html || ''), this.ownerDocument);\n"
"      pos = String(pos || '').toLowerCase();\n"
"      if(pos === 'beforeend') this.appendChild(frag);\n"
"      else if(pos === 'afterbegin') this.insertBefore(frag, this.firstChild);\n"
"      else if(pos === 'beforebegin' && this.parentNode) this.parentNode.insertBefore(frag, this);\n"
"      else if(pos === 'afterend' && this.parentNode) this.parentNode.insertBefore(frag, this.nextSibling);\n"
"    }\n"
"    matches(sel){ return matchSelector(this, sel); }\n"
"    closest(sel){ let c = this; while(c && c.nodeType === 1){ if(matchSelector(c, sel)) return c; c = c.parentElement; } return null; }\n"
"    querySelector(sel){ let found = null; const walk = n => { for(const c of n.childNodes){ if(found) return; if(c.nodeType === 1){ if(matchSelector(c, sel)){ found = c; return; } walk(c); } } }; walk(this); return found; }\n"
"    querySelectorAll(sel){ const res = []; const walk = n => { for(const c of n.childNodes){ if(c.nodeType === 1){ if(matchSelector(c, sel)) res.push(c); walk(c); } } }; walk(this); return res; }\n"
"    getElementsByTagName(t){ t = String(t||'').toLowerCase(); const res = []; const walk = n => { for(const c of n.childNodes){ if(c.nodeType === 1){ if(t === '*' || c.tag === t) res.push(c); walk(c); } } }; walk(this); return res; }\n"
"    getElementsByClassName(cls){ const want = String(cls||'').trim().split(/\\s+/).filter(Boolean); if(!want.length) return []; const res = []; const walk = n => { for(const c of n.childNodes){ if(c.nodeType === 1){ const has = want.every(w => c.classList.contains(w)); if(has) res.push(c); walk(c); } } }; walk(this); return res; }\n"
"    getBoundingClientRect(){ return { x: 0, y: 0, top: 0, left: 0, right: 800, bottom: 32, width: 800, height: 32 }; }\n"
"    get offsetWidth(){ return 800; } get offsetHeight(){ return 32; } get clientWidth(){ return 800; } get clientHeight(){ return 32; }\n"
"    focus(){} blur(){} click(){ this.dispatchEvent(new Event('click', { bubbles: true, cancelable: true })); }\n"
"    cloneNode(deep){ const cp = new Element(this.tag); Object.assign(cp.__attrs, this.__attrs); cp.__rawContent = this.__rawContent; if(deep){ for(const c of this.childNodes) cp.appendChild(c.cloneNode(true)); } return cp; }\n"
"  }\n"
"  class DocumentFragment extends DomNode { constructor(){ super(11, '#document-fragment'); } querySelector(s){ return Element.prototype.querySelector.call(this, s); } querySelectorAll(s){ return Element.prototype.querySelectorAll.call(this, s); } }\n"
"  function parseAttrs(raw, el){\n"
"    const re = /([A-Za-z_:][A-Za-z0-9_.:-]*)(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+)))?/g;\n"
"    let m;\n"
"    while((m = re.exec(raw)) !== null){\n"
"      const k = m[1].toLowerCase();\n"
"      const v = m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : ''));\n"
"      el.__attrs[k] = decodeEntities(v);\n"
"      if(k === 'onclick' || el.tag === 'button') el.__ensureQid();\n"
"    }\n"
"    if(el.tag === 'button') el.__ensureQid();\n"
"  }\n"
"  function parseHtmlFragment(html, ownerDoc){\n"
"    const frag = new DocumentFragment(); frag.ownerDocument = ownerDoc;\n"
"    let stack = [frag], i = 0, n = html.length;\n"
"    while(i < n){\n"
"      if(html.startsWith('<!--', i)){ const e = html.indexOf('-->', i + 4); i = e >= 0 ? e + 3 : n; continue; }\n"
"      if(html[i] === '<'){\n"
"        if(html[i+1] === '!' || html[i+1] === '?'){ const e = html.indexOf('>', i + 2); i = e >= 0 ? e + 1 : n; continue; }\n"
"        let j = i + 1, q = '';\n"
"        while(j < n){ const c = html[j]; if(q){ if(c === q) q = ''; } else if(c === '\"' || c === \"'\") q = c; else if(c === '>') break; j++; }\n"
"        if(j >= n) break;\n"
"        let inside = html.slice(i + 1, j).trim(); i = j + 1;\n"
"        let closing = false;\n"
"        if(inside.startsWith('/')){ closing = true; inside = inside.slice(1).trim(); }\n"
"        let selfClose = false;\n"
"        if(!closing && inside.endsWith('/')){ selfClose = true; inside = inside.slice(0, -1).trim(); }\n"
"        const sp = inside.search(/\\s/);\n"
"        const tname = (sp >= 0 ? inside.slice(0, sp) : inside).toLowerCase();\n"
"        const attrStr = sp >= 0 ? inside.slice(sp + 1) : '';\n"
"        if(!tname) continue;\n"
"        if(tname === 'noscript'){\n"
"          if(!closing){ const cl = html.toLowerCase().indexOf('</noscript', i); if(cl >= 0){ const gt = html.indexOf('>', cl); i = gt >= 0 ? gt + 1 : n; } else i = n; }\n"
"          continue;\n"
"        }\n"
"        if(closing){\n"
"          for(let k = stack.length - 1; k >= 1; k--){ if(stack[k].tag === tname){ stack.length = k; break; } }\n"
"          continue;\n"
"        }\n"
"        if(tname === 'p' && stack[stack.length - 1].tag === 'p') stack.pop();\n"
"        if(tname === 'li' && stack[stack.length - 1].tag === 'li') stack.pop();\n"
"        const el = new Element(tname); el.ownerDocument = ownerDoc;\n"
"        parseAttrs(attrStr, el);\n"
"        stack[stack.length - 1].appendChild(el);\n"
"        if(RAW_TAGS.has(tname) && !selfClose){\n"
"          const pat = '</' + tname;\n"
"          const low = html.toLowerCase();\n"
"          let closeIdx = low.indexOf(pat, i);\n"
"          if(closeIdx >= 0){\n"
"            el.__rawContent = html.slice(i, closeIdx);\n"
"            const gt = html.indexOf('>', closeIdx + pat.length);\n"
"            i = gt >= 0 ? gt + 1 : n;\n"
"          } else { el.__rawContent = html.slice(i); i = n; }\n"
"          continue;\n"
"        }\n"
"        if(!selfClose && !VOID_TAGS.has(tname)) stack.push(el);\n"
"        continue;\n"
"      }\n"
"      const nxt = html.indexOf('<', i);\n"
"      const txt = nxt >= 0 ? html.slice(i, nxt) : html.slice(i);\n"
"      i = nxt >= 0 ? nxt : n;\n"
"      if(txt) stack[stack.length - 1].appendChild(new TextNode(decodeEntities(txt)));\n"
"    }\n"
"    return frag;\n"
"  }\n"
"  function serializeNode(node){\n"
"    if(!node) return '';\n"
"    if(node.nodeType === 3) return escText(node.__data);\n"
"    if(node.nodeType === 11 || node.nodeType === 9){ let s = ''; for(const c of node.childNodes) s += serializeNode(c); return s; }\n"
"    if(node.nodeType !== 1) return '';\n"
"    if(node.tag === 'script' || node.tag === 'noscript') return '';\n"
"    let out = '<' + node.tag;\n"
"    for(const k of Object.keys(node.__attrs)){\n"
"      const v = node.__attrs[k];\n"
"      out += v === '' ? (' ' + k) : (' ' + k + '=\"' + escAttr(v) + '\"');\n"
"    }\n"
"    out += '>';\n"
"    if(VOID_TAGS.has(node.tag)) return out;\n"
"    if(node.__rawContent != null) return out + node.__rawContent + '</' + node.tag + '>';\n"
"    for(const c of node.childNodes) out += serializeNode(c);\n"
"    return out + '</' + node.tag + '>';\n"
"  }\n"
"  class Document extends DomNode {\n"
"    constructor(){ super(9, '#document'); this.readyState = 'loading'; this.cookie = ''; this.compatMode = 'CSS1Compat'; this.characterSet = 'UTF-8'; this.documentElement = new Element('html'); this.head = new Element('head'); this.body = new Element('body'); this.documentElement.appendChild(this.head); this.documentElement.appendChild(this.body); this.appendChild(this.documentElement); }\n"
"    get title(){ const t = this.querySelector('title'); return t ? t.textContent : ''; }\n"
"    set title(v){ let t = this.querySelector('title'); if(!t){ t = this.createElement('title'); (this.head || this.documentElement).appendChild(t); } t.textContent = v; }\n"
"    createElement(tag){ const e = new Element(tag); e.ownerDocument = this; return e; }\n"
"    createElementNS(_, tag){ return this.createElement(tag); }\n"
"    createTextNode(t){ const n = new TextNode(t); n.ownerDocument = this; return n; }\n"
"    createComment(){ return new TextNode(''); }\n"
"    createDocumentFragment(){ const f = new DocumentFragment(); f.ownerDocument = this; return f; }\n"
"    createEvent(){ const e = new Event(''); e.initEvent = function(t,b,c){ this.type=t; this.bubbles=!!b; this.cancelable=!!c; }; return e; }\n"
"    getElementById(id){ const w = String(id||''); if(!w) return null; let f = null; const walk = n => { for(const c of n.childNodes){ if(f) return; if(c.nodeType === 1){ if(c.__attrs.id === w){ f = c; return; } walk(c); } } }; walk(this); return f; }\n"
"    querySelector(s){ return Element.prototype.querySelector.call(this, s); }\n"
"    querySelectorAll(s){ return Element.prototype.querySelectorAll.call(this, s); }\n"
"    getElementsByTagName(t){ return Element.prototype.getElementsByTagName.call(this, t); }\n"
"    getElementsByClassName(c){ return Element.prototype.getElementsByClassName.call(this, c); }\n"
"    getElementsByName(nm){ return this.querySelectorAll('[name=\"' + nm + '\"]'); }\n"
"    get forms(){ return this.getElementsByTagName('form'); }\n"
"    get links(){ return this.getElementsByTagName('a'); }\n"
"    get images(){ return this.getElementsByTagName('img'); }\n"
"    get scripts(){ return this.getElementsByTagName('script'); }\n"
"    write(...args){ const s = args.join(''); if(__writeBuf !== null) __writeBuf.push(s); else if(this.body) this.body.insertAdjacentHTML('beforeend', s); __dirty = true; }\n"
"    writeln(...args){ this.write(args.join('') + '\\n'); }\n"
"    open(){} close(){}\n"
"  }\n"
"  function makeStorage(){\n"
"    const store = Object.create(null);\n"
"    const api = {\n"
"      getItem(k){ return (k in store) ? store[k] : null; },\n"
"      setItem(k, v){ store[String(k)] = String(v); },\n"
"      removeItem(k){ delete store[String(k)]; },\n"
"      clear(){ for(const k of Object.keys(store)) delete store[k]; },\n"
"      key(i){ return Object.keys(store)[i] || null; },\n"
"      get length(){ return Object.keys(store).length; }\n"
"    };\n"
"    return new Proxy(api, { get(t, p){ if(p in t) return t[p]; return (typeof p === 'string' && p in store) ? store[p] : undefined; }, set(t, p, v){ if(typeof p === 'string' && !(p in t)) store[p] = String(v); return true; } });\n"
"  }\n"
"  g.localStorage = makeStorage(); g.sessionStorage = makeStorage();\n"
"  g.navigator = { userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 DivineWeb/2.0 QuickJS/ES2023', appName: 'Netscape', platform: 'Linux x86_64', language: 'ru-RU', languages: ['ru-RU','en-US'], cookieEnabled: true, onLine: true, webdriver: false, hardwareConcurrency: 4, clipboard: { writeText(){ return Promise.resolve(); } } };\n"
"  g.screen = { width: 1280, height: 800, availWidth: 1280, availHeight: 760, colorDepth: 24, pixelDepth: 24 };\n"
"  g.devicePixelRatio = 1;\n"
"  g.console = { log(){}, info(){}, warn(){}, error(){}, debug(){}, dir(){}, table(){}, time(){}, timeEnd(){} };\n"
"  g.alert = function(){}; g.confirm = function(){ return true; }; g.prompt = function(_, d){ return d || ''; };\n"
"  g.performance = { now(){ return __native_now_ms(); }, timing: { navigationStart: Date.now() } };\n"
"  g.matchMedia = q => ({ matches: !String(q||'').includes('max-width: 4'), media: String(q||''), addListener(){}, removeListener(){}, addEventListener(){}, removeEventListener(){} });\n"
"  g.getComputedStyle = el => (el && el.style) ? el.style : { getPropertyValue(){ return ''; } };\n"
"  g.MutationObserver = class { constructor(){} observe(){} disconnect(){} takeRecords(){ return []; } };\n"
"  g.IntersectionObserver = class { constructor(cb){ this.cb = cb; } observe(el){ try{ this.cb([{ isIntersecting: true, intersectionRatio: 1, target: el }], this); }catch(e){} } unobserve(){} disconnect(){} };\n"
"  g.ResizeObserver = class { observe(){} unobserve(){} disconnect(){} };\n"
"  g.DOMParser = class { parseFromString(str){ const d = new Document(); const f = parseHtmlFragment(String(str||''), d); d.body.childNodes = []; d.body.appendChild(f); return d; } };\n"
"  const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';\n"
"  g.btoa = function(s){ s = String(s); let o = '', i = 0; while(i < s.length){ const a = s.charCodeAt(i++) & 255, b = i < s.length ? s.charCodeAt(i++) & 255 : NaN, c = i < s.length ? s.charCodeAt(i++) & 255 : NaN; o += B64[a>>2] + B64[((a&3)<<4)|((b||0)>>4)] + (isNaN(b)?'=':B64[((b&15)<<2)|((c||0)>>6)]) + (isNaN(c)?'=':B64[c&63]); } return o; };\n"
"  g.atob = function(s){ s = String(s).replace(/=+$/,'').replace(/[^A-Za-z0-9+/]/g,''); let o = '', i = 0; while(i < s.length){ const a = B64.indexOf(s[i++]), b = B64.indexOf(s[i++]), c = i < s.length ? B64.indexOf(s[i++]) : -1, d = i < s.length ? B64.indexOf(s[i++]) : -1; o += String.fromCharCode((a<<2)|(b>>4)); if(c >= 0) o += String.fromCharCode(((b&15)<<4)|(c>>2)); if(d >= 0) o += String.fromCharCode(((c&3)<<6)|d); } return o; };\n"
"  g.URLSearchParams = class {\n"
"    constructor(q){ this.__m = []; q = String(q||'').replace(/^\\?/,''); if(q) for(const p of q.split('&')){ if(!p) continue; const eq = p.indexOf('='); this.__m.push([decodeURIComponent(eq>=0?p.slice(0,eq):p), decodeURIComponent(eq>=0?p.slice(eq+1):'')]); } }\n"
"    get(k){ const f = this.__m.find(x => x[0] === k); return f ? f[1] : null; }\n"
"    has(k){ return this.__m.some(x => x[0] === k); }\n"
"    set(k,v){ this.delete(k); this.__m.push([String(k), String(v)]); }\n"
"    append(k,v){ this.__m.push([String(k), String(v)]); }\n"
"    delete(k){ this.__m = this.__m.filter(x => x[0] !== k); }\n"
"    toString(){ return this.__m.map(x => encodeURIComponent(x[0]) + '=' + encodeURIComponent(x[1])).join('&'); }\n"
"  };\n"
"  function parseUrlObj(u, base){\n"
"    const full = base ? resolveUrl(base, u) : String(u || 'http://localhost/');\n"
"    const m = full.match(/^([a-zA-Z][a-zA-Z0-9+.-]*:)(?:\\/\\/([^\\/?#]*))?([^?#]*)(\\?[^#]*)?(#.*)?$/) || [];\n"
"    const protocol = m[1] || 'http:', host = m[2] || '', pathname = m[3] || '/', search = m[4] || '', hash = m[5] || '';\n"
"    const hm = host.split(':');\n"
"    return { href: full, protocol, host, hostname: hm[0]||'', port: hm[1]||'', pathname, search, hash, origin: protocol + '//' + host, searchParams: new g.URLSearchParams(search), toString(){ return this.href; } };\n"
"  }\n"
"  g.URL = function(u, base){ Object.assign(this, parseUrlObj(u, base)); };\n"
"  let __curUrl = 'http://localhost/';\n"
"  g.location = {\n"
"    get href(){ return __curUrl; },\n"
"    set href(v){ __redirect = resolveUrl(__curUrl, v); __curUrl = __redirect; },\n"
"    assign(v){ this.href = v; }, replace(v){ this.href = v; }, reload(){ __redirect = __curUrl; },\n"
"    get protocol(){ return parseUrlObj(__curUrl).protocol; },\n"
"    get host(){ return parseUrlObj(__curUrl).host; },\n"
"    get hostname(){ return parseUrlObj(__curUrl).hostname; },\n"
"    get pathname(){ return parseUrlObj(__curUrl).pathname; },\n"
"    get search(){ return parseUrlObj(__curUrl).search; },\n"
"    get hash(){ return parseUrlObj(__curUrl).hash; },\n"
"    get origin(){ return parseUrlObj(__curUrl).origin; },\n"
"    toString(){ return __curUrl; }\n"
"  };\n"
"  g.history = { length: 1, state: null, pushState(st, _, u){ this.state = st; if(u) __curUrl = resolveUrl(__curUrl, u); }, replaceState(st, _, u){ this.state = st; if(u) __curUrl = resolveUrl(__curUrl, u); }, back(){}, forward(){}, go(){} };\n"
"  g.setTimeout = function(fn, ms, ...args){ const id = __nextTid++; const d = Math.max(0, Number(ms)||0); __timers.push({ id, fn, args, due: __native_now_ms() + d, iv: 0 }); return id; };\n"
"  g.setInterval = function(fn, ms, ...args){ const id = __nextTid++; const d = Math.max(16, Number(ms)||16); __timers.push({ id, fn, args, due: __native_now_ms() + d, iv: d }); return id; };\n"
"  g.clearTimeout = g.clearInterval = function(id){ __timers = __timers.filter(t => t.id !== id); };\n"
"  g.requestAnimationFrame = function(fn){ return g.setTimeout(() => fn(__native_now_ms()), 16); };\n"
"  g.cancelAnimationFrame = g.clearTimeout;\n"
"  g.queueMicrotask = fn => Promise.resolve().then(fn);\n"
"  g.fetch = function(input){\n"
"    const u = resolveUrl(__curUrl, typeof input === 'string' ? input : (input && input.url) || '');\n"
"    return new Promise((resolve, reject) => {\n"
"      const r = __native_fetch_sync(u, false);\n"
"      if(!r) return reject(new Error('Network error'));\n"
"      const st = r.status || 200, body = r.body || '';\n"
"      resolve({ status: st, ok: st >= 200 && st < 300, url: u, headers: { get(){ return null; } }, text: () => Promise.resolve(body), json: () => Promise.resolve(JSON.parse(body)) });\n"
"    });\n"
"  };\n"
"  g.XMLHttpRequest = class extends EventTarget {\n"
"    constructor(){ super(); this.readyState = 0; this.status = 0; this.responseText = ''; this.response = ''; }\n"
"    open(m, u){ this.__u = resolveUrl(__curUrl, u); this.readyState = 1; }\n"
"    setRequestHeader(){}\n"
"    getAllResponseHeaders(){ return ''; } getResponseHeader(){ return null; }\n"
"    send(){\n"
"      const r = __native_fetch_sync(this.__u, false);\n"
"      this.readyState = 4;\n"
"      if(r){ this.status = r.status || 200; this.responseText = this.response = r.body || ''; }\n"
"      else { this.status = 0; }\n"
"      this.dispatchEvent(new Event('readystatechange'));\n"
"      if(this.status >= 200) this.dispatchEvent(new Event('load')); else this.dispatchEvent(new Event('error'));\n"
"    }\n"
"  };\n"
"  const winET = new EventTarget();\n"
"  g.addEventListener = winET.addEventListener.bind(winET);\n"
"  g.removeEventListener = winET.removeEventListener.bind(winET);\n"
"  g.dispatchEvent = winET.dispatchEvent.bind(winET);\n"
"  g.document = new Document();\n"
"  g.__qjsLoadPage = function(rawHtml, url){\n"
"    __curUrl = url || 'http://localhost/'; __redirect = ''; __dirty = false; __timers = []; __qidMap.clear(); __nextQid = 1;\n"
"    const doc = new Document(); g.document = doc;\n"
"    const frag = parseHtmlFragment(String(rawHtml || ''), doc);\n"
"    const htmlEl = frag.querySelector('html');\n"
"    if(htmlEl){\n"
"      doc.childNodes = []; doc.documentElement = htmlEl; doc.appendChild(htmlEl);\n"
"      doc.head = htmlEl.querySelector('head') || doc.createElement('head');\n"
"      if(!doc.head.parentNode) htmlEl.insertBefore(doc.head, htmlEl.firstChild);\n"
"      doc.body = htmlEl.querySelector('body') || doc.createElement('body');\n"
"      if(!doc.body.parentNode) htmlEl.appendChild(doc.body);\n"
"    } else {\n"
"      doc.body.childNodes = []; doc.body.appendChild(frag);\n"
"    }\n"
"    const scripts = doc.querySelectorAll('script');\n"
"    for(const sc of scripts){\n"
"      const tp = (sc.getAttribute('type') || '').trim().toLowerCase();\n"
"      if(tp && tp !== 'text/javascript' && tp !== 'application/javascript' && tp !== 'module') continue;\n"
"      let code = sc.__rawContent || sc.textContent || '', name = '<inline>';\n"
"      const srcAttr = sc.getAttribute('src');\n"
"      if(srcAttr){\n"
"        const su = resolveUrl(__curUrl, srcAttr);\n"
"        const res = __native_fetch_sync(su, true);\n"
"        if(!res || !res.body) continue;\n"
"        code = res.body; name = su;\n"
"      }\n"
"      if(!code.trim()) continue;\n"
"      if(tp === 'module') code = code.replace(/^\\s*export\\s+default\\s+/gm, '').replace(/^\\s*export\\s+(?=const|let|var|function|class)/gm, '').replace(/^\\s*import\\s+[^;\\n]+[;\\n]/gm, '');\n"
"      __writeBuf = [];\n"
"      __native_inc_script();\n"
"      __native_eval_global(code, name);\n"
"      if(__writeBuf.length && sc.parentNode){\n"
"        const wf = parseHtmlFragment(__writeBuf.join(''), doc);\n"
"        sc.parentNode.insertBefore(wf, sc.nextSibling);\n"
"      }\n"
"      __writeBuf = null;\n"
"      if(__redirect) break;\n"
"    }\n"
"    doc.readyState = 'interactive';\n"
"    doc.dispatchEvent(new Event('DOMContentLoaded', { bubbles: true }));\n"
"    doc.readyState = 'complete';\n"
"    g.dispatchEvent(new Event('load'));\n"
"    g.__qjsRunDueTimers(65);\n"
"  };\n"
"  g.__qjsRunDueTimers = function(extraMs){\n"
"    const cutoff = __native_now_ms() + (extraMs || 0);\n"
"    let fired = 0;\n"
"    while(fired < 24){\n"
"      let pick = -1, best = Infinity;\n"
"      for(let i = 0; i < __timers.length; i++){ if(__timers[i].due <= cutoff && __timers[i].due < best){ best = __timers[i].due; pick = i; } }\n"
"      if(pick < 0) break;\n"
"      const t = __timers[pick];\n"
"      if(t.iv > 0) t.due = __native_now_ms() + t.iv; else __timers.splice(pick, 1);\n"
"      fired++;\n"
"      try{ if(typeof t.fn === 'function') t.fn(...t.args); else if(typeof t.fn === 'string') __native_eval_global(t.fn, '<timer>'); }catch(e){}\n"
"      if(__redirect) break;\n"
"    }\n"
"    return (__dirty || !!__redirect) ? 1 : 0;\n"
"  };\n"
"  g.__qjsClickId = function(id){\n"
"    __dirty = false;\n"
"    const el = __qidMap.get(Number(id));\n"
"    if(!el) return 0;\n"
"    const ev = new Event('click', { bubbles: true, cancelable: true });\n"
"    el.dispatchEvent(ev);\n"
"    const a = el.closest('a');\n"
"    if(!ev.defaultPrevented && !__redirect && a && a.getAttribute('href')){ const href = a.getAttribute('href'); if(/^javascript:/i.test(href)) __native_eval_global(href.slice(11), '<javascript-url>'); else if(href[0] !== '#') g.location.href = href; }\n"
"    g.__qjsRunDueTimers(35);\n"
"    return (__dirty || !!__redirect) ? 1 : 0;\n"
"  };\n"
"  g.__qjsConsumeDirty = function(){ const d = (__dirty || !!__redirect) ? 1 : 0; __dirty = false; return d; };\n"
"  g.__qjsHasTimers = function(){ return __timers.length > 0 ? 1 : 0; };\n"
"  g.__qjsPopRedirect = function(){ const r = __redirect || ''; __redirect = ''; return r; };\n"
"  g.__qjsSerialize = function(){\n"
"    for(const [qid, el] of __qidMap.entries()){ el.__attrs['data-qjs-id'] = String(qid); }\n"
"    return '<!DOCTYPE html>' + serializeNode(g.document.documentElement);\n"
"  };\n"
"})(globalThis);\n";

static void qjs_consume_dirty(QjsPage *page)
{
    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsConsumeDirty");
    JSValue r = JS_Call(page->ctx, fn, global, 0, NULL);
    if (JS_IsException(r)) { JSValue e = JS_GetException(page->ctx); JS_FreeValue(page->ctx, e); }
    JS_FreeValue(page->ctx, r); JS_FreeValue(page->ctx, fn); JS_FreeValue(page->ctx, global);
}

static void qjs_drain_jobs(QjsPage *page)
{
    JSContext *ctx1 = NULL;
    int guard = 0;
    while (guard++ < 256) {
        int err = JS_ExecutePendingJob(page->rt, &ctx1);
        if (err <= 0) break;
    }
}

QjsPage *QjsPageCreate(void)
{
    QjsPage *page = (QjsPage *)calloc(1, sizeof(QjsPage));
    if (!page) return NULL;

    page->rt = JS_NewRuntime();
    if (!page->rt) {
        free(page);
        return NULL;
    }

    JS_SetMemoryLimit(page->rt, 64 * 1024 * 1024);
    JS_SetMaxStackSize(page->rt, 1024 * 1024);
    JS_SetInterruptHandler(page->rt, qjs_interrupt_handler, page);

    page->ctx = JS_NewContext(page->rt);
    if (!page->ctx) {
        JS_FreeRuntime(page->rt);
        free(page);
        return NULL;
    }
    JS_SetContextOpaque(page->ctx, page);

    JSValue global = JS_GetGlobalObject(page->ctx);
    JS_SetPropertyStr(page->ctx, global, "__native_now_ms",
                      JS_NewCFunction(page->ctx, js_native_now_ms, "__native_now_ms", 0));
    JS_SetPropertyStr(page->ctx, global, "__native_fetch_sync",
                      JS_NewCFunction(page->ctx, js_native_fetch_sync, "__native_fetch_sync", 2));
    JS_SetPropertyStr(page->ctx, global, "__native_eval_global",
                      JS_NewCFunction(page->ctx, js_native_eval_global, "__native_eval_global", 2));
    JS_SetPropertyStr(page->ctx, global, "__native_inc_script",
                      JS_NewCFunction(page->ctx, js_native_inc_script, "__native_inc_script", 0));
    JS_FreeValue(page->ctx, global);

    page->deadline_ms = now_monotonic_ms() + 1000.0;
    JSValue boot = JS_Eval(page->ctx, DOM_BOOTSTRAP_JS, sizeof(DOM_BOOTSTRAP_JS) - 1,
                           "<dom-bootstrap>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(boot)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
    }
    JS_FreeValue(page->ctx, boot);
    page->deadline_ms = 0.0;

    return page;
}

void QjsPageDestroy(QjsPage *page)
{
    if (!page) return;
    if (page->ctx) JS_FreeContext(page->ctx);
    if (page->rt)  JS_FreeRuntime(page->rt);
    free(page);
}

char *QjsPageSerializeHtml(QjsPage *page, int64_t *out_html_len)
{
    if (out_html_len) *out_html_len = 0;
    if (!page || !page->ctx) return NULL;

    page->deadline_ms = now_monotonic_ms() + 300.0;
    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsSerialize");
    JSValue res = JS_Call(page->ctx, fn, global, 0, NULL);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);

    if (JS_IsException(res)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
        page->deadline_ms = 0.0;
        return NULL;
    }

    size_t slen = 0;
    const char *cstr = JS_ToCStringLen(page->ctx, &slen, res);
    char *copy = NULL;
    if (cstr) {
        copy = (char *)malloc(slen + 1);
        if (copy) {
            memcpy(copy, cstr, slen);
            copy[slen] = '\0';
            if (out_html_len) *out_html_len = (int64_t)slen;
        }
        JS_FreeCString(page->ctx, cstr);
    }
    JS_FreeValue(page->ctx, res);
    page->deadline_ms = 0.0;
    return copy;
}

char *QjsPageLoadHtml(QjsPage *page, const char *html, int64_t html_len,
                      const char *page_url, int64_t *out_html_len)
{
    if (out_html_len) *out_html_len = 0;
    if (!page || !page->ctx || !html || html_len <= 0) return NULL;

    page->script_count = 0;
    page->ext_scripts_loaded = 0;
    page->request_count = 0;
    snprintf(page->page_url, sizeof(page->page_url), "%s", page_url ? page_url : "http://localhost/");

    page->deadline_ms = now_monotonic_ms() + 750.0;

    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsLoadPage");
    JSValue args[2];
    args[0] = JS_NewStringLen(page->ctx, html, (size_t)html_len);
    args[1] = JS_NewString(page->ctx, page->page_url);

    JSValue ret = JS_Call(page->ctx, fn, global, 2, args);
    JS_FreeValue(page->ctx, args[0]);
    JS_FreeValue(page->ctx, args[1]);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);

    if (JS_IsException(ret)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
    } else {
        JS_FreeValue(page->ctx, ret);
    }

    qjs_drain_jobs(page);

    /* Выполняем таймеры 0ms после завершения Promise.then() */
    global = JS_GetGlobalObject(page->ctx);
    JSValue tfn = JS_GetPropertyStr(page->ctx, global, "__qjsRunDueTimers");
    JSValue targ = JS_NewInt32(page->ctx, 30);
    JSValue tret = JS_Call(page->ctx, tfn, global, 1, &targ);
    JS_FreeValue(page->ctx, targ);
    JS_FreeValue(page->ctx, tfn);
    JS_FreeValue(page->ctx, global);
    if (JS_IsException(tret)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
    } else {
        JS_FreeValue(page->ctx, tret);
    }
    qjs_drain_jobs(page);
    global = JS_GetGlobalObject(page->ctx);
    JSValue clear_fn = JS_GetPropertyStr(page->ctx, global, "__qjsConsumeDirty");
    JSValue clear_val = JS_Call(page->ctx, clear_fn, global, 0, NULL);
    if (JS_IsException(clear_val)) { JSValue e = JS_GetException(page->ctx); JS_FreeValue(page->ctx, e); }
    JS_FreeValue(page->ctx, clear_val);
    JS_FreeValue(page->ctx, clear_fn);
    JS_FreeValue(page->ctx, global);
    page->deadline_ms = 0.0;

    return QjsPageSerializeHtml(page, out_html_len);
}

int32_t QjsPageClickId(QjsPage *page, int32_t qjs_id)
{
    if (!page || !page->ctx || qjs_id <= 0) return 0;
    page->deadline_ms = now_monotonic_ms() + 300.0;

    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsClickId");
    JSValue arg = JS_NewInt32(page->ctx, qjs_id);
    JSValue res = JS_Call(page->ctx, fn, global, 1, &arg);
    JS_FreeValue(page->ctx, arg);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);

    int32_t changed = 0;
    if (JS_IsException(res)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
    } else {
        JS_ToInt32(page->ctx, &changed, res);
        JS_FreeValue(page->ctx, res);
    }
    qjs_drain_jobs(page);
    qjs_consume_dirty(page);
    page->deadline_ms = 0.0;
    return changed;
}

int32_t QjsPageEvalUrl(QjsPage *page, const char *js_code)
{
    if (!page || !page->ctx || !js_code) return 0;
    if (strncasecmp(js_code, "javascript:", 11) == 0) js_code += 11;
    while (*js_code == ' ') js_code++;
    if (*js_code == '\0') return 0;

    page->deadline_ms = now_monotonic_ms() + 300.0;
    JSValue val = JS_Eval(page->ctx, js_code, strlen(js_code), "<javascript-url>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(val)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
    } else {
        JS_FreeValue(page->ctx, val);
    }
    qjs_drain_jobs(page);

    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsConsumeDirty");
    JSValue res = JS_Call(page->ctx, fn, global, 0, NULL);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);

    int32_t changed = 0;
    if (!JS_IsException(res)) JS_ToInt32(page->ctx, &changed, res);
    else { JSValue exc = JS_GetException(page->ctx); JS_FreeValue(page->ctx, exc); }
    JS_FreeValue(page->ctx, res);
    page->deadline_ms = 0.0;
    return changed;
}

int32_t QjsPageTickTimers(QjsPage *page)
{
    if (!page || !page->ctx) return 0;
    page->deadline_ms = now_monotonic_ms() + 120.0;

    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsRunDueTimers");
    JSValue arg = JS_NewInt32(page->ctx, 0);
    JSValue res = JS_Call(page->ctx, fn, global, 1, &arg);
    JS_FreeValue(page->ctx, arg);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);

    int32_t changed = 0;
    if (!JS_IsException(res)) JS_ToInt32(page->ctx, &changed, res);
    else { JSValue exc = JS_GetException(page->ctx); JS_FreeValue(page->ctx, exc); }
    JS_FreeValue(page->ctx, res);

    if (changed) qjs_drain_jobs(page);
    qjs_consume_dirty(page);
    page->deadline_ms = 0.0;
    return changed;
}

int32_t QjsPageHasActiveTimers(QjsPage *page)
{
    if (!page || !page->ctx) return 0;
    page->deadline_ms = now_monotonic_ms() + 120.0;
    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsHasTimers");
    JSValue res = JS_Call(page->ctx, fn, global, 0, NULL);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);
    int32_t has = 0;
    if (!JS_IsException(res)) JS_ToInt32(page->ctx, &has, res);
    else { JSValue exc = JS_GetException(page->ctx); JS_FreeValue(page->ctx, exc); }
    JS_FreeValue(page->ctx, res);
    page->deadline_ms = 0.0;
    return has;
}

int32_t QjsPagePopRedirect(QjsPage *page, char *out_url, int64_t out_cap)
{
    if (out_url && out_cap > 0) out_url[0] = '\0';
    if (!page || !page->ctx || !out_url || out_cap <= 1) return 0;
    page->deadline_ms = now_monotonic_ms() + 120.0;

    JSValue global = JS_GetGlobalObject(page->ctx);
    JSValue fn = JS_GetPropertyStr(page->ctx, global, "__qjsPopRedirect");
    JSValue res = JS_Call(page->ctx, fn, global, 0, NULL);
    JS_FreeValue(page->ctx, fn);
    JS_FreeValue(page->ctx, global);

    if (JS_IsException(res)) {
        JSValue exc = JS_GetException(page->ctx);
        JS_FreeValue(page->ctx, exc);
        page->deadline_ms = 0.0;
        return 0;
    }

    const char *s = JS_ToCString(page->ctx, res);
    int32_t got = 0;
    if (s && s[0] != '\0') {
        snprintf(out_url, (size_t)out_cap, "%s", s);
        got = 1;
    }
    if (s) JS_FreeCString(page->ctx, s);
    JS_FreeValue(page->ctx, res);
    page->deadline_ms = 0.0;
    return got;
}

int32_t QjsPageGetScriptCount(QjsPage *page)
{
    return page ? page->script_count : 0;
}
