#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "../sketchybar.h"
#include "network.h"

int main(int argc, char **argv) {
  double update_freq = 0.0;
  if (argc < 4 || sscanf(argv[3], "%lf", &update_freq) != 1
      || update_freq <= 0.0
      || update_freq > (double)UINT_MAX / 1000000.0) {
    fprintf(stderr,
            "Usage: %s \"<interface>\" \"<event-name>\" \"<event_freq>\"\n",
            argv[0]);
    return 1;
  }
  useconds_t sleep_us = (useconds_t)(update_freq * 1000000.0);

  struct network network;
  if (!network_init(&network, argv[1])) {
    fprintf(stderr, "Error: Could not find network interface %s.\n", argv[1]);
    return 1;
  }

  alarm(0);
  char event_message[512];
  snprintf(event_message, sizeof(event_message), "--add event '%s'", argv[2]);
  sketchybar(event_message);

  char trigger_message[512];
  for (;;) {
    if (network_update(&network)) {
      snprintf(trigger_message,
               sizeof(trigger_message),
               "--trigger '%s' upload='%03d%s' download='%03d%s'",
               argv[2],
               network.up,
               unit_str[network.up_unit],
               network.down,
               unit_str[network.down_unit]);
      sketchybar(trigger_message);
    }
    usleep(sleep_us);
  }
}
