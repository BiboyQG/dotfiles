#pragma once

#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

struct cpu {
  host_t host;
  mach_msg_type_number_t count;
  host_cpu_load_info_data_t load;
  host_cpu_load_info_data_t prev_load;
  bool has_prev_load;
  int user_load;
  int sys_load;
  int total_load;
};

static inline void cpu_init(struct cpu *cpu) {
  *cpu = (struct cpu){ 0 };
  cpu->host = mach_host_self();
  cpu->count = HOST_CPU_LOAD_INFO_COUNT;
}

static inline bool cpu_update(struct cpu *cpu) {
  cpu->count = HOST_CPU_LOAD_INFO_COUNT;
  kern_return_t error = host_statistics(cpu->host,
                                        HOST_CPU_LOAD_INFO,
                                        (host_info_t)&cpu->load,
                                        &cpu->count);
  if (error != KERN_SUCCESS) {
    fprintf(stderr, "Error: Could not read CPU host statistics.\n");
    return false;
  }

  if (!cpu->has_prev_load) {
    cpu->prev_load = cpu->load;
    cpu->has_prev_load = true;
    return false;
  }

  uint32_t delta_user = cpu->load.cpu_ticks[CPU_STATE_USER]
                        - cpu->prev_load.cpu_ticks[CPU_STATE_USER];
  uint32_t delta_nice = cpu->load.cpu_ticks[CPU_STATE_NICE]
                        - cpu->prev_load.cpu_ticks[CPU_STATE_NICE];
  uint32_t delta_system = cpu->load.cpu_ticks[CPU_STATE_SYSTEM]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_SYSTEM];
  uint32_t delta_idle = cpu->load.cpu_ticks[CPU_STATE_IDLE]
                        - cpu->prev_load.cpu_ticks[CPU_STATE_IDLE];
  cpu->prev_load = cpu->load;

  uint64_t user_ticks = (uint64_t)delta_user + (uint64_t)delta_nice;
  uint64_t total_ticks = user_ticks + (uint64_t)delta_system
                         + (uint64_t)delta_idle;
  if (!total_ticks) return false;

  cpu->user_load = (int)((double)user_ticks / (double)total_ticks * 100.0);
  cpu->sys_load = (int)((double)delta_system / (double)total_ticks * 100.0);
  cpu->total_load = cpu->user_load + cpu->sys_load;
  return true;
}
