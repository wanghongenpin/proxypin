//
//  GBPingSummary.m
//  GBPing
//
//  Created by Luka Mirosevic on 05/11/2012.
//  Copyright (c) 2012 Goonbee. All rights reserved.
//

#import "GBPingSummary.h"

@implementation GBPingSummary

#pragma mark - custom acc

-(void)setHost:(NSString *)host {
    _host = host;
}

-(NSTimeInterval)rtt {
    if (self.sendDate) {
        return [self.receiveDate timeIntervalSinceDate:self.sendDate];
    }
    else {
        return 0;
    }
}

#pragma mark - copying

-(id)copyWithZone:(NSZone *)zone {
    GBPingSummary *copy = [[[self class] allocWithZone:zone] init];
    
    copy.sequenceNumber = self.sequenceNumber;
    copy.payloadSize = self.payloadSize;
    copy.ttl = self.ttl;
    copy.host = [self.host copy];
    copy.ip = [self.ip copy];
    copy.sendDate = [self.sendDate copy];
    copy.receiveDate = [self.receiveDate copy];
    copy.status = self.status;
    
    return copy;
}

#pragma mark - memory

-(id)init {
    if (self = [super init]) {
        self.status = GBPingStatusPending;
    }
    
    return self;
}

-(void)dealloc {
    self.host = nil;
    self.ip = nil;
    self.sendDate = nil;
    self.receiveDate = nil;
}

#pragma mark - description

-(NSString *)description {
    return [NSString stringWithFormat:@"host: %@, ip:%@, seq: %lu, status: %d, ttl: %lu, payloadSize: %lu, sendDate: %@, receiveDate: %@, rtt: %f", self.host, self.ip, (unsigned long)self.sequenceNumber, self.status, (unsigned long)self.ttl, (unsigned long)self.payloadSize, self.sendDate, self.receiveDate, self.rtt];
}

@end
