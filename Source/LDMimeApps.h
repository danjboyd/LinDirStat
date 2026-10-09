#import <Foundation/Foundation.h>

@class LDDesktopEntry;

// The freedesktop.org application database for a MIME type: installed
// desktop entries (Desktop Entry Specification) and the user's and
// system's mimeapps.list files (MIME Applications Associations
// Specification 1.0.1), with shared-mime-info's type hierarchy. Used by
// LDOpenWith on Linux.
@interface LDMimeApps : NSObject
{
  NSArray *_applicationDirectories;
  NSArray *_listPaths;
  NSString *_mimeDirectory;
  NSString *_signature;
  NSMutableDictionary *_entries;
  NSMutableDictionary *_implicit;
  NSMutableDictionary *_usable;
  NSArray *_lists;
  NSDictionary *_parents;
  NSDictionary *_aliases;
}

// The XDG locations from environment (XDG_DATA_HOME, XDG_DATA_DIRS,
// XDG_CONFIG_HOME, XDG_CONFIG_DIRS, XDG_CURRENT_DESKTOP, HOME) with the
// specification's defaults.
+ (NSArray *)applicationDirectoriesForEnvironment:(NSDictionary *)environment;
+ (NSArray *)mimeappsListPathsForEnvironment:(NSDictionary *)environment;

// applicationDirectories and listPaths in precedence order, highest first;
// mimeDirectory is a shared-mime-info database (for subclasses and aliases)
// or nil.
- (id)initWithApplicationDirectories:(NSArray *)applicationDirectories
                  mimeappsListPaths:(NSArray *)listPaths
                      mimeDirectory:(NSString *)mimeDirectory;

// The files are read on first use; this rereads them if any of their
// folders changed since.
- (void)reloadIfChanged;

- (LDDesktopEntry *)entryForIdentifier:(NSString *)identifier;

// type and its ancestors, nearest first (aliases resolved; text/* types
// descend from text/plain).
- (NSArray *)typeWithAncestors:(NSString *)type;

// The default application for type (or the nearest ancestor that has one),
// or nil.
- (LDDesktopEntry *)defaultEntryForType:(NSString *)type;

// Usable applications for type and its ancestors: the default first, then
// added associations, then applications that list the type themselves, with
// removed associations left out.
- (NSArray *)entriesForType:(NSString *)type;

@end
