#import <Foundation/Foundation.h>

typedef enum {
  LDFileActionReveal = 0,
  LDFileActionOpen = 1,
  LDFileActionMoveToTrash = 2,
  LDFileActionPermanentDelete = 3
} LDFileActionType;

@interface LDFileActionPlan : NSObject
{
  LDFileActionType _actionType;
  NSString *_targetPath;
  BOOL _allowed;
  BOOL _destructive;
  BOOL _requiresConfirmation;
  NSString *_message;
}

+ (id)planWithActionType:(LDFileActionType)actionType targetPath:(NSString *)targetPath;
- (id)initWithActionType:(LDFileActionType)actionType targetPath:(NSString *)targetPath;
- (LDFileActionType)actionType;
- (NSString *)targetPath;
- (BOOL)isAllowed;
- (BOOL)isDestructive;
- (BOOL)requiresConfirmation;
- (NSString *)message;
- (NSDictionary *)snapshotDictionary;

@end
