#pragma once

#include <ifaddrs.h>
#include <limits.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/time.h>

static const char unit_str[][6] = { " Bps", "KBps", "MBps", "GBps" };

enum unit {
  UNIT_BPS,
  UNIT_KBPS,
  UNIT_MBPS,
  UNIT_GBPS
};

enum network_connection_status {
  NETWORK_CONNECTION_UNKNOWN,
  NETWORK_CONNECTION_OFF,
  NETWORK_CONNECTION_ON
};

struct network {
  int32_t row;
  struct ifmibdata data;
  struct timeval previous_time;
  int up;
  int down;
  enum unit up_unit;
  enum unit down_unit;
};

static inline bool ifdata(int32_t net_row, struct ifmibdata *data) {
  int data_option[] = {
    CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, net_row, IFDATA_GENERAL
  };
  size_t size = sizeof(*data);
  return sysctl(data_option, 6, data, &size, NULL, 0) == 0;
}

// A self-assigned IPv4 address (169.254/16) or a link-local IPv6 address
// (fe80::/10) means the interface is up without a usable network.
static inline bool address_is_routable(const struct sockaddr *address) {
  if (address->sa_family == AF_INET) {
    const struct sockaddr_in *inet =
        (const struct sockaddr_in *)(const void *)address;
    const uint8_t *octets = (const uint8_t *)&inet->sin_addr;
    return !(octets[0] == 169 && octets[1] == 254);
  }
  if (address->sa_family == AF_INET6) {
    const struct sockaddr_in6 *inet6 =
        (const struct sockaddr_in6 *)(const void *)address;
    return !IN6_IS_ADDR_LINKLOCAL(&inet6->sin6_addr);
  }
  return false;
}

static inline enum network_connection_status
network_connection_from_interfaces(const char *ifname,
                                   const struct ifaddrs *interfaces) {
  if (!ifname) return NETWORK_CONNECTION_UNKNOWN;

  for (const struct ifaddrs *interface = interfaces;
       interface;
       interface = interface->ifa_next) {
    if (interface->ifa_name && interface->ifa_addr
        && strcmp(interface->ifa_name, ifname) == 0
        && address_is_routable(interface->ifa_addr)) {
      return NETWORK_CONNECTION_ON;
    }
  }
  return NETWORK_CONNECTION_OFF;
}

static inline enum network_connection_status
network_connection(const char *ifname) {
  struct ifaddrs *interfaces = NULL;
  if (getifaddrs(&interfaces) != 0) return NETWORK_CONNECTION_UNKNOWN;

  enum network_connection_status status =
      network_connection_from_interfaces(ifname, interfaces);
  if (interfaces) freeifaddrs(interfaces);
  return status;
}

static inline const char *network_connection_string(
    enum network_connection_status status) {
  switch (status) {
    case NETWORK_CONNECTION_ON:
      return "on";
    case NETWORK_CONNECTION_OFF:
      return "off";
    case NETWORK_CONNECTION_UNKNOWN:
      return "unknown";
  }
  return "unknown";
}

static inline bool network_init(struct network *net, const char *ifname) {
  *net = (struct network){ 0 };

  int count_option[] = {
    CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT
  };
  uint32_t interface_count = 0;
  size_t size = sizeof(interface_count);
  if (sysctl(count_option, 5, &interface_count, &size, NULL, 0) != 0) {
    return false;
  }

  for (uint32_t row = 1; row <= interface_count && row <= INT32_MAX; ++row) {
    if (!ifdata((int32_t)row, &net->data)) continue;
    if (strcmp(net->data.ifmd_name, ifname) == 0) {
      net->row = (int32_t)row;
      gettimeofday(&net->previous_time, NULL);
      return true;
    }
  }
  return false;
}

static inline void scaled_rate(double rate, int *value, enum unit *unit) {
  double divisor = 1.0;
  *unit = UNIT_BPS;
  if (rate >= 1000000000.0) {
    divisor = 1000000000.0;
    *unit = UNIT_GBPS;
  } else if (rate >= 1000000.0) {
    divisor = 1000000.0;
    *unit = UNIT_MBPS;
  } else if (rate >= 1000.0) {
    divisor = 1000.0;
    *unit = UNIT_KBPS;
  }

  double scaled = rate / divisor;
  if (scaled > (double)INT_MAX) scaled = (double)INT_MAX;
  *value = (int)scaled;
}

static inline bool network_update(struct network *net) {
  uint64_t previous_in = net->data.ifmd_data.ifi_ibytes;
  uint64_t previous_out = net->data.ifmd_data.ifi_obytes;
  if (!ifdata(net->row, &net->data)) return false;

  struct timeval current_time = { 0 };
  struct timeval delta_time = { 0 };
  gettimeofday(&current_time, NULL);
  timersub(&current_time, &net->previous_time, &delta_time);
  net->previous_time = current_time;

  if (net->data.ifmd_data.ifi_ibytes < previous_in
      || net->data.ifmd_data.ifi_obytes < previous_out) {
    return false;
  }

  double elapsed = (double)delta_time.tv_sec
                   + (double)delta_time.tv_usec / 1000000.0;
  if (elapsed < 0.000001 || elapsed > 100.0) return false;

  double down_rate = (double)(net->data.ifmd_data.ifi_ibytes - previous_in)
                     / elapsed;
  double up_rate = (double)(net->data.ifmd_data.ifi_obytes - previous_out)
                   / elapsed;
  scaled_rate(down_rate, &net->down, &net->down_unit);
  scaled_rate(up_rate, &net->up, &net->up_unit);
  return true;
}
