//
//  GREventsGenerator.m
//  HelloSDL
//
//  Created by Ezequiel Lowi on 11/17/16.
//  Copyright © 2016 Ford. All rights reserved.
//

#import "GREventsGenerator.h"

static GREventsGenerator* _uniqueRef = nil;
static const int MAX_RAND_PART = 30;
static const int MIN_INTERVAL_BETWEEN_EVENTS = 5;

@interface GREventsGenerator()
@property (atomic, assign) BOOL running;
@end

@implementation GREventsGenerator

+ (GREventsGenerator*) sharedInstance {
    if (_uniqueRef == nil) {
        @synchronized (_uniqueRef) {
            if (_uniqueRef == nil) {
                _uniqueRef = [[GREventsGenerator alloc] init];
            }
        }
    }
    
    return _uniqueRef;
}

- (GREventsGenerator*) init {
    if (self = [super init]) {
        self.running = NO;
    }
    
    return self;
}

- (void) start {
    @synchronized (self) {
        if (self.running == NO) {
            self.running = YES;
            [self dispatchNewEvent];
        }
    }
}

- (void) stop {
    @synchronized (self) {
        self.running = NO;
    }
}

- (void) dispatchNewEvent {
    int delayLength = arc4random_uniform(MAX_RAND_PART);
    int intervalLength = MIN_INTERVAL_BETWEEN_EVENTS + delayLength;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(intervalLength * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self generateRandomEvent];
    });
}

- (void) generateRandomEvent {
    int eventType = arc4random_uniform(4);
    
    switch (eventType) {
        case 0:
            NSLog(@"BREAK EVENT");
            break;
        case 1:
            NSLog(@"AXLERATE EVENT");
            break;
        case 2:
            NSLog(@"CORNER RIGHT EVENT");
            break;
        case 3:
            NSLog(@"CORNER LEFT EVENT");
            break;
        default:
            NSLog(@"WFT EVENT - HOW DID WE GET VALUE ABOVE MAX RANDOM PARAM??");
            break;
    }
    
    @synchronized (self) {
        if (self.running) {
            [self dispatchNewEvent];
        }
    }
}


@end
