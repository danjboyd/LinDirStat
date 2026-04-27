#import "LDFileActions.h"
#import "LDFileActionPlan.h"

@implementation LDFileActions

+ (LDFileActionPlan *)revealPlanForPath:(NSString *)path
{
  return [LDFileActionPlan planWithActionType:LDFileActionReveal targetPath:path];
}

+ (LDFileActionPlan *)openPlanForPath:(NSString *)path
{
  return [LDFileActionPlan planWithActionType:LDFileActionOpen targetPath:path];
}

+ (LDFileActionPlan *)trashPlanForPath:(NSString *)path
{
  return [LDFileActionPlan planWithActionType:LDFileActionMoveToTrash targetPath:path];
}

+ (LDFileActionPlan *)permanentDeletePlanForPath:(NSString *)path
{
  return [LDFileActionPlan planWithActionType:LDFileActionPermanentDelete targetPath:path];
}

@end
