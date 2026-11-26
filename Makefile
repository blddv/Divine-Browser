# =============================================================================
# Makefile — Сборка графического 2D-браузера DivineWeb v2.0 на HolyC (holyc-lang)
# Вкладки, Закладки, Картинки (PNG/JPEG/SVG/WebP), 2D-таблицы, P2P HOLYNET
# =============================================================================

HCC    ?= $(shell if [ -x /home/user/hcc-toolchain/bin/hcc ]; then echo /home/user/hcc-toolchain/bin/hcc; else echo hcc; fi)
CLIBS  := -lX11 -lcairo -lgdk_pixbuf-2.0 -lgobject-2.0 -lssl -lcrypto -lz -lpthread -lm
TARGET := holy-browser
SRCS   := browser.HC bindings.HH url_http.HC image_loader.HC html_dom.HC layout_render.HC holynet_p2p.HC holynet_global_mesh.HC holynet_search.HC holynet_builder.HC css_legacy.HC js_engine.HC

.PHONY: all run holynet demo modern clean test

all: $(TARGET)

QJS_OBJS := $(addprefix quickjs/,quickjs.o dtoa.o libregexp.o libunicode.o cutils.o qjs_bridge.o)
QJS_LIB := quickjs/libqjs_divine.a

quickjs/%.o: quickjs/%.c
	$(CC) -O2 -std=gnu11 -Dhas_suffix=qjs_has_suffix -D_GNU_SOURCE -DCONFIG_VERSION=\"2026-06-04\" -c $< -o $@

$(QJS_LIB): $(QJS_OBJS)
	$(AR) rcs $@ $^

tor_bridge.o: tor_bridge.c
	$(CC) -O2 -Wall -Wextra -c $< -o $@

$(TARGET): $(SRCS) $(QJS_LIB) tor_bridge.o
	$(HCC) -clibs="$(CURDIR)/$(QJS_LIB) $(CURDIR)/tor_bridge.o $(CLIBS) -ldl" -o $(TARGET) browser.HC

run: $(TARGET)
	./$(TARGET) temple://home

holynet: $(TARGET)
	./$(TARGET) --holynet

demo: $(TARGET)
	./$(TARGET) ./demo.html

modern: $(TARGET)
	./$(TARGET) ./demo.html --modern

test: $(TARGET)
	$(CC) -O2 tests/test_quickjs.c $(QJS_LIB) -lm -ldl -lpthread -o tests/test_quickjs
	./tests/test_quickjs
	$(HCC) -clibs="$(CLIBS)" -o tests/test_css tests/test_css.HC
	./tests/test_css
	$(HCC) -clibs="$(CURDIR)/tor_bridge.o $(CLIBS)" -o tests/test_holynet tests/test_holynet.HC
	./tests/test_holynet
	$(HCC) -clibs="$(CLIBS)" -o tests/test_tls tests/test_tls.HC
	python3 tests/test_tls.py
	python3 tests/test_http.py
	python3 tests/test_tor_bridge.py
	python3 tests/test_relay_privacy.py

clean:
	rm -f $(TARGET) *.o $(QJS_OBJS) $(QJS_LIB) tests/test_quickjs tests/test_css tests/test_holynet tests/test_tls
