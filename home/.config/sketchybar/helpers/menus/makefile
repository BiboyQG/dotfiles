include ../common.mk

$(BINDIR)/menus: menus.c
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) -F/System/Library/PrivateFrameworks -framework Carbon -framework SkyLight $< -o $@

.PHONY: all
all: $(BINDIR)/menus
