#import <Foundation/Foundation.h>

/// Catches Objective-C NSExceptions that Swift's do/catch cannot handle.
@interface ObjCExceptionCatcher : NSObject
+ (void)tryBlock:(void(^)(void))tryBlock catchBlock:(void(^)(NSException *))catchBlock;
@end
