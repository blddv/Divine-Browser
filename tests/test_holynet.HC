#include "../bindings.HH"
#include "../url_http.HC"
#include "../image_loader.HC"
#include "../css_legacy.HC"
#include "../html_dom.HC"
#include "../layout_render.HC"
#include "../holynet_p2p.HC"

extern "c" I32 socketpair(I32 domain, I32 type, I32 protocol, I32 *sv);
extern "c" I32 shutdown(I32 fd, I32 how);

I32 Main(I32 argc, U8 **argv)
{
  if (!SafeHolynetEmbeddedImage("data:image/svg+xml,<svg></svg>")) return 10;
  if (SafeHolynetEmbeddedImage("data:image/svg+xml,<svg><image%20href='file:///etc/passwd'/></svg>")) return 11;
  if (SafeHolynetEmbeddedImage("data:image/svg+xml,<svg><style>p%7Bfill:url(file:///tmp/a)%7D</style></svg>")) return 12;
  if (HolyValidDomain("../steal") || HolyValidDomain("x+evil") || !HolyValidDomain("good-site.ru")) return 1;
  if (HolyValidNodeId("../bad") || !HolyValidNodeId("HLY-123-CAFE")) return 2;
  MemSet(&g_holy, 0, sizeof(g_holy));
  SafeCopy(g_holy.node_id, "HLY-100-1234", sizeof(g_holy.node_id));
  g_holy.site_count = 1;
  HolySite *s = &g_holy.sites[0];
  s->used = TRUE; s->is_local = TRUE; s->version = 1;
  SafeCopy(s->domain, "local.test", sizeof(s->domain));
  SafeCopy(s->owner_node, g_holy.node_id, sizeof(s->owner_node));
  s->html = StrNew("ORIGINAL"); s->html_len = 8;
  U8 *bad = "SITE_META|local.test|EVIL-NODE|99|0|100|Bad\n";
  HolyMeshIngestSitePacket(bad, StrLen(bad));
  if (s->version != 1 || StrCmp(s->html, "ORIGINAL") != 0) return 3;
  U8 *first = "SITE_META|other.test|NODE-A|1|0|100|<script>\n";
  HolyMeshIngestSitePacket(first, StrLen(first));
  HolySite *r = HolyFindSiteUnlocked("other.test");
  if (r == NULL || strchr(r->title, '<') != NULL) return 4;
  U8 *take = "SITE_META|other.test|NODE-B|999|0|100|Evil\n";
  HolyMeshIngestSitePacket(take, StrLen(take));
  if (StrCmp(r->owner_node, "NODE-A") != 0 || r->version != 1) return 5;
  U8 *topic_bad = "SITE_META|wrong.test|NODE-C|1|0|100|Bad\n";
  HolyMeshOnMessage("holynet/divineweb/v2/sites/different.test", topic_bad, StrLen(topic_bad));
  if (HolyFindSiteUnlocked("wrong.test") != NULL) return 6;
  U8 *chunk = "CHUNK|local.test|EVIL-NODE|4|0|0|1|8|Bad\n123";
  g_mesh_rx.active = TRUE; SafeCopy(g_mesh_rx.domain, "local.test", sizeof(g_mesh_rx.domain));
  HolyMeshHandleRpcChunk(chunk, StrLen(chunk));
  if (g_mesh_rx.got_chunks != 0) return 7;
  I32 pair[2];
  if (socketpair(1, SOCK_STREAM, 0, pair) != 0) return 8;
  U8 packet[512];
  I64 plen = snprintf(packet, sizeof(packet), "%s ANNOUNCE local.test|%s|127.0.0.1|1234|999|5|Spoof\nEVIL!", HOLY_MAGIC, g_holy.node_id);
  send(pair[0], packet, plen, 0);
  shutdown(pair[0], 1);
  HolyHandleClientConn(pair[1], "127.0.0.1");
  close(pair[0]);
  if (s->version != 1 || StrCmp(s->html, "ORIGINAL") != 0) return 9;
  Free(s->html);
  printf("Holynet metadata, local ownership and chunk validation: OK\n");
  return 0;
}
