CC ?= clang
CFLAGS ?= -std=c99 -O3 -Wall -Wextra -Wpedantic -Wconversion -Wshadow
BINDIR ?= bin

$(BINDIR)/menus: menus.c
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) -F/System/Library/PrivateFrameworks -framework Carbon -framework SkyLight $< -o $@

.PHONY: all
all: $(BINDIR)/menus
