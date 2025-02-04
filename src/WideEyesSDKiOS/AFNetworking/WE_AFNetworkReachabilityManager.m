// WE_AFNetworkReachabilityManager.m
//
// Copyright (c) 2013-2015 WE_AFNetworking (http://afnetworking.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "WE_AFNetworkReachabilityManager.h"

#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

NSString * const WE_AFNetworkingReachabilityDidChangeNotification = @"com.alamofire.networking.reachability.change";
NSString * const WE_AFNetworkingReachabilityNotificationStatusItem = @"WE_AFNetworkingReachabilityNotificationStatusItem";

typedef void (^WE_AFNetworkReachabilityStatusBlock)(WE_AFNetworkReachabilityStatus status);

typedef NS_ENUM(NSUInteger, WE_AFNetworkReachabilityAssociation) {
    WE_AFNetworkReachabilityForAddress = 1,
    WE_AFNetworkReachabilityForAddressPair = 2,
    WE_AFNetworkReachabilityForName = 3,
};

NSString * WE_AFStringFromNetworkReachabilityStatus(WE_AFNetworkReachabilityStatus status) {
    switch (status) {
        case WE_AFNetworkReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"WE_AFNetworking", nil);
        case WE_AFNetworkReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"WE_AFNetworking", nil);
        case WE_AFNetworkReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"WE_AFNetworking", nil);
        case WE_AFNetworkReachabilityStatusUnknown:
        default:
            return NSLocalizedStringFromTable(@"Unknown", @"WE_AFNetworking", nil);
    }
}

static WE_AFNetworkReachabilityStatus WE_AFNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));

    WE_AFNetworkReachabilityStatus status = WE_AFNetworkReachabilityStatusUnknown;
    if (isNetworkReachable == NO) {
        status = WE_AFNetworkReachabilityStatusNotReachable;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        status = WE_AFNetworkReachabilityStatusReachableViaWWAN;
    }
#endif
    else {
        status = WE_AFNetworkReachabilityStatusReachableViaWiFi;
    }

    return status;
}

static void WE_AFNetworkReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkReachabilityFlags flags, void *info) {
    WE_AFNetworkReachabilityStatus status = WE_AFNetworkReachabilityStatusForFlags(flags);
    WE_AFNetworkReachabilityStatusBlock block = (__bridge WE_AFNetworkReachabilityStatusBlock)info;
    if (block) {
        block(status);
    }


    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSDictionary *userInfo = @{ WE_AFNetworkingReachabilityNotificationStatusItem: @(status) };
        [notificationCenter postNotificationName:WE_AFNetworkingReachabilityDidChangeNotification object:nil userInfo:userInfo];
    });

}

static const void * WE_AFNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}

static void WE_AFNetworkReachabilityReleaseCallback(const void *info) {
    if (info) {
        Block_release(info);
    }
}

@interface WE_AFNetworkReachabilityManager ()
@property (readwrite, nonatomic, assign) SCNetworkReachabilityRef networkReachability;
@property (readwrite, nonatomic, assign) WE_AFNetworkReachabilityAssociation networkReachabilityAssociation;
@property (readwrite, nonatomic, assign) WE_AFNetworkReachabilityStatus networkReachabilityStatus;
@property (readwrite, nonatomic, copy) WE_AFNetworkReachabilityStatusBlock networkReachabilityStatusBlock;
@end

@implementation WE_AFNetworkReachabilityManager

+ (instancetype)sharedManager {
    static WE_AFNetworkReachabilityManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct sockaddr_in address;
        bzero(&address, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;

        _sharedManager = [self managerForAddress:&address];
    });

    return _sharedManager;
}

+ (instancetype)managerForDomain:(NSString *)domain {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);

    WE_AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    manager.networkReachabilityAssociation = WE_AFNetworkReachabilityForName;

    return manager;
}

+ (instancetype)managerForAddress:(const void *)address {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);

    WE_AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    manager.networkReachabilityAssociation = WE_AFNetworkReachabilityForAddress;

    return manager;
}

- (instancetype)initWithReachability:(SCNetworkReachabilityRef)reachability {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.networkReachability = reachability;
    self.networkReachabilityStatus = WE_AFNetworkReachabilityStatusUnknown;

    return self;
}

- (void)dealloc {
    [self stopMonitoring];

    if (_networkReachability) {
        CFRelease(_networkReachability);
        _networkReachability = NULL;
    }
}

#pragma mark -

- (BOOL)isReachable {
    return [self isReachableViaWWAN] || [self isReachableViaWiFi];
}

- (BOOL)isReachableViaWWAN {
    return self.networkReachabilityStatus == WE_AFNetworkReachabilityStatusReachableViaWWAN;
}

- (BOOL)isReachableViaWiFi {
    return self.networkReachabilityStatus == WE_AFNetworkReachabilityStatusReachableViaWiFi;
}

#pragma mark -

- (void)startMonitoring {
    [self stopMonitoring];

    if (!self.networkReachability) {
        return;
    }

    __weak __typeof(self)weakSelf = self;
    WE_AFNetworkReachabilityStatusBlock callback = ^(WE_AFNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;

        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }

    };

    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, WE_AFNetworkReachabilityRetainCallback, WE_AFNetworkReachabilityReleaseCallback, NULL};
    SCNetworkReachabilitySetCallback(self.networkReachability, WE_AFNetworkReachabilityCallback, &context);
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);

    switch (self.networkReachabilityAssociation) {
        case WE_AFNetworkReachabilityForName:
            break;
        case WE_AFNetworkReachabilityForAddress:
        case WE_AFNetworkReachabilityForAddressPair:
        default: {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
                SCNetworkReachabilityFlags flags;
                SCNetworkReachabilityGetFlags(self.networkReachability, &flags);
                WE_AFNetworkReachabilityStatus status = WE_AFNetworkReachabilityStatusForFlags(flags);
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback(status);

                    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
                    [notificationCenter postNotificationName:WE_AFNetworkingReachabilityDidChangeNotification object:nil userInfo:@{ WE_AFNetworkingReachabilityNotificationStatusItem: @(status) }];


                });
            });
        }
            break;
    }
}

- (void)stopMonitoring {
    if (!self.networkReachability) {
        return;
    }

    SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

#pragma mark -

- (NSString *)localizedNetworkReachabilityStatusString {
    return WE_AFStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}

#pragma mark -

- (void)setReachabilityStatusChangeBlock:(void (^)(WE_AFNetworkReachabilityStatus status))block {
    self.networkReachabilityStatusBlock = block;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }

    return [super keyPathsForValuesAffectingValueForKey:key];
}

@end
