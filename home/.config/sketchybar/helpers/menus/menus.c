#include <Carbon/Carbon.h>

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int SLSMainConnectionID(void);
extern void SLSSetMenuBarVisibilityOverrideOnDisplay(int cid,
                                                     int did,
                                                     bool enabled);
extern void SLSSetMenuBarInsetAndAlpha(int cid,
                                       double unused1,
                                       double unused2,
                                       float alpha);
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

static AXUIElementRef ax_get_extra_menu_item(const char *alias) {
  pid_t pid = 0;
  CGRect bounds = CGRectNull;
  CFArrayRef window_list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll,
                                                      kCGNullWindowID);
  if (!window_list) return NULL;

  char owner_buffer[256];
  char name_buffer[256];
  char buffer[512];
  CFIndex window_count = CFArrayGetCount(window_list);
  for (CFIndex i = 0; i < window_count; ++i) {
    CFDictionaryRef dictionary = CFArrayGetValueAtIndex(window_list, i);
    if (!dictionary) continue;

    CFStringRef owner = CFDictionaryGetValue(dictionary, kCGWindowOwnerName);
    CFNumberRef owner_pid = CFDictionaryGetValue(dictionary, kCGWindowOwnerPID);
    CFStringRef name = CFDictionaryGetValue(dictionary, kCGWindowName);
    CFNumberRef layer = CFDictionaryGetValue(dictionary, kCGWindowLayer);
    CFDictionaryRef bounds_ref = CFDictionaryGetValue(dictionary,
                                                      kCGWindowBounds);
    if (!name || !owner || !owner_pid || !layer || !bounds_ref) continue;

    int layer_number = 0;
    int owner_pid_number = 0;
    if (!CFNumberGetValue(layer, kCFNumberIntType, &layer_number)
        || !CFNumberGetValue(owner_pid,
                             kCFNumberIntType,
                             &owner_pid_number)
        || layer_number != 0x19
        || !CGRectMakeWithDictionaryRepresentation(bounds_ref, &bounds)
        || !CFStringGetCString(owner,
                               owner_buffer,
                               sizeof(owner_buffer),
                               kCFStringEncodingUTF8)
        || !CFStringGetCString(name,
                               name_buffer,
                               sizeof(name_buffer),
                               kCFStringEncodingUTF8)) {
      continue;
    }

    snprintf(buffer, sizeof(buffer), "%s,%s", owner_buffer, name_buffer);
    if (strcmp(buffer, alias) == 0) {
      pid = (pid_t)owner_pid_number;
      break;
    }
  }
  CFRelease(window_list);
  if (!pid) return NULL;

  AXUIElementRef app = AXUIElementCreateApplication(pid);
  if (!app) return NULL;

  AXUIElementRef result = NULL;
  AXUIElementRef extras = NULL;
  CFArrayRef children = NULL;
  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXExtrasMenuBarAttribute,
                                                (CFTypeRef *)&extras);
  if (error == kAXErrorSuccess) {
    error = AXUIElementCopyAttributeValue(extras,
                                          kAXVisibleChildrenAttribute,
                                          (CFTypeRef *)&children);
  }

  if (error == kAXErrorSuccess) {
    CFIndex count = CFArrayGetCount(children);
    for (CFIndex i = 0; i < count; ++i) {
      AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
      CFTypeRef position_ref = NULL;
      CFTypeRef size_ref = NULL;
      AXError position_error = AXUIElementCopyAttributeValue(
          item,
          kAXPositionAttribute,
          &position_ref);
      AXError size_error = AXUIElementCopyAttributeValue(item,
                                                         kAXSizeAttribute,
                                                         &size_ref);

      CGPoint position = CGPointZero;
      CGSize size = CGSizeZero;
      bool valid = position_ref && size_ref
                   && position_error == kAXErrorSuccess
                   && size_error == kAXErrorSuccess
                   && AXValueGetValue(position_ref,
                                      kAXValueCGPointType,
                                      &position)
                   && AXValueGetValue(size_ref, kAXValueCGSizeType, &size);
      if (position_ref) CFRelease(position_ref);
      if (size_ref) CFRelease(size_ref);

      if (valid && size.width > 0.0
          && fabs(position.x - bounds.origin.x) <= 10.0) {
        result = (AXUIElementRef)CFRetain(item);
        break;
      }
    }
  }

  if (children) CFRelease(children);
  if (extras) CFRelease(extras);
  CFRelease(app);
  return result;
}

static void ax_select_menu_extra(const char *alias) {
  AXUIElementRef item = ax_get_extra_menu_item(alias);
  if (!item) return;

  int connection = SLSMainConnectionID();
  SLSSetMenuBarInsetAndAlpha(connection, 0.0, 1.0, 0.0F);
  SLSSetMenuBarVisibilityOverrideOnDisplay(connection, 0, true);
  ax_perform_click(item);
  SLSSetMenuBarVisibilityOverrideOnDisplay(connection, 0, false);
  SLSSetMenuBarInsetAndAlpha(connection, 0.0, 1.0, 1.0F);
  CFRelease(item);
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
    printf("Usage: %s [-l | -s id/alias ]\n", argv[0]);
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
    if (sscanf(argv[2], "%d", &id) == 1) {
      AXUIElementRef app = ax_get_front_app();
      if (!app) return 1;
      ax_select_menu_option(app, id);
      CFRelease(app);
    } else {
      ax_select_menu_extra(argv[2]);
    }
  }
  return 0;
}
