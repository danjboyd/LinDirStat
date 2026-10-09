#import <Foundation/Foundation.h>

// Human-readable file type names for the extension list, as WinDirStat shows
// the shell's type names. On Linux they come from the freedesktop
// shared-mime-info database GNOME uses ("*.txt" -> "Plain text document");
// on macOS from Uniform Type Identifiers, as Finder shows them ("Plain Text
// Document").
@interface LDFileTypeDescriptions : NSObject
{
  NSString *_mimeDirectory;
  NSDictionary *_mimeTypesByExtension;
  NSMutableDictionary *_descriptionsByMimeType;
  NSMutableDictionary *_descriptionsByExtension;
}

+ (LDFileTypeDescriptions *)sharedDescriptions;
// directory is a shared-mime-info database; nil uses the system's type
// names (Uniform Type Identifiers on macOS, none elsewhere).
- (id)initWithMimeDirectory:(NSString *)directory;

// Lowercase extension key ("txt"); nil when unknown or "<none>".
- (NSString *)descriptionForExtensionKey:(NSString *)extensionKey;

@end
