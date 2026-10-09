#import "LDOptionsWindowController.h"
#import "LDLocalization.h"
#import "LDLanguages.h"
#import "LDPlatformUI.h"
#import "LDFilterPatterns.h"
#import "LDPreferences.h"
#import "LDTreeCells.h"
#import "LDTreemapPreview.h"

static const CGFloat LDOptionsMargin = 18.0;
static const CGFloat LDOptionsRowSpacing = 6.0;
static const CGFloat LDOptionsSectionSpacing = 12.0;
static const CGFloat LDOptionsControlSpacing = 6.0;
// The Treemap page's live preview (WinDirStat's CTreeMapPreview).
static const CGFloat LDTreemapPreviewWidth = 220.0;
static const CGFloat LDTreemapPreviewHeight = 160.0;

// Pages are laid out top-down.
@interface LDOptionsPageView : NSView
@end

@implementation LDOptionsPageView
- (BOOL)isFlipped
{
  return YES;
}
@end

@interface LDOptionsWindowController ()
{
  NSTabView *_tabView;
  NSInteger _applying;

  // Layout cursor for the page being built.
  NSView *_page;
  CGFloat _y;
  CGFloat _left;
  CGFloat _right;
  BOOL _sectionStarted;

  // General
  NSButton *_humanFormat;
  NSButton *_fullRowSelection;
  NSButton *_listGrid;
  NSButton *_listStripes;
  NSButton *_autoResizeColumns;

  // Filtering
  NSTextView *_folderPatterns;
  NSTextView *_filePatterns;
  NSButton *_filterRegex;
  NSTextField *_filterError;
  NSTextField *_minimumSize;
  NSPopUpButton *_minimumSizeUnit;
  NSPopUpButton *_language;

  // Folder List
  NSButton *_pacman;
  NSButton *_timeSpent;
  NSMutableArray *_columnButtons;
  NSMutableArray *_levelColorWells;
  NSSlider *_levelCount;

  // Treemap
  NSPopUpButton *_treemapStyle;
  NSButton *_treemapGrid;
  NSSlider *_brightness;
  NSSlider *_cushionShading;
  NSSlider *_height;
  NSSlider *_scaleFactor;
  NSSlider *_lightX;
  NSSlider *_lightY;
  NSMapTable *_sliderLabels;
  NSColorWell *_gridColor;
  NSColorWell *_highlightColor;
  NSImageView *_treemapPreview;

  // Cleanups
  NSMutableArray *_cleanups;
  NSTableView *_cleanupTable;
  NSButton *_moveUp;
  NSButton *_moveDown;
  NSButton *_cleanupEnabled;
  NSTextField *_cleanupTitle;
  NSTextField *_cleanupCommand;
  NSTextField *_cleanupHint;
  NSButton *_worksForMountPoints;
  NSButton *_worksForFolders;
  NSButton *_worksForFiles;
  NSButton *_recurse;
  NSButton *_askForConfirmation;
  NSButton *_runInTerminal;
  NSButton *_waitForCompletion;
  NSTextField *_cleanupTitleLabel;
  NSTextField *_cleanupCommandLabel;
  NSTextField *_refreshPolicyLabel;
  NSPopUpButton *_refreshPolicy;

  // Prompts
  NSButton *_deleteWarning;

  // Advanced
  NSButton *_excludeMountPoints;
  NSButton *_excludeSymlinks;
  NSButton *_excludeHidden;
  NSButton *_processHardLinks;
  NSButton *_scanDuplicates;
  NSPopUpButton *_threads;
  NSTextField *_largeFileCount;
  NSStepper *_largeFileStepper;
  NSTextField *_historyCount;
  NSStepper *_historyStepper;
}
@end

@implementation LDOptionsWindowController

+ (LDOptionsWindowController *)sharedController
{
  static LDOptionsWindowController *shared = nil;
  if (!shared) {
    shared = [[LDOptionsWindowController alloc] init];
  }
  return shared;
}

- (id)init
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 520)
                                                 styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [window setTitle:[LDPlatformUI settingsTitle]];
  [window setReleasedWhenClosed:NO];
  self = [super initWithWindow:window];
  if (self) {
    _columnButtons = [NSMutableArray array];
    _levelColorWells = [NSMutableArray array];
    _sliderLabels = [NSMapTable strongToStrongObjectsMapTable];
    _cleanups = [[[LDPreferences sharedPreferences] customCleanups] mutableCopy];
    [self buildContents];
    [_cleanupTable reloadData];
    [_cleanupTable selectRow:0 byExtendingSelection:NO];
    [self refreshControls];
    [window center];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(preferencesDidChange:)
                                                 name:LDPreferencesDidChangeNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Showing

- (void)showWindow:(id)sender
{
  NSInteger page = [[LDPreferences sharedPreferences] lastOptionsPage];
  if (page < 0 || page >= [_tabView numberOfTabViewItems]) {
    page = LDOptionsPageGeneral;
  }
  [self refreshControls];
  [_tabView selectTabViewItemAtIndex:page];
  [super showWindow:sender];
}

- (void)showPage:(LDOptionsPage)page
{
  [self refreshControls];
  if ((NSInteger)page >= 0 && (NSInteger)page < [_tabView numberOfTabViewItems]) {
    [_tabView selectTabViewItemAtIndex:page];
  }
  [super showWindow:nil];
}

- (LDOptionsPage)selectedPage
{
  return (LDOptionsPage)[_tabView indexOfTabViewItem:[_tabView selectedTabViewItem]];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item
{
  NSInteger page = [tabView indexOfTabViewItem:item];
  if (page != NSNotFound && page != [[LDPreferences sharedPreferences] lastOptionsPage]) {
    [self apply:^(LDPreferences *preferences) {
      [preferences setLastOptionsPage:page];
    }];
  }
}

#pragma mark - Applying changes

// Writes through LDPreferences without reloading the controls in response
// to our own change notification.
- (void)apply:(void (^)(LDPreferences *preferences))change
{
  _applying++;
  change([LDPreferences sharedPreferences]);
  _applying--;
}

- (void)preferencesDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_applying == 0) {
    [self refreshControls];
  }
}

#pragma mark - Control factories

- (NSTextField *)labelWithString:(NSString *)string
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  [label setBezeled:NO];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setStringValue:string];
  [label sizeToFit];
  return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title action:(SEL)action
{
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  [button setButtonType:NSSwitchButton];
  [button setTitle:title];
  [button setTarget:self];
  [button setAction:action];
  [button sizeToFit];
  return button;
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
  return button;
}

- (NSPopUpButton *)popUpWithTitles:(NSArray *)titles action:(SEL)action
{
  NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [popUp addItemsWithTitles:titles];
  [popUp setTarget:self];
  [popUp setAction:action];
  [popUp sizeToFit];
  return popUp;
}

- (NSTextField *)numberFieldWithAction:(SEL)action
{
  NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)];
  [field setAlignment:NSRightTextAlignment];
  [field setDelegate:self];
  [field setTarget:self];
  [field setAction:action];
  [field sizeToFit];
  return field;
}

- (NSStepper *)stepperFrom:(double)low to:(double)high action:(SEL)action
{
  NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
  [stepper setMinValue:low];
  [stepper setMaxValue:high];
  [stepper setIncrement:1.0];
  [stepper setValueWraps:NO];
  [stepper setTarget:self];
  [stepper setAction:action];
  [stepper setFrameSize:NSMakeSize(19.0, 26.0)];
  return stepper;
}

- (NSColorWell *)colorWellWithAction:(SEL)action
{
  NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
  [well setTarget:self];
  [well setAction:action];
  return well;
}

- (NSSlider *)sliderFrom:(double)low to:(double)high
{
  NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 220, 22)];
  [slider setMinValue:low];
  [slider setMaxValue:high];
  [slider setContinuous:YES];
  [slider setTarget:self];
  [slider setAction:@selector(sliderChanged:)];
  return slider;
}

#pragma mark - Layout

- (NSView *)beginPage:(NSString *)label
{
  NSRect content = [_tabView contentRect];
  _page = [[LDOptionsPageView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(content), NSHeight(content))];
  [_page setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _y = LDOptionsMargin;
  _left = LDOptionsMargin;
  _right = NSWidth(content) - LDOptionsMargin;
  _sectionStarted = NO;

  NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:label];
  [item setLabel:label];
  [item setView:_page];
  [_tabView addTabViewItem:item];
  return _page;
}

- (void)place:(NSView *)view x:(CGFloat)x width:(CGFloat)width height:(CGFloat)height mask:(NSUInteger)mask
{
  [view setFrame:NSMakeRect(x, _y, width, height)];
  [view setAutoresizingMask:mask | NSViewMaxYMargin];
  [_page addSubview:view];
}

- (void)addSectionTitle:(NSString *)title
{
  if (_sectionStarted) {
    _y += LDOptionsSectionSpacing;
  }
  _sectionStarted = YES;
  NSTextField *label = [self labelWithString:title];
  [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
  [label sizeToFit];
  [self place:label x:_left width:_right - _left height:NSHeight([label frame]) mask:NSViewWidthSizable];
  _y += NSHeight([label frame]) + LDOptionsRowSpacing;
}

- (void)addFullWidthView:(NSView *)view height:(CGFloat)height
{
  _sectionStarted = YES;
  [self place:view x:_left width:_right - _left height:height mask:NSViewWidthSizable];
  _y += height + LDOptionsRowSpacing;
}

- (NSButton *)addCheckbox:(NSString *)title action:(SEL)action
{
  NSButton *button = [self checkboxWithTitle:title action:action];
  [self addFullWidthView:button height:NSHeight([button frame])];
  return button;
}

// Checkboxes side by side on one row.
- (void)addCheckboxRow:(NSArray *)buttons
{
  _sectionStarted = YES;
  CGFloat x = _left;
  CGFloat height = 0;
  for (NSButton *button in buttons) {
    NSRect frame = [button frame];
    [self place:button x:x width:NSWidth(frame) height:NSHeight(frame) mask:NSViewMaxXMargin];
    x += NSWidth(frame) + LDOptionsMargin;
    height = MAX(height, NSHeight(frame));
  }
  _y += height + LDOptionsRowSpacing;
}

// A preference row: the label on the left, the controls (at their current
// widths) packed against the right edge, all vertically centred.
- (NSTextField *)addRow:(NSString *)title controls:(NSArray *)controls
{
  _sectionStarted = YES;
  CGFloat height = 0;
  CGFloat controlsWidth = 0;
  for (NSView *control in controls) {
    height = MAX(height, NSHeight([control frame]));
    controlsWidth += NSWidth([control frame]);
  }
  controlsWidth += LDOptionsControlSpacing * ([controls count] - 1);

  NSTextField *label = [self labelWithString:title];
  height = MAX(height, NSHeight([label frame]));
  CGFloat rowY = _y;
  _y = rowY + floor((height - NSHeight([label frame])) / 2.0);
  [self place:label x:_left width:_right - _left - controlsWidth - LDOptionsControlSpacing height:NSHeight([label frame])
         mask:NSViewWidthSizable];

  CGFloat x = _right - controlsWidth;
  for (NSView *control in controls) {
    NSRect frame = [control frame];
    _y = rowY + floor((height - NSHeight(frame)) / 2.0);
    [self place:control x:x width:NSWidth(frame) height:NSHeight(frame) mask:NSViewMinXMargin];
    x += NSWidth(frame) + LDOptionsControlSpacing;
  }
  _y = rowY + height + LDOptionsRowSpacing;
  return label;
}

- (NSTextView *)addPatternEditor:(NSString *)title height:(CGFloat)height
{
  NSTextField *label = [self labelWithString:title];
  [self addFullWidthView:label height:NSHeight([label frame])];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, _right - _left, height)];
  [scroll setBorderType:NSBezelBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  NSSize size = [scroll contentSize];
  NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
  [textView setRichText:NO];
  [textView setImportsGraphics:NO];
  [textView setAllowsUndo:YES];
  [textView setFont:[NSFont userFixedPitchFontOfSize:0]];
  [textView setMinSize:NSMakeSize(0, size.height)];
  [textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
  [textView setVerticallyResizable:YES];
  [textView setHorizontallyResizable:NO];
  [textView setAutoresizingMask:NSViewWidthSizable];
  [[textView textContainer] setWidthTracksTextView:YES];
  [textView setDelegate:self];
  [scroll setDocumentView:textView];
  [self addFullWidthView:scroll height:height];
  return textView;
}

- (NSTextField *)addNote:(NSString *)text color:(NSColor *)color lines:(NSUInteger)lines
{
  NSTextField *note = [self labelWithString:text];
  [note setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [note setTextColor:color];
  [[note cell] setWraps:YES];
  [note sizeToFit];
  [self addFullWidthView:note height:NSHeight([note frame]) * lines];
  return note;
}

- (void)buildContents
{
  NSView *content = [[self window] contentView];
  NSRect bounds = [content bounds];
  _tabView = [[NSTabView alloc] initWithFrame:NSInsetRect(bounds, 12.0, 12.0)];
  [_tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [content addSubview:_tabView];

  [self buildGeneralPage];
  [self buildFilteringPage];
  [self buildFolderListPage];
  [self buildTreemapPage];
  [self buildCleanupsPage];
  [self buildPromptsPage];
  [self buildAdvancedPage];
  _page = nil;
  [_tabView setDelegate:self];
}

- (void)buildGeneralPage
{
  [self beginPage:LDLocalized(@"General")];
  [self addSectionTitle:LDLocalized(@"Sizes")];
  _humanFormat = [self addCheckbox:LDLocalized(@"Show sizes in human-readable format") action:@selector(generalChanged:)];
  [self addSectionTitle:LDLocalized(@"List Style")];
  _autoResizeColumns = [self addCheckbox:LDLocalized(@"Automatically resize columns") action:@selector(generalChanged:)];
  _fullRowSelection = [self addCheckbox:LDLocalized(@"Full row selection") action:@selector(generalChanged:)];
  _listGrid = [self addCheckbox:LDLocalized(@"Show grid") action:@selector(generalChanged:)];
  _listStripes = [self addCheckbox:LDLocalized(@"Show stripes") action:@selector(generalChanged:)];

  // WinDirStat's Language setting; it applies from the next launch.
  [self addSectionTitle:LDLocalized(@"Language")];
  NSMutableArray *names = [NSMutableArray arrayWithObject:LDLocalized(@"System Default")];
  for (NSString *code in [LDLanguages availableLanguages]) {
    [names addObject:[LDLanguages nativeNameOfLanguage:code]];
  }
  _language = [self popUpWithTitles:names action:@selector(languageChanged:)];
  NSString *chosen = [LDLanguages chosenLanguage];
  NSUInteger index = chosen ? [[LDLanguages availableLanguages] indexOfObject:chosen] : NSNotFound;
  [_language selectItemAtIndex:index == NSNotFound ? 0 : (NSInteger)index + 1];
  [self addRow:LDLocalized(@"Language") controls:@[_language]];
  [self addNote:LDLocalized(@"Takes effect when LinDirStat is opened again.") color:[NSColor secondaryLabelColor] lines:1];
}

- (void)languageChanged:(id)sender
{
  NSInteger index = [(NSPopUpButton *)sender indexOfSelectedItem];
  NSArray *codes = [LDLanguages availableLanguages];
  [LDLanguages setChosenLanguage:index > 0 && index <= (NSInteger)[codes count] ? [codes objectAtIndex:index - 1] : nil];
}

- (void)buildFilteringPage
{
  [self beginPage:LDLocalized(@"Filtering")];
  _folderPatterns = [self addPatternEditor:LDLocalized(@"Folder paths to exclude:") height:84.0];
  _y += LDOptionsSectionSpacing - LDOptionsRowSpacing;
  _filePatterns = [self addPatternEditor:LDLocalized(@"File name patterns to exclude:") height:84.0];
  _filterRegex = [self addCheckbox:LDLocalized(@"Use regular expressions instead of glob patterns") action:@selector(filterRegexChanged:)];
  _filterError = [self labelWithString:@" "];
  [_filterError setTextColor:[NSColor systemRedColor]];
  [[_filterError cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [self addFullWidthView:_filterError height:NSHeight([_filterError frame])];

  _minimumSize = [self numberFieldWithAction:@selector(minimumSizeEntered:)];
  [_minimumSize setFrameSize:NSMakeSize(100, NSHeight([_minimumSize frame]))];
  _minimumSizeUnit = [self popUpWithTitles:@[@"bytes", @"KiB", @"MiB", @"GiB", @"TiB"]
                                    action:@selector(minimumSizeUnitChanged:)];
  [self addRow:LDLocalized(@"Exclude files smaller than") controls:@[_minimumSize, _minimumSizeUnit]];
  _y += LDOptionsSectionSpacing - LDOptionsRowSpacing;
  [self addNote:LDLocalized(@"Changes apply to the next scan or refresh.") color:[NSColor secondaryLabelColor] lines:1];
}

+ (NSDictionary *)columnTitles
{
  return @{
    LDColumnPhysicalSize: LDLocalized(@"Physical Size"),
    LDColumnLogicalSize: LDLocalized(@"Logical Size"),
    LDColumnItems: LDLocalized(@"Items"),
    LDColumnFiles: LDLocalized(@"Files"),
    LDColumnFolders: LDLocalized(@"Folders"),
    LDColumnLastChange: LDLocalized(@"Last Change"),
    LDColumnAttributes: LDLocalized(@"Attributes"),
    LDColumnOwner: LDLocalized(@"Owner"),
  };
}

- (void)buildFolderListPage
{
  [self beginPage:LDLocalized(@"Folder List")];
  [self addSectionTitle:LDLocalized(@"Scanning")];
  _pacman = [self addCheckbox:LDLocalized(@"Pacman animation") action:@selector(folderListChanged:)];
  _timeSpent = [self addCheckbox:LDLocalized(@"Show time spent during scan") action:@selector(folderListChanged:)];
  [self addSectionTitle:LDLocalized(@"Optional Columns")];
  NSDictionary *titles = [LDOptionsWindowController columnTitles];
  // Two columns of checkboxes, in WinDirStat's order down each column.
  NSArray *columns = [LDPreferences optionalColumns];
  NSUInteger half = ([columns count] + 1) / 2;
  CGFloat top = _y;
  CGFloat bottom = _y;
  for (NSUInteger i = 0; i < [columns count]; i++) {
    NSString *column = [columns objectAtIndex:i];
    NSButton *button = [self checkboxWithTitle:[titles objectForKey:column] ?: column action:@selector(columnChanged:)];
    if (i == half) {
      _y = top;
    }
    CGFloat x = i < half ? _left : _left + floor((_right - _left) / 2.0);
    [self place:button x:x width:NSWidth([button frame]) height:NSHeight([button frame]) mask:NSViewMaxXMargin];
    _y += NSHeight([button frame]) + LDOptionsRowSpacing;
    bottom = MAX(bottom, _y);
    [_columnButtons addObject:button];
  }
  _y = bottom;

  // WinDirStat's Subtree Percentage colours: one per level, used in turn.
  [self addSectionTitle:LDLocalized(@"Subtree Percentage Colors")];
  NSMutableArray *wells = [NSMutableArray array];
  for (NSUInteger i = 0; i < [LDPreferences fileTreeColorSlots]; i++) {
    NSColorWell *well = [self colorWellWithAction:@selector(levelColorChanged:)];
    [wells addObject:well];
    [_levelColorWells addObject:well];
  }
  [self addRow:LDLocalized(@"Level colors") controls:wells];
  _levelCount = [self addSliderRow:LDLocalized(@"Levels used") from:1 to:[LDPreferences fileTreeColorSlots]];
  [_levelCount setNumberOfTickMarks:[LDPreferences fileTreeColorSlots]];
  [_levelCount setAllowsTickMarkValuesOnly:YES];
  [_levelCount setAction:@selector(levelCountChanged:)];
}

- (NSSlider *)addSliderRow:(NSString *)title from:(double)low to:(double)high
{
  NSSlider *slider = [self sliderFrom:low to:high];
  NSTextField *value = [self labelWithString:@"-100 %"];
  [value setAlignment:NSRightTextAlignment];
  [value setFrameSize:NSMakeSize(NSWidth([value frame]) + 8.0, NSHeight([value frame]))];
  [_sliderLabels setObject:value forKey:slider];
  [self addRow:title controls:@[slider, value]];
  return slider;
}

- (void)buildTreemapPage
{
  [self beginPage:LDLocalized(@"Treemap")];
  // The settings take the left; WinDirStat's live preview sits on the right.
  CGFloat pageRight = _right;
  _right = pageRight - LDTreemapPreviewWidth - LDOptionsMargin;
  _treemapPreview = [[NSImageView alloc] initWithFrame:NSZeroRect];
  [_treemapPreview setImageFrameStyle:NSImageFrameNone];
  [_treemapPreview setImageScaling:NSImageScaleNone];
  [_treemapPreview setEditable:NO];
  CGFloat top = _y;
  _y = top + 26.0;
  [self place:_treemapPreview x:pageRight - LDTreemapPreviewWidth width:LDTreemapPreviewWidth
       height:LDTreemapPreviewHeight mask:NSViewMinXMargin];
  _y = top;
  NSTextField *previewTitle = [self labelWithString:LDLocalized(@"Preview")];
  [previewTitle setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
  [previewTitle sizeToFit];
  [self place:previewTitle x:pageRight - LDTreemapPreviewWidth width:LDTreemapPreviewWidth
       height:NSHeight([previewTitle frame]) mask:NSViewMinXMargin];

  [self addSectionTitle:LDLocalized(@"Layout")];
  _treemapStyle = [self popUpWithTitles:@[LDLocalized(@"KDirStat"), @"SequoiaView"] action:@selector(treemapChanged:)];
  [_treemapStyle setFrameSize:NSMakeSize(MAX(NSWidth([_treemapStyle frame]), 160.0), NSHeight([_treemapStyle frame]))];
  [self addRow:LDLocalized(@"Style") controls:@[_treemapStyle]];
  _treemapGrid = [self addCheckbox:LDLocalized(@"Show grid") action:@selector(treemapChanged:)];
  _gridColor = [self colorWellWithAction:@selector(treemapColorChanged:)];
  [self addRow:LDLocalized(@"Grid color") controls:@[_gridColor]];
  _highlightColor = [self colorWellWithAction:@selector(treemapColorChanged:)];
  [self addRow:LDLocalized(@"Highlight color") controls:@[_highlightColor]];

  [self addSectionTitle:LDLocalized(@"Cushions")];
  _brightness = [self addSliderRow:LDLocalized(@"Brightness") from:0 to:100];
  _cushionShading = [self addSliderRow:LDLocalized(@"Cushion shading") from:0 to:100];
  _height = [self addSliderRow:LDLocalized(@"Height") from:0 to:100];
  _scaleFactor = [self addSliderRow:LDLocalized(@"Scale factor") from:0 to:100];

  [self addSectionTitle:LDLocalized(@"Light Source")];
  _lightX = [self addSliderRow:LDLocalized(@"Horizontal position") from:-100 to:100];
  _lightY = [self addSliderRow:LDLocalized(@"Vertical position") from:-100 to:100];

  _y += LDOptionsSectionSpacing - LDOptionsRowSpacing;
  NSButton *reset = [self pushButtonWithTitle:LDLocalized(@"Reset to Defaults") action:@selector(resetTreemap:)];
  NSRect frame = [reset frame];
  [self place:reset x:_right - NSWidth(frame) width:NSWidth(frame) height:NSHeight(frame) mask:NSViewMinXMargin];
  _y += NSHeight(frame);
  _right = pageRight;
}

- (void)buildCleanupsPage
{
  NSView *page = [self beginPage:LDLocalized(@"Cleanups")];
  CGFloat listWidth = 220.0;

  _moveUp = [self pushButtonWithTitle:LDLocalized(@"Move Up") action:@selector(moveCleanupUp:)];
  _moveDown = [self pushButtonWithTitle:LDLocalized(@"Move Down") action:@selector(moveCleanupDown:)];
  CGFloat buttonHeight = NSHeight([_moveUp frame]);
  CGFloat buttonWidth = floor((listWidth - LDOptionsControlSpacing) / 2.0);
  CGFloat buttonY = NSHeight([page frame]) - LDOptionsMargin - buttonHeight;
  [_moveUp setFrame:NSMakeRect(_left, buttonY, buttonWidth, buttonHeight)];
  [_moveDown setFrame:NSMakeRect(_left + listWidth - buttonWidth, buttonY, buttonWidth, buttonHeight)];
  [_moveUp setAutoresizingMask:NSViewMinYMargin];
  [_moveDown setAutoresizingMask:NSViewMinYMargin];
  [page addSubview:_moveUp];
  [page addSubview:_moveDown];

  CGFloat listHeight = buttonY - LDOptionsRowSpacing - _y;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(_left, _y, listWidth, listHeight)];
  [scroll setBorderType:NSBezelBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewHeightSizable];
  _cleanupTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, [scroll contentSize].width, listHeight)];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
  [column setEditable:NO];
  [column setWidth:[scroll contentSize].width];
  [column setResizingMask:NSTableColumnAutoresizingMask];
  [_cleanupTable addTableColumn:column];
  [_cleanupTable setHeaderView:nil];
  [_cleanupTable setCornerView:nil];
  [_cleanupTable setAllowsEmptySelection:NO];
  [_cleanupTable setAllowsMultipleSelection:NO];
  [_cleanupTable setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
  [_cleanupTable setDataSource:self];
  [_cleanupTable setDelegate:self];
  [scroll setDocumentView:_cleanupTable];
  [page addSubview:scroll];

  _left += listWidth + LDOptionsMargin;

  _cleanupEnabled = [self addCheckbox:LDLocalized(@"Enabled") action:@selector(cleanupChanged:)];
  CGFloat fieldWidth = _right - _left - 110.0;
  _cleanupTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, fieldWidth, 24)];
  [_cleanupTitle sizeToFit];
  [_cleanupTitle setFrameSize:NSMakeSize(fieldWidth, NSHeight([_cleanupTitle frame]))];
  [_cleanupTitle setDelegate:self];
  _cleanupTitleLabel = [self addRow:LDLocalized(@"Title") controls:@[_cleanupTitle]];
  _cleanupCommand = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, fieldWidth, 24)];
  [_cleanupCommand sizeToFit];
  [_cleanupCommand setFrameSize:NSMakeSize(fieldWidth, NSHeight([_cleanupCommand frame]))];
  [_cleanupCommand setDelegate:self];
  _cleanupCommandLabel = [self addRow:LDLocalized(@"Command line") controls:@[_cleanupCommand]];
  _cleanupHint = [self addNote:LDLocalized(@"%p path, %n name; %sp, %sn subfolder path and name when recursing")
                         color:[NSColor secondaryLabelColor]
                         lines:2];

  [self addSectionTitle:LDLocalized(@"Works For")];
  _worksForMountPoints = [self checkboxWithTitle:LDLocalized(@"Mount points & scan roots") action:@selector(cleanupChanged:)];
  _worksForFolders = [self checkboxWithTitle:LDLocalized(@"Folders") action:@selector(cleanupChanged:)];
  _worksForFiles = [self checkboxWithTitle:LDLocalized(@"Files") action:@selector(cleanupChanged:)];
  [self addCheckboxRow:@[_worksForMountPoints, _worksForFolders, _worksForFiles]];

  [self addSectionTitle:LDLocalized(@"Behavior")];
  _recurse = [self addCheckbox:LDLocalized(@"Recurse into subfolders") action:@selector(cleanupChanged:)];
  _askForConfirmation = [self addCheckbox:LDLocalized(@"Ask for confirmation") action:@selector(cleanupChanged:)];
  _runInTerminal = [self addCheckbox:LDLocalized(@"Run in a terminal") action:@selector(cleanupChanged:)];
  _waitForCompletion = [self addCheckbox:LDLocalized(@"Wait for completion") action:@selector(cleanupChanged:)];
  _refreshPolicy = [self popUpWithTitles:@[LDLocalized(@"No refresh"), LDLocalized(@"Refresh this entry"), LDLocalized(@"Refresh this entry's parent")]
                                  action:@selector(cleanupChanged:)];
  _refreshPolicyLabel = [self addRow:LDLocalized(@"After running") controls:@[_refreshPolicy]];
}

- (void)buildPromptsPage
{
  [self beginPage:LDLocalized(@"Prompts")];
  [self addSectionTitle:LDLocalized(@"Confirmations")];
  _deleteWarning = [self addCheckbox:LDLocalized(@"Warn before deleting") action:@selector(promptsChanged:)];
}

- (void)buildAdvancedPage
{
  [self beginPage:LDLocalized(@"Advanced")];
  [self addSectionTitle:LDLocalized(@"Scanning")];
  _excludeMountPoints = [self addCheckbox:LDLocalized(@"Exclude mount points (do not enter other filesystems)")
                                   action:@selector(advancedChanged:)];
  _excludeSymlinks = [self addCheckbox:LDLocalized(@"Exclude symbolic links") action:@selector(advancedChanged:)];
  _excludeHidden = [self addCheckbox:LDLocalized(@"Exclude hidden files and folders") action:@selector(advancedChanged:)];
  _processHardLinks = [self addCheckbox:LDLocalized(@"Scan and display hard link information") action:@selector(advancedChanged:)];
  _scanDuplicates = [self addCheckbox:LDLocalized(@"Scan for duplicate files") action:@selector(advancedChanged:)];
  NSMutableArray *counts = [NSMutableArray array];
  for (NSUInteger i = 1; i <= 16; i++) {
    [counts addObject:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
  }
  _threads = [self popUpWithTitles:counts action:@selector(advancedChanged:)];
  [_threads setFrameSize:NSMakeSize(MAX(NSWidth([_threads frame]), 80.0), NSHeight([_threads frame]))];
  [self addRow:LDLocalized(@"Scanning threads") controls:@[_threads]];

  [self addSectionTitle:LDLocalized(@"Lists")];
  _largeFileCount = [self numberFieldWithAction:@selector(countEntered:)];
  [_largeFileCount setFrameSize:NSMakeSize(80, NSHeight([_largeFileCount frame]))];
  _largeFileStepper = [self stepperFrom:0 to:10000 action:@selector(countStepped:)];
  [self addRow:LDLocalized(@"Largest files shown") controls:@[_largeFileCount, _largeFileStepper]];
  _historyCount = [self numberFieldWithAction:@selector(countEntered:)];
  [_historyCount setFrameSize:NSMakeSize(80, NSHeight([_historyCount frame]))];
  _historyStepper = [self stepperFrom:0 to:100 action:@selector(countStepped:)];
  [self addRow:LDLocalized(@"Folder history entries") controls:@[_historyCount, _historyStepper]];

  [self addSectionTitle:LDLocalized(@"Reset")];
  NSButton *reset = [self pushButtonWithTitle:LDLocalized(@"Reset All Preferences…") action:@selector(resetAll:)];
  [self addRow:LDLocalized(@"Restore every setting to its default") controls:@[reset]];
}

#pragma mark - Refreshing

static NSInteger LDState(BOOL flag)
{
  return flag ? NSOnState : NSOffState;
}

- (void)setText:(NSString *)text ofTextView:(NSTextView *)textView
{
  if (![[textView string] isEqualToString:text]) {
    [textView setString:text];
  }
}

- (void)setString:(NSString *)string ofField:(NSTextField *)field
{
  if (![[field stringValue] isEqualToString:string]) {
    [field setStringValue:string];
  }
}

- (void)refreshControls
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];

  [_humanFormat setState:LDState([preferences humanFormat])];
  [_fullRowSelection setState:LDState([preferences listFullRowSelection])];
  [_listGrid setState:LDState([preferences listGrid])];
  [_listStripes setState:LDState([preferences listStripes])];
  [_autoResizeColumns setState:LDState([preferences automaticallyResizeColumns])];

  [self setText:[preferences excludedFolderPatterns] ofTextView:_folderPatterns];
  [self setText:[preferences excludedFilePatterns] ofTextView:_filePatterns];
  [_filterRegex setState:LDState([preferences filterUsesRegex])];
  [self setString:[NSString stringWithFormat:@"%llu", [preferences minimumFileSize]] ofField:_minimumSize];
  [_minimumSizeUnit selectItemAtIndex:[preferences minimumFileSizeUnit]];
  [self validateFilters];

  [_pacman setState:LDState([preferences pacmanAnimation])];
  [_timeSpent setState:LDState([preferences showTimeSpent])];
  NSArray *columns = [LDPreferences optionalColumns];
  for (NSUInteger i = 0; i < [columns count] && i < [_columnButtons count]; i++) {
    [[_columnButtons objectAtIndex:i] setState:LDState([preferences isColumnShown:[columns objectAtIndex:i]])];
  }

  for (NSUInteger i = 0; i < [_levelColorWells count]; i++) {
    NSColorWell *well = [_levelColorWells objectAtIndex:i];
    [self setColor:[preferences fileTreeColorAtIndex:i] ofWell:well];
    [well setEnabled:i < [preferences fileTreeColorCount]];
  }
  [_levelCount setIntegerValue:(NSInteger)[preferences fileTreeColorCount]];
  [self updateLabelForSlider:_levelCount];

  [_treemapStyle selectItemAtIndex:[preferences treemapStyle]];
  [self setColor:[preferences treemapGridColor] ofWell:_gridColor];
  [self setColor:[preferences treemapHighlightColor] ofWell:_highlightColor];
  [_treemapGrid setState:LDState([preferences treemapGrid])];
  [_brightness setIntegerValue:[preferences treemapBrightness]];
  [_cushionShading setIntegerValue:[preferences treemapCushionShading]];
  [_height setIntegerValue:[preferences treemapHeight]];
  [_scaleFactor setIntegerValue:[preferences treemapScaleFactor]];
  [_lightX setIntegerValue:[preferences treemapLightSourceX]];
  [_lightY setIntegerValue:[preferences treemapLightSourceY]];
  for (NSSlider *slider in @[_brightness, _cushionShading, _height, _scaleFactor, _lightX, _lightY]) {
    [self updateLabelForSlider:slider];
  }
  [self updateTreemapPreview];

  _cleanups = [[preferences customCleanups] mutableCopy];
  [_cleanupTable reloadData];
  if ([self selectedCleanupIndex] < 0 && [_cleanups count] > 0) {
    [_cleanupTable selectRow:0 byExtendingSelection:NO];
  }
  [self refreshCleanupControls];

  [_deleteWarning setState:LDState([preferences showDeleteWarning])];

  [_excludeMountPoints setState:LDState([preferences excludeMountPoints])];
  [_excludeSymlinks setState:LDState([preferences excludeSymbolicLinks])];
  [_excludeHidden setState:LDState([preferences excludeHiddenEntries])];
  [_processHardLinks setState:LDState([preferences processHardLinks])];
  [_scanDuplicates setState:LDState([preferences scanForDuplicates])];
  [_threads selectItemAtIndex:(NSInteger)[preferences scanningThreads] - 1];
  [self setString:[NSString stringWithFormat:@"%lu", (unsigned long)[preferences largeFileCount]] ofField:_largeFileCount];
  [_largeFileStepper setIntegerValue:(NSInteger)[preferences largeFileCount]];
  [self setString:[NSString stringWithFormat:@"%lu", (unsigned long)[preferences folderHistoryCount]] ofField:_historyCount];
  [_historyStepper setIntegerValue:(NSInteger)[preferences folderHistoryCount]];
}

#pragma mark - General, Folder List, Prompts, Advanced

- (void)generalChanged:(id)sender
{
  BOOL on = [(NSButton *)sender state] == NSOnState;
  [self apply:^(LDPreferences *preferences) {
    if (sender == self->_humanFormat) {
      [preferences setHumanFormat:on];
    } else if (sender == self->_fullRowSelection) {
      [preferences setListFullRowSelection:on];
    } else if (sender == self->_listGrid) {
      [preferences setListGrid:on];
    } else if (sender == self->_listStripes) {
      [preferences setListStripes:on];
    } else if (sender == self->_autoResizeColumns) {
      [preferences setAutomaticallyResizeColumns:on];
    }
  }];
}

- (void)folderListChanged:(id)sender
{
  BOOL on = [(NSButton *)sender state] == NSOnState;
  [self apply:^(LDPreferences *preferences) {
    if (sender == self->_pacman) {
      [preferences setPacmanAnimation:on];
    } else if (sender == self->_timeSpent) {
      [preferences setShowTimeSpent:on];
    }
  }];
}

- (void)setColor:(uint32_t)rgb ofWell:(NSColorWell *)well
{
  if (LDRGBFromColor([well color]) != rgb) {
    [well setColor:LDColorFromRGB(rgb)];
  }
}

- (void)levelColorChanged:(id)sender
{
  NSUInteger index = [_levelColorWells indexOfObjectIdenticalTo:sender];
  uint32_t color = LDRGBFromColor([(NSColorWell *)sender color]);
  [self apply:^(LDPreferences *preferences) {
    [preferences setFileTreeColor:color atIndex:index];
  }];
}

- (void)levelCountChanged:(id)sender
{
  NSInteger count = [sender integerValue];
  [self updateLabelForSlider:sender];
  [self apply:^(LDPreferences *preferences) {
    [preferences setFileTreeColorCount:(NSUInteger)count];
  }];
  for (NSUInteger i = 0; i < [_levelColorWells count]; i++) {
    [[_levelColorWells objectAtIndex:i] setEnabled:(NSInteger)i < count];
  }
}

- (void)columnChanged:(id)sender
{
  NSUInteger index = [_columnButtons indexOfObjectIdenticalTo:sender];
  NSArray *columns = [LDPreferences optionalColumns];
  if (index == NSNotFound || index >= [columns count]) {
    return;
  }
  BOOL on = [(NSButton *)sender state] == NSOnState;
  [self apply:^(LDPreferences *preferences) {
    [preferences setColumn:[columns objectAtIndex:index] shown:on];
  }];
}

- (void)promptsChanged:(id)sender
{
  BOOL on = [(NSButton *)sender state] == NSOnState;
  [self apply:^(LDPreferences *preferences) {
    [preferences setShowDeleteWarning:on];
  }];
}

- (void)advancedChanged:(id)sender
{
  BOOL on = [(NSButton *)sender state] == NSOnState;
  [self apply:^(LDPreferences *preferences) {
    if (sender == self->_excludeMountPoints) {
      [preferences setExcludeMountPoints:on];
    } else if (sender == self->_excludeSymlinks) {
      [preferences setExcludeSymbolicLinks:on];
    } else if (sender == self->_excludeHidden) {
      [preferences setExcludeHiddenEntries:on];
    } else if (sender == self->_processHardLinks) {
      [preferences setProcessHardLinks:on];
    } else if (sender == self->_scanDuplicates) {
      [preferences setScanForDuplicates:on];
    } else if (sender == self->_threads) {
      [preferences setScanningThreads:(NSUInteger)[self->_threads indexOfSelectedItem] + 1];
    }
  }];
}

- (void)applyCountFromField:(NSTextField *)field reformat:(BOOL)reformat
{
  NSInteger value = MAX((NSInteger)0, [field integerValue]);
  [self apply:^(LDPreferences *preferences) {
    if (field == self->_largeFileCount) {
      [preferences setLargeFileCount:(NSUInteger)value];
    } else if (field == self->_historyCount) {
      [preferences setFolderHistoryCount:(NSUInteger)value];
    }
  }];
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSUInteger stored = field == _largeFileCount ? [preferences largeFileCount] : [preferences folderHistoryCount];
  [(field == _largeFileCount ? _largeFileStepper : _historyStepper) setIntegerValue:(NSInteger)stored];
  if (reformat) {
    [self setString:[NSString stringWithFormat:@"%lu", (unsigned long)stored] ofField:field];
  }
}

- (void)countEntered:(id)sender
{
  [self applyCountFromField:sender reformat:YES];
}

- (void)countStepped:(id)sender
{
  NSTextField *field = sender == _largeFileStepper ? _largeFileCount : _historyCount;
  [field setIntegerValue:[sender integerValue]];
  [self applyCountFromField:field reformat:YES];
}

#pragma mark - Filtering

- (void)validateFilters
{
  BOOL regex = [_filterRegex state] == NSOnState;
  NSString *invalid = [LDFilterPatterns firstInvalidPatternInString:[_folderPatterns string] usesRegex:regex];
  if (!invalid) {
    invalid = [LDFilterPatterns firstInvalidPatternInString:[_filePatterns string] usesRegex:regex];
  }
  [_filterError setStringValue:invalid ? [NSString stringWithFormat:LDLocalized(@"Invalid filter: %@"), invalid] : @""];
}

- (void)textDidChange:(NSNotification *)notification
{
  NSTextView *textView = [notification object];
  NSString *text = [[textView string] copy];
  [self apply:^(LDPreferences *preferences) {
    if (textView == self->_folderPatterns) {
      [preferences setExcludedFolderPatterns:text];
    } else if (textView == self->_filePatterns) {
      [preferences setExcludedFilePatterns:text];
    }
  }];
  [self validateFilters];
}

- (void)filterRegexChanged:(id)sender
{
  BOOL on = [(NSButton *)sender state] == NSOnState;
  [self apply:^(LDPreferences *preferences) {
    [preferences setFilterUsesRegex:on];
  }];
  [self validateFilters];
}

- (void)applyMinimumSizeReformat:(BOOL)reformat
{
  long long value = MAX(0LL, [[_minimumSize stringValue] longLongValue]);
  [self apply:^(LDPreferences *preferences) {
    [preferences setMinimumFileSize:(unsigned long long)value];
  }];
  if (reformat) {
    [self setString:[NSString stringWithFormat:@"%lld", value] ofField:_minimumSize];
  }
}

- (void)minimumSizeEntered:(id)sender
{
  (void)sender;
  [self applyMinimumSizeReformat:YES];
}

- (void)minimumSizeUnitChanged:(id)sender
{
  LDSizeUnit unit = (LDSizeUnit)[sender indexOfSelectedItem];
  [self apply:^(LDPreferences *preferences) {
    [preferences setMinimumFileSizeUnit:unit];
  }];
}

#pragma mark - Treemap

- (void)updateLabelForSlider:(NSSlider *)slider
{
  NSTextField *label = [_sliderLabels objectForKey:slider];
  NSString *format = slider == _levelCount ? @"%ld" : LDLocalized(@"%ld %%");
  [label setStringValue:[NSString stringWithFormat:format, (long)[slider integerValue]]];
}

// Renders WinDirStat's demo tree with the current settings.
- (void)updateTreemapPreview
{
  NSRect bounds = [_treemapPreview bounds];
  int width = (int)NSWidth(bounds);
  int height = (int)NSHeight(bounds);
  if (width <= 0 || height <= 0) {
    return;
  }
  LDTreemapPreview *preview = [LDTreemapPreview sharedPreview];
  NSData *pixels = [preview renderRGBAWithWidth:width height:height options:[[LDPreferences sharedPreferences] treemapOptions]];
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                  pixelsWide:width
                                                                  pixelsHigh:height
                                                               bitsPerSample:8
                                                             samplesPerPixel:4
                                                                    hasAlpha:YES
                                                                    isPlanar:NO
                                                              colorSpaceName:NSDeviceRGBColorSpace
                                                                 bytesPerRow:width * 4
                                                                bitsPerPixel:32];
  memcpy([rep bitmapData], [pixels bytes], [pixels length]);
  NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
  [image addRepresentation:rep];
  [_treemapPreview setImage:image];
}

- (void)treemapColorChanged:(id)sender
{
  uint32_t color = LDRGBFromColor([(NSColorWell *)sender color]);
  [self apply:^(LDPreferences *preferences) {
    if (sender == self->_gridColor) {
      [preferences setTreemapGridColor:color];
    } else {
      [preferences setTreemapHighlightColor:color];
    }
  }];
  [self updateTreemapPreview];
}

- (void)treemapChanged:(id)sender
{
  [self apply:^(LDPreferences *preferences) {
    if (sender == self->_treemapStyle) {
      [preferences setTreemapStyle:[self->_treemapStyle indexOfSelectedItem]];
    } else if (sender == self->_treemapGrid) {
      [preferences setTreemapGrid:[(NSButton *)sender state] == NSOnState];
    }
  }];
  [self updateTreemapPreview];
}

- (void)sliderChanged:(id)sender
{
  NSInteger value = [sender integerValue];
  [self updateLabelForSlider:sender];
  [self apply:^(LDPreferences *preferences) {
    if (sender == self->_brightness) {
      [preferences setTreemapBrightness:value];
    } else if (sender == self->_cushionShading) {
      [preferences setTreemapCushionShading:value];
    } else if (sender == self->_height) {
      [preferences setTreemapHeight:value];
    } else if (sender == self->_scaleFactor) {
      [preferences setTreemapScaleFactor:value];
    } else if (sender == self->_lightX) {
      [preferences setTreemapLightSourceX:value];
    } else if (sender == self->_lightY) {
      [preferences setTreemapLightSourceY:value];
    }
  }];
  [self updateTreemapPreview];
}

- (void)resetTreemap:(id)sender
{
  (void)sender;
  [self apply:^(LDPreferences *preferences) {
    [preferences resetTreemapOptions];
  }];
  [self refreshControls];
}

#pragma mark - Cleanups

- (NSInteger)selectedCleanupIndex
{
  NSInteger row = [_cleanupTable selectedRow];
  return row >= 0 && row < (NSInteger)[_cleanups count] ? row : -1;
}

- (LDCustomCleanup *)selectedCleanup
{
  NSInteger index = [self selectedCleanupIndex];
  return index >= 0 ? [_cleanups objectAtIndex:index] : nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  (void)tableView;
  return (NSInteger)[_cleanups count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  (void)tableView;
  (void)column;
  if (row < 0 || row >= (NSInteger)[_cleanups count]) {
    return nil;
  }
  return [[_cleanups objectAtIndex:row] displayTitleForSlot:(NSUInteger)row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
  [self refreshCleanupControls];
}

- (void)refreshCleanupControls
{
  // Leave any title or command field being edited before showing another
  // slot in it.
  NSResponder *responder = [[self window] firstResponder];
  if ([responder isKindOfClass:[NSText class]] && ([(NSText *)responder delegate] == (id)_cleanupTitle ||
                                                   [(NSText *)responder delegate] == (id)_cleanupCommand)) {
    [[self window] makeFirstResponder:_cleanupTable];
  }

  NSInteger index = [self selectedCleanupIndex];
  LDCustomCleanup *cleanup = [self selectedCleanup];
  [cleanup normalize];
  [_moveUp setEnabled:index > 0];
  [_moveDown setEnabled:index >= 0 && index + 1 < (NSInteger)[_cleanups count]];

  BOOL enabled = [cleanup isEnabled];
  [_cleanupEnabled setEnabled:cleanup != nil];
  [_cleanupEnabled setState:LDState(enabled)];
  [self setString:cleanup ? [cleanup displayTitleForSlot:(NSUInteger)index] : @"" ofField:_cleanupTitle];
  [self setString:[cleanup commandLine] ?: @"" ofField:_cleanupCommand];
  [_worksForMountPoints setState:LDState([cleanup worksForMountPoints])];
  [_worksForFolders setState:LDState([cleanup worksForDirectories])];
  [_worksForFiles setState:LDState([cleanup worksForFiles])];
  [_recurse setState:LDState([cleanup recurseIntoSubdirectories])];
  [_askForConfirmation setState:LDState([cleanup askForConfirmation])];
  [_runInTerminal setState:LDState([cleanup showInTerminal])];
  [_waitForCompletion setState:LDState([cleanup waitForCompletion])];
  [_refreshPolicy selectItemAtIndex:cleanup ? [cleanup refreshPolicy] : 0];

  // PageCleanups.cpp:211-240.
  for (NSControl *control in @[_cleanupTitle, _cleanupCommand, _worksForMountPoints, _worksForFolders,
                               _worksForFiles, _askForConfirmation, _runInTerminal]) {
    [control setEnabled:enabled];
  }
  [_recurse setEnabled:enabled && ([cleanup worksForMountPoints] || [cleanup worksForDirectories])];
  [_waitForCompletion setEnabled:enabled && ![cleanup recurseIntoSubdirectories]];
  [_refreshPolicy setEnabled:enabled && [cleanup waitForCompletion]];
  // Labels follow their controls, as GTK dims an insensitive row.
  [_cleanupTitleLabel setEnabled:enabled];
  [_cleanupCommandLabel setEnabled:enabled];
  [_cleanupHint setEnabled:enabled];
  [_refreshPolicyLabel setEnabled:[_refreshPolicy isEnabled]];
}

- (void)saveCleanups
{
  NSArray *cleanups = [_cleanups copy];
  [self apply:^(LDPreferences *preferences) {
    [preferences setCustomCleanups:cleanups];
  }];
}

- (void)cleanupChanged:(id)sender
{
  LDCustomCleanup *cleanup = [self selectedCleanup];
  if (!cleanup) {
    return;
  }
  BOOL on = [(NSButton *)sender state] == NSOnState;
  if (sender == _cleanupEnabled) {
    [cleanup setEnabled:on];
  } else if (sender == _worksForMountPoints) {
    [cleanup setWorksForMountPoints:on];
  } else if (sender == _worksForFolders) {
    [cleanup setWorksForDirectories:on];
  } else if (sender == _worksForFiles) {
    [cleanup setWorksForFiles:on];
  } else if (sender == _recurse) {
    [cleanup setRecurseIntoSubdirectories:on];
  } else if (sender == _askForConfirmation) {
    [cleanup setAskForConfirmation:on];
  } else if (sender == _runInTerminal) {
    [cleanup setShowInTerminal:on];
  } else if (sender == _waitForCompletion) {
    [cleanup setWaitForCompletion:on];
  } else if (sender == _refreshPolicy) {
    [cleanup setRefreshPolicy:(LDRefreshPolicy)[_refreshPolicy indexOfSelectedItem]];
  }
  [cleanup normalize];
  [self saveCleanups];
  [self refreshCleanupControls];
}

- (void)moveCleanupBy:(NSInteger)offset
{
  NSInteger index = [self selectedCleanupIndex];
  NSInteger target = index + offset;
  if (index < 0 || target < 0 || target >= (NSInteger)[_cleanups count]) {
    return;
  }
  [_cleanups exchangeObjectAtIndex:(NSUInteger)index withObjectAtIndex:(NSUInteger)target];
  [self saveCleanups];
  [_cleanupTable reloadData];
  [_cleanupTable selectRow:target byExtendingSelection:NO];
  [self refreshCleanupControls];
}

- (void)moveCleanupUp:(id)sender
{
  (void)sender;
  [self moveCleanupBy:-1];
}

- (void)moveCleanupDown:(id)sender
{
  (void)sender;
  [self moveCleanupBy:1];
}

#pragma mark - Text fields

- (void)controlTextDidChange:(NSNotification *)notification
{
  id field = [notification object];
  if (field == _minimumSize) {
    [self applyMinimumSizeReformat:NO];
  } else if (field == _largeFileCount || field == _historyCount) {
    [self applyCountFromField:field reformat:NO];
  } else if (field == _cleanupTitle || field == _cleanupCommand) {
    NSInteger index = [self selectedCleanupIndex];
    LDCustomCleanup *cleanup = [self selectedCleanup];
    if (!cleanup) {
      return;
    }
    NSString *text = [field stringValue];
    if (field == _cleanupCommand) {
      [cleanup setCommandLine:text];
    } else {
      // A title left at, or emptied back to, the default stays "virgin" so it
      // follows the slot number.
      BOOL isDefault = [text length] == 0 || [text isEqualToString:[LDCustomCleanup defaultTitleForSlot:(NSUInteger)index]];
      [cleanup setTitle:isDefault ? @"" : text];
    }
    [self saveCleanups];
    if (field == _cleanupTitle) {
      [_cleanupTable setNeedsDisplayInRect:[_cleanupTable rectOfRow:index]];
    }
  }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  id field = [notification object];
  if (field == _cleanupTitle && [[_cleanupTitle stringValue] length] == 0) {
    NSInteger index = [self selectedCleanupIndex];
    if (index >= 0) {
      [_cleanupTitle setStringValue:[LDCustomCleanup defaultTitleForSlot:(NSUInteger)index]];
    }
  } else if (field == _minimumSize) {
    [self applyMinimumSizeReformat:YES];
  } else if (field == _largeFileCount || field == _historyCount) {
    [self applyCountFromField:field reformat:YES];
  }
}

#pragma mark - Reset All

- (void)resetAll:(id)sender
{
  (void)sender;
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:LDLocalized(@"Reset All Preferences?")];
  [alert setInformativeText:LDLocalized(@"Every setting, including filters and custom cleanups, returns to its default.")];
  [alert addButtonWithTitle:LDLocalized(@"Cancel")];
  [alert addButtonWithTitle:LDLocalized(@"Reset")];
  if ([alert runModal] != NSAlertSecondButtonReturn) {
    return;
  }
  NSInteger page = [self selectedPage];
  [self apply:^(LDPreferences *preferences) {
    [preferences resetAll];
    [preferences setLastOptionsPage:page];
  }];
  [self refreshControls];
}

@end
