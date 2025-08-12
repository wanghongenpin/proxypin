//
//  GBPing.h
//  GBPing
//
//  Created by Luka Mirosevic on 05/11/2012.
//  Copyright (c) 2012 Goonbee. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "GBPingSummary.h"

@class GBPingSummary;
@protocol GBPingDelegate;

NS_ASSUME_NONNULL_BEGIN

typedef void(^StartupCallback)(BOOL success, NSError * _Nullable error);

@interface GBPing : NSObject

@property (weak, nonatomic, nullable) id<GBPingDelegate>      delegate;

@property (copy, nonatomic, nullable) NSString                *host;
@property (assign, atomic) NSTimeInterval           pingPeriod;
@property (assign, atomic) NSTimeInterval           timeout;
@property (assign, atomic) NSUInteger               payloadSize;
@property (assign, atomic) NSUInteger               ttl;
@property (assign, atomic) NSUInteger               count;
@property (assign, atomic, readonly) BOOL           isPinging;
@property (assign, atomic, readonly) BOOL           isReady;
@property (assign, atomic) BOOL                     useIpv4;
@property (assign, atomic) BOOL                     useIpv6;

@property (assign, atomic) BOOL                     debug;

-(void)setupWithBlock:(StartupCallback)callback;
-(void)startPinging;
-(void)stop;

@end

@protocol GBPingDelegate <NSObject>

@optional

-(void)ping:(GBPing *)pinger didFinishWithTime:(NSTimeInterval)time;
-(void)ping:(GBPing *)pinger didFailWithError:(NSError *)error;

-(void)ping:(GBPing *)pinger didSendPingWithSummary:(GBPingSummary *)summary;
-(void)ping:(GBPing *)pinger didFailToSendPingWithSummary:(GBPingSummary *)summary error:(NSError *)error;
-(void)ping:(GBPing *)pinger didTimeoutWithSummary:(GBPingSummary *)summary;
-(void)ping:(GBPing *)pinger didReceiveReplyWithSummary:(GBPingSummary *)summary;
-(void)ping:(GBPing *)pinger didReceiveUnexpectedReplyWithSummary:(GBPingSummary *)summary;

@end

NS_ASSUME_NONNULL_END
