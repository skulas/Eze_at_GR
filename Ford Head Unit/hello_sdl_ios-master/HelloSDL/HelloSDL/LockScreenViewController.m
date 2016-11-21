//
//  LockScreenViewController.m
//  HelloSDL
//
//  Created by Ford Developer on 10/5/15.
//  Copyright © 2015 Ford. All rights reserved.
//

#import "LockScreenViewController.h"

@interface LockScreenViewController ()
@property (weak, nonatomic) IBOutlet UIView *viewLockedView;
@property (weak, nonatomic) IBOutlet UIImageView *imgGRLogo;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *constrYAlign;

@end

@implementation LockScreenViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) animateInWithCompletionBlock:(void (^)())animationDone {
    [self.view layoutIfNeeded];
    
    [UIView animateWithDuration:0.8 animations:^{
        self.constrYAlign.constant = 50;
        [self.viewLockedView setHidden:NO];
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.35 animations:^{
            [self.viewLockedView setAlpha:1.0];
        } completion:^(BOOL finished) {
            animationDone();
        }];
    }];
}

- (void) animateOutWithCompletionBlock:(void (^)())animatrionDone {
    [UIView animateWithDuration:0.3
                     animations:^{
                         [self.viewLockedView setAlpha:0.0];
                     } completion:^(BOOL finished) {
                         [self.viewLockedView setHidden:YES];
                         [UIView animateWithDuration:0.8
                                          animations:^{
                                              self.constrYAlign.constant = 0;
                                              [self.view layoutIfNeeded];
                                          } completion:^(BOOL finished) {
                                              animatrionDone();
                                          }];
                     }];
}
@end
