#include <stdio.h>
#include <unistd.h>

#include "../frequency.h"
#include "../sketchybar.h"
#include "network.h"

int main(int argc, char **argv) {
  useconds_t sleep_us = 0;
  if (argc != 4 || !parse_update_frequency(argv[3], &sleep_us)) {
    fprintf(stderr,
            "Usage: %s \"<interface>\" \"<event-name>\" \"<event_freq>\"\n",
            argv[0]);
    return 1;
  }

  struct network network = { 0 };
  bool network_ready = false;

  char event_message[512];
  snprintf(event_message, sizeof(event_message), "--add event '%s'", argv[2]);
  sketchybar(event_message);

  char trigger_message[512];
  for (;;) {
    if (!network_ready || !network_update(&network)) {
      network_ready = network_init(&network, argv[1]);
    }

    snprintf(trigger_message,
             sizeof(trigger_message),
             "--trigger '%s' upload='%03d%s' download='%03d%s' connected='%s'",
             argv[2],
             network.up,
             unit_str[network.up_unit],
             network.down,
             unit_str[network.down_unit],
             network_connected(argv[1]) ? "on" : "off");
    sketchybar(trigger_message);
    usleep(sleep_us);
  }
}
