/* ============================================================================
 * holynet_global_mesh.HC — Планетарный P2P-транспорт HOLY/2.0_WORLD_MESH
 * Автоматически связывает ВСЕ браузеры DivineWeb в любой точке мира через
 * зашифрованный TLS-рой (NAT / CGNAT / Firewall Traversal без настройки IP!)
 * ============================================================================ */

#define MESH_TOPIC_PREFIX   "holynet/divineweb/v2"
#define MESH_MAX_INLINE_GZ  90000
#define MESH_CHUNK_SIZE     32768
#define MESH_MAX_CHUNKS     48

class MeshChunkAssembler
{
  Bool active;
  U8   domain[128];
  U8   owner_node[64];
  U8   title[160];
  I32  version;
  I64  hits;
  I64  raw_len;
  I32  total_chunks;
  I32  got_chunks;
  Bool chunk_seen[MESH_MAX_CHUNKS];
  U8  *chunk_data[MESH_MAX_CHUNKS];
  I32  chunk_len[MESH_MAX_CHUNKS];
  Bool done;
};

MeshChunkAssembler g_mesh_rx;

Bool HolyIsAutoNodeDomain(U8 *dom)
{
  if (dom == NULL) return FALSE;
  if (StartsWithIgnoreCase(dom, "node-") && strstr(dom, ".holy") != NULL) {
    return TRUE;
  }
  return FALSE;
}

U0 MeshTxLock()
{
  if (g_holy.initialized) {
    pthread_mutex_lock((&g_holy.mesh_tx_mtx)(pthread_mutex_t *));
  }
}

U0 MeshTxUnlock()
{
  if (g_holy.initialized) {
    pthread_mutex_unlock((&g_holy.mesh_tx_mtx)(pthread_mutex_t *));
  }
}

I32 MqttEncodeVarLen(I64 len, U8 *out)
{
  I32 i = 0;
  while (TRUE) {
    U8 b = len & 0x7F;
    len = len >> 7;
    if (len > 0) b = b | 0x80;
    out[i++] = b;
    if (len == 0) break;
  }
  return i;
}

Bool MeshWriteAllUnlocked(I32 sock, U0 *ssl, Bool use_tls, U8 *buf, I64 len)
{
  if (sock < 0) return FALSE;
  I64 off = 0;
  while (off < len) {
    I64 chunk = len - off;
    if (chunk > 32768) chunk = 32768;
    I64 wr = 0;
    if (use_tls) {
      if (ssl == NULL) return FALSE;
      wr = SSL_write(ssl, buf + off, chunk);
    } else {
      wr = send(sock, buf + off, chunk, 0);
    }
    if (wr <= 0) return FALSE;
    off += wr;
  }
  return TRUE;
}

Bool MeshReadExact(I32 sock, U0 *ssl, Bool use_tls, U8 *dst, I64 want)
{
  I64 got = 0;
  while (got < want) {
    I64 r = 0;
    if (use_tls) {
      if (ssl == NULL) return FALSE;
      r = SSL_read(ssl, dst + got, want - got);
    } else {
      r = recv(sock, dst + got, want - got, 0);
    }
    if (r <= 0) return FALSE;
    got += r;
  }
  return TRUE;
}

/* Отправка бинарного пакета MQTT PUBLISH (retain=TRUE хранит сайт в глобальном рое) */
Bool HolyMeshSendPublish(U8 *topic, U8 *payload, I64 payload_len, Bool retain)
{
  if (!g_holy.initialized || !g_holy.mesh_connected || topic == NULL) return FALSE;

  I64 tlen = StrLen(topic);
  if (tlen <= 0 || tlen > 512) return FALSE;
  if (payload_len < 0) payload_len = 0;

  I64 rem_len = 2 + tlen + payload_len;
  U8  vlen_bytes[8];
  I32 vlen_n = MqttEncodeVarLen(rem_len, vlen_bytes);

  I64 frame_len = 1 + vlen_n + rem_len;
  U8 *frame = MAlloc(frame_len + 8);
  I64 pos = 0;

  if (retain) frame[pos++] = 0x31;
  else        frame[pos++] = 0x30;

  for (I32 k = 0; k < vlen_n; k++) frame[pos++] = vlen_bytes[k];

  frame[pos++] = (tlen >> 8) & 0xFF;
  frame[pos++] = tlen & 0xFF;
  MemCpy(frame + pos, topic, tlen);
  pos += tlen;

  if (payload != NULL && payload_len > 0) {
    MemCpy(frame + pos, payload, payload_len);
    pos += payload_len;
  }

  MeshTxLock();
  Bool ok = FALSE;
  if (g_holy.mesh_connected && g_holy.mesh_sock >= 0) {
    ok = MeshWriteAllUnlocked(g_holy.mesh_sock, g_holy.mesh_ssl, g_holy.mesh_use_tls, frame, pos);
    if (ok) {
      g_holy.mesh_tx_packets++;
      g_holy.packets_served++;
      g_holy.bytes_served += pos;
    }
  }
  MeshTxUnlock();

  Free(frame);
  return ok;
}

/* Публикация присутствия нашего браузера в глобальной мировой карте узлов */
U0 HolyMeshSendHeartbeat()
{
  if (!g_holy.mesh_connected) return;
  U8 topic[160];
  U8 msg[256];
  snprintf(topic, sizeof(topic), "%s/peers/%s", MESH_TOPIC_PREFIX, g_holy.node_id);
  I64 n = snprintf(msg, sizeof(msg), "HELLO|%s|%d|%d|%ld",
                   g_holy.node_id, 0, 0, 0);
  HolyMeshSendPublish(topic, msg, n, TRUE);
}

/* Глобальная публикация сайта (Gzip + RETAIN для мгновенного доступа из любой страны мира) */
U0 HolyMeshBroadcastSite(U8 *dom, U8 *title, I32 version, I64 hits, U8 *html, I64 html_len)
{
  if (dom == NULL || html == NULL || html_len <= 0) return;
  if (HolyIsAutoNodeDomain(dom)) return;

  /* Если узел только что стартовал (например CLI --publish-html), подождём до 1.2с рукопожатия */
  for (I32 w = 0; w < 24 && !g_holy.mesh_connected && g_holy.running; w++) {
    usleep(50000);
  }
  if (!g_holy.mesh_connected) return;

  U8 topic[256];
  snprintf(topic, sizeof(topic), "%s/sites/%s", MESH_TOPIC_PREFIX, dom);

  I64 gz_len = 0;
  U8 *gz_data = CompressGzipAlloc(html, html_len, &gz_len);

  if (gz_data != NULL && gz_len > 0 && gz_len <= MESH_MAX_INLINE_GZ) {
    U8 hdr[512];
    I64 hn = snprintf(hdr, sizeof(hdr), "SITE_GZ|%s|%s|%d|%ld|%ld|%s\n",
                      dom, g_holy.node_id, version, hits, html_len, title);
    U8 *pkt = MAlloc(hn + gz_len + 8);
    MemCpy(pkt, hdr, hn);
    MemCpy(pkt + hn, gz_data, gz_len);
    HolyMeshSendPublish(topic, pkt, hn + gz_len, TRUE);
    Free(pkt);
  } else {
    /* Очень крупный сайт (>90 КБ в сжатом виде, до 1.5 МБ): публикуем мета-запись в каталог,
     * а само тело отдаём чанками напрямую по P2P-запросу rpc/get через NAT! */
    U8 meta[512];
    I64 mn = snprintf(meta, sizeof(meta), "SITE_META|%s|%s|%d|%ld|%ld|%s\n",
                      dom, g_holy.node_id, version, hits, html_len, title);
    HolyMeshSendPublish(topic, meta, mn, TRUE);
  }

  if (gz_data != NULL) Free(gz_data);
}

/* Уведомление глобальной сети об открытии чужого сайта (живой счётчик хитов по всему миру) */
U0 HolyMeshNotifyRemoteHit(U8 *dom)
{
  if (!g_holy.mesh_connected || dom == NULL || dom[0] == 0) return;
  U8 topic[160];
  U8 msg[256];
  snprintf(topic, sizeof(topic), "%s/rpc/hit", MESH_TOPIC_PREFIX);
  I64 n = snprintf(msg, sizeof(msg), "HIT|%s|%s", dom, g_holy.node_id);
  HolyMeshSendPublish(topic, msg, n, FALSE);
}

/* Регистрация или обновление глобального WAN-пира в таблице мониторинга */
U0 HolyMeshUpsertWanPeer(U8 *rem_node_id, I32 rem_port, I64 rem_sites, I64 rem_up, Bool is_online)
{
  if (rem_node_id == NULL || rem_node_id[0] == 0) return;
  if (StrCmp(rem_node_id, g_holy.node_id) == 0) return;

  LinuxTimeval tv;
  gettimeofday((&tv)(timeval *), NULL);

  HolyLock();
  HolyPeer *found = NULL;
  for (I32 i = 0; i < g_holy.peer_count; i++) {
    if (g_holy.peers[i].used && g_holy.peers[i].is_wan_mesh &&
        StrCmp(g_holy.peers[i].node_id, rem_node_id) == 0) {
      found = &g_holy.peers[i];
      break;
    }
  }

  if (found == NULL && is_online && g_holy.peer_count < HOLY_MAX_PEERS) {
    found = &g_holy.peers[g_holy.peer_count++];
    MemSet(found, 0, sizeof(HolyPeer));
    found->used = TRUE;
    found->is_wan_mesh = TRUE;
    SafeCopy(found->host, "WAN-MESH (TLS)", sizeof(found->host));
    SafeCopy(found->node_id, rem_node_id, sizeof(found->node_id));
  }

  if (found != NULL) {
    found->online = is_online;
    if (rem_port > 0) found->port = rem_port;
    found->remote_sites = rem_sites;
    found->remote_uptime = rem_up;
    found->ping_ms = g_holy.mesh_rtt_ms;
    found->last_seen_sec = tv.tv_sec;
  }
  HolyUnlock();
}

/* Приём глобального сайта (SITE_GZ или SITE_META) в локальный P2P-реестр */
U0 HolyMeshIngestSitePacket(U8 *payload, I64 payload_len)
{
  if (payload == NULL || payload_len < 12) return;

  U8 *nl = memchr(payload, '\n', payload_len);
  if (nl == NULL) return;

  I64 hdr_len = nl - payload;
  if (hdr_len <= 8 || hdr_len >= 500) return;

  U8 hdr_copy[512];
  SafeCopyLen(hdr_copy, payload, hdr_len, sizeof(hdr_copy));

  U8 *f[8];
  I32 fc = HolySplitPipe(hdr_copy, f, 8);
  if (fc < 7) return;

  U8 *kind     = f[0];
  U8 *dom      = f[1];
  U8 *own_node = f[2];
  I32 ver      = Atoi(f[3]);
  I64 hits     = Atoi(f[4]);
  I64 raw_len  = Atoi(f[5]);
  U8 *title    = f[6];

  if (!HolyValidDomain(dom) || !HolyValidNodeId(own_node) || ver < 1 || raw_len <= 0 || raw_len > HOLY_MAX_HTML ||
      HolyIsSystemDomain(dom) || HolyIsAutoNodeDomain(dom)) return;
  HolyCleanMetadata(title);
  if (StrCmp(own_node, g_holy.node_id) == 0) return; /* Свои сайты у нас уже в памяти */

  Bool is_gz   = (StrCmp(kind, "SITE_GZ") == 0);
  Bool is_meta = (StrCmp(kind, "SITE_META") == 0);
  if (!is_gz && !is_meta) return;

  U8 *unz_html = NULL;
  I64 unz_len  = 0;

  if (is_gz) {
    U8 *gz_ptr = nl + 1;
    I64 gz_avail = payload_len - (hdr_len + 1);
    if (gz_avail <= 0 || gz_avail > MESH_MAX_INLINE_GZ) return;
    unz_html = DecompressGzipAlloc(gz_ptr, gz_avail, &unz_len);
    if (unz_html == NULL || unz_len != raw_len || unz_len > HOLY_MAX_HTML) { if (unz_html != NULL) Free(unz_html); return; }
  }

  HolyLock();
  HolySite *s = HolyFindSiteUnlocked(dom);
  if (s != NULL && s->is_local) {
    /* Наш локально занятый домен имеет приоритет */
    HolyUnlock();
    if (unz_html != NULL) Free(unz_html);
    return;
  }

  if (s == NULL && g_holy.site_count < HOLY_MAX_SITES) {
    s = &g_holy.sites[g_holy.site_count++];
    MemSet(s, 0, sizeof(HolySite));
    s->used = TRUE;
    s->is_local = FALSE;
    SafeCopy(s->domain, dom, sizeof(s->domain));
    SafeCopy(s->owner_node, own_node, sizeof(s->owner_node));
    SafeCopy(s->owner_host, "WAN-MESH", sizeof(s->owner_host));
    s->owner_port = 8883;
  }

  if (s != NULL && StrCmp(s->owner_node, own_node) == 0) {
    if (ver >= s->version || s->html == NULL) {
      SafeCopy(s->owner_node, own_node, sizeof(s->owner_node));
      SafeCopy(s->title, title, sizeof(s->title));
      s->version = ver;
      if (hits > s->hits) s->hits = hits;
      s->last_status = 200;
      s->last_ping_ms = g_holy.mesh_rtt_ms;
      if (unz_html != NULL) {
        if (s->html != NULL) Free(s->html);
        s->html = unz_html;
        s->html_len = unz_len;
        unz_html = NULL;
      } else if (s->html == NULL) {
        s->html_len = raw_len;
      }
      g_holy.mesh_catalog_seq++;
    }
  }
  HolyUnlock();

  if (unz_html != NULL) Free(unz_html);
}

/* Ответ владельца домена на живой P2P-запрос GET|<req_node>|<domain> через NAT */
U0 HolyMeshServeRpcGet(U8 *req_node, U8 *dom)
{
  if (req_node == NULL || dom == NULL || !HolyValidNodeId(req_node) || !HolyValidDomain(dom)) return;
  if (StrCmp(req_node, g_holy.node_id) == 0) return;

  U8 *html_copy = NULL;
  I64 html_len = 0;
  U8  title_copy[160];
  I32 ver = 1;
  I64 hits = 0;

  HolyLock();
  HolySite *s = HolyFindSiteUnlocked(dom);
  if (s != NULL && s->is_local && s->html != NULL && s->html_len > 0) {
    s->hits++;
    hits = s->hits;
    ver = s->version;
    html_len = s->html_len;
    SafeCopy(title_copy, s->title, sizeof(title_copy));
    html_copy = MAlloc(html_len + 1);
    MemCpy(html_copy, s->html, html_len);
    html_copy[html_len] = 0;
  }
  HolyUnlock();

  if (html_copy == NULL) return;

  I64 gz_len = 0;
  U8 *gz_data = CompressGzipAlloc(html_copy, html_len, &gz_len);
  Free(html_copy);
  if (gz_data == NULL || gz_len <= 0) return;

  I32 total_chunks = (gz_len + MESH_CHUNK_SIZE - 1) / MESH_CHUNK_SIZE;
  if (total_chunks < 1) total_chunks = 1;
  if (total_chunks > MESH_MAX_CHUNKS) total_chunks = MESH_MAX_CHUNKS;

  U8 resp_topic[192];
  snprintf(resp_topic, sizeof(resp_topic), "%s/rpc/resp/%s", MESH_TOPIC_PREFIX, req_node);

  for (I32 idx = 0; idx < total_chunks; idx++) {
    I64 off = idx * MESH_CHUNK_SIZE;
    I64 clen = gz_len - off;
    if (clen > MESH_CHUNK_SIZE) clen = MESH_CHUNK_SIZE;

    U8 chdr[512];
    I64 hn = snprintf(chdr, sizeof(chdr), "CHUNK|%s|%s|%d|%ld|%d|%d|%ld|%s\n",
                      dom, g_holy.node_id, ver, hits, idx, total_chunks, html_len, title_copy);
    U8 *pkt = MAlloc(hn + clen + 8);
    MemCpy(pkt, chdr, hn);
    MemCpy(pkt + hn, gz_data + off, clen);
    HolyMeshSendPublish(resp_topic, pkt, hn + clen, FALSE);
    Free(pkt);
  }

  Free(gz_data);
}

/* Обработка входящего CHUNK-ответа при скачивании крупного сайта у пира за NAT */
U0 HolyMeshHandleRpcChunk(U8 *payload, I64 payload_len)
{
  U8 *nl = memchr(payload, '\n', payload_len);
  if (nl == NULL) return;
  I64 hdr_len = nl - payload;
  if (hdr_len <= 6 || hdr_len >= 500) return;

  U8 hdr_copy[512];
  SafeCopyLen(hdr_copy, payload, hdr_len, sizeof(hdr_copy));

  U8 *f[10];
  I32 fc = HolySplitPipe(hdr_copy, f, 10);
  if (fc < 9 || StrCmp(f[0], "CHUNK") != 0) return;

  U8 *dom      = f[1];
  U8 *own_node = f[2];
  I32 ver      = Atoi(f[3]);
  I64 hits     = Atoi(f[4]);
  I32 idx      = Atoi(f[5]);
  I32 total    = Atoi(f[6]);
  I64 raw_len  = Atoi(f[7]);
  U8 *title    = f[8];

  if (!HolyValidDomain(dom) || !HolyValidNodeId(own_node) || ver < 1 || raw_len <= 0 || raw_len > HOLY_MAX_HTML ||
      idx < 0 || total <= 0 || total > MESH_MAX_CHUNKS || idx >= total) return;
  HolyCleanMetadata(title);

  U8 *cptr = nl + 1;
  I64 clen = payload_len - (hdr_len + 1);
  if (clen <= 0 || clen > MESH_CHUNK_SIZE) return;

  HolyLock();
  HolySite *known = HolyFindSiteUnlocked(dom);
  if (known != NULL && (known->is_local || StrCmp(known->owner_node, own_node) != 0)) { HolyUnlock(); return; }
  if (g_mesh_rx.active && StrCmp(g_mesh_rx.domain, dom) == 0 && !g_mesh_rx.done) {
    if (g_mesh_rx.got_chunks > 0 && (StrCmp(g_mesh_rx.owner_node, own_node) != 0 ||
        g_mesh_rx.version != ver || g_mesh_rx.total_chunks != total || g_mesh_rx.raw_len != raw_len)) { HolyUnlock(); return; }
    SafeCopy(g_mesh_rx.owner_node, own_node, sizeof(g_mesh_rx.owner_node));
    SafeCopy(g_mesh_rx.title, title, sizeof(g_mesh_rx.title));
    g_mesh_rx.version = ver;
    g_mesh_rx.hits = hits;
    g_mesh_rx.raw_len = raw_len;
    g_mesh_rx.total_chunks = total;

    if (!g_mesh_rx.chunk_seen[idx]) {
      g_mesh_rx.chunk_seen[idx] = TRUE;
      g_mesh_rx.chunk_data[idx] = MAlloc(clen);
      MemCpy(g_mesh_rx.chunk_data[idx], cptr, clen);
      g_mesh_rx.chunk_len[idx] = clen;
      g_mesh_rx.got_chunks++;
      if (g_mesh_rx.got_chunks >= total) {
        g_mesh_rx.done = TRUE;
      }
    }
  }
  HolyUnlock();
}

/* Диспетчер всех входящих пакетов глобального роя HOLY/2.0_WORLD_MESH */
U0 HolyMeshOnMessage(U8 *topic, U8 *payload, I64 payload_len)
{
  g_holy.mesh_rx_packets++;

  /* 1. Карта онлайн-узлов мира: holynet/divineweb/v2/peers/<node_id> */
  if (StartsWithIgnoreCase(topic, "holynet/divineweb/v2/peers/")) {
    U8 *rem_id_topic = topic + 27;
    if (payload_len == 0 && HolyValidNodeId(rem_id_topic)) {
      /* Пустой LWT-пакет: удалённый браузер закрылся */
      HolyMeshUpsertWanPeer(rem_id_topic, 0, 0, 0, FALSE);
      return;
    }
    U8 pbuf[256];
    SafeCopyLen(pbuf, payload, payload_len, sizeof(pbuf));
    U8 *f[6];
    I32 fc = HolySplitPipe(pbuf, f, 6);
    if (fc >= 5 && StrCmp(f[0], "HELLO") == 0 && HolyValidNodeId(f[1]) && StrCmp(rem_id_topic, f[1]) == 0) {
      HolyMeshUpsertWanPeer(f[1], Atoi(f[2]), Atoi(f[3]), Atoi(f[4]), TRUE);
    }
    return;
  }

  /* 2. Глобальный реестр сайтов: holynet/divineweb/v2/sites/<domain> */
  if (StartsWithIgnoreCase(topic, "holynet/divineweb/v2/sites/")) {
    if (payload_len > 0) {
      U8 *nl = memchr(payload, '\n', payload_len);
      if (nl != NULL && nl - payload < 500) {
        U8 head[512]; SafeCopyLen(head, payload, nl - payload, sizeof(head));
        U8 *fields[8]; I32 n = HolySplitPipe(head, fields, 8);
        if (n >= 2 && HolyValidDomain(fields[1]) && StrCmp(topic + StrLen("holynet/divineweb/v2/sites/"), fields[1]) == 0)
          HolyMeshIngestSitePacket(payload, payload_len);
      }
    }
    return;
  }

  /* 3. Живой счётчик просмотров со всего мира */
  if (StrCmp(topic, "holynet/divineweb/v2/rpc/hit") == 0 && payload_len > 4) {
    U8 hbuf[256];
    SafeCopyLen(hbuf, payload, payload_len, sizeof(hbuf));
    U8 *f[4];
    I32 fc = HolySplitPipe(hbuf, f, 4);
    if (fc >= 3 && StrCmp(f[0], "HIT") == 0 && StrCmp(f[2], g_holy.node_id) != 0) {
      HolyLock();
      HolySite *s = HolyFindSiteUnlocked(f[1]);
      if (s != NULL) s->hits++;
      HolyUnlock();
    }
    return;
  }

  /* 4. Входящий P2P-запрос на отдачу сайта через NAT */
  if (StrCmp(topic, "holynet/divineweb/v2/rpc/get") == 0 && payload_len > 4) {
    U8 gbuf[256];
    SafeCopyLen(gbuf, payload, payload_len, sizeof(gbuf));
    U8 *f[4];
    I32 fc = HolySplitPipe(gbuf, f, 4);
    if (fc >= 3 && StrCmp(f[0], "GET") == 0) {
      HolyMeshServeRpcGet(f[1], f[2]);
    }
    return;
  }

  /* 5. Входящий чанк сайта, запрошенного нашим узлом */
  U8 my_resp_topic[192];
  snprintf(my_resp_topic, sizeof(my_resp_topic), "%s/rpc/resp/%s", MESH_TOPIC_PREFIX, g_holy.node_id);
  if (StrCmp(topic, my_resp_topic) == 0 && payload_len > 8) {
    HolyMeshHandleRpcChunk(payload, payload_len);
    return;
  }
}

/* Активная докачка крупного сайта напрямую у владельца через глобальный P2P-рой */
Bool HolyMeshPullLargeSite(U8 *dom)
{
  if (!g_holy.mesh_connected || dom == NULL || dom[0] == 0) return FALSE;

  HolyLock();
  MemSet(&g_mesh_rx, 0, sizeof(MeshChunkAssembler));
  g_mesh_rx.active = TRUE;
  SafeCopy(g_mesh_rx.domain, dom, sizeof(g_mesh_rx.domain));
  HolyUnlock();

  U8 req_topic[160];
  U8 req_msg[256];
  snprintf(req_topic, sizeof(req_topic), "%s/rpc/get", MESH_TOPIC_PREFIX);
  I64 rn = snprintf(req_msg, sizeof(req_msg), "GET|%s|%s", g_holy.node_id, dom);
  HolyMeshSendPublish(req_topic, req_msg, rn, FALSE);

  for (I32 w = 0; w < 24; w++) {
    if (g_mesh_rx.done) break;
    /* После 700 мс без ответа прекращаем ожидание (это не доказывает, что домен свободен) */
    if (w >= 14 && g_mesh_rx.got_chunks == 0) break;
    usleep(50000);
  }

  Bool success = FALSE;
  HolyLock();
  if (g_mesh_rx.done && g_mesh_rx.total_chunks > 0) {
    I64 total_gz = 0;
    for (I32 i = 0; i < g_mesh_rx.total_chunks; i++) {
      total_gz += g_mesh_rx.chunk_len[i];
    }
    if (total_gz > 0) {
      U8 *all_gz = MAlloc(total_gz + 8);
      I64 pos = 0;
      for (I32 i = 0; i < g_mesh_rx.total_chunks; i++) {
        MemCpy(all_gz + pos, g_mesh_rx.chunk_data[i], g_mesh_rx.chunk_len[i]);
        pos += g_mesh_rx.chunk_len[i];
      }
      HolyUnlock();

      I64 unz_len = 0;
      U8 *unz = DecompressGzipAlloc(all_gz, total_gz, &unz_len);
      Free(all_gz);

      HolyLock();
      if (unz != NULL && (unz_len != g_mesh_rx.raw_len || unz_len > HOLY_MAX_HTML)) { Free(unz); unz = NULL; }
      if (unz != NULL && unz_len > 0) {
        HolySite *s = HolyFindSiteUnlocked(dom);
        if (s == NULL && g_holy.site_count < HOLY_MAX_SITES) {
          s = &g_holy.sites[g_holy.site_count++];
          MemSet(s, 0, sizeof(HolySite));
          s->used = TRUE;
          s->is_local = FALSE;
          SafeCopy(s->domain, dom, sizeof(s->domain));
        }
        if (s != NULL && !s->is_local && (s->owner_node[0] == 0 || StrCmp(s->owner_node, g_mesh_rx.owner_node) == 0)) {
          SafeCopy(s->owner_node, g_mesh_rx.owner_node, sizeof(s->owner_node));
          SafeCopy(s->title, g_mesh_rx.title, sizeof(s->title));
          SafeCopy(s->owner_host, "WAN-MESH", sizeof(s->owner_host));
          s->version = g_mesh_rx.version;
          s->hits = g_mesh_rx.hits;
          s->last_status = 200;
          s->last_ping_ms = g_holy.mesh_rtt_ms;
          if (s->html != NULL) Free(s->html);
          s->html = unz;
          s->html_len = unz_len;
          success = TRUE;
        } else {
          Free(unz);
        }
      }
    }
  }

  for (I32 i = 0; i < MESH_MAX_CHUNKS; i++) {
    if (g_mesh_rx.chunk_data[i] != NULL) {
      Free(g_mesh_rx.chunk_data[i]);
      g_mesh_rx.chunk_data[i] = NULL;
    }
  }
  g_mesh_rx.active = FALSE;
  HolyUnlock();
  return success;
}

/* Подписка на фильтр топиков MQTT SUBSCRIBE (0x82) */
Bool MeshSendSubscribeUnlocked(I32 sock, U0 *ssl, Bool use_tls, U16 pkt_id, U8 *filter)
{
  I64 flen = StrLen(filter);
  I64 body_len = 2 + 2 + flen + 1;
  U8  vlen[8];
  I32 vn = MqttEncodeVarLen(body_len, vlen);

  U8  pkt[600];
  I64 pos = 0;
  pkt[pos++] = 0x82;
  for (I32 k = 0; k < vn; k++) pkt[pos++] = vlen[k];
  pkt[pos++] = (pkt_id >> 8) & 0xFF;
  pkt[pos++] = pkt_id & 0xFF;
  pkt[pos++] = (flen >> 8) & 0xFF;
  pkt[pos++] = flen & 0xFF;
  MemCpy(pkt + pos, filter, flen);
  pos += flen;
  pkt[pos++] = 0x00; /* QoS 0 */

  return MeshWriteAllUnlocked(sock, ssl, use_tls, pkt, pos);
}

/* Фоновый поток планетарной синхронизации HOLY/2.0_WORLD_MESH */
U0 *HolyGlobalMeshThreadFn(U0 *arg)
{
  EnsureHttpGlobals();

  U8 *hosts[2];
  I32 ports[2];
  Bool tls_flags[2];
  hosts[0] = "broker.emqx.io";     ports[0] = 8883; tls_flags[0] = TRUE;
  hosts[1] = "broker.hivemq.com";  ports[1] = 8883; tls_flags[1] = TRUE;

  I32 relay_idx = 0;

  while (g_holy.running) {
    U8  *rhost = hosts[relay_idx % 2];
    I32  rport = ports[relay_idx % 2];
    Bool rtls  = tls_flags[relay_idx % 2];
    relay_idx++;

    F64 t_conn0 = HolyNowMs();
    I32 sock = HolyTorConnect(rhost, rport); /* SOCKS5: имя разрешает Tor; прямого fallback нет */
    if (sock < 0) {
      usleep(300000);
      continue;
    }

    U0 *ssl = NULL;
    if (rtls) {
      if (g_http_fast.ssl_ctx == NULL) {
        close(sock);
        continue;
      }
      ssl = SSL_new(g_http_fast.ssl_ctx);
      if (ssl == NULL || SSL_set_fd(ssl, sock) != 1 || !SecureTlsSetHost(ssl, rhost) || SSL_connect(ssl) <= 0) {
        if (ssl != NULL) SSL_free(ssl);
        close(sock);
        usleep(200000);
        continue;
      }
    }

    /* Формируем пакет MQTT 3.1.1 CONNECT с Last Will (автоочистка присутствия при выходе) */
    U8 client_id[96];
    U8 will_topic[160];
    snprintf(client_id, sizeof(client_id), "dw2_%s_%d", g_holy.node_id, getpid() & 0xFFF);
    snprintf(will_topic, sizeof(will_topic), "%s/peers/%s", MESH_TOPIC_PREFIX, g_holy.node_id);

    I64 cid_len  = StrLen(client_id);
    I64 will_len = StrLen(will_topic);
    I64 vh_len   = 10 + (2 + cid_len) + (2 + will_len) + 2;

    U8 conn_pkt[512];
    U8 vlen[8];
    I32 vn = MqttEncodeVarLen(vh_len, vlen);
    I64 cp = 0;
    conn_pkt[cp++] = 0x10;
    for (I32 k = 0; k < vn; k++) conn_pkt[cp++] = vlen[k];
    conn_pkt[cp++] = 0x00; conn_pkt[cp++] = 0x04;
    conn_pkt[cp++] = 'M';  conn_pkt[cp++] = 'Q'; conn_pkt[cp++] = 'T'; conn_pkt[cp++] = 'T';
    conn_pkt[cp++] = 0x04; /* MQTT 3.1.1 */
    conn_pkt[cp++] = 0x26; /* CleanSession | WillFlag | WillRetain */
    conn_pkt[cp++] = 0x00; conn_pkt[cp++] = 45; /* KeepAlive 45s */

    conn_pkt[cp++] = (cid_len >> 8) & 0xFF;
    conn_pkt[cp++] = cid_len & 0xFF;
    MemCpy(conn_pkt + cp, client_id, cid_len);
    cp += cid_len;

    conn_pkt[cp++] = (will_len >> 8) & 0xFF;
    conn_pkt[cp++] = will_len & 0xFF;
    MemCpy(conn_pkt + cp, will_topic, will_len);
    cp += will_len;

    /* Пустое тело LWT (0 байт) — автоматически удаляет карточку узла при закрытии окна */
    conn_pkt[cp++] = 0x00;
    conn_pkt[cp++] = 0x00;

    if (!MeshWriteAllUnlocked(sock, ssl, rtls, conn_pkt, cp)) {
      if (rtls) SSL_free(ssl);
      close(sock);
      continue;
    }

    U8 connack[4];
    if (!MeshReadExact(sock, ssl, rtls, connack, 4) ||
        connack[0] != 0x20 || connack[3] != 0x00) {
      if (rtls) SSL_free(ssl);
      close(sock);
      continue;
    }

    F64 handshake_rtt = HolyNowMs() - t_conn0;

    /* Подписываемся на все каналы планетарного роя Holynet */
    U8 sub_all_peers[128];
    U8 sub_all_sites[128];
    U8 sub_rpc_get[128];
    U8 sub_rpc_hit[128];
    U8 sub_my_resp[192];
    snprintf(sub_all_peers, sizeof(sub_all_peers), "%s/peers/#", MESH_TOPIC_PREFIX);
    snprintf(sub_all_sites, sizeof(sub_all_sites), "%s/sites/#", MESH_TOPIC_PREFIX);
    snprintf(sub_rpc_get,   sizeof(sub_rpc_get),   "%s/rpc/get", MESH_TOPIC_PREFIX);
    snprintf(sub_rpc_hit,   sizeof(sub_rpc_hit),   "%s/rpc/hit", MESH_TOPIC_PREFIX);
    snprintf(sub_my_resp,   sizeof(sub_my_resp),   "%s/rpc/resp/%s", MESH_TOPIC_PREFIX, g_holy.node_id);

    MeshSendSubscribeUnlocked(sock, ssl, rtls, 1, sub_all_peers);
    MeshSendSubscribeUnlocked(sock, ssl, rtls, 2, sub_all_sites);
    MeshSendSubscribeUnlocked(sock, ssl, rtls, 3, sub_rpc_get);
    MeshSendSubscribeUnlocked(sock, ssl, rtls, 4, sub_rpc_hit);
    MeshSendSubscribeUnlocked(sock, ssl, rtls, 5, sub_my_resp);

    MeshTxLock();
    g_holy.mesh_sock = sock;
    g_holy.mesh_ssl = ssl;
    g_holy.mesh_use_tls = rtls;
    g_holy.mesh_rtt_ms = handshake_rtt;
    if (rtls) snprintf(g_holy.mesh_relay_name, sizeof(g_holy.mesh_relay_name), "Tor + TLS %s:%d", rhost, rport);
    else      snprintf(g_holy.mesh_relay_name, sizeof(g_holy.mesh_relay_name), "TCP %s:%d", rhost, rport);
    g_holy.mesh_connected = TRUE;
    MeshTxUnlock();

    /* Заявляем о себе всему миру и выгружаем все локально опубликованные домены */
    HolyMeshSendHeartbeat();

    for (I32 si = 0; si < g_holy.site_count; si++) {
      if (g_holy.sites[si].used && g_holy.sites[si].is_local &&
          !HolyIsAutoNodeDomain(g_holy.sites[si].domain) &&
          g_holy.sites[si].html != NULL) {
        HolyMeshBroadcastSite(
          g_holy.sites[si].domain,
          g_holy.sites[si].title,
          g_holy.sites[si].version,
          g_holy.sites[si].hits,
          g_holy.sites[si].html,
          g_holy.sites[si].html_len
        );
      }
    }

    F64 last_hb_ms = HolyNowMs();
    F64 sync_mark_ms = last_hb_ms + 380.0;

    /* Главный цикл приёма пакетов со всего мира */
    while (g_holy.running) {
      F64 now_ms = HolyNowMs();
      if (!g_holy.mesh_initial_done && now_ms >= sync_mark_ms) {
        g_holy.mesh_initial_done = TRUE;
      }

      if (now_ms - last_hb_ms >= 18000.0) {
        /* PINGREQ (0xC0 0x00) + обновление присутствия узла */
        U8 ping_pkt[2];
        ping_pkt[0] = 0xC0;
        ping_pkt[1] = 0x00;
        MeshTxLock();
        Bool pok = MeshWriteAllUnlocked(sock, ssl, rtls, ping_pkt, 2);
        MeshTxUnlock();
        if (!pok) break;
        HolyMeshSendHeartbeat();
        last_hb_ms = now_ms;
      }

      Bool has_buffered_tls = FALSE;
      if (rtls && ssl != NULL && SSL_pending(ssl) > 0) {
        has_buffered_tls = TRUE;
      }

      if (!has_buffered_tls) {
        LinuxPollFd pfd;
        pfd.fd = sock;
        pfd.events = LINUX_POLLIN;
        pfd.revents = 0;
        I32 prc = poll(&pfd, 1, 150);
        if (prc < 0) break;
        if (prc == 0) continue;
      }

      U8 fhdr = 0;
      if (!MeshReadExact(sock, ssl, rtls, &fhdr, 1)) break;

      I64 rem_len = 0;
      I64 mult = 1;
      Bool v_ok = TRUE;
      for (I32 vb = 0; vb < 4; vb++) {
        U8 eb = 0;
        if (!MeshReadExact(sock, ssl, rtls, &eb, 1)) { v_ok = FALSE; break; }
        rem_len += (eb & 0x7F) * mult;
        mult = mult * 128;
        if ((eb & 0x80) == 0) break;
      }
      if (!v_ok || rem_len < 0 || rem_len > 2 * 1024 * 1024) break;

      if (rem_len == 0) continue;

      U8 *body = MAlloc(rem_len + 8);
      if (!MeshReadExact(sock, ssl, rtls, body, rem_len)) {
        Free(body);
        break;
      }
      body[rem_len] = 0;

      U8 pkt_type = (fhdr >> 4) & 0x0F;
      if (pkt_type == 3 && rem_len >= 2) { /* PUBLISH */
        I64 tlen = ((body[0] & 0xFF) << 8) | (body[1] & 0xFF);
        I64 hdr_skip = 2 + tlen;
        U8 qos = (fhdr >> 1) & 0x03;
        if (qos > 0) hdr_skip += 2;
        if (tlen > 0 && tlen < 500 && hdr_skip <= rem_len) {
          U8 topic_str[512];
          SafeCopyLen(topic_str, body + 2, tlen, sizeof(topic_str));
          HolyMeshOnMessage(topic_str, body + hdr_skip, rem_len - hdr_skip);
        }
      }

      Free(body);
    }

    MeshTxLock();
    g_holy.mesh_connected = FALSE;
    g_holy.mesh_sock = -1;
    g_holy.mesh_ssl = NULL;
    MeshTxUnlock();

    if (rtls && ssl != NULL) SSL_free(ssl);
    close(sock);
    if (g_holy.running) usleep(400000);
  }

  return NULL;
}
