#import "LDSelectTargetPanel.h"
#import "LDColumnChooser.h"
#import "LDLocalization.h"
#import "LDPlatformUI.h"
#import "LDPreferences.h"
#import "LDSelectTargetRules.h"
#import "LDSizeFormatter.h"
#import "LDVolumes.h"

#include <dispatch/dispatch.h>

static const CGFloat LDPanelWidth = 620.0;
static const CGFloat LDPanelHeight = 480.0;
static const CGFloat LDMargin = 18.0;
static const CGFloat LDSpacing = 6.0;
static const CGFloat LDSectionSpacing = 12.0;
// Controls that belong to a radio sit under its label, past the indicator.
static const CGFloat LDRadioIndent = 26.0;
static const CGFloat LDButtonHeight = 34.0;

// Bar geometry, as in LDPercentageBarCell: thin and rounded like GTK's
// level bars.
static const CGFloat LDBarHeight = 8.0;
static const CGFloat LDBarInset = 6.0;

static NSInteger (^LDModalRunnerForTesting)(NSWindow *panel) = nil;

// Runs the panel modally. GNUstep sends distributed notifications over a DO
// connection to gdnc; when gdnc goes away (seen in the release workflow's
// root container) the next request raises NSPortTimeoutException out of the
// modal loop, which already ended its session. That mustn't close Select
// Target, so the dialog carries on in a new session; if every session fails
// at once, it gives up as if cancelled rather than spinning.
static const NSUInteger LDModalTimeoutRetries = 3;

static NSInteger LDRunPanelModally(NSWindow *panel)
{
  NSUInteger timeouts = 0;
  for (;;) {
    @try {
      return LDModalRunnerForTesting ? LDModalRunnerForTesting(panel) : [NSApp runModalForWindow:panel];
    }
    @catch (NSException *exception) {
      if (![[exception name] isEqualToString:NSPortTimeoutException]) {
        @throw;
      }
      if (++timeouts > LDModalTimeoutRetries) {
        NSLog(@"Select Target: %@ (%@) %lu times; closing the dialog", [exception name], [exception reason],
              (unsigned long)timeouts);
        return NSModalResponseCancel;
      }
      NSLog(@"Select Target: %@ (%@); keeping the dialog open", [exception name], [exception reason]);
    }
  }
}

typedef enum {
  LDVolumeUsageQuerying = 0,
  LDVolumeUsageReady = 1,
  LDVolumeUsageUnavailable = 2
} LDVolumeUsageState;

// The "Used" column: WinDirStat's owner-drawn usage bar, in the theme's
// accent over a faint trough, or "(querying…)"/"(unavailable)".
@interface LDVolumeUsageCell : NSCell
{
  LDVolumeUsageState _usageState;
  double _fraction;
}
- (void)setUsageState:(LDVolumeUsageState)state fraction:(double)fraction;
@end

@implementation LDVolumeUsageCell

- (void)setUsageState:(LDVolumeUsageState)state fraction:(double)fraction
{
  _usageState = state;
  _fraction = MAX(0.0, MIN(1.0, fraction));
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  (void)controlView;
  if (_usageState != LDVolumeUsageReady) {
    NSString *text = _usageState == LDVolumeUsageQuerying ? LDLocalized(@"(querying…)") : LDLocalized(@"(unavailable)");
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
                                 NSForegroundColorAttributeName: [NSColor disabledControlTextColor]};
    NSSize size = [text sizeWithAttributes:attributes];
    [text drawAtPoint:NSMakePoint(NSMinX(cellFrame) + LDBarInset, floor(NSMidY(cellFrame) - size.height / 2.0))
       withAttributes:attributes];
    return;
  }
  NSRect track = NSInsetRect(cellFrame, LDBarInset, 0.0);
  track.origin.y = floor(NSMidY(cellFrame) - LDBarHeight / 2.0);
  track.size.height = LDBarHeight;
  if (track.size.width <= LDBarHeight) {
    return;
  }
  CGFloat radius = LDBarHeight / 2.0;
  // Catalog colours ignore alpha, so go through RGB first.
  NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  [[text colorWithAlphaComponent:0.15] set];
  [[NSBezierPath bezierPathWithRoundedRect:track xRadius:radius yRadius:radius] fill];

  CGFloat filled = floor(track.size.width * _fraction);
  if (filled < 1.0) {
    return;
  }
  NSRect fill = track;
  fill.size.width = MAX(filled, LDBarHeight);
  [[NSColor selectedControlColor] set];
  [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:radius yRadius:radius] fill];
}

@end

// Lays the dialog out top-down.
@interface LDSelectTargetContentView : NSView
@end

@implementation LDSelectTargetContentView
- (BOOL)isFlipped
{
  return YES;
}
@end

@interface LDSelectTargetController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate, NSTextFieldDelegate, NSWindowDelegate>
{
  NSPanel *_panel;
  NSButton *_allRadio;
  NSButton *_individualRadio;
  NSButton *_folderRadio;
  NSTableView *_table;
  LDColumnChooser *_columnChooser;
  NSComboBox *_folderCombo;
  NSButton *_browseButton;
  NSButton *_addFoldersButton;
  NSButton *_duplicatesCheckbox;
  NSButton *_okButton;
  NSButton *_cancelButton;

  NSArray *_volumes;
  LDSelectTargetMode _mode;
  // Set while the dialog changes the table selection itself, so that does
  // not switch the mode the way a user's selection does.
  NSInteger _adjustingSelection;
  BOOL _finished;
}
- (NSArray *)runWithInitialFolder:(NSString *)folder;
@end

@implementation LDSelectTargetController

#pragma mark - Building

- (NSButton *)radioWithTitle:(NSString *)title mode:(LDSelectTargetMode)mode
{
  NSButton *radio = [[NSButton alloc] initWithFrame:NSZeroRect];
  [radio setButtonType:NSRadioButton];
  [radio setTitle:title];
  [radio setTag:mode];
  [radio setTarget:self];
  [radio setAction:@selector(radioChanged:)];
  [radio sizeToFit];
  return radio;
}

- (NSButton *)pushButtonWithTitle:(NSString *)title action:(SEL)action
{
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  [button setButtonType:NSMomentaryPushInButton];
  [button setBezelStyle:NSRoundedBezelStyle];
  [button setTitle:title];
  [button setTarget:self];
  [button setAction:action];
  [button sizeToFit];
  NSRect frame = [button frame];
  frame.size.width = MAX(96.0, NSWidth(frame) + 24.0);
  frame.size.height = LDButtonHeight;
  [button setFrame:frame];
  return button;
}

- (NSTableColumn *)addColumn:(NSString *)identifier
                       title:(NSString *)title
                       width:(CGFloat)width
                       right:(BOOL)rightAligned
                   ascending:(BOOL)ascending
{
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
  [[column headerCell] setStringValue:title];
  [column setWidth:width];
  [column setMinWidth:40.0];
  [column setEditable:NO];
  if (rightAligned) {
    [[column dataCell] setAlignment:NSRightTextAlignment];
    [[column headerCell] setAlignment:NSRightTextAlignment];
  }
  [column setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:identifier ascending:ascending]];
  [_table addTableColumn:column];
  return column;
}

- (void)fitNameColumn
{
  NSTableColumn *name = [_table tableColumnWithIdentifier:LDSelectTargetColumnName];
  CGFloat others = 0.0;
  for (NSTableColumn *column in [_table tableColumns]) {
    if (column != name) {
      others += [column width] + [_table intercellSpacing].width;
    }
  }
  CGFloat available = [[_table enclosingScrollView] contentSize].width;
  [name setWidth:MAX(120.0, floor(available - others - [_table intercellSpacing].width))];
}

- (void)buildPanel
{
  _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, LDPanelWidth, LDPanelHeight)
                                      styleMask:NSTitledWindowMask | NSClosableWindowMask
                                        backing:NSBackingStoreBuffered
                                          defer:NO];
  [_panel setTitle:LDLocalized(@"Select Target")];
  [_panel setReleasedWhenClosed:NO];
  [_panel setDelegate:self];
  NSView *content = [[LDSelectTargetContentView alloc] initWithFrame:NSMakeRect(0, 0, LDPanelWidth, LDPanelHeight)];
  [_panel setContentView:content];

  CGFloat left = LDMargin;
  CGFloat right = LDPanelWidth - LDMargin;
  CGFloat indented = left + LDRadioIndent;

  // From the bottom: the buttons, the duplicates checkbox, the folder row.
  _cancelButton = [self pushButtonWithTitle:LDLocalized(@"Cancel") action:@selector(cancel:)];
  [_cancelButton setKeyEquivalent:@"\e"];
  _okButton = [self pushButtonWithTitle:@"OK" action:@selector(confirm:)];
  [_okButton setKeyEquivalent:@"\r"];
  CGFloat buttonY = LDPanelHeight - LDMargin - LDButtonHeight;
  NSRect okFrame = [_okButton frame];
  okFrame.origin = NSMakePoint(right - NSWidth(okFrame), buttonY);
  [_okButton setFrame:okFrame];
  NSRect cancelFrame = [_cancelButton frame];
  cancelFrame.origin = NSMakePoint(NSMinX(okFrame) - 8.0 - NSWidth(cancelFrame), buttonY);
  [_cancelButton setFrame:cancelFrame];
  [content addSubview:_cancelButton];
  [content addSubview:_okButton];

  _duplicatesCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
  [_duplicatesCheckbox setButtonType:NSSwitchButton];
  [_duplicatesCheckbox setTitle:LDLocalized(@"Scan for duplicate files (slower)")];
  [_duplicatesCheckbox sizeToFit];
  CGFloat checkboxHeight = NSHeight([_duplicatesCheckbox frame]);
  CGFloat checkboxY = buttonY - LDSectionSpacing * 1.5 - checkboxHeight;
  [_duplicatesCheckbox setFrame:NSMakeRect(left, checkboxY, right - left, checkboxHeight)];
  [content addSubview:_duplicatesCheckbox];

  _browseButton = [self pushButtonWithTitle:LDLocalized(@"Browse…") action:@selector(browse:)];
  CGFloat rowHeight = NSHeight([_browseButton frame]);
  CGFloat folderRowY = checkboxY - LDSectionSpacing - rowHeight;
  NSRect browseFrame = [_browseButton frame];
  browseFrame.origin = NSMakePoint(right - NSWidth(browseFrame), folderRowY);
  [_browseButton setFrame:browseFrame];
  [content addSubview:_browseButton];
  // WinDirStat 2.8 (1424ff67): the button beside Browse adds folders to the
  // ones already given.
  _addFoldersButton = [self pushButtonWithTitle:@"" action:@selector(addFolders:)];
  [_addFoldersButton setImage:[LDPlatformUI toolbarImageNamed:@"list-add-symbolic" label:LDLocalized(@"Add Folders…")]];
  [_addFoldersButton setImagePosition:NSImageOnly];
  [_addFoldersButton setToolTip:LDLocalized(@"Add Folders…")];
  [_addFoldersButton setFrame:NSMakeRect(NSMinX(browseFrame) - LDSpacing - NSHeight(browseFrame), folderRowY,
                                         NSHeight(browseFrame), NSHeight(browseFrame))];
  [content addSubview:_addFoldersButton];
  browseFrame = [_addFoldersButton frame];

  _folderCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 0, 200, rowHeight)];
  [_folderCombo setEditable:YES];
  [_folderCombo setCompletes:NO];
  [_folderCombo setUsesDataSource:NO];
  [_folderCombo setNumberOfVisibleItems:10];
  [_folderCombo setDelegate:self];
  [_folderCombo sizeToFit];
  CGFloat comboHeight = NSHeight([_folderCombo frame]);
  [_folderCombo setFrame:NSMakeRect(indented,
                                    folderRowY + floor((rowHeight - comboHeight) / 2.0),
                                    NSMinX(browseFrame) - LDSpacing - indented,
                                    comboHeight)];
  [content addSubview:_folderCombo];

  _folderRadio = [self radioWithTitle:LDLocalized(@"Folder") mode:LDSelectTargetFolder];
  CGFloat radioHeight = NSHeight([_folderRadio frame]);
  [_folderRadio setFrame:NSMakeRect(left, folderRowY - LDSpacing - radioHeight, right - left, radioHeight)];
  [content addSubview:_folderRadio];

  // From the top: the two drive radios and the drive list.
  NSArray *mountPoints = [_volumes valueForKey:@"mountPoint"];
  _allRadio = [self radioWithTitle:[LDSelectTargetRules allLocalDrivesTitleForMountPoints:mountPoints]
                              mode:LDSelectTargetAllLocalDrives];
  [_allRadio setFrame:NSMakeRect(left, LDMargin, right - left, radioHeight)];
  [content addSubview:_allRadio];

  _individualRadio = [self radioWithTitle:LDLocalized(@"Individual drives") mode:LDSelectTargetIndividualDrives];
  CGFloat individualY = LDMargin + radioHeight + LDSpacing;
  [_individualRadio setFrame:NSMakeRect(left, individualY, right - left, radioHeight)];
  [content addSubview:_individualRadio];

  CGFloat tableTop = individualY + radioHeight + LDSpacing;
  CGFloat tableBottom = NSMinY([_folderRadio frame]) - LDSectionSpacing;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(indented, tableTop, right - indented, tableBottom - tableTop)];
  [scroll setBorderType:NSBezelBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  NSSize contentSize = [scroll contentSize];
  _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
  [_table setAllowsMultipleSelection:YES];
  [_table setAllowsEmptySelection:YES];
  [_table setAllowsColumnReordering:NO];
  // A header click sorts; selecting the column would clear the rows.
  [_table setAllowsColumnSelection:NO];
  [_table setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
  CGFloat fixedWidths = 80.0 + 80.0 + 110.0 + 70.0;
  [self addColumn:LDSelectTargetColumnName title:LDLocalized(@"Name")
            width:MAX(120.0, contentSize.width - fixedWidths - 5 * [_table intercellSpacing].width)
            right:NO ascending:YES];
  [self addColumn:LDSelectTargetColumnTotal title:LDLocalized(@"Total") width:80.0 right:YES ascending:NO];
  [self addColumn:LDSelectTargetColumnFree title:LDLocalized(@"Free") width:80.0 right:YES ascending:NO];
  NSTableColumn *used = [self addColumn:LDSelectTargetColumnUsed title:LDLocalized(@"Used") width:110.0 right:NO ascending:NO];
  [used setDataCell:[[LDVolumeUsageCell alloc] init]];
  [self addColumn:LDSelectTargetColumnPercent title:LDLocalized(@"% Used") width:70.0 right:YES ascending:NO];
  // WinDirStat 2.6's header column chooser; Name takes the room a hidden
  // column leaves (or gives it back).
  _columnChooser = [[LDColumnChooser alloc] initWithTable:_table
                                                     list:LDColumnListDrives
                                          requiredColumns:nil
                                              preferences:[LDPreferences sharedPreferences]];
  __weak LDSelectTargetController *weakSelf = self;
  [_columnChooser setChangeHandler:^{
    [weakSelf fitNameColumn];
  }];
  [_table setDataSource:self];
  [_table setDelegate:self];
  [_table setTarget:self];
  [_table setDoubleAction:@selector(tableDoubleClicked:)];
  [scroll setDocumentView:_table];
  [_columnChooser applyPreferences];
  // Overlay scrollbars: a corner view would hide the last column's title.
  [_table setCornerView:nil];
  [content addSubview:scroll];
}

#pragma mark - Running

- (void)restoreFromPreferences:(LDPreferences *)preferences initialFolder:(NSString *)folder
{
  NSArray *history = [preferences folderHistory];
  [_folderCombo addItemsWithObjectValues:history];
  [_folderCombo setStringValue:[LDSelectTargetRules initialFolderForRequested:folder history:history]];
  [_duplicatesCheckbox setState:[preferences scanForDuplicates] ? NSOnState : NSOffState];
  _adjustingSelection++;
  [_table reloadData];
  [_table selectRowIndexes:[LDSelectTargetRules indexesOfMountPoints:[preferences selectedDrives] inVolumes:_volumes]
      byExtendingSelection:NO];
  _adjustingSelection--;
  [self setMode:[preferences selectTargetMode]];
}

- (NSArray *)runWithInitialFolder:(NSString *)folder
{
  _volumes = [LDVolumes localVolumes];
  [self buildPanel];
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [self restoreFromPreferences:preferences initialFolder:folder];
  [self queryVolumes];

  NSView *first = _mode == LDSelectTargetFolder ? (NSView *)_folderCombo
    : (_mode == LDSelectTargetIndividualDrives ? (NSView *)_table : (NSView *)_allRadio);
  [_panel setInitialFirstResponder:first];
  [_panel center];
  NSInteger result = LDRunPanelModally(_panel);
  _finished = YES;
  [_panel orderOut:nil];
  if (result != NSModalResponseOK) {
    return nil;
  }

  NSArray *paths = [self currentPaths];
  if (paths == nil) {
    return nil;
  }
  [preferences setSelectTargetMode:_mode];
  [preferences setSelectedDrives:[self selectedMountPoints]];
  [preferences setScanForDuplicates:[_duplicatesCheckbox state] == NSOnState];
  // Each folder on its own, the first one newest.
  if (_mode == LDSelectTargetFolder) {
    for (NSString *path in [paths reverseObjectEnumerator]) {
      [preferences addFolderToHistory:path];
    }
  }
  return paths;
}

- (NSArray *)mountPoints
{
  return [_volumes valueForKey:@"mountPoint"];
}

- (NSArray *)selectedMountPoints
{
  return [[self mountPoints] objectsAtIndexes:[_table selectedRowIndexes]];
}

- (NSArray *)currentPaths
{
  return [LDSelectTargetRules pathsForMode:_mode
                               mountPoints:[self mountPoints]
                           selectedIndexes:[_table selectedRowIndexes]
                                folderText:[_folderCombo stringValue]];
}

#pragma mark - Volume usage

// statvfs can hang (a dead device), so each volume is queried off the main
// thread, on a copy, and the result is applied on the main thread.
- (void)queryVolumes
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  for (LDVolume *volume in _volumes) {
    LDVolume *probe = [[LDVolume alloc] initWithMountPointData:[volume mountPointData]
                                                        device:[volume device]
                                                fileSystemType:[volume fileSystemType]
                                                        source:[volume source]
                                                         label:[volume label]];
    dispatch_async(queue, ^{
      [LDVolumes queryUsageForVolume:probe];
      [self performSelectorOnMainThread:@selector(applyQueryResult:)
                             withObject:@[volume, probe]
                          waitUntilDone:NO
                                  modes:@[NSDefaultRunLoopMode, NSModalPanelRunLoopMode]];
    });
  }
}

- (void)applyQueryResult:(NSArray *)pair
{
  LDVolume *volume = [pair objectAtIndex:0];
  LDVolume *probe = [pair objectAtIndex:1];
  if ([probe isQueried]) {
    [volume setTotalBytes:[probe totalBytes] freeBytes:[probe freeBytes]];
  } else {
    [volume markQueryFailed];
  }
  if (_finished) {
    return;
  }
  // WinDirStat re-sorts as results arrive.
  NSSortDescriptor *descriptor = [[_table sortDescriptors] firstObject];
  if (descriptor && ![[descriptor key] isEqualToString:LDSelectTargetColumnName]) {
    [self resortVolumes];
    return;
  }
  NSUInteger row = [_volumes indexOfObjectIdenticalTo:volume];
  if (row != NSNotFound) {
    [_table setNeedsDisplayInRect:[_table rectOfRow:(NSInteger)row]];
  }
}

- (void)resortVolumes
{
  NSSortDescriptor *descriptor = [[_table sortDescriptors] firstObject];
  if (!descriptor) {
    return;
  }
  NSArray *selected = [self selectedMountPoints];
  _volumes = [LDSelectTargetRules volumes:_volumes sortedByKey:[descriptor key] ascending:[descriptor ascending]];
  _adjustingSelection++;
  [_table reloadData];
  [_table selectRowIndexes:[LDSelectTargetRules indexesOfMountPoints:selected inVolumes:_volumes] byExtendingSelection:NO];
  _adjustingSelection--;
}

#pragma mark - Mode and validation

- (void)setMode:(LDSelectTargetMode)mode
{
  _mode = mode;
  [_allRadio setState:mode == LDSelectTargetAllLocalDrives ? NSOnState : NSOffState];
  [_individualRadio setState:mode == LDSelectTargetIndividualDrives ? NSOnState : NSOffState];
  [_folderRadio setState:mode == LDSelectTargetFolder ? NSOnState : NSOffState];
  [self validate];
}

- (void)validate
{
  [_okButton setEnabled:[LDSelectTargetRules canConfirmMode:_mode
                                                volumeCount:[_volumes count]
                                              selectedCount:[[_table selectedRowIndexes] count]
                                                 folderText:[_folderCombo stringValue]]];
}

- (void)radioChanged:(id)sender
{
  [self setMode:(LDSelectTargetMode)[sender tag]];
}

#pragma mark - Actions

- (void)confirm:(id)sender
{
  (void)sender;
  if ([self currentPaths] == nil) {
    NSBeep();
    return;
  }
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender
{
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (void)tableDoubleClicked:(id)sender
{
  (void)sender;
  if ([_table clickedRow] >= 0 && [_okButton isEnabled]) {
    [self confirm:sender];
  }
}

// BrowseFolders: one or more folders replace the text (Browse) or are
// added to it (the button beside it).
- (void)browseFoldersAppending:(BOOL)append
{
  NSOpenPanel *open = [NSOpenPanel openPanel];
  [open setCanChooseFiles:NO];
  [open setCanChooseDirectories:YES];
  [open setAllowsMultipleSelection:YES];
  NSArray *current = [LDSelectTargetRules folderPathsFromText:[_folderCombo stringValue]];
  NSString *first = [current firstObject];
  NSString *directory = first && [LDSelectTargetRules isUsableFolderText:first] ? first : NSHomeDirectory();
  NSInteger result = [open runModalForDirectory:directory file:nil types:nil];
  if (result != NSFileHandlingPanelOKButton && result != NSOKButton) {
    return;
  }
  NSArray *chosen = [self selectedDirectoryPathsFromOpenPanel:open];
  if ([chosen count] == 0) {
    return;
  }
  NSArray *paths = append ? [current arrayByAddingObjectsFromArray:chosen] : chosen;
  NSString *text = [LDSelectTargetRules folderTextForPaths:paths];
  [_folderCombo setStringValue:[LDSelectTargetRules folderTextForPaths:[LDSelectTargetRules folderPathsFromText:text]]];
  [self setMode:LDSelectTargetFolder];
}

- (void)browse:(id)sender
{
  (void)sender;
  [self browseFoldersAppending:NO];
}

- (void)addFolders:(id)sender
{
  (void)sender;
  [self browseFoldersAppending:YES];
}

- (NSArray *)selectedDirectoryPathsFromOpenPanel:(NSOpenPanel *)panel
{
  NSArray *filenames = [panel filenames];
  if ([filenames count] > 0) {
    return filenames;
  }
  NSString *path = [self selectedDirectoryPathFromOpenPanel:panel];
  return [path length] > 0 ? @[path] : @[];
}

// As AppController's: GNUstep's panel may report the choice by filenames,
// URL or filename.
- (NSString *)selectedDirectoryPathFromOpenPanel:(NSOpenPanel *)panel
{
  NSArray *filenames = [panel filenames];
  if ([filenames count] > 0) {
    return [filenames objectAtIndex:0];
  }
  if ([panel respondsToSelector:@selector(URL)]) {
    NSURL *url = [panel URL];
    if (url && [url path]) {
      return [url path];
    }
  }
  return [panel filename];
}

#pragma mark - Folder combo

- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
  if ([notification object] == _folderCombo) {
    [self setMode:LDSelectTargetFolder];
  }
}

- (void)controlTextDidChange:(NSNotification *)notification
{
  if ([notification object] == _folderCombo) {
    [self setMode:LDSelectTargetFolder];
  }
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
  // The field's text changes after this notification; validate then.
  [self performSelector:@selector(folderPicked)
             withObject:nil
             afterDelay:0.0
                inModes:@[NSDefaultRunLoopMode, NSModalPanelRunLoopMode]];
}

- (void)folderPicked
{
  if (!_finished) {
    [self setMode:LDSelectTargetFolder];
  }
}

// Return in the folder field confirms and Escape cancels, as they do
// elsewhere in the dialog.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
  (void)textView;
  if (control != _folderCombo) {
    return NO;
  }
  if (command == @selector(insertNewline:)) {
    [self validate];
    if ([_okButton isEnabled]) {
      [self confirm:nil];
    } else {
      NSBeep();
    }
    return YES;
  }
  if (command == @selector(cancelOperation:)) {
    [self cancel:nil];
    return YES;
  }
  return NO;
}

#pragma mark - Drive list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  (void)tableView;
  return (NSInteger)[_volumes count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  (void)tableView;
  if (row < 0 || (NSUInteger)row >= [_volumes count]) {
    return nil;
  }
  LDVolume *volume = [_volumes objectAtIndex:(NSUInteger)row];
  NSString *identifier = [column identifier];
  if ([identifier isEqualToString:LDSelectTargetColumnName]) {
    return [volume displayName];
  }
  if ([identifier isEqualToString:LDSelectTargetColumnTotal]) {
    return [volume isQueried] ? [LDSizeFormatter stringForBytes:[volume totalBytes]] : @"";
  }
  if ([identifier isEqualToString:LDSelectTargetColumnFree]) {
    return [volume isQueried] ? [LDSizeFormatter stringForBytes:[volume freeBytes]] : @"";
  }
  if ([identifier isEqualToString:LDSelectTargetColumnPercent]) {
    return [LDSelectTargetRules percentStringForVolume:volume];
  }
  return nil;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  (void)tableView;
  if (![cell isKindOfClass:[LDVolumeUsageCell class]] || row < 0 || (NSUInteger)row >= [_volumes count]) {
    return;
  }
  (void)column;
  LDVolume *volume = [_volumes objectAtIndex:(NSUInteger)row];
  LDVolumeUsageState state = [volume isQueried] ? LDVolumeUsageReady
    : ([volume queryFailed] ? LDVolumeUsageUnavailable : LDVolumeUsageQuerying);
  [(LDVolumeUsageCell *)cell setUsageState:state fraction:[volume usedFraction]];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
  (void)tableView;
  (void)oldDescriptors;
  [self resortVolumes];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_adjustingSelection == 0 && [[_table selectedRowIndexes] count] > 0) {
    [self setMode:LDSelectTargetIndividualDrives];
  } else {
    [self validate];
  }
}

#pragma mark - Window

- (BOOL)windowShouldClose:(id)sender
{
  (void)sender;
  [self cancel:nil];
  return YES;
}

@end

@implementation LDSelectTargetPanel

+ (void)setModalRunnerForTesting:(NSInteger (^)(NSWindow *panel))runner
{
  LDModalRunnerForTesting = [runner copy];
}

+ (NSArray *)runWithInitialFolder:(NSString *)folder
{
  LDSelectTargetController *controller = [[LDSelectTargetController alloc] init];
  return [controller runWithInitialFolder:folder];
}

@end
