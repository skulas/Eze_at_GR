//
//  LockScreenViewController.h
//  HelloSDL
//
//  Created by Ford Developer on 10/5/15.
//  Copyright © 2015 Ford. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LockScreenViewController : UIViewController

- (void) animateInWithCompletionBlock : (void (^)()) animationDone;
- (void) animateOutWithCompletionBlock : (void (^)()) animatrionDone;
@end

