CC ?= clang
CFLAGS ?= -std=c99 -O3 -Wall -Wextra -Wpedantic -Wconversion -Wshadow
BINDIR ?= bin

$(BINDIR)/cpu_load: cpu_load.c cpu.h ../sketchybar.h
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $< -o $@

.PHONY: all
all: $(BINDIR)/cpu_load
