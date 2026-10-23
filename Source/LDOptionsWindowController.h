#import <AppKit/AppKit.h>

// The pages of the Preferences window, in WinDirStat's order
// (MainFrame.cpp:1396-1424). The values are stored as ConfigPage.
typedef enum {
  LDOptionsPageGeneral = 0,
  LDOptionsPageFiltering = 1,
  LDOptionsPageFolderList = 2,
  LDOptionsPageTreemap = 3,
  LDOptionsPageCleanups = 4,
  LDOptionsPagePrompts = 5,
  LDOptionsPageAdvanced = 6
} LDOptionsPage;

// Posted when the Filtering page's settings changed and the user left the
// page or closed the window (WinDirStat 2.6 refreshes everything when its
// filtering settings change, 5e3dcd0e). Only valid filters are announced.
FOUNDATION_EXPORT NSString *const LDOptionsFiltersDidChangeNotification;

// WinDirStat's Options dialog as a non-modal GNOME-style "Preferences"
// window. Every change is written straight to LDPreferences, which posts
// LDPreferencesDidChangeNotification; the window also follows changes made
// elsewhere.
@interface LDOptionsWindowController : NSWindowController <NSTabViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate>

+ (LDOptionsWindowController *)sharedController;

// -showWindow: opens on the page last shown (LDPreferences -lastOptionsPage).
- (void)showPage:(LDOptionsPage)page;
- (LDOptionsPage)selectedPage;

// Reloads every control from LDPreferences.
- (void)refreshControls;

@end
