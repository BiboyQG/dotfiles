CC ?= clang
CFLAGS ?= -std=c99 -O3 -Wall -Wextra -Wpedantic -Wconversion -Wshadow
BINDIR ?= bin

$(BINDIR)/network_load: network_load.c network.h ../sketchybar.h
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $< -o $@

.PHONY: all
all: $(BINDIR)/network_load
