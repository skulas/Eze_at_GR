//
//  AppDelegate.m
//  HelloSDL
//
//  Created by Ford Developer on 10/5/15.
//  Copyright © 2015 Ford. All rights reserved.
//

#import "AppDelegate.h"
#import "HSDLProxyManager.h"
@import SmartDeviceLink_iOS;

@interface AppDelegate ()

@property UIViewController *lockScreenViewController;
@property UIViewController *mainViewController;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    // Store references to the 2 view controllers
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *lockvc = [sb instantiateViewControllerWithIdentifier:@"LockScreenViewController"];
    self.lockScreenViewController = lockvc;
    self.mainViewController = self.window.rootViewController;

    [self hsdl_registerForLockScreenNotifications];

    // Start the proxy
    [[HSDLProxyManager manager] startProxy];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)hsdl_lockScreen {
    @synchronized(self) {
        // Display the lock screen if it is not presented already.
        if ([self.window.rootViewController isEqual:self.lockScreenViewController] == NO) {
            [self.window setRootViewController:self.lockScreenViewController];
        }
    }
}

- (void)hsdl_unlockScreen {
    @synchronized(self) {
        // Display the regular screen if it is not presented already.
        if ([self.window.rootViewController isEqual:self.mainViewController] == NO) {
            [self.window setRootViewController:self.mainViewController];
        }
    }
}

- (void)hsdl_registerForLockScreenNotifications {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(didChangeLockScreenStatus:) name:HSDLLockScreenStatusNotification object:nil];
    [center addObserver:self selector:@selector(proxyDidDisconnect:) name:HSDLDisconnectNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark SDL Lockscreen Notifications

- (void)didChangeLockScreenStatus:(NSNotification *)notification {
    // Delegate method to handle changes in lockscreen status

    NSLog(@"AppDelegate received didChangeLockScreenStatus notification: %@", notification);

    SDLOnLockScreenStatus *lockScreenStatus = nil;
    if (notification && notification.userInfo) {
        lockScreenStatus = notification.userInfo[HSDLNotificationUserInfoObject];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if (lockScreenStatus && ![lockScreenStatus.lockScreenStatus isEqualToEnum:[SDLLockScreenStatus OFF]]) {
          [self hsdl_lockScreen];
      } else {
          [self hsdl_unlockScreen];
      }
    });
}

- (void)proxyDidDisconnect:(NSNotification *)notification {
    // Delegate method to perform actions on disconnect from SYNC
    // Clear the lockscreen

    NSLog(@"AppDelegate received proxyDidDisconnect notification: %@", notification);

    dispatch_async(dispatch_get_main_queue(), ^{
      [self hsdl_unlockScreen];
    });
}

@end
