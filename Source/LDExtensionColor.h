#import <AppKit/AppKit.h>

@interface LDExtensionColor : NSObject

+ (NSColor *)colorForExtensionKey:(NSString *)extensionKey;
+ (NSUInteger)paletteIndexForExtensionKey:(NSString *)extensionKey;

@end
