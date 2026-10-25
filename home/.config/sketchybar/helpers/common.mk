# Shared settings for the SketchyBar helper builds. make's builtin CC (cc)
# is Apple clang. setup.sh builds with these flags as they are; check.sh
# passes EXTRA_CFLAGS=-Werror so warnings fail the suite.
CFLAGS ?= -std=c99 -O3 -Wall -Wextra -Wpedantic -Wconversion -Wshadow $(EXTRA_CFLAGS)
