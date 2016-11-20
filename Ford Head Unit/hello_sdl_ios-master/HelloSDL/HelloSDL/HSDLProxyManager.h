//
//  HSDLProxyManager.h
//  HelloSDL
//
//  Created by Ford Developer on 10/5/15.
//  Copyright © 2015 Ford. All rights reserved.
//

extern NSString *const HSDLDisconnectNotification;
extern NSString *const HSDLLockScreenStatusNotification;
extern NSString *const HSDLNotificationUserInfoObject;

@interface HSDLProxyManager : NSObject

+ (instancetype)manager;
- (void)startProxy;
- (void)disposeProxy;

@end
