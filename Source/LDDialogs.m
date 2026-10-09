#import "LDDialogs.h"
#import "LDFileNode.h"
#import "LDSizeFormatter.h"

#include <grp.h>
#include <pwd.h>
#include <sys/stat.h>

static const CGFloat LDDialogMargin = 18.0;
static const CGFloat LDDialogSpacing = 12.0;

// Panels that are open; kept alive until they close.
static NSMutableArray *LDOpenPanels = nil;

@interface LDDialogTarget : NSObject
@end

@implementation LDDialogTarget

- (void)buttonPressed:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

- (void)windowWillClose:(NSNotification *)notification
{
  if ([NSApp modalWindow] == [notification object]) {
    [NSApp stopModalWithCode:-1];
  }
  [LDOpenPanels removeObject:[notification object]];
}

@end

static LDDialogTarget *LDSharedTarget(void)
{
  static LDDialogTarget *target = nil;
  if (!target) {
    target = [[LDDialogTarget alloc] init];
    LDOpenPanels = [[NSMutableArray alloc] init];
  }
  return target;
}

static NSTextField *LDLabel(NSString *text, NSFont *font)
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  [label setStringValue:text ?: @""];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:YES];
  [label setFont:font];
  [[label cell] setWraps:YES];
  [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
  return label;
}

// Height a wrapping label needs at width.
static CGFloat LDLabelHeight(NSTextField *label, CGFloat width)
{
  return ceil([[label cell] cellSizeForBounds:NSMakeRect(0, 0, width, 10000)].height);
}

@implementation LDDialogs

+ (NSInteger)runListPanelWithTitle:(NSString *)title
                           message:(NSString *)message
                             items:(NSArray *)items
                           buttons:(NSArray *)buttons
                      defaultIndex:(NSUInteger)defaultIndex
                     checkboxTitle:(NSString *)checkboxTitle
                           checked:(BOOL *)checked
{
  LDDialogTarget *target = LDSharedTarget();
  CGFloat width = 560.0;
  CGFloat inner = width - 2 * LDDialogMargin;
  NSTextField *titleLabel = LDLabel(title, [NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]);
  NSTextField *messageLabel = LDLabel(message, [NSFont systemFontOfSize:[NSFont systemFontSize]]);
  CGFloat titleHeight = LDLabelHeight(titleLabel, inner);
  CGFloat messageHeight = [message length] ? LDLabelHeight(messageLabel, inner) : 0.0;
  CGFloat listHeight = [items count] ? MIN(260.0, 34.0 + 18.0 * [items count]) : 0.0;
  CGFloat buttonHeight = 34.0;
  CGFloat checkboxHeight = checkboxTitle ? 24.0 : 0.0;

  CGFloat height = LDDialogMargin + titleHeight
    + (messageHeight ? LDDialogSpacing + messageHeight : 0.0)
    + (listHeight ? LDDialogSpacing + listHeight : 0.0)
    + (checkboxHeight ? LDDialogSpacing + checkboxHeight : 0.0)
    + LDDialogSpacing * 1.5 + buttonHeight + LDDialogMargin;
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                              styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  // The heading is in the content, as in GNOME's alert dialogs.
  [panel setTitle:@""];
  [panel setReleasedWhenClosed:NO];
  NSView *content = [panel contentView];

  CGFloat y = height - LDDialogMargin - titleHeight;
  [titleLabel setFrame:NSMakeRect(LDDialogMargin, y, inner, titleHeight)];
  [content addSubview:titleLabel];
  if (messageHeight) {
    y -= LDDialogSpacing + messageHeight;
    [messageLabel setFrame:NSMakeRect(LDDialogMargin, y, inner, messageHeight)];
    [content addSubview:messageLabel];
  }
  if (listHeight) {
    y -= LDDialogSpacing + listHeight;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(LDDialogMargin, y, inner, listHeight)];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    // One path per line, scrolling sideways instead of wrapping.
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height)];
    [text setEditable:NO];
    [text setSelectable:YES];
    [text setFont:[NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]]];
    [text setHorizontallyResizable:YES];
    [text setMaxSize:NSMakeSize(1.0e7, 1.0e7)];
    [[text textContainer] setWidthTracksTextView:NO];
    [[text textContainer] setContainerSize:NSMakeSize(1.0e7, 1.0e7)];
    [text setString:[items componentsJoinedByString:@"\n"]];
    [scroll setDocumentView:text];
    [content addSubview:scroll];
  }
  NSButton *checkbox = nil;
  if (checkboxHeight) {
    y -= LDDialogSpacing + checkboxHeight;
    checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(LDDialogMargin, y, inner, checkboxHeight)];
    [checkbox setButtonType:NSSwitchButton];
    [checkbox setTitle:checkboxTitle];
    [checkbox setState:(checked && *checked) ? NSOnState : NSOffState];
    [content addSubview:checkbox];
  }

  // Buttons right-aligned in the given order.
  CGFloat x = width - LDDialogMargin;
  for (NSInteger i = (NSInteger)[buttons count] - 1; i >= 0; i--) {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    [button setTitle:[buttons objectAtIndex:(NSUInteger)i]];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button sizeToFit];
    NSRect frame = [button frame];
    frame.size.width = MAX(96.0, frame.size.width + 24.0);
    frame.size.height = buttonHeight;
    x -= frame.size.width;
    frame.origin = NSMakePoint(x, LDDialogMargin);
    x -= 8.0;
    [button setFrame:frame];
    [button setTag:i];
    [button setTarget:target];
    [button setAction:@selector(buttonPressed:)];
    if ((NSUInteger)i == defaultIndex) {
      [button setKeyEquivalent:@"\r"];
    } else if (i == 0) {
      [button setKeyEquivalent:@"\e"];
    }
    [content addSubview:button];
  }

  [[NSNotificationCenter defaultCenter] addObserver:target
                                           selector:@selector(windowWillClose:)
                                               name:NSWindowWillCloseNotification
                                             object:panel];
  [panel center];
  NSInteger result = [NSApp runModalForWindow:panel];
  [[NSNotificationCenter defaultCenter] removeObserver:target name:NSWindowWillCloseNotification object:panel];
  if (checked && checkbox) {
    *checked = [checkbox state] == NSOnState;
  }
  [panel orderOut:nil];
  return result < 0 ? 0 : result;
}

+ (BOOL)confirmDestructiveAction:(NSString *)actionTitle
                         message:(NSString *)message
                           paths:(NSArray *)paths
                    dontAskAgain:(BOOL *)dontAskAgain
{
  // Cancel is the default, as WinDirStat's warning defaults to No.
  NSInteger choice = [self runListPanelWithTitle:actionTitle
                                         message:message
                                           items:paths
                                         buttons:@[@"Cancel", actionTitle]
                                    defaultIndex:0
                                   checkboxTitle:@"Do not show this message again"
                                         checked:dontAskAgain];
  return choice == 1;
}

+ (void)showFailures:(NSArray *)lines title:(NSString *)title
{
  [self runListPanelWithTitle:title
                      message:nil
                        items:lines
                      buttons:@[@"Close"]
                 defaultIndex:0
                checkboxTitle:nil
                      checked:NULL];
}

static NSString *LDPermissionString(mode_t mode)
{
  char text[11];
  text[0] = S_ISDIR(mode) ? 'd' : (S_ISLNK(mode) ? 'l' : '-');
  const char *letters = "rwxrwxrwx";
  for (int i = 0; i < 9; i++) {
    text[i + 1] = (mode & (1 << (8 - i))) ? letters[i] : '-';
  }
  text[10] = '\0';
  return [NSString stringWithFormat:@"%s (%04o)", text, (unsigned)(mode & 07777)];
}

+ (NSString *)kindOfNode:(LDFileNode *)node
{
  if ([node isMountPoint]) {
    return @"Mount point (not scanned)";
  }
  switch ([node kind]) {
    case LDFileNodeKindDirectory: return @"Folder";
    case LDFileNodeKindSymlink: return @"Symbolic link";
    case LDFileNodeKindSpecial: return [node error] == LDFileNodeErrorStatFailed ? @"Unreadable entry" : @"Special file";
    default: return @"File";
  }
}

+ (void)showPropertiesForNode:(LDFileNode *)node
{
  LDSharedTarget();
  NSDateFormatter *dates = [[NSDateFormatter alloc] init];
  [dates setDateStyle:NSDateFormatterLongStyle];
  [dates setTimeStyle:NSDateFormatterMediumStyle];

  NSMutableArray *rows = [NSMutableArray array];
  void (^add)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
    if (value) {
      [rows addObject:@[name, value]];
    }
  };
  NSString *path = [node path];
  add(@"Name", [node parent] ? [node displayName] : path);
  add(@"Location", [node parent] ? [[node parent] path] : [path stringByDeletingLastPathComponent]);
  add(@"Type", [self kindOfNode:node]);
  add(@"Size on disk", [NSString stringWithFormat:@"%@ (%llu bytes)",
                        [LDSizeFormatter stringForBytes:[node aggregateAllocatedSize]], [node aggregateAllocatedSize]]);
  add(@"Size", [NSString stringWithFormat:@"%@ (%llu bytes)",
                [LDSizeFormatter stringForBytes:[node aggregateSize]], [node aggregateSize]]);
  if ([node kind] == LDFileNodeKindDirectory) {
    add(@"Contents", [NSString stringWithFormat:@"%lu files, %lu folders",
                      (unsigned long)[node fileCount], (unsigned long)MAX((NSUInteger)1, [node directoryCount]) - 1]);
  }
  if ([node modificationTime] > 0) {
    add(@"Modified", [dates stringFromDate:[NSDate dateWithTimeIntervalSince1970:[node modificationTime]]]);
  }

  NSMutableData *terminated = [[node pathData] mutableCopy];
  [terminated appendBytes:"\0" length:1];
  struct stat info;
  if (lstat([terminated bytes], &info) == 0) {
    add(@"Permissions", LDPermissionString(info.st_mode));
    struct passwd *user = getpwuid(info.st_uid);
    struct group *group = getgrgid(info.st_gid);
    add(@"Owner", user ? [NSString stringWithUTF8String:user->pw_name] : [NSString stringWithFormat:@"%u", (unsigned)info.st_uid]);
    add(@"Group", group ? [NSString stringWithUTF8String:group->gr_name] : [NSString stringWithFormat:@"%u", (unsigned)info.st_gid]);
    add(@"Links", [NSString stringWithFormat:@"%lu", (unsigned long)info.st_nlink]);
    add(@"Inode", [NSString stringWithFormat:@"%llu on device %llu",
                   (unsigned long long)info.st_ino, (unsigned long long)info.st_dev]);
    add(@"Accessed", [dates stringFromDate:[NSDate dateWithTimeIntervalSince1970:info.st_atime]]);
    add(@"Changed", [dates stringFromDate:[NSDate dateWithTimeIntervalSince1970:info.st_ctime]]);
  } else {
    add(@"Status", @"No longer exists or cannot be read");
  }
  if ([node errorCode]) {
    add(@"Scan note", [node errorCode]);
  }

  CGFloat width = 520.0;
  CGFloat labelWidth = 120.0;
  CGFloat valueWidth = width - 2 * LDDialogMargin - labelWidth - LDDialogSpacing;
  NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
  NSMutableArray *heights = [NSMutableArray array];
  CGFloat height = 2 * LDDialogMargin;
  for (NSArray *row in rows) {
    CGFloat rowHeight = MAX(20.0, LDLabelHeight(LDLabel([row objectAtIndex:1], font), valueWidth));
    [heights addObject:@(rowHeight)];
    height += rowHeight + 6.0;
  }
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                              styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  [panel setTitle:[NSString stringWithFormat:@"%@ Properties", [node parent] ? [node displayName] : path]];
  [panel setReleasedWhenClosed:NO];
  NSView *content = [panel contentView];
  CGFloat y = height - LDDialogMargin;
  for (NSUInteger i = 0; i < [rows count]; i++) {
    NSArray *row = [rows objectAtIndex:i];
    CGFloat rowHeight = [[heights objectAtIndex:i] doubleValue];
    y -= rowHeight;
    NSTextField *name = LDLabel([row objectAtIndex:0], font);
    [name setAlignment:NSRightTextAlignment];
    [name setTextColor:[NSColor disabledControlTextColor]];
    [name setFrame:NSMakeRect(LDDialogMargin, y, labelWidth, 20.0)];
    NSTextField *value = LDLabel([row objectAtIndex:1], font);
    [value setFrame:NSMakeRect(LDDialogMargin + labelWidth + LDDialogSpacing, y, valueWidth, rowHeight)];
    [content addSubview:name];
    [content addSubview:value];
    y -= 6.0;
  }
  [[NSNotificationCenter defaultCenter] addObserver:LDSharedTarget()
                                           selector:@selector(windowWillClose:)
                                               name:NSWindowWillCloseNotification
                                             object:panel];
  [LDOpenPanels addObject:panel];
  [panel center];
  [panel makeKeyAndOrderFront:nil];
}

+ (void)showText:(NSString *)text title:(NSString *)title
{
  NSArray *lines = [text componentsSeparatedByString:@"\n"];
  [self runListPanelWithTitle:title message:nil items:lines buttons:@[@"Close"] defaultIndex:0 checkboxTitle:nil checked:NULL];
}

@end
