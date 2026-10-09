#import "LDTabCycle.h"

@implementation LDTabCycle

+ (NSInteger)nextFocusFrom:(NSInteger)current
               visibleTabs:(NSUInteger)tabCount
     extensionListVisible:(BOOL)extensionListVisible
                   forward:(BOOL)forward
{
  NSInteger last = (NSInteger)tabCount - 1;
  if (tabCount == 0) {
    return extensionListVisible ? LDFocusExtensionList : LDFocusOther;
  }
  if (current == LDFocusOther || current > last) {
    return 0;
  }
  if (current == LDFocusExtensionList) {
    return forward ? 0 : last;
  }
  NSInteger next = current + (forward ? 1 : -1);
  if (next >= 0 && next <= last) {
    return next;
  }
  if (extensionListVisible) {
    return LDFocusExtensionList;
  }
  return forward ? 0 : last;
}

@end
