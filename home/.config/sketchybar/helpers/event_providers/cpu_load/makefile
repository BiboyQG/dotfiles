include ../../common.mk

$(BINDIR)/cpu_load: cpu_load.c cpu.h ../frequency.h ../sketchybar.h
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $< -o $@
