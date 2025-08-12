//
//  GBPing.m
//  GBPing
//
//  Created by Luka Mirosevic on 05/11/2012.
//  Copyright (c) 2012 Goonbee. All rights reserved.
//

#import "GBPing.h"

#if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
    #import <CFNetwork/CFNetwork.h>
#else
    #import <CoreServices/CoreServices.h>
#endif

#import "ICMPHeader.h"

#include <sys/socket.h>
#include <netinet/in.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <netdb.h>

static NSTimeInterval const kPendingPingsCleanupGrace = 1.0;

static NSUInteger const kDefaultPayloadSize =           56;
static NSUInteger const kDefaultTTL =                   49;
static NSTimeInterval const kDefaultPingPeriod =        1.0;
static NSTimeInterval const kDefaultTimeout =           2.0;

@interface GBPing ()

@property (assign, atomic) int                          socket;
@property (strong, nonatomic) NSData                    *hostAddress;
@property (strong, nonatomic) NSString                  *hostAddressString;
@property (assign, nonatomic) uint16_t                  identifier;
@property (assign, nonatomic) NSUInteger                counter;

@property (assign, atomic, readwrite) BOOL              isPinging;
@property (assign, atomic, readwrite) BOOL              isReady;
@property (assign, nonatomic) NSUInteger                nextSequenceNumber;
@property (strong, atomic) NSMutableDictionary          *pendingPings;
@property (strong, nonatomic) NSMutableDictionary       *timeoutTimers;

@property (strong, nonatomic) dispatch_queue_t          setupQueue;

@property (assign, atomic) BOOL                         isStopped;

@end

@implementation GBPing {
    NSUInteger                                          _payloadSize;
    NSUInteger                                          _ttl;
    NSUInteger                                          _count;
    NSTimeInterval                                      _timeout;
    NSTimeInterval                                      _pingPeriod;
    NSTimeInterval                                      _endTime;
}

#pragma mark - custom acc

-(void)setTimeout:(NSTimeInterval)timeout {
    @synchronized(self) {
        if (self.isPinging) {
            if (self.debug) {
                NSLog(@"GBPing: can't set timeout while pinger is running.");
            }
        }
        else {
            _timeout = timeout;
        }
    }
}

-(NSTimeInterval)timeout {
    @synchronized(self) {
        if (!_timeout) {
            return kDefaultTimeout;
        }
        else {
            return _timeout;
        }
    }
}

-(void)setTtl:(NSUInteger)ttl {
    @synchronized(self) {
        if (self.isPinging) {
            if (self.debug) {
                NSLog(@"GBPing: can't set ttl while pinger is running.");
            }
        }
        else {
            _ttl = ttl;
        }
    }
}

-(NSUInteger)ttl {
    @synchronized(self) {
        if (!_ttl) {
            return kDefaultTTL;
        }
        else {
            return _ttl;
        }
    }
}

-(void)setCount:(NSUInteger)count {
    @synchronized(self) {
        if (self.isPinging) {
            if (self.debug) {
                NSLog(@"GBPing: can't set count while pinger is running.");
            }
        }
        else {
            _count = count;
        }
    }
}

-(NSUInteger)count {
    @synchronized(self) {
        if (!_count) {
            return 0;
        }
        else {
            return _count;
        }
    }
}

-(void)setPayloadSize:(NSUInteger)payloadSize {
    @synchronized(self) {
        if (self.isPinging) {
            if (self.debug) {
                NSLog(@"GBPing: can't set payload size while pinger is running.");
            }
        }
        else {
            _payloadSize = payloadSize;
        }
    }
}

-(NSUInteger)payloadSize {
    @synchronized(self) {
        if (!_payloadSize) {
            return kDefaultPayloadSize;
        }
        else {
            return _payloadSize;
        }
    }
}

-(void)setPingPeriod:(NSTimeInterval)pingPeriod {
    @synchronized(self) {
        if (self.isPinging) {
            if (self.debug) {
                NSLog(@"GBPing: can't set pingPeriod while pinger is running.");
            }
        }
        else {
            _pingPeriod = pingPeriod;
        }
    }
}

-(NSTimeInterval)pingPeriod {
    @synchronized(self) {
        if (!_pingPeriod) {
            return (NSTimeInterval)kDefaultPingPeriod;
        }
        else {
            return _pingPeriod;
        }
    }
}

#pragma mark - core pinging methods

-(void)setupWithBlock:(StartupCallback)callback {
    //error out of its already setup
    if (self.isReady) {
        if (self.debug) {
            NSLog(@"GBPing: Can't setup, already setup.");
        }
        
        //notify about error and return
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(NO, nil);
        });
        return;
    }
    
    //error out if no host is set
    if (!self.host) {
        if (self.debug) {
            NSLog(@"GBPing: set host before attempting to start.");
        }
        
        //notify about error and return
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(NO, nil);
        });
        return;
    }
    
    //set up data structs
    self.nextSequenceNumber = 0;
    @synchronized (self) {
        self.pendingPings = [[NSMutableDictionary alloc] init];
        self.timeoutTimers = [[NSMutableDictionary alloc] init];
    }
    
    dispatch_async(self.setupQueue, ^{
        CFStreamError streamError;
        BOOL success;
        
        CFHostRef hostRef = CFHostCreateWithName(NULL, (__bridge CFStringRef)self.host);
        
        /*
         * CFHostCreateWithName will return a null result in certain cases.
         * CFHostStartInfoResolution will return YES if _hostRef is null.
         */
        if (hostRef) {
            success = CFHostStartInfoResolution(hostRef, kCFHostAddresses, &streamError);
        } else {
            success = NO;
        }
        
        if (!success) {
            //construct an error
            NSDictionary *userInfo;
            NSError *error;
            
            if (hostRef && streamError.domain == kCFStreamErrorDomainNetDB) {
                userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithInteger:streamError.error], kCFGetAddrInfoFailureKey,
                            nil
                            ];
            }
            else {
                userInfo = nil;
            }
            error = [NSError errorWithDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFHostErrorUnknown userInfo:userInfo];
            
            //clean up so far
            [self stop];
            
            //notify about error and return
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(NO, error);
            });
          
            //just incase
            if (hostRef) {
              CFRelease(hostRef);
            }
            return;
        }
        
        //get the first IPv4 or IPv6 address
        Boolean resolved;
        NSArray *addresses = (__bridge NSArray *)CFHostGetAddressing(hostRef, &resolved);
        if (resolved && (addresses != nil)) {
            resolved = false;
            for (NSData *address in addresses) {
                const struct sockaddr *anAddrPtr = (const struct sockaddr *)[address bytes];
                
                if ([address length] >= sizeof(struct sockaddr) &&
                    ((self.useIpv4 && anAddrPtr->sa_family == AF_INET) ||
                     (self.useIpv6 && anAddrPtr->sa_family == AF_INET6)) ) {
                    resolved = true;
                    self.hostAddress = address;
                    self.hostAddressString = [self ntop:(struct sockaddr *)anAddrPtr len:(socklen_t)address.length];
                    break;
                }
            }
        }
        
        //we can stop host resolution now
        if (hostRef) {
            CFRelease(hostRef);
        }
        
        //if an error occurred during resolution
        if (!resolved) {
            //stop
            [self stop];
            
            //notify about error and return
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(NO, [NSError errorWithDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFHostErrorHostNotFound userInfo:nil]);
            });
            return;
        }
        
        //set up socket
        int err = 0;
        switch (self.hostAddressFamily) {
            case AF_INET: {
                self.socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
                if (self.socket < 0) {
                    err = errno;
                }
            } break;
            case AF_INET6: {
                self.socket = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6);
                if (self.socket < 0) {
                    err = errno;
                }
            } break;
            default: {
                err = EPROTONOSUPPORT;
            } break;
        }
        
        //couldnt setup socket
        if (err) {
            //clean up so far
            [self stop];
            
            //notify about error and close
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(NO, [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]);
            });
            return;
        }
        
        //set ttl on the socket
        if (self.ttl) {
            u_char ttlForSockOpt = (u_char)self.ttl;
            setsockopt(self.socket, IPPROTO_IP, IP_TTL, &ttlForSockOpt, sizeof(NSUInteger));
        }
        
        //we are ready now
        self.isReady = YES;
        
        //notify that we are ready
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(YES, nil);
        });
    });
    
    self.isStopped = NO;
}


-(void)startPinging {
    if (self.isReady && !self.isPinging) {
        //go into infinite listenloop on a new thread (listenThread)
        NSThread *listenThread = [[NSThread alloc] initWithTarget:self selector:@selector(listenLoop) object:nil];
        listenThread.name = @"listenThread";
        
        //set up loop that sends packets on a new thread (sendThread)
        NSThread *sendThread = [[NSThread alloc] initWithTarget:self selector:@selector(sendLoop) object:nil];
        sendThread.name = @"sendThread";
        
        //we're pinging now
        self.isPinging = YES;
        [listenThread start];
        [sendThread start];
    }
}

-(void)listenLoop {
    @autoreleasepool {
        while (self.isPinging) {
            [self listenOnce];
        }
    }
}

-(void)listenOnce {
    int                     err;
    struct sockaddr_storage addr;
    socklen_t               addrLen;
    ssize_t                 bytesRead;
    void *                  buffer;
    enum { kBufferSize = 65535 };
    
    buffer = malloc(kBufferSize);

    if (buffer == nil) {
        err = errno;
        return;
    }
    
    //read the data.
    addrLen = sizeof(addr);
    bytesRead = recvfrom(self.socket, buffer, kBufferSize, 0, (struct sockaddr *)&addr, &addrLen);
    err = 0;
    if (bytesRead < 0) {
        err = errno;
    }

    //process the data we read.
    if (bytesRead > 0) {
        _endTime = CFAbsoluteTimeGetCurrent();
        struct sockaddr_in *sin = (struct sockaddr_in *)&addr;
        NSString *host = [self ntop:(struct sockaddr *)&addr len:addrLen];

        if([host isEqualToString:self.hostAddressString]) { // only make sense where received packet comes from expected source
            NSDate *receiveDate = [NSDate date];
            NSMutableData *packet;

            packet = [NSMutableData dataWithBytes:buffer length:(NSUInteger) bytesRead];

            if (packet == nil) {
                err = errno;
                return;
            }

            //complete the ping summary
            const struct ICMPHeader *headerPointer;
            
            if (sin->sin_family == AF_INET) {
                headerPointer = [[self class] icmp4InPacket:packet];
            } else {
                headerPointer = (const struct ICMPHeader *)[packet bytes];
            }
            
            NSUInteger seqNo = (NSUInteger)OSSwapBigToHostInt16(headerPointer->sequenceNumber);
            NSNumber *key = @(seqNo);
            GBPingSummary *pingSummary;
            @synchronized (self) {
                pingSummary = [(GBPingSummary *)self.pendingPings[key] copy];
            }

            if (pingSummary) {
                if ([self isValidPingResponsePacket:packet]) {
                    pingSummary.receiveDate = receiveDate;
                    if (sin->sin_family == AF_INET) {
                        //set ttl from response (different servers may respond with different ttls)
                        const struct IPHeader *ipPtr;
                        if ([packet length] >= sizeof(IPHeader)) {
                            ipPtr = (const IPHeader *)[packet bytes];
                             pingSummary.ttl = ipPtr->timeToLive;
                        }
                    }

                    pingSummary.status = GBPingStatusSuccess;

                    //invalidate the timeouttimer
                    @synchronized (self) {
                        NSTimer *timer = self.timeoutTimers[key];
                        [timer invalidate];
                        [self.timeoutTimers removeObjectForKey:key];
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        //notify delegate
                        if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didReceiveReplyWithSummary:)] ) {
                            [self.delegate ping:self didReceiveReplyWithSummary:[pingSummary copy]];
                        }
                    });
                }
                else {
                    pingSummary.status = GBPingStatusFail;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didReceiveUnexpectedReplyWithSummary:)] ) {
                            [self.delegate ping:self didReceiveUnexpectedReplyWithSummary:[pingSummary copy]];
                        }
                    });
                }
            }
        }
    }
    else {

        //we failed to read the data, so shut everything down.
        if (err == 0) {
            err = EPIPE;
        }
        
        @synchronized(self) {
            if (!self.isStopped) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didFailWithError:)] ) {
                        [self.delegate ping:self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]];
                    }
                });
            }
        }
        
        //stop the whole thing
        [self stop];
    }
    
    free(buffer);
}

-(void)sendLoop {
    @autoreleasepool {
        self.counter = _count;
        BOOL stopping = NO;
        NSTimeInterval startTime = CFAbsoluteTimeGetCurrent();
        _endTime = 0;
        while (self.isPinging) {
            [self sendPing];
          
            if (_count > 0) {
                self.counter -= 1;
                if (self.counter == 0) {
                    stopping = YES;
                }
            }

            NSTimeInterval runUntil = CFAbsoluteTimeGetCurrent() + (stopping ? self.timeout : self.pingPeriod);
            NSTimeInterval time = 0;
            while (runUntil > time) {
                NSDate *runUntilDate = [NSDate dateWithTimeIntervalSinceReferenceDate:runUntil];
                [[NSRunLoop currentRunLoop] runUntilDate:runUntilDate];
        
                time = CFAbsoluteTimeGetCurrent();
            }
            if (stopping) {
              break;
            }
        }
        [self stop];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didFinishWithTime:)] ) {
                NSTimeInterval interval = 0;
                if (self->_endTime > 0) {
                    interval = self->_endTime - startTime;
                }
                [self.delegate ping:self didFinishWithTime:interval];
            }
        });
    }
}

-(void)sendPing {
    if (self.isPinging) {
      
        int err;
        NSData *packet;
        ssize_t bytesSent;
        
        // Construct the ping packet.
        NSData *payload = [self generateDataWithLength:(self.payloadSize)];
        
        switch (self.hostAddressFamily) {
            case AF_INET: {
                packet = [self pingPacketWithType:kICMPv4TypeEchoRequest payload:payload requiresChecksum:YES];
            } break;
            case AF_INET6: {
                packet = [self pingPacketWithType:kICMPv6TypeEchoRequest payload:payload requiresChecksum:NO];
            } break;
            default: {
                err = errno;
                return;
            } break;
        }
        
        // this is our ping summary
        GBPingSummary *newPingSummary = [GBPingSummary new];
        
        // Send the packet.
        if (self.socket == 0) {
            bytesSent = -1;
            err = EBADF;
        }
        else {
            
            //record the send date
            NSDate *sendDate = [NSDate date];
            
            //construct ping summary, as much as it can
            newPingSummary.sequenceNumber = self.nextSequenceNumber;
            newPingSummary.host = self.host;
            newPingSummary.ip = self.hostAddressString;
            newPingSummary.sendDate = sendDate;
            newPingSummary.ttl = self.ttl;
            newPingSummary.payloadSize = self.payloadSize;
            newPingSummary.status = GBPingStatusPending;
            
            //add it to pending pings
            NSNumber *key = @(self.nextSequenceNumber);
            @synchronized (self) {
                self.pendingPings[key] = newPingSummary;
            }
            
            //increment sequence number
            self.nextSequenceNumber += 1;
            
            //we create a copy, this one will be passed out to other threads
            GBPingSummary *pingSummaryCopy = [newPingSummary copy];
            
            //we need to clean up our list of pending pings, and we do that after the timeout has elapsed (+ some grace period)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.timeout + kPendingPingsCleanupGrace) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                //remove the ping from the pending list
                @synchronized (self) {
                    [self.pendingPings removeObjectForKey:key];
                }
            });
            
            //add a timeout timer
            //add a timeout timer
            NSTimer *timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.timeout
                                                                     target:[NSBlockOperation blockOperationWithBlock:^{

                                                                         newPingSummary.status = GBPingStatusFail;
                                                                         self->_endTime = CFAbsoluteTimeGetCurrent();

                                                                         //notify about the failure
                                                                         dispatch_async(dispatch_get_main_queue(), ^{
                                                                             if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didTimeoutWithSummary:)]) {
                                                                                 [self.delegate ping:self didTimeoutWithSummary:pingSummaryCopy];
                                                                             }
                                                                         });

                                                                         //remove the timer itself from the timers list
                                                                         //lm make sure that the timer list doesnt grow and these removals actually work... try logging the count of the timeoutTimers when stopping the pinger
                                                                         @synchronized (self) {
                                                                             [self.timeoutTimers removeObjectForKey:key];
                                                                         }
                                                                     }]
                                                                   selector:@selector(main)
                                                                   userInfo:nil
                                                                    repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:timeoutTimer forMode:NSRunLoopCommonModes];
            
            //keep a local ref to it
            if (self.timeoutTimers) {
                @synchronized (self) {
                    self.timeoutTimers[key] = timeoutTimer;
                }
            }
            
            //notify delegate about this
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didSendPingWithSummary:)]) {
                    [self.delegate ping:self didSendPingWithSummary:pingSummaryCopy];
                }
            });
            
            bytesSent = sendto(
                               self.socket,
                               [packet bytes],
                               [packet length],
                               0,
                               (struct sockaddr *) [self.hostAddress bytes],
                               (socklen_t) [self.hostAddress length]
                               );
            err = 0;
            if (bytesSent < 0) {
                err = errno;
            }
        }
        
        // This is after the sending
        
        //successfully sent
        if ((bytesSent > 0) && (((NSUInteger) bytesSent) == [packet length])) {
            //noop, we already notified delegate about sending of the ping
        }
        //failed to send
        else {
            //complete the error
            if (err == 0) {
                err = ENOBUFS;          // This is not a hugely descriptor error, alas.
            }
            
            //little log
            if (self.debug) {
                NSLog(@"GBPing: failed to send packet with error code: %d", err);
            }
            
            //change status
            newPingSummary.status = GBPingStatusFail;
            
            GBPingSummary *pingSummaryCopyAfterFailure = [newPingSummary copy];
            
            //notify delegate
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.delegate && [self.delegate respondsToSelector:@selector(ping:didFailToSendPingWithSummary:error:)]) {
                    [self.delegate ping:self didFailToSendPingWithSummary:pingSummaryCopyAfterFailure error:[NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]];
                }
            });
        }
    }
}

-(void)stop {
    @synchronized(self) {
        if (!self.isStopped) {
            self.isPinging = NO;
            
            self.isReady = NO;
            
            //destroy listenThread by closing socket (listenThread)
            if (self.socket) {
                close(self.socket);
                self.socket = 0;
            }
            
            //destroy host
            self.hostAddress = nil;
            
            //clean up pendingpings
            [self.pendingPings removeAllObjects];
            self.pendingPings = nil;
            for (NSNumber *key in [self.timeoutTimers copy]) {
                NSTimer *timer = self.timeoutTimers[key];
                [timer invalidate];
            }
            
            //clean up timeouttimers
            [self.timeoutTimers removeAllObjects];
            self.timeoutTimers = nil;
            
            //reset seq number
            self.nextSequenceNumber = 0;
            
            self.isStopped = YES;
        }
    }
}

#pragma mark - util

static uint16_t in_cksum(const void *buffer, size_t bufferLen)
// This is the standard BSD checksum code, modified to use modern types.
{
    size_t              bytesLeft;
    int32_t             sum;
    const uint16_t *    cursor;
    union {
        uint16_t        us;
        uint8_t         uc[2];
    } last;
    uint16_t            answer;
    
    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;
    
    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = * (const uint8_t *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff);  /* add hi 16 to low 16 */
    sum += (sum >> 16);      /* add carry */
    answer = (uint16_t) ~sum;   /* truncate to 16 bits */
    
    return answer;
}

+(NSString *)sourceAddressInPacket:(NSData *)packet {
    // Returns the source address of the IP packet
    
    const struct IPHeader   *ipPtr;
    const uint8_t           *sourceAddress;
    
    if ([packet length] >= sizeof(IPHeader)) {
        ipPtr = (const IPHeader *)[packet bytes];
        
        sourceAddress = ipPtr->sourceAddress;//dont need to swap byte order those cuz theyre the smallest atomic unit (1 byte)
        NSString *ipString = [NSString stringWithFormat:@"%d.%d.%d.%d", sourceAddress[0], sourceAddress[1], sourceAddress[2], sourceAddress[3]];
        
        return ipString;
    }
    else return nil;
}

+ (NSUInteger)icmp4HeaderOffsetInPacket:(NSData *)packet
// Returns the offset of the ICMPHeader within an IP packet.
{
    NSUInteger              result;
    const struct IPHeader * ipPtr;
    size_t                  ipHeaderLength;
    
    result = NSNotFound;
    if ([packet length] >= (sizeof(IPHeader) + sizeof(ICMPHeader))) {
        ipPtr = (const IPHeader *) [packet bytes];
        assert((ipPtr->versionAndHeaderLength & 0xF0) == 0x40);     // IPv4
        assert(ipPtr->protocol == 1);                               // ICMP
        ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);
        if ([packet length] >= (ipHeaderLength + sizeof(ICMPHeader))) {
            result = ipHeaderLength;
        }
    }
    return result;
}

+ (const struct ICMPHeader *)icmp4InPacket:(NSData *)packet
// See comment in header.
{
    const struct ICMPHeader *   result;
    NSUInteger                  icmpHeaderOffset;
    
    result = nil;
    icmpHeaderOffset = [self icmp4HeaderOffsetInPacket:packet];
    if (icmpHeaderOffset != NSNotFound) {
        result = (const struct ICMPHeader *) (((const uint8_t *)[packet bytes]) + icmpHeaderOffset);
    }
    return result;
}

- (BOOL)isValidPingResponsePacket:(NSMutableData *)packet
{
    BOOL result;
    
    switch (self.hostAddressFamily) {
        case AF_INET: {
            result = [self isValidPing4ResponsePacket:packet];
        } break;
        case AF_INET6: {
            result = [self isValidPing6ResponsePacket:packet];
        } break;
        default: {
            result = NO;
        } break;
    }
    return result;
}

- (BOOL)isValidPing4ResponsePacket:(NSMutableData *)packet
// Returns true if the packet looks like a valid ping response packet destined
// for us.
{
    BOOL                result;
    NSUInteger          icmpHeaderOffset;
    ICMPHeader *        icmpPtr;
    uint16_t            receivedChecksum;
    uint16_t            calculatedChecksum;
    
    result = NO;
    
    icmpHeaderOffset = [[self class] icmp4HeaderOffsetInPacket:packet];
    if (icmpHeaderOffset != NSNotFound) {
        icmpPtr = (struct ICMPHeader *) (((uint8_t *)[packet mutableBytes]) + icmpHeaderOffset);
        
        receivedChecksum   = icmpPtr->checksum;
        icmpPtr->checksum  = 0;
        calculatedChecksum = in_cksum(icmpPtr, [packet length] - icmpHeaderOffset);
        icmpPtr->checksum  = receivedChecksum;
        
        if (receivedChecksum == calculatedChecksum) {
            if ( (icmpPtr->type == kICMPv4TypeEchoReply) && (icmpPtr->code == 0) ) {
                if ( OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier ) {
                    if ( OSSwapBigToHostInt16(icmpPtr->sequenceNumber) < self.nextSequenceNumber ) {
                        result = YES;
                    }
                }
            }
        }
    }
    
    //    NSLog(@"valid: %@, type: %d", _b(result), icmpPtr->type);
    
    return result;
}

- (BOOL)isValidPing6ResponsePacket:(NSMutableData *)packet
// Returns true if the IPv6 packet looks like a valid ping response packet destined
// for us.
{
    BOOL                      result;
    const ICMPHeader *        icmpPtr;
    
    result = NO;
    
    if (packet.length >= sizeof(*icmpPtr)) {
        icmpPtr = packet.bytes;
        
        if ( (icmpPtr->type == kICMPv6TypeEchoReply) && (icmpPtr->code == 0) ) {
            if ( OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier ) {
                if ( OSSwapBigToHostInt16(icmpPtr->sequenceNumber) < self.nextSequenceNumber ) {
                    result = YES;
                }
            }
        }

    }
    
    return result;
}

-(NSData *)generateDataWithLength:(NSUInteger)length {
    //create a buffer full of 7's of specified length
    char tempBuffer[length];
    memset(tempBuffer, 7, length);
    
    return [[NSData alloc] initWithBytes:tempBuffer length:length];
}

- (void)_invokeTimeoutCallback:(NSTimer *)timer
{
    dispatch_block_t callback = timer.userInfo;
    if (callback) {
        callback();
    }
}

- (NSData *)pingPacketWithType:(uint8_t)type payload:(NSData *)payload requiresChecksum:(BOOL)requiresChecksum {
    NSMutableData *         packet;
    ICMPHeader *            icmpPtr;
    
    packet = [NSMutableData dataWithLength:sizeof(*icmpPtr) + payload.length];
    if (packet == nil) { return nil; }
    
    icmpPtr = packet.mutableBytes;
    icmpPtr->type = type;
    icmpPtr->code = 0;
    icmpPtr->checksum = 0;
    icmpPtr->identifier     = OSSwapHostToBigInt16(self.identifier);
    icmpPtr->sequenceNumber = OSSwapHostToBigInt16(self.nextSequenceNumber);
    memcpy(&icmpPtr[1], [payload bytes], [payload length]);
    
    if (requiresChecksum) {
        // The IP checksum routine returns a 16-bit number that's already in correct byte order
        // (due to wacky 1's complement maths), so we just put it into the packet as a 16-bit unit.
        
        icmpPtr->checksum = in_cksum(packet.bytes, packet.length);
    }
    
    return packet;
}

- (sa_family_t)hostAddressFamily {
    sa_family_t result = AF_UNSPEC;
    // Save a reference to a local variable, avoid crash when hostAddress is release by other thread.
    NSData *hostAddress = self.hostAddress; 
    if (hostAddress != nil && hostAddress.length >= sizeof(struct sockaddr)) {
        result = ((const struct sockaddr *)hostAddress.bytes)->sa_family;
    }
    
    return result;
}

- (NSString*)ntop:(struct sockaddr *)sa len:(socklen_t)len {
    char ntop[NI_MAXHOST] = { 0 };
    int ecode = getnameinfo(sa, len, ntop, sizeof(ntop), NULL, 0, NI_NUMERICHOST);
    if (ecode == 0) {
        return [[NSString alloc] initWithUTF8String:ntop];
    } else {
        return nil;
    }
}

#pragma mark - memory

-(id)init {
    if (self = [super init]) {
        self.setupQueue = dispatch_queue_create("GBPing setup queue", 0);
        self.isStopped = YES;
        self.identifier = arc4random();
        self.useIpv4 = YES;
        self.useIpv6 = YES;
    }
    
    return self;
}

-(void)dealloc {
    self.delegate = nil;
    self.host = nil;
    @synchronized (self) {
        self.timeoutTimers = nil;
        self.pendingPings = nil;
    }
    self.hostAddress = nil;
    
    //clean up socket to be sure
    if (self.socket) {
        close(self.socket);
        self.socket = 0;
    }
}

@end
