#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (void)tryBlock:(void(^)(void))tryBlock catchBlock:(void(^)(NSException *))catchBlock {
    @try {
        tryBlock();
    } @catch (NSException *exception) {
        catchBlock(exception);
    }
}

@end
