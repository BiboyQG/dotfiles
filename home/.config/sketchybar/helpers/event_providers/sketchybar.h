#pragma once

#include <bootstrap.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static mach_port_t g_mach_port = MACH_PORT_NULL;

struct mach_message {
  mach_msg_header_t header;
  mach_msg_size_t msgh_descriptor_count;
  mach_msg_ool_descriptor_t descriptor;
};

static inline mach_port_t mach_get_bs_port(void) {
  mach_port_t bs_port = MACH_PORT_NULL;
  if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &bs_port)
      != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }

  const char *name = getenv("BAR_NAME");
  if (!name) name = "sketchybar";

  size_t lookup_len = strlen(name) + sizeof("git.felix.");
  char buffer[lookup_len];
  snprintf(buffer, lookup_len, "git.felix.%s", name);

  mach_port_t port = MACH_PORT_NULL;
  kern_return_t error = bootstrap_look_up(bs_port, buffer, &port);
  mach_port_deallocate(mach_task_self(), bs_port);
  return error == KERN_SUCCESS ? port : MACH_PORT_NULL;
}

static inline mach_msg_return_t mach_send_message(mach_port_t port,
                                                  char *message,
                                                  size_t len) {
  if (!MACH_PORT_VALID(port)) return MACH_SEND_INVALID_DEST;

  struct mach_message msg = { 0 };
  msg.header.msgh_remote_port = port;
  msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND,
                                            MACH_MSG_TYPE_MAKE_SEND,
                                            0,
                                            MACH_MSGH_BITS_COMPLEX);
  msg.header.msgh_size = (mach_msg_size_t)sizeof(msg);
  msg.msgh_descriptor_count = 1;
  msg.descriptor.address = message;
  msg.descriptor.size = (mach_msg_size_t)len;
  msg.descriptor.copy = MACH_MSG_VIRTUAL_COPY;
  msg.descriptor.deallocate = false;
  msg.descriptor.type = MACH_MSG_OOL_DESCRIPTOR;

  return mach_msg(&msg.header,
                  MACH_SEND_MSG,
                  (mach_msg_size_t)sizeof(msg),
                  0,
                  MACH_PORT_NULL,
                  MACH_MSG_TIMEOUT_NONE,
                  MACH_PORT_NULL);
}

static inline size_t format_message(const char *message,
                                    char *formatted_message) {
  char outer_quote = 0;
  size_t caret = 0;
  size_t message_length = strlen(message) + 1;

  for (size_t i = 0; i < message_length; ++i) {
    if (message[i] == '"' || message[i] == '\'') {
      if (outer_quote == message[i]) outer_quote = 0;
      else if (!outer_quote) outer_quote = message[i];
      continue;
    }

    formatted_message[caret] = message[i];
    if (message[i] == ' ' && !outer_quote) formatted_message[caret] = '\0';
    ++caret;
  }

  formatted_message[caret] = '\0';
  return caret + 1;
}

static inline void sketchybar(const char *message) {
  char formatted_message[strlen(message) + 2];
  size_t length = format_message(message, formatted_message);

  if (!MACH_PORT_VALID(g_mach_port)) g_mach_port = mach_get_bs_port();
  mach_msg_return_t error = mach_send_message(g_mach_port,
                                              formatted_message,
                                              length);
  if (error == MACH_MSG_SUCCESS) return;

  fprintf(stderr,
          "Error: Could not send message to SketchyBar (%d).\n",
          error);
  exit(EXIT_FAILURE);
}
