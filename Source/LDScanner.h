#import <Foundation/Foundation.h>

@class LDFileNode;
@class LDScanSession;

@interface LDScanner : NSObject
{
  NSMutableSet *_visitedHardLinks;
  NSMutableSet *_visitedDirectories;
}

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session;

@end
