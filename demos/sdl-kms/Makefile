CC ?= cc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2 -g
CFLAGS += -Wall -Wextra
GRAPHICS_PREFIX ?= /opt/darkos-graphics
CPPFLAGS += -I$(GRAPHICS_PREFIX)/usr/include/SDL2 -I$(GRAPHICS_PREFIX)/usr/include
LDFLAGS += -L$(GRAPHICS_PREFIX)/usr/lib/aarch64-linux-gnu

hello: hello.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@ $(LDFLAGS) $$($(PKG_CONFIG) --cflags --libs sdl2 glesv2)

clean:
	rm -f hello

.PHONY: clean
