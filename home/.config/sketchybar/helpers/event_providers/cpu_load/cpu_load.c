#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "../sketchybar.h"
#include "cpu.h"

int main(int argc, char **argv) {
  double update_freq = 0.0;
  if (argc < 3 || sscanf(argv[2], "%lf", &update_freq) != 1
      || update_freq <= 0.0
      || update_freq > (double)UINT_MAX / 1000000.0) {
    fprintf(stderr, "Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    return 1;
  }
  useconds_t sleep_us = (useconds_t)(update_freq * 1000000.0);

  alarm(0);
  struct cpu cpu;
  cpu_init(&cpu);

  char event_message[512];
  snprintf(event_message, sizeof(event_message), "--add event '%s'", argv[1]);
  sketchybar(event_message);

  char trigger_message[512];
  for (;;) {
    if (cpu_update(&cpu)) {
      snprintf(trigger_message,
               sizeof(trigger_message),
               "--trigger '%s' user_load='%d' sys_load='%02d' total_load='%02d'",
               argv[1],
               cpu.user_load,
               cpu.sys_load,
               cpu.total_load);
      sketchybar(trigger_message);
    }
    usleep(sleep_us);
  }
}
