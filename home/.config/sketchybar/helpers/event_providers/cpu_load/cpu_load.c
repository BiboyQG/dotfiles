#include <stdio.h>
#include <unistd.h>

#include "../frequency.h"
#include "../sketchybar.h"
#include "cpu.h"

int main(int argc, char **argv) {
  useconds_t sleep_us = 0;
  if (argc != 3 || !parse_update_frequency(argv[2], &sleep_us)) {
    fprintf(stderr, "Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    return 1;
  }

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
