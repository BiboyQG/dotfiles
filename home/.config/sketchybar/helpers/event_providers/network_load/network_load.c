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

  alarm(0);
  char event_message[512];
  snprintf(event_message, sizeof(event_message), "--add event '%s'", argv[2]);
  sketchybar(event_message);

  char trigger_message[512];
  for (;;) {
    bool has_rate = false;
    if (!network_ready) {
      network_ready = network_init(&network, argv[1]);
    } else if (!(has_rate = network_update(&network))) {
      network_ready = network_init(&network, argv[1]);
    }
    int up = has_rate ? network.up : 0;
    int down = has_rate ? network.down : 0;
    enum unit up_unit = has_rate ? network.up_unit : UNIT_BPS;
    enum unit down_unit = has_rate ? network.down_unit : UNIT_BPS;
    const char *connected = network_connection_string(
        network_connection(argv[1]));

    snprintf(trigger_message,
             sizeof(trigger_message),
             "--trigger '%s' upload='%03d%s' download='%03d%s' connected='%s'",
             argv[2],
             up,
             unit_str[up_unit],
             down,
             unit_str[down_unit],
             connected);
    sketchybar(trigger_message);
    usleep(sleep_us);
  }
}
