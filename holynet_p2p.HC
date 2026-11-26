/* ============================================================================
 * holynet_p2p.HC — Собственная P2P-сеть браузера (протокол HOLY/1.0),
 * реестр доменов Холинета и живой мониторинг узлов/сайтов на чистом HolyC
 * ============================================================================ */

#define HOLY_MAGIC          "HOLY/1.0_DIVINE_MESH"
#define HOLY_DEFAULT_PORT   19400
#define HOLY_MAX_SITES      128
#define HOLY_MAX_PEERS      32
#define HOLY_MAX_HTML       (2 * 1024 * 1024)

class HolySite
{
  Bool used;
  Bool is_local;
  U8   domain[128];
  U8   title[160];
  U8   owner_node[64];
  U8   owner_host[128];
  I32  owner_port;
  I32  version;
  I64  hits;
  I32  last_status;
  F64  last_ping_ms;
  U8  *html;
  I64  html_len;
};

class HolyPeer
{
  Bool used;
  Bool online;
  Bool is_wan_mesh;
  U8   host[128];
  I32  port;
  U8   node_id[64];
  F64  ping_ms;
  I64  remote_sites;
  I64  remote_uptime;
  I64  last_seen_sec;
};

class HolyNodeState
{
  Bool initialized;
  Bool running;
  I32  listen_fd;
  I32  listen_port;   /* 0: relay-only, no inbound TCP listener */
  I32  profile_number;
  I32  identity_lock_fd;
  U8   node_id[64];
  I64  start_sec;
  I64  packets_served;
  I64  bytes_served;

  HolySite sites[HOLY_MAX_SITES];
  I32      site_count;

  HolyPeer peers[HOLY_MAX_PEERS];
  I32      peer_count;

  /* Планетарная P2P-сеть через любой NAT/CGNAT (HOLY/2.0_WORLD_MESH) */
  Bool       mesh_connected;
  Bool       mesh_initial_done;
  U8         mesh_relay_name[96];
  F64        mesh_rtt_ms;
  I64        mesh_rx_packets;
  I64        mesh_tx_packets;
  I64        mesh_catalog_seq;
  pthread_t *mesh_thread;
  U8         mesh_tx_mtx[96];
  I32        mesh_sock;
  U0        *mesh_ssl;
  Bool       mesh_use_tls;

  U8       mtx_buf[96];
  pthread_t *server_thread;
};

HolyNodeState g_holy;

U16 HolyHtons(I32 port)
{
  U16 p = port & 0xFFFF;
  return ((p & 0xFF) << 8) | ((p >> 8) & 0xFF);
}

F64 HolyNowMs()
{
  LinuxTimeval tv;
  gettimeofday((&tv)(timeval *), NULL);
  F64 sec_ms = tv.tv_sec * 1000.0;
  F64 usec_ms = tv.tv_usec / 1000.0;
  return sec_ms + usec_ms;
}

I64 HolyUptimeSec()
{
  LinuxTimeval tv;
  gettimeofday((&tv)(timeval *), NULL);
  I64 diff = tv.tv_sec - g_holy.start_sec;
  if (diff < 0) diff = 0;
  return diff;
}

U0 HolyLock()
{
  if (g_holy.initialized) {
    pthread_mutex_lock((&g_holy.mtx_buf)(pthread_mutex_t *));
  }
}

U0 HolyUnlock()
{
  if (g_holy.initialized) {
    pthread_mutex_unlock((&g_holy.mtx_buf)(pthread_mutex_t *));
  }
}

/* Быстрое TCP-соединение с коротким таймаутом (для опроса P2P-узлов без фризов GUI) */
/* Direct HOLY/1.0 sockets are disabled: a direct peer would see our IP. */
I32 HolyConnectPeerSocket(U8 *host, I32 port, I64 timeout_usec)
{
  return -1;
}

/* Нормализация любого введённого адреса в домен Холинета */
U0 HolyNormalizeUrl(U8 *raw, U8 *out_domain, I64 dom_cap, U8 *out_query, I64 q_cap)
{
  out_domain[0] = 0;
  out_query[0] = 0;
  if (raw == NULL) {
    SafeCopy(out_domain, "home", dom_cap);
    return;
  }

  U8 *p = raw;
  while (*p && IsSpace(*p)) p++;
  if (*p == 0) {
    SafeCopy(out_domain, "home", dom_cap);
    return;
  }

  /* Отрезаем любую схему: holy://, https://, http://, temple:// */
  U8 *sch = strstr(p, "://");
  if (sch != NULL) {
    p = sch + 3;
  }
  while (*p == '/') p++;

  /* Убираем префикс www. для удобства, чтобы www.wikipedia.org == wikipedia.org */
  if (StrCaseEqLen(p, "www.", 4)) {
    p += 4;
  }

  I64 di = 0;
  while (*p && *p != '/' && *p != '?' && *p != '#' && *p != ':' && !IsSpace(*p)) {
    if (di < dom_cap - 1) {
      U8 ch = ToLower(*p);
      if (ch != '|') out_domain[di++] = ch;
    }
    p++;
  }
  out_domain[di] = 0;

  if (out_domain[0] == 0) {
    SafeCopy(out_domain, "home", dom_cap);
  }

  /* Сохраняем query-параметр если есть (?claim=...) */
  U8 *qm = strchr(p, '?');
  if (qm != NULL) {
    SafeCopy(out_query, qm + 1, q_cap);
  }
}

/* Public metadata is untrusted; never use arbitrary protocol strings as HTML,
 * topic names or filesystem paths. Node labels are not cryptographic IDs. */
Bool HolyValidDomain(U8 *dom)
{
  I64 n = StrLen(dom);
  if (n == 0 || n > 120 || dom[0] == '.' || dom[n-1] == '.') return FALSE;
  for (I64 i = 0; i < n; i++) {
    U8 c = dom[i];
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.')) return FALSE;
    if (c == '.' && i > 0 && dom[i-1] == '.') return FALSE;
  }
  return TRUE;
}

Bool HolyValidNodeId(U8 *id)
{
  I64 n = StrLen(id);
  if (n == 0 || n >= 64) return FALSE;
  for (I64 i = 0; i < n; i++) {
    U8 c = id[i];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '-' || c == '_')) return FALSE;
  }
  return TRUE;
}

U0 HolyCleanMetadata(U8 *s)
{
  while (*s) {
    if (*s < 32 || *s == '<' || *s == '>' || *s == '&' || *s == '\"' || *s == '\'' || *s == '|') *s = ' ';
    s++;
  }
}

Bool HolyIsSystemDomain(U8 *dom)
{
  if (StrCmp(dom, "home") == 0) return TRUE;
  if (StrCmp(dom, "builder") == 0) return TRUE;
  if (StrCmp(dom, "monitor") == 0) return TRUE;
  if (StrCmp(dom, "search") == 0) return TRUE;
  return FALSE;
}

HolySite *HolyFindSiteUnlocked(U8 *domain)
{
  for (I32 i = 0; i < g_holy.site_count; i++) {
    if (g_holy.sites[i].used && StrCmp(g_holy.sites[i].domain, domain) == 0) {
      return &g_holy.sites[i];
    }
  }
  return NULL;
}

/* Форматирование IPv4-адреса из сетевого U32 (LinuxSockAddrIn.sin_addr) */
U0 HolyFormatIpv4(U32 net_addr, U8 *out, I64 cap)
{
  I32 b0 = net_addr & 0xFF;
  I32 b1 = (net_addr >> 8) & 0xFF;
  I32 b2 = (net_addr >> 16) & 0xFF;
  I32 b3 = (net_addr >> 24) & 0xFF;
  if (b0 == 0 && b1 == 0 && b2 == 0 && b3 == 0) {
    SafeCopy(out, "127.0.0.1", cap);
  } else {
    snprintf(out, cap, "%d.%d.%d.%d", b0, b1, b2, b3);
  }
}

Bool HolyIsLoopbackHost(U8 *host)
{
  if (host == NULL || host[0] == 0) return TRUE;
  if (StrCmp(host, "127.0.0.1") == 0) return TRUE;
  if (StrCmp(host, "0.0.0.0") == 0) return TRUE;
  if (StrCaseEqLen(host, "localhost", 9)) return TRUE;
  return FALSE;
}

U8 *HolyPeerScopeLabel(U8 *host)
{
  if (HolyIsLoopbackHost(host)) return "LOCAL";
  if (StrCmp(host, "WAN-MESH (TLS)") == 0 || StrCmp(host, "WAN-MESH") == 0) {
    return "GLOBAL MESH (Мир)";
  }
  if (StrNCmp(host, "192.168.", 8) == 0 ||
      StrNCmp(host, "10.", 3) == 0 ||
      StrNCmp(host, "172.16.", 7) == 0 ||
      StrNCmp(host, "172.17.", 7) == 0) {
    return "LAN";
  }
  return "WAN P2P (Внешний узел)";
}

/* No unauthenticated peer discovery or direct peer connections. */
U0 HolyAddPeerCandidate(U8 *host, I32 port)
{
  return;
}

/* Сохранение внешних P2P-узлов в файл holynet_peers.conf для межсетевого бутстрапа */
U0 HolySaveExternalPeerConf(U8 *host, I32 port)
{
  if (HolyIsLoopbackHost(host)) return;
  I32 fd = open("holynet_peers.conf", O_WRONLY | O_CREAT | O_APPEND, 0x1A4); /* 0644 rw-r--r-- */
  if (fd < 0) return;
  U8 line[180];
  I64 n = snprintf(line, sizeof(line), "%s:%d\n", host, port);
  write(fd, line, n);
  close(fd);
}

U0 HolyLoadExternalPeersConf()
{
  I32 fd = open("holynet_peers.conf", O_RDONLY, 0);
  if (fd < 0) return;
  U8 buf[4096];
  I64 n = read(fd, buf, sizeof(buf) - 1);
  close(fd);
  if (n <= 0) return;
  buf[n] = 0;

  U8 *line = buf;
  while (*line) {
    U8 *nl = strchr(line, '\n');
    if (nl != NULL) *nl = 0;
    U8 *p = line;
    while (*p && IsSpace(*p)) p++;
    if (*p != 0 && *p != '#') {
      U8 *colon = strchr(p, ':');
      if (colon != NULL) {
        U8 h[128];
        SafeCopyLen(h, p, colon - p, sizeof(h));
        I32 prt = Atoi(colon + 1);
        if (prt > 0) HolyAddPeerCandidate(h, prt);
      }
    }
    if (nl == NULL) break;
    line = nl + 1;
  }
}

/* Разбор строки с разделителем '|' */
I32 HolySplitPipe(U8 *line, U8 **fields, I32 max_fields)
{
  I32 count = 0;
  fields[count++] = line;
  U8 *p = line;
  while (*p && count < max_fields) {
    if (*p == '|') {
      *p = 0;
      fields[count++] = p + 1;
    } else if (*p == '\r' || *p == '\n') {
      *p = 0;
      break;
    }
    p++;
  }
  while (*p) {
    if (*p == '\r' || *p == '\n') { *p = 0; break; }
    p++;
  }
  return count;
}

/* Обработка одного входящего P2P-соединения протокола HOLY/1.0 (с любого внешнего/локального IP) */
U0 HolyHandleClientConn(I32 cfd, U8 *remote_ip)
{
  LinuxTimeval tv;
  tv.tv_sec = 2;
  tv.tv_usec = 0;
  setsockopt(cfd, LINUX_SOL_SOCKET, LINUX_SO_RCVTIMEO, &tv, sizeof(LinuxTimeval));
  setsockopt(cfd, LINUX_SOL_SOCKET, LINUX_SO_SNDTIMEO, &tv, sizeof(LinuxTimeval));

  I64 cap = 65536;
  U8 *buf = MAlloc(cap);
  I64 n = recv(cfd, buf, cap - 1, 0);
  if (n <= 0) {
    Free(buf);
    close(cfd);
    return;
  }
  buf[n] = 0;

  I64 mlen = StrLen(HOLY_MAGIC);
  if (n < mlen + 2 || StrNCmp(buf, HOLY_MAGIC, mlen) != 0) {
    U8 *deny = "ERR_NOT_HOLYNET_BROWSER: Only DivineWeb HolyC P2P protocol is accepted.\n";
    send(cfd, deny, StrLen(deny), 0);
    Free(buf);
    close(cfd);
    return;
  }

  U8 *cmd = buf + mlen + 1;

  /* 1. PING <sender_id> <sender_port> */
  if (StrNCmp(cmd, "PING ", 5) == 0) {
    U8 sender_id[64];
    I32 sender_port = 0;
    U8 *p = cmd + 5;
    I64 i = 0;
    while (*p && *p != ' ' && *p != '\n' && i < 63) sender_id[i++] = *p++;
    sender_id[i] = 0;
    if (*p == ' ') sender_port = Atoi(p + 1);
    if (sender_port > 0 && sender_port <= 65535 && HolyValidNodeId(sender_id)) {
      /* Запоминаем реальный IP-адрес пира (WAN / LAN / Local) */
      HolyAddPeerCandidate(remote_ip, sender_port);
    }

    U8 reply[256];
    HolyLock();
    g_holy.packets_served++;
    I32 sc = g_holy.site_count;
    HolyUnlock();

    snprintf(reply, sizeof(reply), "%s PONG %s %d %d\n",
             HOLY_MAGIC, g_holy.node_id, sc, HolyUptimeSec());
    I64 rlen = StrLen(reply);
    send(cfd, reply, rlen, 0);

    HolyLock();
    g_holy.bytes_served += rlen;
    HolyUnlock();
  }
  /* 2. LIST — отдать PEX-список известных онлайн-пиров + каталог известных доменов */
  else if (StrNCmp(cmd, "LIST", 4) == 0) {
    I64 out_cap = 32768;
    U8 *out = MAlloc(out_cap);
    Bool req_is_external = !HolyIsLoopbackHost(remote_ip);

    HolyLock();
    g_holy.packets_served++;
    I64 pos = snprintf(out, out_cap, "%s CATALOG %d\n", HOLY_MAGIC, g_holy.site_count);

    /* PEX (Peer Exchange): делимся координатами всех известных онлайн-узлов глобальной P2P-сети! */
    for (I32 pi = 0; pi < g_holy.peer_count; pi++) {
      HolyPeer *pr = &g_holy.peers[pi];
      if (!pr->used || !pr->online) continue;
      if (req_is_external && HolyIsLoopbackHost(pr->host)) continue;
      if (pos + 256 >= out_cap) {
        out_cap *= 2;
        out = ReAlloc(out, out_cap);
      }
      pos += snprintf(out + pos, out_cap - pos, "PEER|%s|%d|%s\n",
                      pr->host, pr->port, pr->node_id);
    }

    for (I32 i = 0; i < g_holy.site_count; i++) {
      HolySite *s = &g_holy.sites[i];
      if (!s->used) continue;
      if (pos + 512 >= out_cap) {
        out_cap *= 2;
        out = ReAlloc(out, out_cap);
      }
      pos += snprintf(out + pos, out_cap - pos,
                      "ENTRY|%s|%s|%s|%d|%d|%d|%d|%s\n",
                      s->domain, s->owner_node, s->owner_host, s->owner_port,
                      s->version, s->html_len, s->hits, s->title);
    }
    g_holy.bytes_served += pos;
    HolyUnlock();

    send(cfd, out, pos, 0);
    Free(out);
  }
  /* 3. GET <domain> — отдать содержимое P2P-сайта */
  else if (StrNCmp(cmd, "GET ", 4) == 0) {
    U8 req_dom[128];
    I64 i = 0;
    U8 *p = cmd + 4;
    while (*p && *p != '\r' && *p != '\n' && *p != ' ' && i < 127) {
      req_dom[i++] = ToLower(*p);
      p++;
    }
    req_dom[i] = 0;

    HolyLock();
    g_holy.packets_served++;
    HolySite *s = HolyFindSiteUnlocked(req_dom);
    if (s == NULL || s->html == NULL) {
      HolyUnlock();
      U8 nf[128];
      snprintf(nf, sizeof(nf), "%s SITE 404\n", HOLY_MAGIC);
      send(cfd, nf, StrLen(nf), 0);
    } else {
      s->hits++;
      I64 total_cap = s->html_len + 512;
      U8 *pkt = MAlloc(total_cap);
      I64 hlen = snprintf(pkt, total_cap, "%s SITE 200|%s|%d|%d|%d|%s\n",
                          HOLY_MAGIC, s->owner_node, s->version, s->hits, s->html_len, s->title);
      MemCpy(pkt + hlen, s->html, s->html_len);
      I64 total_len = hlen + s->html_len;
      g_holy.bytes_served += total_len;
      HolyUnlock();

      send(cfd, pkt, total_len, 0);
      Free(pkt);
    }
  }
  /* 4. ANNOUNCE <domain>|<owner_node>|<host>|<port>|<ver>|<len>|<title>\n<html> */
  else if (StrNCmp(cmd, "ANNOUNCE ", 9) == 0) {
    /* Дочитываем остаток пакета, если HTML большой */
    while (n < cap - 4096) {
      I64 more = recv(cfd, buf + n, 4096, 0);
      if (more <= 0) break;
      n += more;
      buf[n] = 0;
    }

    U8 *nl = strchr(cmd + 9, '\n');
    if (nl != NULL) {
      *nl = 0;
      U8 *body_ptr = nl + 1;
      I64 avail_len = (buf + n) - body_ptr;

      U8 *f[8];
      I32 fc = HolySplitPipe(cmd + 9, f, 8);
      if (fc >= 7) {
        U8 *dom = f[0];
        U8 *own_node = f[1];
        U8 *own_host = f[2];
        I32 own_port = Atoi(f[3]);
        I32 ver = Atoi(f[4]);
        I64 blen = Atoi(f[5]);
        U8 *title = f[6];
        if (!HolyValidDomain(dom) || !HolyValidNodeId(own_node) || own_port <= 0 || own_port > 65535 ||
            ver < 1 || blen <= 0 || blen > HOLY_MAX_HTML || blen != avail_len) blen = 0;
        HolyCleanMetadata(title);

        /* Если пакет ANNOUNCE пришёл от внешнего узла, подставляем его реальный маршрут IP! */
        U8 real_owner_host[128];
        /* Never allow a sender to nominate a third-party address. */
        SafeCopy(real_owner_host, remote_ip, sizeof(real_owner_host));
        if (own_port > 0) HolyAddPeerCandidate(real_owner_host, own_port);

        if (blen > 0 && !HolyIsSystemDomain(dom)) {
          HolyLock();
          HolySite *ex = HolyFindSiteUnlocked(dom);
          if (ex == NULL && g_holy.site_count < HOLY_MAX_SITES) {
            ex = &g_holy.sites[g_holy.site_count++];
            MemSet(ex, 0, sizeof(HolySite));
            ex->used = TRUE;
            ex->is_local = FALSE;
            SafeCopy(ex->domain, dom, sizeof(ex->domain));
            SafeCopy(ex->owner_node, own_node, sizeof(ex->owner_node));
            SafeCopy(ex->owner_host, real_owner_host, sizeof(ex->owner_host));
            ex->owner_port = own_port;
          }
          /* Обновляем только если владелец совпадает и версия новее */
          if (ex != NULL && !ex->is_local && StrCmp(ex->owner_node, own_node) == 0 && ver >= ex->version) {
            ex->version = ver;
            ex->last_status = 200;
            SafeCopy(ex->title, title, sizeof(ex->title));
            if (ex->html != NULL) Free(ex->html);
            ex->html = MAlloc(blen + 1);
            MemCpy(ex->html, body_ptr, blen);
            ex->html[blen] = 0;
            ex->html_len = blen;
          }
          HolyUnlock();
        }
      }
    }
    U8 *ack = "HOLY/1.0_DIVINE_MESH OK\n";
    send(cfd, ack, StrLen(ack), 0);
  }

  Free(buf);
  close(cfd);
}

/* Фоновый поток P2P-узла браузера (принимает входящие соединения со всего мира на 0.0.0.0) */
U0 *HolyServerThreadFn(U0 *arg)
{
  while (g_holy.running) {
    LinuxSockAddrIn cli_addr;
    MemSet(&cli_addr, 0, sizeof(LinuxSockAddrIn));
    I64 cli_len = sizeof(LinuxSockAddrIn);
    I32 cfd = accept(g_holy.listen_fd, (&cli_addr)(sockaddr *), &cli_len);
    if (cfd < 0) {
      if (!g_holy.running) break;
      usleep(20000);
      continue;
    }
    U8 remote_ip[64];
    HolyFormatIpv4(cli_addr.sin_addr, remote_ip, sizeof(remote_ip));
    HolyHandleClientConn(cfd, remote_ip);
  }
  return NULL;
}

/* Legacy 16-bit node label, not a secret key or proof of ownership. */
I32 HolyLoadOrCreateNodeTag(I32 port)
{
  U8 kpath[64];
  snprintf(kpath, sizeof(kpath), "holynet_node_%d.key", port);
  I32 fd = open(kpath, O_RDONLY, 0);
  if (fd >= 0) {
    U8 kbuf[32];
    I64 r = read(fd, kbuf, sizeof(kbuf) - 1);
    close(fd);
    if (r > 0) {
      kbuf[r] = 0;
      I32 val = Atoi(kbuf);
      if (val > 0 && val <= 0xFFFF) return val;
    }
  }

  LinuxTimeval tv;
  gettimeofday((&tv)(timeval *), NULL);
  I32 gen = ((tv.tv_usec ^ (tv.tv_sec * 31) ^ (getpid() * 131)) & 0xFFFF);
  if (gen <= 0) gen = 0x7A3F;

  I32 wfd = open(kpath, O_WRONLY | O_CREAT | O_TRUNC, 0x180);
  if (wfd >= 0) {
    U8 out[32];
    I64 n = snprintf(out, sizeof(out), "%d\n", gen);
    write(wfd, out, n);
    close(wfd);
  }
  return gen;
}

#include "holynet_global_mesh.HC"

/* Запуск локального и планетарного P2P-узла Холинета */
Bool HolyStartNode(I32 preferred_port)
{
  if (g_holy.initialized) return TRUE;
  MemSet(&g_holy, 0, sizeof(HolyNodeState));
  pthread_mutex_init((&g_holy.mtx_buf)(pthread_mutex_t *), NULL);
  pthread_mutex_init((&g_holy.mesh_tx_mtx)(pthread_mutex_t *), NULL);

  LinuxTimeval tv;
  gettimeofday((&tv)(timeval *), NULL);
  g_holy.start_sec = tv.tv_sec;
  g_holy.listen_fd = -1;
  g_holy.mesh_sock = -1;
  SafeCopy(g_holy.mesh_relay_name, "подключение к мировому рою...", sizeof(g_holy.mesh_relay_name));

  /* Profiles replace TCP ports. Lock locally so two instances in the same
   * directory do not announce the same legacy node label at the same time. */
  I32 base_p = preferred_port;
  if (base_p <= 0 || base_p > 65500) base_p = HOLY_DEFAULT_PORT;
  g_holy.identity_lock_fd = -1;
  for (I32 attempt = 0; attempt < 25; attempt++) {
    I32 profile = base_p + attempt;
    U8 lock_path[80];
    snprintf(lock_path, sizeof(lock_path), "holynet_node_%d.lock", profile);
    I32 fd = open(lock_path, O_RDWR | O_CREAT, 0x180);
    if (fd < 0) continue;
    if (flock(fd, 2 | 4) == 0) { /* LOCK_EX | LOCK_NB */
      g_holy.identity_lock_fd = fd;
      g_holy.profile_number = profile;
      break;
    }
    close(fd);
  }
  if (g_holy.identity_lock_fd < 0) return FALSE;
  g_holy.listen_port = 0;
  I32 node_tag = HolyLoadOrCreateNodeTag(g_holy.profile_number);
  snprintf(g_holy.node_id, sizeof(g_holy.node_id), "HLY-%d-%04X", g_holy.profile_number, node_tag);
  g_holy.initialized = TRUE;
  g_holy.running = TRUE;

  /* No server, local port scan, saved peers or direct network transport. */
  /* 3. Запускаем глобальный планетарный P2P-мост через NAT/CGNAT (связывает все ПК в мире!) */
  pthread_create(&g_holy.mesh_thread, NULL, &HolyGlobalMeshThreadFn, NULL);

  return TRUE;
}

/* Загрузка одного сайта напрямую с удалённого P2P-пира по протоколу HOLY/1.0 GET */
Bool HolyPullSiteFromPeer(U8 *host, I32 port, U8 *domain, F64 *out_ping_ms)
{
  F64 t0 = HolyNowMs();
  I32 sfd = HolyConnectPeerSocket(host, port, 600000);
  if (sfd < 0) return FALSE;

  U8 req[256];
  snprintf(req, sizeof(req), "%s GET %s\n", HOLY_MAGIC, domain);
  if (send(sfd, req, StrLen(req), 0) <= 0) {
    close(sfd);
    return FALSE;
  }

  I64 cap = 65536;
  I64 len = 0;
  U8 *buf = MAlloc(cap);
  while (TRUE) {
    if (len + 8192 + 1 > cap) {
      if (cap >= 4 * 1024 * 1024) break;
      cap *= 2;
      buf = ReAlloc(buf, cap);
    }
    I64 r = recv(sfd, buf + len, 8192, 0);
    if (r <= 0) break;
    len += r;
  }
  buf[len] = 0;
  close(sfd);
  F64 rtt = HolyNowMs() - t0;
  if (out_ping_ms != NULL) *out_ping_ms = rtt;

  U8 prefix[64];
  snprintf(prefix, sizeof(prefix), "%s SITE 200|", HOLY_MAGIC);
  I64 plen = StrLen(prefix);
  if (len < plen || StrNCmp(buf, prefix, plen) != 0) {
    Free(buf);
    return FALSE;
  }

  U8 *nl = strchr(buf + plen, '\n');
  if (nl == NULL) {
    Free(buf);
    return FALSE;
  }
  *nl = 0;
  U8 *html_ptr = nl + 1;
  I64 avail_html = (buf + len) - html_ptr;

  U8 *f[6];
  I32 fc = HolySplitPipe(buf + plen, f, 6);
  if (fc < 5) {
    Free(buf);
    return FALSE;
  }

  U8 *own_node = f[0];
  I32 ver = Atoi(f[1]);
  I64 hits = Atoi(f[2]);
  I64 expected_len = Atoi(f[3]);
  U8 *title = f[4];
  if (!HolyValidDomain(domain) || !HolyValidNodeId(own_node) || HolyIsSystemDomain(domain) ||
      ver < 1 || expected_len <= 0 || expected_len > HOLY_MAX_HTML || expected_len != avail_html) { Free(buf); return FALSE; }
  HolyCleanMetadata(title);

  HolyLock();
  HolySite *s = HolyFindSiteUnlocked(domain);
  if (s == NULL && g_holy.site_count < HOLY_MAX_SITES) {
    s = &g_holy.sites[g_holy.site_count++];
    MemSet(s, 0, sizeof(HolySite));
    s->used = TRUE;
    s->is_local = FALSE;
    SafeCopy(s->domain, domain, sizeof(s->domain));
    SafeCopy(s->owner_node, own_node, sizeof(s->owner_node));
    SafeCopy(s->owner_host, host, sizeof(s->owner_host));
    s->owner_port = port;
  }
  if (s != NULL && !s->is_local && StrCmp(s->owner_node, own_node) == 0 && ver >= s->version) {
    s->version = ver;
    s->hits = hits;
    s->last_status = 200;
    s->last_ping_ms = rtt;
    SafeCopy(s->title, title, sizeof(s->title));
    if (s->html != NULL) Free(s->html);
    s->html = MAlloc(expected_len + 1);
    MemCpy(s->html, html_ptr, expected_len);
    s->html[expected_len] = 0;
    s->html_len = expected_len;
  }
  HolyUnlock();

  Free(buf);
  return TRUE;
}

/* Активный опрос всех P2P-пиров (WAN и локальных): PING + PEX-обмен пирами + Gossip-реестр */
U0 HolySyncNetwork()
{
  if (!g_holy.initialized) return;

  /* Даём глобальному планетарному рою при самом первом запуске до ~2.4 с на TLS-рукопожатие и пакеты */
  for (I32 mw = 0; mw < 48 && !g_holy.mesh_initial_done && g_holy.running; mw++) {
    usleep(50000);
  }

  LinuxTimeval now_tv;
  gettimeofday((&now_tv)(timeval *), NULL);

  /* Идём по динамическому g_holy.peer_count: пиры, обнаруженные по PEX (PEER|...),
   * опрашиваются сразу в этом же цикле (транзитивное multi-hop обнаружение P2P-сети)! */
  for (I32 idx = 0; idx < g_holy.peer_count; idx++) {
    U8 host[128];
    I32 port = 0;
    Bool is_wan = FALSE;
    HolyLock();
    is_wan = g_holy.peers[idx].is_wan_mesh;
    if (is_wan) {
      if (now_tv.tv_sec - g_holy.peers[idx].last_seen_sec > 120) {
        g_holy.peers[idx].online = FALSE;
      }
      g_holy.peers[idx].ping_ms = g_holy.mesh_rtt_ms;
      HolyUnlock();
      continue;
    }
    SafeCopy(host, g_holy.peers[idx].host, sizeof(host));
    port = g_holy.peers[idx].port;
    HolyUnlock();

    /* 1. PING пира и точный замер RTT */
    F64 t0 = HolyNowMs();
    I32 sfd = HolyConnectPeerSocket(host, port, 250000);
    if (sfd < 0) {
      HolyLock();
      g_holy.peers[idx].online = FALSE;
      HolyUnlock();
      continue;
    }

    U8 ping_msg[160];
    snprintf(ping_msg, sizeof(ping_msg), "%s PING %s %d\n",
             HOLY_MAGIC, g_holy.node_id, g_holy.listen_port);
    send(sfd, ping_msg, StrLen(ping_msg), 0);

    U8 pong_buf[256];
    I64 pn = recv(sfd, pong_buf, sizeof(pong_buf) - 1, 0);
    close(sfd);
    F64 rtt = HolyNowMs() - t0;

    U8 pong_prefix[64];
    snprintf(pong_prefix, sizeof(pong_prefix), "%s PONG ", HOLY_MAGIC);
    I64 pplen = StrLen(pong_prefix);

    if (pn <= pplen || StrNCmp(pong_buf, pong_prefix, pplen) != 0) {
      HolyLock();
      g_holy.peers[idx].online = FALSE;
      HolyUnlock();
      continue;
    }
    pong_buf[pn] = 0;

    /* Разбираем: <node_id> <site_count> <uptime> */
    U8 rem_id[64];
    I64 rem_sites = 0;
    I64 rem_up = 0;
    U8 *p = pong_buf + pplen;
    I64 k = 0;
    while (*p && *p != ' ' && *p != '\n' && k < 63) rem_id[k++] = *p++;
    rem_id[k] = 0;
    if (*p == ' ') {
      rem_sites = Atoi(p + 1);
      p++;
      while (*p && *p != ' ') p++;
      if (*p == ' ') rem_up = Atoi(p + 1);
    }

    HolyLock();
    g_holy.peers[idx].online = TRUE;
    g_holy.peers[idx].ping_ms = rtt;
    g_holy.peers[idx].remote_sites = rem_sites;
    g_holy.peers[idx].remote_uptime = rem_up;
    if (HolyValidNodeId(rem_id)) SafeCopy(g_holy.peers[idx].node_id, rem_id, sizeof(g_holy.peers[idx].node_id));
    HolyUnlock();

    /* 2. Запрашиваем каталог доменов у онлайн-пира */
    I32 lfd = HolyConnectPeerSocket(host, port, 350000);
    if (lfd < 0) continue;
    U8 list_req[64];
    snprintf(list_req, sizeof(list_req), "%s LIST\n", HOLY_MAGIC);
    send(lfd, list_req, StrLen(list_req), 0);

    I64 ccap = 32768;
    I64 clen = 0;
    U8 *cbuf = MAlloc(ccap);
    while (clen < ccap - 2048) {
      I64 r = recv(lfd, cbuf + clen, 2048, 0);
      if (r <= 0) break;
      clen += r;
    }
    cbuf[clen] = 0;
    close(lfd);

    /* Идём построчно по ENTRY|domain|owner_node|owner_host|owner_port|ver|size|hits|title */
    U8 *line = cbuf;
    while (*line) {
      U8 *next = strchr(line, '\n');
      if (next != NULL) *next = 0;

      if (StrNCmp(line, "PEER|", 5) == 0) {
        /* PEX: соседний узел прислал координаты ещё одного пира глобальной P2P-сети! */
        U8 *pf[5];
        I32 pfc = HolySplitPipe(line, pf, 5);
        if (pfc >= 3) {
          U8 *phost = pf[1];
          I32 pport = Atoi(pf[2]);
          /* Unauthenticated PEX must not make the browser connect to arbitrary hosts. */
        }
      } else if (StrNCmp(line, "ENTRY|", 6) == 0) {
        U8 *f[10];
        I32 fc = HolySplitPipe(line, f, 10);
        if (fc >= 9) {
          U8 *dom = f[1];
          U8 *own_node = f[2];
          I32 ver = Atoi(f[5]);
          I64 hits = Atoi(f[7]);

          Bool need_pull = FALSE;
          HolyLock();
          HolySite *ex = HolyFindSiteUnlocked(dom);
          if (ex == NULL) {
            need_pull = TRUE;
          } else if (!ex->is_local && StrCmp(ex->owner_node, own_node) == 0) {
            if (hits > ex->hits) ex->hits = hits;
            ex->last_ping_ms = rtt;
            ex->last_status = 200;
            if (ver > ex->version || ex->html == NULL) need_pull = TRUE;
          }
          HolyUnlock();

          if (need_pull && HolyValidDomain(dom) && !HolyIsSystemDomain(dom) && HolyValidNodeId(own_node)) {
            HolyPullSiteFromPeer(host, port, dom, NULL);
          }
        }
      }

      if (next == NULL) break;
      line = next + 1;
    }
    Free(cbuf);
  }
}

/* Публикация (захват домена или обновление своего сайта) и P2P-рассылка ANNOUNCE */
Bool HolyPublishSite(U8 *raw_domain, U8 *title, U8 *html, U8 *err_out, I64 err_cap)
{
  U8 dom[128];
  U8 dummy_q[64];
  HolyNormalizeUrl(raw_domain, dom, sizeof(dom), dummy_q, sizeof(dummy_q));

  if (!HolyValidDomain(dom) || HolyIsSystemDomain(dom)) {
    SafeCopy(err_out, "Системные имена (home, builder, monitor) зарезервированы.", err_cap);
    return FALSE;
  }

  /* Чистим вертикальные черты в заголовке для протокола */
  U8 clean_title[160];
  SafeCopy(clean_title, title, sizeof(clean_title));
  for (I64 i = 0; clean_title[i]; i++) {
    if (clean_title[i] == '|' || clean_title[i] == '\n' || clean_title[i] == '\r')
      clean_title[i] = ' ';
  }
  HolyCleanMetadata(clean_title);
  if (clean_title[0] == 0) SafeCopy(clean_title, dom, sizeof(clean_title));

  I64 hlen = StrLen(html);
  if (hlen <= 0 || hlen > HOLY_MAX_HTML) { SafeCopy(err_out, "HTML превышает допустимый размер (2 МиБ).", err_cap); return FALSE; }
  I32 pub_ver = 1;

  HolyLock();
  HolySite *s = HolyFindSiteUnlocked(dom);
  if (s != NULL && StrCmp(s->owner_node, g_holy.node_id) != 0) {
    snprintf(err_out, err_cap, "Домен '%s' уже занят в P2P-сети узлом %s!", dom, s->owner_node);
    HolyUnlock();
    return FALSE;
  }

  if (s == NULL) {
    if (g_holy.site_count >= HOLY_MAX_SITES) {
      HolyUnlock();
      SafeCopy(err_out, "Достигнут лимит реестра доменов узла.", err_cap);
      return FALSE;
    }
    s = &g_holy.sites[g_holy.site_count++];
    MemSet(s, 0, sizeof(HolySite));
    s->used = TRUE;
    SafeCopy(s->domain, dom, sizeof(s->domain));
    SafeCopy(s->owner_node, g_holy.node_id, sizeof(s->owner_node));
    SafeCopy(s->owner_host, "127.0.0.1", sizeof(s->owner_host));
    s->owner_port = g_holy.listen_port;
    s->version = 1;
  } else {
    s->version++;
  }

  pub_ver = s->version;
  s->is_local = TRUE;
  s->last_status = 200;
  s->last_ping_ms = 0.1;
  SafeCopy(s->title, clean_title, sizeof(s->title));
  if (s->html != NULL) Free(s->html);
  s->html = StrNew(html);
  s->html_len = hlen;
  HolyUnlock();

  /* Relay-only: do not construct or send direct ANNOUNCE packets. */

  /* Одновременно транслируем сайт в глобальную планетарную P2P-сеть (через любой NAT/CGNAT в любую точку мира!) */
  HolyMeshBroadcastSite(dom, clean_title, pub_ver, 0, html, hlen);
  HolyMeshSendHeartbeat();

  err_out[0] = 0;
  return TRUE;
}

/* Сохранение созданного пользователем сайта на диск (holynet_sites/<domain>.site) */
U0 HolySaveUserSiteToDisk(U8 *raw_domain, U8 *title, U8 *html)
{
  U8 dom[128];
  U8 dq[64];
  HolyNormalizeUrl(raw_domain, dom, sizeof(dom), dq, sizeof(dq));
  if (!HolyValidDomain(dom) || HolyIsSystemDomain(dom) || html == NULL) return;

  mkdir("holynet_sites", 0x1ED); /* 0755 */
  U8 path[256];
  snprintf(path, sizeof(path), "holynet_sites/%s.site", dom);

  I32 fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0x1A4); /* 0644 */
  if (fd < 0) return;

  U8 hdr[300];
  I64 hn = snprintf(hdr, sizeof(hdr), "%s\n%s\n", dom, title);
  write(fd, hdr, hn);
  write(fd, html, StrLen(html));
  close(fd);

  /* Также записываем имя домена в индекс сохранённых сайтов узла */
  I32 ifd = open("holynet_sites/index.list", O_WRONLY | O_CREAT | O_APPEND, 0x1A4);
  if (ifd >= 0) {
    U8 iline[140];
    I64 in_len = snprintf(iline, sizeof(iline), "%s\n", dom);
    write(ifd, iline, in_len);
    close(ifd);
  }
}

/* Загрузка произвольного .html файла с диска и публикация его на домене в P2P-сети Холинет */
Bool HolyPublishHtmlFile(U8 *raw_domain, U8 *file_path, U8 *err_out, I64 err_cap)
{
  if (file_path == NULL || file_path[0] == 0) {
    SafeCopy(err_out, "Укажите путь к .html файлу на диске.", err_cap);
    return FALSE;
  }

  U8 actual_path[512];
  if (file_path[0] == '~' && file_path[1] == '/') {
    U8 *home = getenv("HOME");
    if (home == NULL || home[0] == 0) home = "/home/user";
    snprintf(actual_path, sizeof(actual_path), "%s/%s", home, file_path + 2);
  } else {
    SafeCopy(actual_path, file_path, sizeof(actual_path));
  }

  I32 fd = open(actual_path, O_RDONLY, 0);
  if (fd < 0) {
    snprintf(err_out, err_cap, "Не удалось открыть файл '%s'.", actual_path);
    return FALSE;
  }

  I64 fsz = lseek(fd, 0, SEEK_END);
  lseek(fd, 0, SEEK_SET);
  if (fsz <= 0 || fsz > 1500000) {
    close(fd);
    SafeCopy(err_out, "Файл пуст или превышает лимит P2P-пакета (1.5 МБ).", err_cap);
    return FALSE;
  }

  U8 *html = MAlloc(fsz + 1);
  I64 rd = read(fd, html, fsz);
  close(fd);
  if (rd <= 0) {
    Free(html);
    SafeCopy(err_out, "Ошибка чтения .html файла.", err_cap);
    return FALSE;
  }
  html[rd] = 0;

  /* Автоматически извлекаем <title>...</title> из HTML (если есть) */
  U8 extracted_title[160];
  extracted_title[0] = 0;
  for (I64 i = 0; i + 7 < rd; i++) {
    if (html[i] == '<' && StrCaseEqLen(html + i + 1, "title", 5) &&
        (html[i + 6] == '>' || IsSpace(html[i + 6]))) {
      U8 *gt = strchr(html + i + 6, '>');
      if (gt != NULL) {
        U8 *st = gt + 1;
        while (*st && IsSpace(*st)) st++;
        I64 tlen = 0;
        while (st[tlen] != 0 && !(st[tlen] == '<' && st[tlen + 1] == '/')) tlen++;
        while (tlen > 0 && IsSpace(st[tlen - 1])) tlen--;
        if (tlen > 0) {
          SafeCopyLen(extracted_title, st, tlen, sizeof(extracted_title));
          /* Убираем переводы строк внутри заголовка */
          for (I64 k = 0; extracted_title[k]; k++) {
            if (extracted_title[k] == '\n' || extracted_title[k] == '\r' || extracted_title[k] == '|')
              extracted_title[k] = ' ';
          }
        }
      }
      break;
    }
  }
  if (extracted_title[0] == 0) {
    snprintf(extracted_title, sizeof(extracted_title), "HTML-сайт (%s)", raw_domain);
  }

  Bool ok = HolyPublishSite(raw_domain, extracted_title, html, err_out, err_cap);
  if (ok) {
    HolySaveUserSiteToDisk(raw_domain, extracted_title, html);
  }
  Free(html);
  return ok;
}

/* Автозагрузка сохранённых сайтов пользователя с диска при старте браузера */
U0 HolyLoadSavedSitesFromDisk()
{
  I32 ifd = open("holynet_sites/index.list", O_RDONLY, 0);
  if (ifd < 0) return;
  U8 ibuf[4096];
  I64 n = read(ifd, ibuf, sizeof(ibuf) - 1);
  close(ifd);
  if (n <= 0) return;
  ibuf[n] = 0;

  U8 *line = ibuf;
  while (*line) {
    U8 *nl = strchr(line, '\n');
    if (nl != NULL) *nl = 0;
    if (line[0] != 0) {
      U8 path[256];
      snprintf(path, sizeof(path), "holynet_sites/%s.site", line);
      I32 sfd = open(path, O_RDONLY, 0);
      if (sfd >= 0) {
        I64 fsz = lseek(sfd, 0, SEEK_END);
        lseek(sfd, 0, SEEK_SET);
        if (fsz > 4 && fsz < 2 * 1024 * 1024) {
          U8 *fbuf = MAlloc(fsz + 1);
          I64 rd = read(sfd, fbuf, fsz);
          if (rd > 0) {
            fbuf[rd] = 0;
            U8 *nl1 = strchr(fbuf, '\n');
            if (nl1 != NULL) {
              *nl1 = 0;
              U8 *nl2 = strchr(nl1 + 1, '\n');
              if (nl2 != NULL) {
                *nl2 = 0;
                U8 err[128];
                HolyPublishSite(fbuf, nl1 + 1, nl2 + 1, err, sizeof(err));
              }
            }
          }
          Free(fbuf);
        }
        close(sfd);
      }
    }
    if (nl == NULL) break;
    line = nl + 1;
  }
}

/* Проверка статуса домена для Конструктора: 0 = свободен, 1 = наш, 2 = чужой */
I32 HolyInspectDomainOwner(U8 *raw_domain, U8 *owner_out, I64 owner_cap, I32 *ver_out)
{
  U8 dom[128];
  U8 dq[64];
  HolyNormalizeUrl(raw_domain, dom, sizeof(dom), dq, sizeof(dq));
  if (HolyIsSystemDomain(dom)) {
    SafeCopy(owner_out, "СИСТЕМНЫЙ", owner_cap);
    if (ver_out) *ver_out = 0;
    return 2;
  }
  HolyLock();
  HolySite *s = HolyFindSiteUnlocked(dom);
  if (s == NULL) {
    HolyUnlock();
    owner_out[0] = 0;
    if (ver_out) *ver_out = 0;
    return 0;
  }
  SafeCopy(owner_out, s->owner_node, owner_cap);
  if (ver_out) *ver_out = s->version;
  Bool ours = (StrCmp(s->owner_node, g_holy.node_id) == 0);
  HolyUnlock();
  if (ours) return 1;
  return 2;
}

/* Предустановленные стартовые сайты для демонстрации живых P2P-узлов */
U0 HolySeedPresetSites(I32 preset_id)
{
  U8 err[128];
  if (preset_id == 1) {
    /* Узел №1 уже успел занять wikipedia.org и beresta.su в Холинете! */
    HolyPublishSite(
      "wikipedia.org",
      "БерестаПедия — Свободная Энциклопедия Холинета",
      "<!DOCTYPE html><html><head><title>БерестаПедия (wikipedia.org в Холинете)</title></head><body>"
      "<h1>БерестаПедия — Народная Энциклопедия Холинета</h1>"
      "<blockquote><b>Узел-владелец домена wikipedia.org:</b> Публикуется через Tor и TLS-брокер по протоколу "
      "<code>HOLY/2.0_WORLD_MESH</code>! Внешней Википедии в Холинете не существует — кто первым "
      "занял домен, тот и хозяин.</blockquote>"
      "<h2>Избранная статья дня: Холинет и HolyC</h2>"
      "<p><b>Холинет</b> — суверенная пиринговая компьютерная сеть, работающая исключительно внутри "
      "браузера <b>DivineWeb</b> на языке <b>HolyC</b>. В отличие от классического веба, здесь нет "
      "внешних DNS-корпораций: каждый запущенный браузер подключается к общему ретранслятору.</p>"
      "<ul>"
      "<li>Протокол передачи: <code>HOLY/2.0_WORLD_MESH</code> (несовместим с обычными браузерами).</li>"
      "<li>Любой свободный домен (хоть <code>google.com</code> или <code>kvas.su</code>) можно занять в 1 клик!</li>"
      "<li>Перейти на соседний P2P-узел: <a href=\"holy://youtube.com\">Смотреть Диафильм-Поток (youtube.com)</a></li>"
      "<li>Посмотреть пульс сети: <a href=\"holy://monitor\">Открыть Мониторинг P2P-узлов и сайтов</a></li>"
      "</ul>"
      "<hr><p><a href=\"holy://home\">&larr; На главную Холинета</a> | "
      "<a href=\"holy://builder\">Создать свой сайт в Конструкторе</a></p>"
      "</body></html>",
      err, sizeof(err)
    );

    HolyPublishSite(
      "beresta.su",
      "Береста.СУ — Первая доска объявлений Холинета",
      "<!DOCTYPE html><html><head><title>Береста.СУ — P2P Борда</title></head><body>"
      "<h1>Береста.СУ — Ламповая P2P-борда</h1>"
      "<p>Добро пожаловать на <b>beresta.su</b>! Сайт передан вашему браузеру напрямую от пира к пиру.</p>"
      "<h2>Свежие треды в сети:</h2>"
      "<ol>"
      "<li><b>[Анонс]</b> Собрал браузер на чистом HolyC с X11 и Cairo — полёт нормальный!</li>"
      "<li><b>[Обмен]</b> Меняю сборник алгоритмов Дональда Кнута на 3 литра домашнего кваса.</li>"
      "<li><b>[Домены]</b> Пацаны, <code>google.com</code> и <code>vk.com</code> ещё свободны — <a href=\"holy://google.com\">проверьте сами!</a></li>"
      "</ol>"
      "<p><a href=\"holy://home\">&larr; Вернуться в каталог Холинета</a></p>"
      "</body></html>",
      err, sizeof(err)
    );
  } else if (preset_id == 2) {
    /* Узел №2 занял youtube.com и kvas.ru! */
    HolyPublishSite(
      "youtube.com",
      "ДиафильмПроектор — Суверенный видеохостинг на youtube.com",
      "<!DOCTYPE html><html><head><title>ДиафильмПроектор (youtube.com в Холинете)</title></head><body>"
      "<h1>ДиафильмПроектор (домен youtube.com занят нами!)</h1>"
      "<blockquote>Этот домен <code>youtube.com</code> зарегистрирован за P2P-узлом второго браузера! "
      "Никакой рекламы и алгоритмов — только текстовые диафильмы по протоколу <code>HOLY/2.0</code>.</blockquote>"
      "<h2>В эфире сегодня:</h2>"
      "<pre>"
      "+--------------------------------------------------+\n"
      "|   КАДР #1: ТЕРРИ ДЭВИС ПИШЕТ КОМПИЛЯТОР HOLYC    |\n"
      "|                                                  |\n"
      "|      [o_o]   --->   U0 Main() { \"Divine!\"; }     |\n"
      "|     /|___|\\                                      |\n"
      "+--------------------------------------------------+"
      "</pre>"
      "<p>Другие узлы сети: <a href=\"holy://wikipedia.org\">БерестаПедия (wikipedia.org)</a> | "
      "<a href=\"holy://kvas.ru\">Рецепты цехового кваса (kvas.ru)</a> | "
      "<a href=\"holy://monitor\">Мониторинг P2P</a></p>"
      "</body></html>",
      err, sizeof(err)
    );

    HolyPublishSite(
      "kvas.ru",
      "КвасПром — Стратегический запас ржаного кваса",
      "<!DOCTYPE html><html><head><title>КвасПром — kvas.ru</title></head><body>"
      "<h1>КвасПром (holy://kvas.ru)</h1>"
      "<p>Официальное представительство ценителей холодного хлебного кваса в P2P-сети Холинет.</p>"
      "<ul>"
      "<li>Плотность сусла: <b>12.4%</b></li>"
      "<li>Температура брожения: <b>+26 C</b></li>"
      "<li>Статус бочек на узле: <b>ПОЛНЫЕ (200 OK)</b></li>"
      "</ul>"
      "<p><a href=\"holy://home\">&larr; На главную Холинета</a> | "
      "<a href=\"holy://builder\">Открыть Конструктор сайтов</a></p>"
      "</body></html>",
      err, sizeof(err)
    );
  } else if (preset_id == 0) {
    /* Дефолтный локальный визитный сайт самого браузера */
    U8 my_dom[64];
    snprintf(my_dom, sizeof(my_dom), "node-%d.holy", g_holy.profile_number);
    HolyPublishSite(
      my_dom,
      "Личный узел браузера DivineWeb",
      "<!DOCTYPE html><html><head><title>Личный P2P-узел DivineWeb</title></head><body>"
      "<h1>Личный P2P-узел активен!</h1>"
      "<p>Это стандартная визитка вашего собственного узла Холинета. "
      "Откройте <a href=\"holy://builder\">Конструктор сайтов</a>, чтобы занять любой красивый домен "
      "(например, <code>google.com</code>, <code>habr.com</code> или <code>moy-mir.ru</code>) и раздавать его другим браузерам!</p>"
      "<p><a href=\"holy://monitor\">Перейти в Мониторинг сети</a> | <a href=\"holy://home\">На главную Холинета</a></p>"
      "</body></html>",
      err, sizeof(err)
    );
    HolyLoadSavedSitesFromDisk();
  }
}

#include "holynet_search.HC"

/* Генерация HTML страницы holy://home (Главная Холинета) */
U8 *HolyBuildHomeHtml(I64 *out_len)
{
  HolySyncNetwork();

  I64 cap = 32768;
  U8 *buf = MAlloc(cap);
  I64 pos = 0;

  I32 online_peers = 0;
  I32 wan_peers = 0;
  HolyLock();
  for (I32 i = 0; i < g_holy.peer_count; i++) {
    if (g_holy.peers[i].online) {
      online_peers++;
      if (g_holy.peers[i].is_wan_mesh) wan_peers++;
    }
  }

  U8 *mesh_badge = "ПОДКЛЮЧЕНИЕ...";
  if (g_holy.mesh_connected) mesh_badge = "ОНЛАЙН (ВЕСЬ МИР БЕЗ NAT)";

  pos += snprintf(buf + pos, cap - pos,
    "<!DOCTYPE html><html><head><title>ХОЛИНЕТ P2P — Главный узел</title></head><body>"
    "<img src=\"data:image/svg+xml,"
    "<svg xmlns='http://www.w3.org/2000/svg' width='760' height='78'>"
    "<rect width='760' height='78' rx='8' fill='%%230d4730'/>"
    "<rect x='3' y='3' width='754' height='72' rx='6' fill='none' stroke='%%23e0b341' stroke-width='2'/>"
    "<circle cx='44' cy='39' r='22' fill='%%2318704a' stroke='%%23ffe57f' stroke-width='2'/>"
    "<circle cx='44' cy='39' r='7' fill='%%2359ff88'/>"
    "<text x='82' y='34' font-family='DejaVu Sans' font-size='19' font-weight='bold' fill='%%23fff0a8'>ПЛАНЕТАРНАЯ P2P-СЕТЬ HOLYNET / ХОЛИНЕТ (HOLY/2.0)</text>"
    "<text x='82' y='57' font-family='DejaVu Sans' font-size='12' fill='%%23b8f5cd'>Соединение Холинета через Tor + TLS; постоянный ID публичен</text>"
    "</svg>\" alt=\"Эмблема Холинета\">"
    "<blockquote>"
    "<b>Ваш узел:</b> <code>%s</code> | "
    "<b>Мировой рой:</b> <code>%s</code> [<code>%s</code>] | "
    "<b>Онлайн-браузеров в P2P:</b> <code>%d</code> (в мире: <code>%d</code>) | "
    "<b>Доменов:</b> <code>%d</code><br>"
    "Брокер видит выходной узел Tor, провайдер видит Tor; постоянный ID допускает отслеживание. "
    "Чтобы выложить свой <code>.html</code> файл на весь мир, введите сверху: <code>загрузить мой-домен.org ~/файл.html</code>."
    "</blockquote>"
    "<h2>Инструменты Холинета</h2>"
    "<ul>"
    "<li><a href=\"holy://search\"><b>[ ПОИСК САЙТОВ ]</b> — Найти сайты в P2P по заголовкам, доменам, подзаголовкам и тексту</a></li>"
    "<li><a href=\"holy://builder\"><b>[ КОНСТРУКТОР САЙТОВ ]</b> — Занять свободный домен и собрать сайт из блоков</a></li>"
    "<li><a href=\"holy://monitor?sync=1\"><b>[ МОНИТОРИНГ СЕТИ И САЙТОВ ]</b> — Пинг P2P-узлов, таблицы доменов, аптайм и хиты</a></li>"
    "</ul>"
    "<h2>Сайты, обнаруженные в мировой P2P-сети прямо сейчас:</h2>"
    "<table>"
    "<tr><th>Домен</th><th>Заголовок P2P-сайта</th><th>Узел-владелец</th><th>Вер.</th><th>Хиты</th></tr>",
    g_holy.node_id, mesh_badge, g_holy.mesh_relay_name, online_peers, wan_peers, g_holy.site_count
  );

  for (I32 i = 0; i < g_holy.site_count; i++) {
    HolySite *s = &g_holy.sites[i];
    if (!s->used) continue;
    pos += snprintf(buf + pos, cap - pos,
      "<tr><td><a href=\"holy://%s\"><b>%s</b></a></td><td>%s</td><td><code>%s</code></td><td>v%d</td><td>%d</td></tr>",
      s->domain, s->domain, s->title, s->owner_node, s->version, s->hits
    );
  }
  HolyUnlock();

  pos += snprintf(buf + pos, cap - pos,
    "</table>"
    "<h2>Примеры доменов Холинета</h2>"
    "<p>Эти имена не связаны с владельцами обычных интернет-доменов; публикации и владельцы не проверяются.</p>"
    "<ul>"
    "<li><a href=\"holy://google.com\">google.com</a> &mdash; проверить и занять домен в Холинете</li>"
    "<li><a href=\"holy://vk.com\">vk.com</a> &mdash; проверить и занять домен в Холинете</li>"
    "<li><a href=\"holy://goskvas.su\">goskvas.su</a> &mdash; проверить и занять домен в Холинете</li>"
    "</ul>"
    "</body></html>"
  );

  *out_len = pos;
  return buf;
}

/* Генерация HTML страницы holy://monitor (Мониторинг P2P-сети и сайтов) */
U8 *HolyBuildMonitorHtml(Bool do_sync, I64 *out_len)
{
  if (do_sync) HolySyncNetwork();

  I64 cap = 49152;
  U8 *buf = MAlloc(cap);
  I64 pos = 0;

  HolyLock();
  I32 online_cnt = 0;
  I32 wan_online_cnt = 0;
  for (I32 i = 0; i < g_holy.peer_count; i++) {
    if (g_holy.peers[i].online) {
      online_cnt++;
      if (g_holy.peers[i].is_wan_mesh) wan_online_cnt++;
    }
  }

  U8 *mesh_st = "ПОДКЛЮЧЕНИЕ...";
  if (g_holy.mesh_connected) mesh_st = "АКТИВЕН (HOLY/2.0_WORLD_MESH — обход NAT/CGNAT)";

  pos += snprintf(buf + pos, cap - pos,
    "<!DOCTYPE html><html><head><title>Мониторинг P2P-узлов и сайтов Холинета</title></head><body>"
    "<h1>Мониторинг мировой P2P-сети и сайтов Холинета</h1>"
    "<p>"
    "<a href=\"holy://monitor?sync=1\"><b>[ Опросить P2P-сеть (PING + SYNC) ]</b></a> &nbsp;&nbsp; "
    "<a href=\"holy://builder\"><b>[ + Занять домен в Конструкторе ]</b></a> &nbsp;&nbsp; "
    "<a href=\"holy://home\"><b>[ Каталог Холинета ]</b></a>"
    "</p>"
    "<h2>1. Телеметрия вашего локального и планетарного P2P-узла</h2>"
    "<pre>"
    "ID узла браузера   : %s\n"
    "Прямой TCP-сокет   : отключён (HOLY/1.0)\n"
    "Профиль узла       : %d  (не сетевой порт)\n"
    "Приватность        : Tor + TLS; публичный ID отслеживается\n"
    "Мировой P2P-мост   : %s [%s | RTT %.1f мс]\n"
    "Пакеты мирового роя: получено %ld / отправлено %ld\n"
    "Аптайм узла        : %d сек.\n"
    "Активных P2P-пиров : %d онлайн (из них через Интернет/NAT: %d)\n"
    "Доменов в реестре  : %d сайтов\n"
    "Отдано P2P-пакетов : %d пакетов (%d байт)"
    "</pre>",
    g_holy.node_id, g_holy.profile_number,
    mesh_st, g_holy.mesh_relay_name, g_holy.mesh_rtt_ms,
    g_holy.mesh_rx_packets, g_holy.mesh_tx_packets,
    HolyUptimeSec(), online_cnt, wan_online_cnt,
    g_holy.site_count, g_holy.packets_served, g_holy.bytes_served
  );

  pos += snprintf(buf + pos, cap - pos,
    "<h2>2. Живая карта пиров P2P-сети (все браузеры мира + локальные узлы)</h2>"
    "<blockquote>"
    "<b>Автоматическая связь через континенты и домашние роутеры:</b> встроенный шифрованный транспорт "
    "<code>HOLY/2.0_WORLD_MESH</code> связывает все запущенные в мире экземпляры <b>DivineWeb</b> без проброса портов "
    "и без ручного ввода IP. HOLY/1.0 отключён; провайдер видит Tor."
    "</blockquote>"
    "<table>"
    "<tr><th>Статус</th><th>Маршрут</th><th>Адрес пира</th><th>ID узла</th><th>Пинг RTT</th><th>Сайты</th></tr>"
  );

  /* Сначала выводим ВСЕ ОНЛАЙН-узлы (включая браузеры на другом конце Земли!), затем офлайн-слоты */
  for (I32 pass = 0; pass < 2; pass++) {
    for (I32 i = 0; i < g_holy.peer_count; i++) {
      HolyPeer *pr = &g_holy.peers[i];
      if (!pr->used) continue;
      if (pass == 0 && !pr->online) continue;
      if (pass == 1 && pr->online) continue;

      U8 *scope_lbl = HolyPeerScopeLabel(pr->host);
      if (pr->online) {
        pos += snprintf(buf + pos, cap - pos,
          "<tr><td><span style=\"color:#0d7a3e\"><b>ОНЛАЙН</b></span></td><td><b>%s</b></td>"
          "<td><code>%s:%d</code></td><td><b>%s</b></td><td><b>%.2f мс</b></td><td>%d</td></tr>",
          scope_lbl, pr->host, pr->port, pr->node_id, pr->ping_ms, pr->remote_sites
        );
      } else {
        pos += snprintf(buf + pos, cap - pos,
          "<tr><td><i>ОФЛАЙН</i></td><td>%s</td><td><code>%s:%d</code></td><td>&mdash;</td><td>&mdash;</td><td>0</td></tr>",
          scope_lbl, pr->host, pr->port
        );
      }
    }
  }

  pos += snprintf(buf + pos, cap - pos,
    "</table>"
    "<h2>3. Мониторинг доступности всех сайтов Холинета</h2>"
    "<table>"
    "<tr><th>Домен</th><th>Название сайта</th><th>Статус</th><th>Владелец</th><th>Пинг</th><th>Размер</th><th>Хиты</th></tr>"
  );

  for (I32 i = 0; i < g_holy.site_count; i++) {
    HolySite *s = &g_holy.sites[i];
    if (!s->used) continue;
    U8 *st = "200 ONLINE";
    if (s->last_status != 200) st = "КЭШ P2P";

    pos += snprintf(buf + pos, cap - pos,
      "<tr><td><a href=\"holy://%s\"><b>%s</b></a></td><td>%s</td>"
      "<td><code>%s</code></td><td><code>%s</code></td>"
      "<td>%.2f мс</td><td>%d Б</td><td><b>%d</b></td></tr>",
      s->domain, s->domain, s->title, st,
      s->owner_node, s->last_ping_ms, s->html_len, s->hits
    );
  }
  HolyUnlock();

  pos += snprintf(buf + pos, cap - pos, "</table></body></html>");
  *out_len = pos;
  return buf;
}

/* Страница свободного незанятого домена с кнопкой захвата в 1 клик! */
U8 *HolyBuildUnclaimedDomainHtml(U8 *domain, I64 *out_len)
{
  U8 *buf = MAlloc(4096);
  I64 pos = snprintf(buf, 4096,
    "<!DOCTYPE html><html><head><title>Домен %s не найден в Холинете</title></head><body>"
    "<h1>Домен &laquo;%s&raquo; не найден</h1>"
    "<blockquote>В доступном сейчас каталоге нет сайта <code>%s</code>. "
    "Это не подтверждает, что имя свободно: узлы могут быть недоступны. "
    "Подлинность владельцев и публикаций протоколом не проверяется.</blockquote>"
    "<h2>Попробовать опубликовать сайт %s?</h2>"
    "<p>Можно создать локальную публикацию; уникальность имени и защита от подмены не гарантируются.</p>"
    "<ul>"
    "<li><a href=\"holy://builder?claim=%s\"><b>[ ОТКРЫТЬ КОНСТРУКТОР ДЛЯ %s ]</b></a></li>"
    "<li><a href=\"holy://monitor?sync=1\">Открыть доступный каталог в Мониторинге</a></li>"
    "<li><a href=\"holy://home\">&larr; Вернуться на главную Холинета</a></li>"
    "</ul>"
    "</body></html>",
    domain, domain, domain, domain, domain, domain
  );
  *out_len = pos;
  return buf;
}

/* Навигация внутри режима Холинета.
 * Возвращает 2, если нужно переключить экран на интерактивный GUI Конструктора (holy://builder)! */
I32 HolyFetchUrl(U8 *raw_url, HttpResponse *resp, U8 *builder_claim_out, I64 claim_cap)
{
  MemSet(resp, 0, sizeof(HttpResponse));
  SafeCopy(resp->content_type, "text/html", sizeof(resp->content_type));

  U8 dom[128];
  U8 query[256];
  HolyNormalizeUrl(raw_url, dom, sizeof(dom), query, sizeof(query));

  if (!HolyValidDomain(dom)) {
    resp->status_code = 400;
    SafeCopy(resp->final_url, "holy://home", sizeof(resp->final_url));
    SafeCopy(resp->error, "Недопустимое имя домена Холинета", sizeof(resp->error));
    resp->body = StrNew("<html><body><h1>Недопустимое имя домена</h1></body></html>");
    resp->body_len = StrLen(resp->body);
    return 1;
  }

  if (StrCmp(dom, "builder") == 0) {
    snprintf(resp->final_url, sizeof(resp->final_url), "holy://builder");
    if (builder_claim_out != NULL && StrNCmp(query, "claim=", 6) == 0) {
      SafeCopy(builder_claim_out, query + 6, claim_cap);
      snprintf(resp->final_url, sizeof(resp->final_url), "holy://builder?claim=%s", builder_claim_out);
    }
    resp->status_code = 200;
    return 2; /* Сигнал открыть графический Конструктор сайтов! */
  }

  snprintf(resp->final_url, sizeof(resp->final_url), "holy://%s", dom);

  if (StrCmp(dom, "home") == 0) {
    resp->status_code = 200;
    resp->body = HolyBuildHomeHtml(&resp->body_len);
    return 1;
  }

  if (StrCmp(dom, "monitor") == 0) {
    Bool force_sync = TRUE;
    resp->status_code = 200;
    resp->body = HolyBuildMonitorHtml(force_sync, &resp->body_len);
    return 1;
  }

  if (StrCmp(dom, "search") == 0) {
    if (query[0] != 0) {
      snprintf(resp->final_url, sizeof(resp->final_url), "holy://search?%s", query);
    } else {
      snprintf(resp->final_url, sizeof(resp->final_url), "holy://search");
    }
    resp->status_code = 200;
    resp->body = HolyBuildSearchHtml(query, &resp->body_len);
    return 1;
  }

  /* Синхронизируем с P2P-пирами перед поиском домена */
  HolySyncNetwork();

  HolyLock();
  HolySite *s = HolyFindSiteUnlocked(dom);
  if (s == NULL) {
    HolyUnlock();
    /* Если пакет ещё в пути — делаем живой P2P-запрос GET к глобальному рою без перезагрузки! */
    HolyMeshPullLargeSite(dom);
    HolyLock();
    s = HolyFindSiteUnlocked(dom);
    if (s == NULL) {
      HolyUnlock();
      resp->status_code = 404;
      snprintf(resp->error, sizeof(resp->error), "Домен %s не найден в доступном каталоге", dom);
      resp->body = HolyBuildUnclaimedDomainHtml(dom, &resp->body_len);
      return 1;
    }
  }

  Bool is_loc = s->is_local;
  U8 peer_host[128];
  I32 peer_port = s->owner_port;
  SafeCopy(peer_host, s->owner_host, sizeof(peer_host));
  HolyUnlock();

  /* Если домен на удалённом пире — запрашиваем напрямую или через глобальный P2P-мост */
  if (!is_loc && StrCmp(peer_host, "WAN-MESH") == 0) {
    Bool need_chunks = FALSE;
    HolyLock();
    s = HolyFindSiteUnlocked(dom);
    if (s != NULL && s->html == NULL) need_chunks = TRUE;
    HolyUnlock();

    if (need_chunks) {
      HolyMeshPullLargeSite(dom);
    }
    /* No public broadcast of page visits. */
    HolyLock();
    s = HolyFindSiteUnlocked(dom);
    if (s != NULL) {
      s->hits++;
      s->last_status = 200;
      s->last_ping_ms = g_holy.mesh_rtt_ms;
    }
    HolyUnlock();
  } else if (!is_loc && peer_port > 0) {
    F64 rtt = 0.0;
    if (!HolyPullSiteFromPeer(peer_host, peer_port, dom, &rtt)) {
      HolyLock();
      s = HolyFindSiteUnlocked(dom);
      if (s != NULL && s->html == NULL) s->last_status = 503;
      HolyUnlock();
    }
  } else {
    HolyLock();
    s = HolyFindSiteUnlocked(dom);
    if (s != NULL) {
      s->hits++;
      s->last_status = 200;
      s->last_ping_ms = 0.08;
    }
    HolyUnlock();
  }

  HolyLock();
  s = HolyFindSiteUnlocked(dom);
  if (s != NULL && s->html != NULL) {
    resp->status_code = 200;
    resp->body_len = s->html_len;
    resp->body = MAlloc(s->html_len + 1);
    MemCpy(resp->body, s->html, s->html_len);
    resp->body[s->html_len] = 0;
    HolyUnlock();
    return 1;
  }
  HolyUnlock();

  resp->status_code = 404;
  resp->body = HolyBuildUnclaimedDomainHtml(dom, &resp->body_len);
  return 1;
}
