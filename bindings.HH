/* ============================================================================
 * bindings.HH — Привязки HolyC (extern "c") к X11, Cairo и OpenSSL (Linux x86_64)
 * Браузер DivineWeb на языке HolyC (holyc-lang)
 * ============================================================================ */

/* --- Константы событий и масок X11 --- */
#define X11_KeyPress              0x02
#define X11_KeyRelease            0x03
#define X11_ButtonPress           0x04
#define X11_ButtonRelease         0x05
#define X11_MotionNotify          0x06
#define X11_Expose                0x0C
#define X11_ConfigureNotify       0x16
#define X11_ClientMessage         0x21

#define X11_KeyPressMask          0x00001
#define X11_ButtonPressMask       0x00004
#define X11_ButtonReleaseMask     0x00008
#define X11_PointerMotionMask     0x00040
#define X11_ExposureMask          0x08000
#define X11_StructureNotifyMask   0x20000

#define X11_ShiftMask             0x01
#define X11_ControlMask           0x04

/* --- Коды клавиш X11 KeySym --- */
#define XK_BackSpace              0xFF08
#define XK_Tab                    0xFF09
#define XK_Return                 0xFF0D
#define XK_Escape                 0xFF1B
#define XK_Home                   0xFF50
#define XK_Left                   0xFF51
#define XK_Up                     0xFF52
#define XK_Right                  0xFF53
#define XK_Down                   0xFF54
#define XK_Page_Up                0xFF55
#define XK_Page_Down              0xFF56
#define XK_End                    0xFF57
#define XK_KP_Enter               0xFF8D
#define XK_F5                     0xFFC2
#define XK_F7                     0xFFC4
#define XK_F12                    0xFFC9
#define XK_Delete                 0xFFFF

/* --- Стандартные курсоры X11 --- */
#define XC_hand2                  0x3C
#define XC_left_ptr               0x44
#define XC_xterm                  0x98

/* --- Константы Cairo --- */
#define CAIRO_FORMAT_ARGB32       0
#define CAIRO_FONT_SLANT_NORMAL   0
#define CAIRO_FONT_SLANT_ITALIC   1
#define CAIRO_FONT_WEIGHT_NORMAL  0
#define CAIRO_FONT_WEIGHT_BOLD    1
#define CAIRO_ANTIALIAS_DEFAULT   0
#define CAIRO_ANTIALIAS_NONE      1
#define CAIRO_FILTER_GOOD         1
#define CAIRO_FILTER_NEAREST      3

/* --- Константы сокетов Linux и TLS SNI --- */
#define LINUX_SOL_SOCKET          1
#define LINUX_SO_REUSEADDR        2
#define LINUX_SO_ERROR            4
#define LINUX_SO_RCVTIMEO         20
#define LINUX_SO_SNDTIMEO         21
#define LINUX_F_GETFL             3
#define LINUX_F_SETFL             4
#define LINUX_O_NONBLOCK          0x800
#define LINUX_EINPROGRESS         115
#define LINUX_POLLIN              0x001
#define LINUX_POLLOUT             0x004
#define SSL_CTRL_SET_TLSEXT_HOSTNAME 55
#define TLSEXT_NAMETYPE_host_name 0

/* --- Структуры событий X11 (точная разметка ABI Linux x86_64, 192 байта) --- */
class XKeyEventHC
{
  I32 type;
  I32 _pad0;
  U64 serial;
  I32 send_event;
  I32 _pad1;
  U0 *display;
  U64 window;
  U64 root;
  U64 subwindow;
  U64 time;
  I32 x;
  I32 y;
  I32 x_root;
  I32 y_root;
  U32 state;
  U32 keycode;
  I32 same_screen;
};

class XButtonEventHC
{
  I32 type;
  I32 _pad0;
  U64 serial;
  I32 send_event;
  I32 _pad1;
  U0 *display;
  U64 window;
  U64 root;
  U64 subwindow;
  U64 time;
  I32 x;
  I32 y;
  I32 x_root;
  I32 y_root;
  U32 state;
  U32 button;
  I32 same_screen;
};

class XMotionEventHC
{
  I32 type;
  I32 _pad0;
  U64 serial;
  I32 send_event;
  I32 _pad1;
  U0 *display;
  U64 window;
  U64 root;
  U64 subwindow;
  U64 time;
  I32 x;
  I32 y;
  I32 x_root;
  I32 y_root;
  U32 state;
  I8  is_hint;
  I8  _pad2[3];
  I32 same_screen;
};

class XConfigureEventHC
{
  I32 type;
  I32 _pad0;
  U64 serial;
  I32 send_event;
  I32 _pad1;
  U0 *display;
  U64 event;
  U64 window;
  I32 x;
  I32 y;
  I32 width;
  I32 height;
  I32 border_width;
  I32 _pad2;
  U64 above;
  I32 override_redirect;
};

class XClientMessageEventHC
{
  I32 type;
  I32 _pad0;
  U64 serial;
  I32 send_event;
  I32 _pad1;
  U0 *display;
  U64 window;
  U64 message_type;
  I32 format;
  I32 _pad2;
  I64 data_l[5];
};

union XEventHC
{
  I32 type;
  XKeyEventHC xkey;
  XButtonEventHC xbutton;
  XMotionEventHC xmotion;
  XConfigureEventHC xconfigure;
  XClientMessageEventHC xclient;
  I64 pad[24];
};

/* --- Метрики текста Cairo --- */
class CairoTextExtents
{
  F64 x_bearing;
  F64 y_bearing;
  F64 width;
  F64 height;
  F64 x_advance;
  F64 y_advance;
};

/* --- Таймаут сокета и addrinfo Linux x86_64 --- */
class LinuxTimeval
{
  I64 tv_sec;
  I64 tv_usec;
};

class LinuxAddrInfo;
class LinuxAddrInfo
{
  I32 ai_flags;
  I32 ai_family;
  I32 ai_socktype;
  I32 ai_protocol;
  U32 ai_addrlen;
  I32 _pad0;
  sockaddr *ai_addr;
  U8 *ai_canonname;
  LinuxAddrInfo *ai_next;
};

/* Точная структура struct sockaddr_in Linux x86_64 (16 байт) */
class LinuxSockAddrIn
{
  U16 sin_family;
  U16 sin_port;
  U32 sin_addr;
  U8  sin_zero[8];
};

/* Точная структура struct pollfd Linux x86_64 (8 байт) */
class LinuxPollFd
{
  I32 fd;
  I16 events;
  I16 revents;
};

extern "c" I32 getpid();
extern "c" U8 *getenv(U8 *name);
extern "c" I32 poll(LinuxPollFd *fds, U64 nfds, I32 timeout);
extern "c" I32 *__errno_location();

/* --- Функции libX11 --- */
extern "c" U0 *XOpenDisplay(U8 *display_name);
extern "c" I32 XCloseDisplay(U0 *display);
extern "c" I32 XDefaultScreen(U0 *display);
extern "c" U64 XRootWindow(U0 *display, I32 screen_number);
extern "c" U0 *XDefaultVisual(U0 *display, I32 screen_number);
extern "c" U64 XBlackPixel(U0 *display, I32 screen_number);
extern "c" U64 XWhitePixel(U0 *display, I32 screen_number);
extern "c" U64 XCreateSimpleWindow(U0 *display, U64 parent, I32 x, I32 y,
    U32 width, U32 height, U32 border_width, U64 border, U64 background);
extern "c" I32 XStoreName(U0 *display, U64 w, U8 *window_name);
extern "c" I32 XSelectInput(U0 *display, U64 w, I64 event_mask);
extern "c" I32 XMapWindow(U0 *display, U64 w);
extern "c" I32 XPending(U0 *display);
extern "c" I32 XNextEvent(U0 *display, XEventHC *event_return);
extern "c" I32 XLookupString(XKeyEventHC *event_struct, U8 *buffer_return,
    I32 bytes_buffer, U64 *keysym_return, U0 *status_in_out);
extern "c" U64 XInternAtom(U0 *display, U8 *atom_name, I32 only_if_exists);
extern "c" I32 XSetWMProtocols(U0 *display, U64 w, U64 *protocols, I32 count);
extern "c" U64 XCreateFontCursor(U0 *display, U32 shape);
extern "c" I32 XDefineCursor(U0 *display, U64 w, U64 cursor);
extern "c" I32 XFreeCursor(U0 *display, U64 cursor);
extern "c" I32 XFlush(U0 *display);
extern "c" I32 XSync(U0 *display, I32 discard);
extern "c" I32 XConnectionNumber(U0 *display);

/* --- Функции libcairo --- */
extern "c" U0 *cairo_xlib_surface_create(U0 *dpy, U64 drawable, U0 *visual, I32 width, I32 height);
extern "c" U0  cairo_xlib_surface_set_size(U0 *surface, I32 width, I32 height);
extern "c" U0 *cairo_image_surface_create(I32 format, I32 width, I32 height);
extern "c" U0 *cairo_image_surface_create_from_png(U8 *filename);
extern "c" U8 *cairo_image_surface_get_data(U0 *surface);
extern "c" I32 cairo_image_surface_get_stride(U0 *surface);
extern "c" I32 cairo_image_surface_get_width(U0 *surface);
extern "c" I32 cairo_image_surface_get_height(U0 *surface);
extern "c" U0  cairo_surface_mark_dirty(U0 *surface);
extern "c" I32 cairo_surface_write_to_png(U0 *surface, U8 *filename);
extern "c" U0  cairo_surface_flush(U0 *surface);
extern "c" U0  cairo_surface_destroy(U0 *surface);

extern "c" U0 *cairo_create(U0 *target);
extern "c" U0  cairo_destroy(U0 *cr);
extern "c" U0  cairo_save(U0 *cr);
extern "c" U0  cairo_restore(U0 *cr);
extern "c" U0  cairo_translate(U0 *cr, F64 tx, F64 ty);
extern "c" U0  cairo_scale(U0 *cr, F64 sx, F64 sy);
extern "c" U0  cairo_set_source_rgb(U0 *cr, F64 red, F64 green, F64 blue);
extern "c" U0  cairo_set_source_rgba(U0 *cr, F64 red, F64 green, F64 blue, F64 alpha);
extern "c" U0  cairo_set_source_surface(U0 *cr, U0 *surface, F64 x, F64 y);
extern "c" U0  cairo_paint(U0 *cr);
extern "c" U0  cairo_rectangle(U0 *cr, F64 x, F64 y, F64 width, F64 height);
extern "c" U0  cairo_clip(U0 *cr);
extern "c" U0  cairo_fill(U0 *cr);
extern "c" U0  cairo_stroke(U0 *cr);
extern "c" U0  cairo_set_line_width(U0 *cr, F64 width);
extern "c" U0  cairo_new_path(U0 *cr);
extern "c" U0  cairo_close_path(U0 *cr);
extern "c" U0  cairo_move_to(U0 *cr, F64 x, F64 y);
extern "c" U0  cairo_line_to(U0 *cr, F64 x, F64 y);
extern "c" U0  cairo_arc(U0 *cr, F64 xc, F64 yc, F64 radius, F64 angle1, F64 angle2);
extern "c" U0  cairo_select_font_face(U0 *cr, U8 *family, I32 slant, I32 weight);
extern "c" U0  cairo_set_font_size(U0 *cr, F64 size);
extern "c" U0  cairo_show_text(U0 *cr, U8 *utf8);
extern "c" U0  cairo_text_extents(U0 *cr, U8 *utf8, CairoTextExtents *extents);
extern "c" U0  cairo_set_antialias(U0 *cr, I32 antialias);
extern "c" U0 *cairo_font_options_create();
extern "c" U0  cairo_font_options_destroy(U0 *options);
extern "c" U0  cairo_font_options_set_antialias(U0 *options, I32 antialias);
extern "c" U0  cairo_set_font_options(U0 *cr, U0 *options);
extern "c" U0 *cairo_get_source(U0 *cr);
extern "c" U0  cairo_pattern_set_filter(U0 *pattern, I32 filter);

/* --- Функции OpenSSL (libssl) для поддержки HTTPS/TLS --- */
extern "c" U0 *TLS_client_method();
extern "c" U0 *SSL_CTX_new(U0 *method);
extern "c" U0  SSL_CTX_free(U0 *ctx);
extern "c" I32 SSL_CTX_set_default_verify_paths(U0 *ctx);
extern "c" U0  SSL_CTX_set_verify(U0 *ctx, I32 mode, U0 *callback);
extern "c" I32 SSL_set1_host(U0 *ssl, U8 *hostname);
extern "c" U0 *SSL_get0_param(U0 *ssl);
extern "c" I32 X509_VERIFY_PARAM_set1_ip_asc(U0 *param, U8 *ip);
extern "c" I32 inet_pton(I32 af, U8 *src, U0 *dst);
extern "c" U0 *SSL_new(U0 *ctx);
extern "c" I32 SSL_set_fd(U0 *ssl, I32 fd);
extern "c" I64 SSL_ctrl(U0 *ssl, I32 cmd, I64 larg, U0 *parg);
extern "c" I32 SSL_connect(U0 *ssl);
extern "c" I32 SSL_write(U0 *ssl, U0 *buf, I32 num);
extern "c" I32 SSL_read(U0 *ssl, U0 *buf, I32 num);
extern "c" I32 SSL_pending(U0 *ssl);
extern "c" I32 SSL_shutdown(U0 *ssl);
extern "c" U0  SSL_set_quiet_shutdown(U0 *ssl, I32 mode);
extern "c" U0  SSL_free(U0 *ssl);

/* --- Функции zlib (libz) для мгновенной упаковки и распаковки gzip --- */
extern "c" U0 *gzopen(U8 *path, U8 *mode);
extern "c" I32 gzread(U0 *file, U0 *buf, U32 len);
extern "c" I32 gzwrite(U0 *file, U0 *buf, U32 len);
extern "c" I32 gzclose(U0 *file);

/* --- Функции libgdk_pixbuf-2.0 для декодирования PNG/JPEG/SVG/GIF/WebP --- */
extern "c" U0 *gdk_pixbuf_new_from_file(U8 *filename, U0 **error);
extern "c" I32 gdk_pixbuf_get_width(U0 *pixbuf);
extern "c" I32 gdk_pixbuf_get_height(U0 *pixbuf);
extern "c" I32 gdk_pixbuf_get_rowstride(U0 *pixbuf);
extern "c" I32 gdk_pixbuf_get_n_channels(U0 *pixbuf);
extern "c" U8 *gdk_pixbuf_get_pixels(U0 *pixbuf);
extern "c" U0  g_object_unref(U0 *object);

extern "c" I32 usleep(U32 usec);

/* QuickJS uses an opaque scalar/pointer ABI; JSValue never crosses HolyC. */
extern "c" U0 QjsSetFetchCallback(U0 *fn);
extern "c" U8 *QjsAllocBuf(I64 size);
extern "c" U0 *QjsPageCreate();
extern "c" U0 QjsPageDestroy(U0 *page);
extern "c" U8 *QjsPageLoadHtml(U0 *page, U8 *html, I64 len, U8 *url, I64 *out_len);
extern "c" I32 QjsPageClickId(U0 *page, I32 id);
extern "c" I32 QjsPageEvalUrl(U0 *page, U8 *code);
extern "c" I32 QjsPageTickTimers(U0 *page);
extern "c" I32 QjsPageHasActiveTimers(U0 *page);
extern "c" U8 *QjsPageSerializeHtml(U0 *page, I64 *out_len);
extern "c" I32 QjsPagePopRedirect(U0 *page, U8 *url, I64 cap);
extern "c" U0 QjsFreeStr(U8 *s);

/* Ignore SIGPIPE so a disconnected peer cannot terminate the process. */
extern "c" U0 *signal(I32 signum, U0 *handler);
extern "c" I32 mkstemp(U8 *template_path);

extern "c" I32 flock(I32 fd, I32 operation);

/* Holynet uses the privately managed Tor process only. */
extern "c" I32 HolyTorConnect(U8 *host, I32 port);
