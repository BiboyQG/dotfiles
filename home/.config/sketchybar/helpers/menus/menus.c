#include <Carbon/Carbon.h>

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
  if (!options) exit(1);

  bool trusted = AXIsProcessTrustedWithOptions(options);
  CFRelease(options);
  if (!trusted) exit(1);
}

static void ax_perform_click(AXUIElementRef element) {
  if (!element) return;
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

static void ax_select_menu_option(AXUIElementRef app, int id) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXMenuBarAttribute,
                                                (CFTypeRef *)&menubar);
  if (error == kAXErrorSuccess) {
    error = AXUIElementCopyAttributeValue(menubar,
                                          kAXVisibleChildrenAttribute,
                                          (CFTypeRef *)&children);
  }

  if (error == kAXErrorSuccess && id >= 0 && (CFIndex)id < CFArrayGetCount(children)) {
    AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(children,
                                                                (CFIndex)id);
    ax_perform_click(item);
  }
  if (children) CFRelease(children);
  if (menubar) CFRelease(menubar);
}

static void ax_print_menu_options(AXUIElementRef app) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXMenuBarAttribute,
                                                (CFTypeRef *)&menubar);
  if (error == kAXErrorSuccess) {
    error = AXUIElementCopyAttributeValue(menubar,
                                          kAXVisibleChildrenAttribute,
                                          (CFTypeRef *)&children);
  }

  if (error == kAXErrorSuccess) {
    CFIndex count = CFArrayGetCount(children);
    for (CFIndex i = 1; i < count; ++i) {
      AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
      CFStringRef title = ax_get_title(item);
      if (!title) continue;

      CFIndex capacity = CFStringGetMaximumSizeForEncoding(
                             CFStringGetLength(title),
                             kCFStringEncodingUTF8)
                         + 1;
      if (capacity > 0) {
        char *buffer = malloc((size_t)capacity);
        if (buffer && CFStringGetCString(title,
                                         buffer,
                                         capacity,
                                         kCFStringEncodingUTF8)) {
          printf("%s\n", buffer);
        }
        free(buffer);
      }
      CFRelease(title);
    }
  }
  if (children) CFRelease(children);
  if (menubar) CFRelease(menubar);
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

int main(int argc, char **argv) {
  if (argc == 1) {
    printf("Usage: %s [-l | -s id]\n", argv[0]);
    return 0;
  }

  ax_init();
  if (strcmp(argv[1], "-l") == 0) {
    AXUIElementRef app = ax_get_front_app();
    if (!app) return 1;
    ax_print_menu_options(app);
    CFRelease(app);
  } else if (argc == 3 && strcmp(argv[1], "-s") == 0) {
    int id = 0;
    if (sscanf(argv[2], "%d", &id) != 1) return 1;
    AXUIElementRef app = ax_get_front_app();
    if (!app) return 1;
    ax_select_menu_option(app, id);
    CFRelease(app);
  }
  return 0;
}
