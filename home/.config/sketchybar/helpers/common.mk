# Shared settings for the SketchyBar helper builds. make's builtin CC (cc)
# is Apple clang; check.sh adds -Werror through EXTRA_CFLAGS.
CFLAGS ?= -std=c99 -O3 -Wall -Wextra -Wpedantic -Wconversion -Wshadow $(EXTRA_CFLAGS)
BINDIR ?= bin
