//
//  GREventsGenerator.h
//  HelloSDL
//
//  Created by Ezequiel Lowi on 11/17/16.
//  Copyright © 2016 Ford. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GREventsGenerator : NSObject

+ (GREventsGenerator*) sharedInstance;
- (void) start;

@end
