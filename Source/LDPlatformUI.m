#import "LDPlatformUI.h"
#import "LDFileNode.h"

#if defined(__APPLE__)
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

@implementation LDPlatformUI

#if defined(__APPLE__)

+ (void)prepareApplication:(NSApplication *)application
{
  NSString *appearance = [[[NSProcessInfo processInfo] environment] objectForKey:@"LINDIRSTAT_APPEARANCE"];
  if ([appearance isEqualToString:@"dark"]) {
    [application setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
  } else if ([appearance isEqualToString:@"light"]) {
    [application setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
  }
}

+ (NSDictionary *)symbolNames
{
  static NSDictionary *names = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    names = @{
      @"document-open-symbolic": @"folder",
      @"view-refresh-symbolic": @"arrow.clockwise",
      @"process-stop-symbolic": @"xmark",
      @"media-playback-pause-symbolic": @"pause.fill",
      @"media-playback-start-symbolic": @"play.fill",
      @"system-search-symbolic": @"magnifyingglass",
      @"user-trash-symbolic": @"trash",
      @"go-up-symbolic": @"arrow.up",
      @"zoom-in-symbolic": @"plus.magnifyingglass",
      @"zoom-out-symbolic": @"minus.magnifyingglass",
      @"zoom-original-symbolic": @"1.magnifyingglass",
      @"edit-copy-symbolic": @"doc.on.doc",
      @"computer-symbolic": @"desktopcomputer",
      @"drive-harddisk-symbolic": @"internaldrive",
      @"folder-symbolic": @"folder",
      @"insert-link-symbolic": @"link",
      @"text-x-generic-symbolic": @"doc",
    };
  });
  return names;
}

+ (NSImage *)toolbarImageNamed:(NSString *)name label:(NSString *)label
{
  NSString *symbol = [[self symbolNames] objectForKey:name];
  NSImage *image = symbol ? [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label] : nil;
  return image ? image : [NSImage imageNamed:name];
}

static NSImage *LDSmallIcon(NSImage *icon)
{
  NSImage *small = [icon copy];
  [small setSize:NSMakeSize(16.0, 16.0)];
  return small;
}

+ (NSImage *)fileIconForNode:(LDFileNode *)node
{
  static NSCache *cache = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    cache = [[NSCache alloc] init];
  });
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  if ([node isComputer]) {
    NSImage *icon = [cache objectForKey:@"computer"];
    if (!icon) {
      icon = LDSmallIcon([NSImage imageNamed:NSImageNameComputer]);
      [cache setObject:icon forKey:@"computer"];
    }
    return icon;
  }

  NSString *extension = [node extensionKey];
  BOOL hasExtension = [extension length] > 0 && ![extension isEqualToString:@"<none>"];
  LDFileNodeKind kind = [node kind];
  // Volumes and packages (apps, bundles) have icons of their own; ask
  // Finder for those by path. Everything else is shared by type.
  BOOL byPath = [node isMountPoint] || [[node parent] isComputer];
  UTType *type = nil;
  if (!byPath && kind == LDFileNodeKindDirectory && hasExtension) {
    type = [UTType typeWithFilenameExtension:extension];
    byPath = type && [type conformsToType:UTTypePackage];
  }
  NSString *key = nil;
  if (byPath) {
    key = [@"path:" stringByAppendingString:[node path]];
  } else if (kind == LDFileNodeKindDirectory) {
    key = @"folder";
  } else if (kind == LDFileNodeKindSymlink) {
    key = @"symlink";
  } else {
    key = [@"ext:" stringByAppendingString:hasExtension ? extension : @""];
  }
  NSImage *icon = [cache objectForKey:key];
  if (icon) {
    return icon;
  }
  if (byPath) {
    icon = [workspace iconForFile:[node path]];
  } else if (kind == LDFileNodeKindDirectory) {
    icon = [workspace iconForContentType:UTTypeFolder];
  } else if (kind == LDFileNodeKindSymlink) {
    icon = [workspace iconForContentType:UTTypeSymbolicLink];
  } else {
    UTType *fileType = hasExtension ? [UTType typeWithFilenameExtension:extension] : nil;
    icon = [workspace iconForContentType:fileType ? fileType : UTTypeData];
  }
  if (!icon) {
    return nil;
  }
  icon = LDSmallIcon(icon);
  [cache setObject:icon forKey:key];
  return icon;
}

+ (BOOL)tablesAutoresizeColumns
{
  return YES;
}

+ (NSString *)showInFileManagerTitle
{
  return @"Show in Finder";
}

+ (NSString *)settingsTitle
{
  return @"Settings";
}

// Puts the standard editing commands (which text fields need for their
// shortcuts) at the top of the Edit menu, before the app's own.
+ (void)completeEditMenu:(NSMenu *)edit
{
  NSUInteger index = 0;
  NSArray *standard = @[
    @[@"Undo", @"undo:", @"z", @(NSEventModifierFlagCommand)],
    @[@"Redo", @"redo:", @"z", @(NSEventModifierFlagCommand | NSEventModifierFlagShift)],
    @[],
    @[@"Cut", @"cut:", @"x", @(NSEventModifierFlagCommand)],
    @[@"Copy", @"copy:", @"c", @(NSEventModifierFlagCommand)],
    @[@"Paste", @"paste:", @"v", @(NSEventModifierFlagCommand)],
    @[@"Select All", @"selectAll:", @"a", @(NSEventModifierFlagCommand)],
    @[],
  ];
  for (NSArray *spec in standard) {
    NSMenuItem *item = nil;
    if ([spec count] == 0) {
      item = [NSMenuItem separatorItem];
    } else {
      item = [[NSMenuItem alloc] initWithTitle:spec[0] action:NSSelectorFromString(spec[1]) keyEquivalent:spec[2]];
      [item setKeyEquivalentModifierMask:[spec[3] unsignedIntegerValue]];
    }
    [edit insertItem:item atIndex:index++];
  }
}

+ (void)completeMainMenu:(NSMenu *)mainMenu
         applicationMenu:(NSMenu *)applicationMenu
       preferencesTarget:(id)preferencesTarget
{
  NSString *name = [[NSProcessInfo processInfo] processName];
  [applicationMenu removeAllItems];
  [applicationMenu addItemWithTitle:[@"About " stringByAppendingString:name]
                             action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
  [applicationMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *settings = [applicationMenu addItemWithTitle:@"Settings…" action:@selector(showPreferences:) keyEquivalent:@","];
  [settings setTarget:preferencesTarget];
  [applicationMenu addItem:[NSMenuItem separatorItem]];
  NSMenu *services = [[NSMenu alloc] initWithTitle:@"Services"];
  [[applicationMenu addItemWithTitle:@"Services" action:NULL keyEquivalent:@""] setSubmenu:services];
  [NSApp setServicesMenu:services];
  [applicationMenu addItem:[NSMenuItem separatorItem]];
  [applicationMenu addItemWithTitle:[@"Hide " stringByAppendingString:name] action:@selector(hide:) keyEquivalent:@"h"];
  NSMenuItem *hideOthers = [applicationMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
  [hideOthers setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
  [applicationMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
  [applicationMenu addItem:[NSMenuItem separatorItem]];
  [applicationMenu addItemWithTitle:[@"Quit " stringByAppendingString:name] action:@selector(terminate:) keyEquivalent:@"q"];

  // Settings live in the application menu on macOS, and F5 needs fn on most
  // Mac keyboards, so refreshing also gets the usual Command-R.
  for (NSMenuItem *top in [mainMenu itemArray]) {
    NSMenu *submenu = [top submenu];
    if (submenu == applicationMenu) {
      continue;
    }
    if ([[submenu title] isEqualToString:@"Edit"]) {
      [self completeEditMenu:submenu];
    }
    for (NSMenuItem *item in [[submenu itemArray] copy]) {
      if ([item action] == @selector(showPreferences:)) {
        NSInteger index = [submenu indexOfItem:item];
        [submenu removeItem:item];
        if (index > 0 && index == [submenu numberOfItems] && [[submenu itemAtIndex:index - 1] isSeparatorItem]) {
          [submenu removeItemAtIndex:index - 1];
        }
      } else if ([item action] == NSSelectorFromString(@"copyPath:")) {
        // Finder's Copy as Pathname.
        [item setKeyEquivalent:@"c"];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
      } else if ([item action] == NSSelectorFromString(@"moveToTrash:")) {
        [item setKeyEquivalent:[NSString stringWithFormat:@"%C", (unichar)NSBackspaceCharacter]];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
      } else if ([item action] == NSSelectorFromString(@"deletePermanently:")) {
        [item setKeyEquivalent:[NSString stringWithFormat:@"%C", (unichar)NSBackspaceCharacter]];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
      } else if ([item action] == NSSelectorFromString(@"rescan:")) {
        [item setKeyEquivalent:@"r"];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
      } else if ([item action] == NSSelectorFromString(@"refreshSelected:")) {
        [item setKeyEquivalent:@"r"];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
      }
    }
  }

  NSMenu *window = [[NSMenu alloc] initWithTitle:@"Window"];
  [[mainMenu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""] setSubmenu:window];
  [window addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  [window addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
  [window addItem:[NSMenuItem separatorItem]];
  [window addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
  [NSApp setWindowsMenu:window];

  // The app's Help menu moves after Window; it also gets the system's menu
  // search.
  NSMenuItem *helpItem = [mainMenu itemWithTitle:@"Help"];
  NSMenu *help = [helpItem submenu];
  if (helpItem) {
    [mainMenu removeItem:helpItem];
  } else {
    help = [[NSMenu alloc] initWithTitle:@"Help"];
  }
  [[mainMenu addItemWithTitle:@"Help" action:NULL keyEquivalent:@""] setSubmenu:help];
  [NSApp setHelpMenu:help];
}

#else

+ (void)prepareApplication:(NSApplication *)application
{
  (void)application;
}

+ (NSImage *)toolbarImageNamed:(NSString *)name label:(NSString *)label
{
  (void)label;
  return [NSImage imageNamed:name];
}

+ (NSImage *)fileIconForNode:(LDFileNode *)node
{
  (void)node;
  return nil;
}

+ (BOOL)tablesAutoresizeColumns
{
  return NO;
}

+ (NSString *)showInFileManagerTitle
{
  return @"Show in Files";
}

+ (NSString *)settingsTitle
{
  return @"Preferences";
}

+ (void)completeMainMenu:(NSMenu *)mainMenu
         applicationMenu:(NSMenu *)applicationMenu
       preferencesTarget:(id)preferencesTarget
{
  (void)mainMenu;
  (void)applicationMenu;
  (void)preferencesTarget;
}

#endif

@end
