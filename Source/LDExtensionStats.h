#import <Foundation/Foundation.h>

@interface LDExtensionStats : NSObject
{
  NSString *_extensionKey;
  NSString *_displayName;
  unsigned long long _bytes;
  NSUInteger _fileCount;
}

+ (NSString *)extensionKeyForFilename:(NSString *)filename;
+ (NSArray *)sortedStatsForRootNode:(id)rootNode;
- (id)initWithExtensionKey:(NSString *)extensionKey;
- (NSString *)extensionKey;
- (NSString *)displayName;
- (unsigned long long)bytes;
- (NSUInteger)fileCount;
- (double)percentageOfTotal:(unsigned long long)totalBytes;
- (void)addBytes:(unsigned long long)bytes;

@end
