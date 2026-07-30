#pragma once

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>

static inline bool parse_update_frequency(const char *text,
                                          useconds_t *sleep_us) {
  if (!text || !sleep_us) return false;

  errno = 0;
  char *end = NULL;
  double seconds = strtod(text, &end);
  if (errno == ERANGE || end == text || *end != '\0' || !isfinite(seconds)
      || seconds <= 0.0) {
    return false;
  }

  double microseconds = seconds * 1000000.0;
  if (microseconds < 1.0 || microseconds > (double)UINT_MAX) return false;

  *sleep_us = (useconds_t)microseconds;
  return true;
}
