#include <Carbon/Carbon.h>

#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int SLSMainConnectionID(void);
extern void _SLPSGetFrontProcess(ProcessSerialNumber *psn);
extern void SLSGetConnectionIDForPSN(int cid,
                                     ProcessSerialNumber *psn,
                                     int *cid_out);
extern void SLSConnectionGetPID(int cid, pid_t *pid_out);

static void ax_init(void) {
  const void *keys[] = { kAXTrustedCheckOptionPrompt };
  const void *values[] = { kCFBooleanTrue };
  CFDictionaryRef options = CFDictionaryCreate(
      kCFAllocatorDefault,
      keys,
      values,
      sizeof(keys) / sizeof(*keys),
      &kCFCopyStringDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);

  bool trusted = AXIsProcessTrustedWithOptions(options);
  CFRelease(options);
  if (!trusted) exit(1);

  // The default messaging timeout is about 6 s per call, so an unresponsive
  // app would block the bar's menu query; a timeout set on the system-wide
  // element applies to every element that does not set its own.
  AXUIElementRef system_wide = AXUIElementCreateSystemWide();
  AXUIElementSetMessagingTimeout(system_wide, 1.0f);
  CFRelease(system_wide);
}

static void ax_perform_click(AXUIElementRef element) {
  AXUIElementPerformAction(element, kAXCancelAction);
  usleep(150000);
  AXUIElementPerformAction(element, kAXPressAction);
}

static CFStringRef ax_get_title(AXUIElementRef element) {
  CFTypeRef title = NULL;
  AXError error = AXUIElementCopyAttributeValue(element,
                                                kAXTitleAttribute,
                                                &title);
  if (error != kAXErrorSuccess || !title
      || CFGetTypeID(title) != CFStringGetTypeID()) {
    if (title) CFRelease(title);
    return NULL;
  }
  return (CFStringRef)title;
}

// Returns the visible children of the app's menubar, or NULL. The children
// hold their own references, so the menubar is released before returning.
static CFArrayRef ax_copy_menu_items(AXUIElementRef app) {
  AXUIElementRef menubar = NULL;
  CFTypeRef children = NULL;
  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXMenuBarAttribute,
                                                (CFTypeRef *)&menubar);
  if (error == kAXErrorSuccess && menubar) {
    error = AXUIElementCopyAttributeValue(menubar,
                                          kAXVisibleChildrenAttribute,
                                          &children);
  }
  if (menubar) CFRelease(menubar);
  if (children
      && (error != kAXErrorSuccess
          || CFGetTypeID(children) != CFArrayGetTypeID())) {
    CFRelease(children);
    children = NULL;
  }
  return (CFArrayRef)children;
}

static bool ax_select_menu_option(AXUIElementRef app, int id) {
  CFArrayRef children = ax_copy_menu_items(app);
  if (!children) return false;

  bool found = (CFIndex)id < CFArrayGetCount(children);
  if (found) {
    ax_perform_click((AXUIElementRef)CFArrayGetValueAtIndex(children,
                                                            (CFIndex)id));
  }
  CFRelease(children);
  return found;
}

// Prints one line per menubar child so line i always maps to child i, which
// `-s i` clicks; an untitled or empty title prints a single space because the
// Lua side skips empty lines.
static void ax_print_title_line(CFStringRef title) {
  bool printed = false;
  if (title) {
    CFIndex capacity = CFStringGetMaximumSizeForEncoding(
                           CFStringGetLength(title),
                           kCFStringEncodingUTF8)
                       + 1;
    char *buffer = malloc((size_t)capacity);
    if (CFStringGetCString(title, buffer, capacity, kCFStringEncodingUTF8)
        && buffer[0] != '\0') {
      printf("%s\n", buffer);
      printed = true;
    }
    free(buffer);
    CFRelease(title);
  }
  if (!printed) printf(" \n");
}

static void ax_print_menu_options(AXUIElementRef app) {
  CFArrayRef children = ax_copy_menu_items(app);
  if (!children) return;

  CFIndex count = CFArrayGetCount(children);
  for (CFIndex i = 1; i < count; ++i) {
    AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
    ax_print_title_line(ax_get_title(item));
  }
  CFRelease(children);
}

static AXUIElementRef ax_get_front_app(void) {
  ProcessSerialNumber psn = { 0 };
  _SLPSGetFrontProcess(&psn);

  int target_cid = 0;
  SLSGetConnectionIDForPSN(SLSMainConnectionID(), &psn, &target_cid);
  if (!target_cid) return NULL;

  pid_t pid = 0;
  SLSConnectionGetPID(target_cid, &pid);
  if (!pid) return NULL;
  return AXUIElementCreateApplication(pid);
}

static bool parse_menu_index(const char *text, int *id) {
  char *end = NULL;
  errno = 0;
  long value = strtol(text, &end, 10);
  if (errno != 0 || end == text || *end != '\0' || value < 0
      || value > INT_MAX) {
    return false;
  }
  *id = (int)value;
  return true;
}

int main(int argc, char **argv) {
  int id = 0;
  bool list = argc == 2 && strcmp(argv[1], "-l") == 0;
  bool select = argc == 3 && strcmp(argv[1], "-s") == 0
                && parse_menu_index(argv[2], &id);
  if (!list && !select) {
    fprintf(stderr, "Usage: %s [-l | -s <index>]\n", argv[0]);
    return 2;
  }

  ax_init();
  AXUIElementRef app = ax_get_front_app();
  if (!app) return 1;

  bool ok = true;
  if (list) {
    ax_print_menu_options(app);
  } else {
    ok = ax_select_menu_option(app, id);
  }
  CFRelease(app);
  return ok ? 0 : 1;
}
