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

static inline mach_port_t mach_get_bs_port(kern_return_t *lookup_error) {
  mach_port_t bs_port = MACH_PORT_NULL;
  *lookup_error = task_get_special_port(mach_task_self(),
                                        TASK_BOOTSTRAP_PORT,
                                        &bs_port);
  if (*lookup_error != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }

  const char *name = getenv("BAR_NAME");
  if (!name) name = "sketchybar";

  size_t lookup_len = strlen(name) + sizeof("git.felix.");
  char buffer[lookup_len];
  snprintf(buffer, lookup_len, "git.felix.%s", name);

  mach_port_t port = MACH_PORT_NULL;
  *lookup_error = bootstrap_look_up(bs_port, buffer, &port);
  mach_port_deallocate(mach_task_self(), bs_port);
  if (*lookup_error != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }
  return port;
}

static inline mach_msg_return_t mach_send_message(mach_port_t port,
                                                  char *message,
                                                  size_t len) {
  if (!message || !MACH_PORT_VALID(port) || len > UINT32_MAX) {
    return MACH_SEND_INVALID_DEST;
  }

  struct mach_message msg = { 0 };
  msg.header.msgh_remote_port = port;
  msg.header.msgh_local_port = MACH_PORT_NULL;
  msg.header.msgh_id = 0;
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

  if (caret > 1 && formatted_message[caret - 1] == '\0'
      && formatted_message[caret - 2] == '\0') {
    --caret;
  }
  formatted_message[caret] = '\0';
  return caret + 1;
}

static inline void sketchybar(const char *message) {
  char formatted_message[strlen(message) + 2];
  size_t length = format_message(message, formatted_message);
  if (!length) return;

  kern_return_t first_lookup_error = KERN_SUCCESS;
  if (!MACH_PORT_VALID(g_mach_port)) {
    g_mach_port = mach_get_bs_port(&first_lookup_error);
  }
  mach_msg_return_t first_send_error = mach_send_message(g_mach_port,
                                                         formatted_message,
                                                         length);
  if (first_send_error == MACH_MSG_SUCCESS) return;

  if (MACH_PORT_VALID(g_mach_port)) {
    mach_port_deallocate(mach_task_self(), g_mach_port);
  }
  g_mach_port = MACH_PORT_NULL;

  kern_return_t retry_lookup_error = KERN_SUCCESS;
  g_mach_port = mach_get_bs_port(&retry_lookup_error);
  mach_msg_return_t retry_send_error = mach_send_message(g_mach_port,
                                                         formatted_message,
                                                         length);
  if (retry_send_error == MACH_MSG_SUCCESS) return;

  fprintf(stderr,
          "Error: Could not send message to SketchyBar after reconnect "
          "(first lookup: %d, first send: %d, "
          "retry lookup: %d, retry send: %d).\n",
          first_lookup_error,
          first_send_error,
          retry_lookup_error,
          retry_send_error);
  exit(EXIT_FAILURE);
}
