#import <Foundation/Foundation.h>

@class LDFileActionPlan;

@interface LDFileActions : NSObject

+ (LDFileActionPlan *)revealPlanForPath:(NSString *)path;
+ (LDFileActionPlan *)openPlanForPath:(NSString *)path;
+ (LDFileActionPlan *)trashPlanForPath:(NSString *)path;
+ (LDFileActionPlan *)permanentDeletePlanForPath:(NSString *)path;

@end
