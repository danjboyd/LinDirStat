#import <Foundation/Foundation.h>

// Human-readable file type names for the extension list, as WinDirStat shows
// the shell's type names. On Linux they come from the freedesktop
// shared-mime-info database GNOME uses ("*.txt" -> "Plain text document").
@interface LDFileTypeDescriptions : NSObject
{
  NSString *_mimeDirectory;
  NSDictionary *_mimeTypesByExtension;
  NSMutableDictionary *_descriptionsByMimeType;
}

+ (LDFileTypeDescriptions *)sharedDescriptions;
- (id)initWithMimeDirectory:(NSString *)directory;

// Lowercase extension key ("txt"); nil when unknown or "<none>".
- (NSString *)descriptionForExtensionKey:(NSString *)extensionKey;

@end
