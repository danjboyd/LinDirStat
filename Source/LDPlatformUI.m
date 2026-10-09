#import "LDPlatformUI.h"
#import "LDFileNode.h"
#import "LDPrivacyAccess.h"

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
  if ([node isSpaceItem]) {
    return nil;
  }
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

static NSString *const LDSuppressFullDiskAccessKey = @"LDSuppressFullDiskAccessPrompt";
static NSString *const LDFullDiskAccessSettingsURL =
  @"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles";

+ (NSString *)abbreviatedPath:(NSString *)path
{
  NSString *home = NSHomeDirectory();
  if ([path hasPrefix:[home stringByAppendingString:@"/"]]) {
    return [@"~" stringByAppendingString:[path substringFromIndex:[home length]]];
  }
  return path;
}

+ (void)openFullDiskAccessSettings
{
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:LDFullDiskAccessSettingsURL]];
}

+ (void)scanDidFinishWithRoot:(LDFileNode *)root window:(NSWindow *)window
{
  static BOOL askedThisLaunch = NO;
  if (askedThisLaunch || [[NSUserDefaults standardUserDefaults] boolForKey:LDSuppressFullDiskAccessKey]) {
    return;
  }
  NSArray *denied = [LDPrivacyAccess directoriesDeniedByPrivacyUnder:root limit:100];
  // Some system folders refuse even with Full Disk Access; only ask when
  // granting it would help.
  if ([denied count] == 0 || [LDPrivacyAccess hasFullDiskAccess]) {
    return;
  }
  askedThisLaunch = YES;
  NSString *count = [denied count] == 1 ? @"1 folder" :
    [NSString stringWithFormat:@"%@%lu folders", [denied count] == 100 ? @"over " : @"", (unsigned long)[denied count]];
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Some folders are protected by macOS"];
  [alert setInformativeText:[NSString stringWithFormat:
    @"LinDirStat couldn't read %@, such as %@, because it doesn't have Full Disk Access. "
    @"Their sizes aren't included in the results.\n\n"
    @"To scan everything, turn on LinDirStat in System Settings › Privacy & Security › Full Disk Access, "
    @"then refresh.",
    count, [self abbreviatedPath:[[denied objectAtIndex:0] path]]]];
  [alert addButtonWithTitle:@"Open Privacy Settings"];
  [alert addButtonWithTitle:@"Not Now"];
  [alert setShowsSuppressionButton:YES];
  [[alert suppressionButton] setTitle:@"Don't ask again"];
  void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
    if ([[alert suppressionButton] state] == NSControlStateValueOn) {
      [[NSUserDefaults standardUserDefaults] setBool:YES forKey:LDSuppressFullDiskAccessKey];
    }
    if (response == NSAlertFirstButtonReturn) {
      [self openFullDiskAccessSettings];
    }
  };
  if (window) {
    [alert beginSheetModalForWindow:window completionHandler:handler];
  } else {
    handler([alert runModal]);
  }
}

+ (void)showFullDiskAccessHelp:(id)sender
{
  (void)sender;
  [self openFullDiskAccessSettings];
}

+ (NSString *)showInFileManagerTitle
{
  return @"Show in Finder";
}

+ (NSString *)settingsTitle
{
  return @"Settings";
}

+ (BOOL)usesCommandDigitsForFileTabs
{
  return YES;
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
  NSMenuItem *access = [help addItemWithTitle:@"Full Disk Access Settings…"
                                       action:@selector(showFullDiskAccessHelp:) keyEquivalent:@""];
  [access setTarget:self];
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

+ (void)scanDidFinishWithRoot:(LDFileNode *)root window:(NSWindow *)window
{
  (void)root;
  (void)window;
}

+ (NSString *)showInFileManagerTitle
{
  return @"Show in Files";
}

+ (NSString *)settingsTitle
{
  return @"Preferences";
}

+ (BOOL)usesCommandDigitsForFileTabs
{
  return NO;
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
