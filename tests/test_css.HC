#include "../bindings.HH"
#include "../url_http.HC"
#include "../image_loader.HC"
#include "../css_legacy.HC"
#include "../html_dom.HC"

I32 Main(I32 argc, U8 **argv)
{
  U8 *html = "<style>body{background:#112233;color:#123456}.hide{display:none}.same{color:blue} div .same{color:green} #x{color:red}</style><body><p class='hide'>HIDDEN</p><div><p class='same' id='x' style='font-size:24px'>VISIBLE</p></div><noscript>FALLBACK</noscript></body>";
  HtmlDocument d;
  ParseHtmlDocument(html, StrLen(html), "file://test.html", &d);
  I32 visible = 0, hidden = 0, fallback = 0;
  for (I64 i = 0; i < d.node_count; i++) {
    DocNode *n = &d.nodes[i];
    if (n->text == NULL) continue;
    if (StrCmp(n->text, "HIDDEN") == 0) hidden++;
    if (StrCmp(n->text, "FALLBACK") == 0) fallback++;
    if (StrCmp(n->text, "VISIBLE") == 0 && n->has_fg_color && n->fg_rgb == 0xff0000 && n->css_font_px == 24) visible++;
  }
  Bool ok = visible == 1 && hidden == 0 && fallback == 1 && d.has_css_bg && d.css_bg_rgb == 0x112233;
  DocFree(&d);
  if (!ok) { printf("CSS test FAILED visible=%d hidden=%d fallback=%d\n", visible, hidden, fallback); return 1; }
  printf("CSS selectors, inheritance, inline, visibility and noscript fallback: OK\n");
  return 0;
}
