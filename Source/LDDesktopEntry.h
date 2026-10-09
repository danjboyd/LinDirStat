#import <Foundation/Foundation.h>

// A freedesktop.org desktop entry (Desktop Entry Specification 1.5): the
// [Desktop Entry] group of an application's .desktop file, and its Exec
// line turned into commands for LDDesktop. Used by LDOpenWith on Linux.
@interface LDDesktopEntry : NSObject
{
  NSString *_identifier;
  NSString *_filePath;
  NSDictionary *_values;
}

// identifier is the desktop file ID ("org.gnome.TextEditor.desktop").
+ (LDDesktopEntry *)entryWithContentsOfFile:(NSString *)path identifier:(NSString *)identifier;
+ (LDDesktopEntry *)entryWithString:(NSString *)text filePath:(NSString *)path identifier:(NSString *)identifier;

- (NSString *)identifier;
- (NSString *)filePath;
// The value of key in [Desktop Entry] with \s \n \t \r \\ unescaped
// (unlocalized), or nil.
- (NSString *)stringForKey:(NSString *)key;
- (BOOL)booleanForKey:(NSString *)key;

- (NSString *)name;
- (NSString *)iconName;
- (NSString *)exec;
- (NSArray *)mimeTypes;
- (BOOL)isApplication;
- (BOOL)isHidden;
- (BOOL)runsInTerminal;
// Exec has a file or URL field code (%f %F %u %U).
- (BOOL)acceptsFiles;
// An application that is not hidden, accepts files, and whose TryExec and
// Exec programs are installed.
- (BOOL)isUsableForOpening;

// Exec split into arguments by the specification's quoting rules (double
// quotes; \" \` \$ \\ escaped inside them); nil when malformed.
+ (NSArray *)argumentsForExec:(NSString *)exec;

// The commands that open paths (exact bytes): one per path for %f and %u,
// one for all of them for %F and %U. %u and %U become file:// URIs, %i the
// icon, %c the name, %k this file, %% a percent sign; deprecated codes are
// dropped. Each command is an argument array for LDDesktop (NSString, or
// NSData where a path is inserted). Empty when Exec is malformed.
- (NSArray *)commandsForPaths:(NSArray *)paths;

@end
