//
//  GREventsGenerator.h
//  HelloSDL
//
//  Created by Ezequiel Lowi on 11/17/16.
//  Copyright © 2016 Ford. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, GREventType) {
    GREventNoEvent,
    GREventBreak,
    GREventAccelerate,
    GREventCornerRight,
    GREventCornerLeft
};

@class GREventsGenerator;
@protocol GREventsGeneratorDelegate <NSObject>

@required
- (void) driveEvent : (GREventsGenerator*) eventGenerator eventType:(GREventType) eventType;

@end

@interface GREventsGenerator : NSObject

@property (nonatomic, weak) id<GREventsGeneratorDelegate> eventsListener;

+ (GREventsGenerator*) sharedInstance;
- (void) start;

@end
