﻿// Header generated by RemObjects Elements for Cocoa 

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#import <objc/NSObject.h>
#import <Foundation/Foundation.h>

#define _Nonnull
#define Int int
@class MiaClasse2;

@interface MiaClasse2: NSObject

- (_Nonnull Int)add:(_Nonnull Int)a b:(_Nonnull Int)b;
- (_Nonnull Int)diff:(_Nonnull Int)a b:(_Nonnull Int)b;
- (void)httpCall:(_Nonnull /* mapped */ NSString *)url completion:(void (^)(/* mapped */ NSString * ))completion;

@end
