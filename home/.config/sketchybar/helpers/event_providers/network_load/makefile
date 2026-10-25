include ../../common.mk

$(BINDIR)/network_load: network_load.c network.h ../frequency.h ../sketchybar.h
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $< -o $@
