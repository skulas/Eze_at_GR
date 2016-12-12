//
//  ViewController.m
//  HelloSDL
//
//  Created by Ford Developer on 10/5/15.
//  Copyright © 2015 Ford. All rights reserved.
//

#import "ViewController.h"
#import "HSDLProxyManager.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imgCoffeeCoupon;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleCoffee) name:kCoffeeMessage object:nil];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) handleCoffee {
    [self.imgCoffeeCoupon setHidden:NO];
}

@end
