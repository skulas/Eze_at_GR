
/*
     File: APLAccelerometerGraphViewController.m
 Abstract: View controller to manage display of output from the accelerometer.

  Version: 1.0.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 
 */

#import "APLAccelerometerGraphViewController.h"
#import "APLAppDelegate.h"
#import "APLGraphView.h"
#import <AudioToolbox/AudioToolbox.h>

static const NSTimeInterval accelerometerMin = 0.01;

// number of areas to split each of the 8 quadrants
// 2: 0<|x|<0.5 or 0.5<|x|<1
static const double resolution = 2.0; // Use Natural numbers. Using double for performance
//static const int avgWindowSize = 20;

@interface Point3D : NSObject

@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;
@property (nonatomic, assign) double z;

+ (Point3D*) Zeroes;

@end

@implementation Point3D

+ (Point3D*) Zeroes {
    Point3D *zeroes = [[Point3D alloc] init];
    
    zeroes.x = 0;
    zeroes.y = 0;
    zeroes.z = 0;
    
    return zeroes;
}

@end


@interface APLAccelerometerGraphViewController ()

@property (nonatomic, weak) IBOutlet APLGraphView *graphView;
@property (weak, nonatomic) IBOutlet UILabel *lblGVec;
@property (weak, nonatomic) IBOutlet UILabel *lblGVecAvg;
//@property (nonatomic, strong) NSMutableArray *arrWindow;
@property (weak, nonatomic) IBOutlet UILabel *lblXY_Quadrant;
@property (weak, nonatomic) IBOutlet UILabel *lblZX_Quadrant;
@property (weak, nonatomic) IBOutlet UILabel *lblYZ_Quadrant;
@property (weak, nonatomic) IBOutlet UILabel *lblDebug;

@property (nonatomic, strong) NSMutableArray *arr_xyoffsets;
@property (nonatomic, strong) NSMutableArray *arr_xzoffsets;
@property (nonatomic, strong) NSMutableArray *arr_zyoffsets;

@end


@implementation APLAccelerometerGraphViewController {
    unsigned long sampleCounter;
}

- (void) viewDidLoad {
    [super viewDidLoad];
    sampleCounter = 0;
    self.arr_xyoffsets = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_xzoffsets = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_zyoffsets = [NSMutableArray arrayWithCapacity:resolution*4];
    for (int ix = 0; ix < resolution*4; ix++) {
        self.arr_xyoffsets[ix] = [Point3D Zeroes];
        self.arr_xzoffsets[ix] = [Point3D Zeroes];
        self.arr_zyoffsets[ix] = [Point3D Zeroes];
    }
}

- (void)startUpdatesWithSliderValue:(int)sliderValue
{
    NSTimeInterval delta = 0.005;
    NSTimeInterval updateInterval = accelerometerMin + delta * sliderValue;
//    if (self.arrWindow == nil) {
//        self.arrWindow = [NSMutableArray array];
//    }

    CMMotionManager *mManager = [(APLAppDelegate *)[[UIApplication sharedApplication] delegate] sharedManager];

    APLAccelerometerGraphViewController * __weak weakSelf = self;
    if ([mManager isAccelerometerAvailable] == YES) {
        [mManager setAccelerometerUpdateInterval:updateInterval];
        [mManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMAccelerometerData *accelerometerData, NSError *error) {
            [weakSelf.graphView addX:accelerometerData.acceleration.x y:accelerometerData.acceleration.y z:accelerometerData.acceleration.z];
            [weakSelf setLabelValueX:accelerometerData.acceleration.x y:accelerometerData.acceleration.y z:accelerometerData.acceleration.z];
            [weakSelf updateGWithX:accelerometerData.acceleration.x
                                 y:accelerometerData.acceleration.y
                                 z:accelerometerData.acceleration.z];
        }];
    }

    self.updateIntervalLabel.text = [NSString stringWithFormat:@"%f", updateInterval];
}

// Build as averages for each segment of each quadrant separately.
// Use infinite avg (the comment out) and not sliding windows.

- (double) avgCalcNewValue:(double) newVal currentAvg: (double) currAvg numberOfsamples: (long) currSampleCounter {
    double result = (currAvg * currSampleCounter + newVal) / (currSampleCounter + 1);
    
    return result;
}


//   1 - XY, 2 - XZ, 3 - ZY
- (void) updateAvgSpaceSelect : (int) space newPoint : (Point3D*) p3d quadrantSliceIx : (int) currSliceInQuadrant {
    NSMutableArray *currArr = nil;
    
    switch (space) {
        case 0:
            currArr = self.arr_xyoffsets;
            break;
        case 1:
            currArr = self.arr_xzoffsets;
            break;
        case 2:
            currArr = self.arr_zyoffsets;
            break;
        default:
            NSLog(@"WRONG SPACE: 1 - XY, 2 - XZ, 3 - ZY");
            return;
            break;
    }
    Point3D *currVal = currArr[currSliceInQuadrant];
    Point3D *newVal = [Point3D Zeroes];
    newVal.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:sampleCounter];
    newVal.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:sampleCounter];
    newVal.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:sampleCounter];
    
    self.arr_xyoffsets[currSliceInQuadrant] = newVal;
}

- (void) updateGWithX:(double)x y:(double)y z:(double)z {
    static double avg = 0;
    
//    unsigned long test = ULONG_MAX;// LONG_MAX * 2 + 1; // twos complement for unsigned
//    test += 1; // after many cycles the long will wrap around and the avg will be distorted a bit.
    
    double gVec = sqrt(pow(x, 2)+pow(y, 2)+pow(z, 2));
    double gVec_xy = sqrt(pow(x, 2)+pow(y, 2));
//    double gVec_zx = sqrt(pow(x, 2)+pow(z, 2));
//    double gVec_yz = sqrt(pow(y, 2)+pow(z, 2));
    
    double theta_xy = atan2(y,x);
    double theta_zx = atan2(x,z);
    double theta_yz = atan2(z,y);
    double sin_phi = gVec_xy / gVec; // Always +
    double phi = asin(sin_phi);     // Always +
    
    if (z < 0) {
        if (theta_xy > 0)
            phi = M_PI - phi;
        else
            phi = phi - M_PI;
    } else {
        if (theta_xy < 0)
            phi = - phi;
    }
    
    
    //    avg = (avg * sampleCounter + gVec) / (sampleCounter + 1);
    avg = [self avgCalcNewValue:gVec currentAvg:avg numberOfsamples:sampleCounter];
    
    
    
//    [_lblDebug setText:[NSString stringWithFormat:@"z %.3f | rs %.3f", z, gVec*cos(phi)]];
    
    int xyQuadrant = [self quadrant:theta_xy];
    int zxQuadrant = [self quadrant:theta_zx];
    int yzQuadrant = [self quadrant:theta_yz];
    
//    [self.lblXY_Quadrant setText:[NSString stringWithFormat:@"%.1f|%d", theta_xy/M_PI, xyQuadrant]];
//    [self.lblZX_Quadrant setText:[NSString stringWithFormat:@"%.1f|%d", theta_zx/M_PI, zxQuadrant]];
//    [self.lblYZ_Quadrant setText:[NSString stringWithFormat:@"%.1f|%d", theta_yz/M_PI, yzQuadrant]];
    
//    double acclX = gVec *
    double oneX = sin_phi * cos(theta_xy);
    double oneY = sin_phi * sin(theta_xy);
    double oneZ = cos(phi);
    
    Point3D *p3d = [[Point3D alloc] init];
    p3d.x = oneX - x;
    p3d.y = oneY - y;
    p3d.z = oneZ - z;
    
//    Point3D *currVal = self.arr_xyoffsets[xyQuadrant];
//    p3d.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:sampleCounter];
//    p3d.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:sampleCounter];
//    p3d.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:sampleCounter];
//    self.arr_xyoffsets[xyQuadrant] = p3d;
    [self updateAvgSpaceSelect:0 newPoint:p3d quadrantSliceIx:xyQuadrant];
    [self updateAvgSpaceSelect:1 newPoint:p3d quadrantSliceIx:zxQuadrant];
    [self updateAvgSpaceSelect:2 newPoint:p3d quadrantSliceIx:yzQuadrant];
    


    [self.lblXY_Quadrant setText:[NSString stringWithFormat:@"%.3f", oneX]];
    [self.lblZX_Quadrant setText:[NSString stringWithFormat:@"%.3f", oneY]];
    [self.lblYZ_Quadrant setText:[NSString stringWithFormat:@"%.3f", oneZ]];
    
    Point3D *pxy = self.arr_xyoffsets[xyQuadrant];
    Point3D *pxz = self.arr_xzoffsets[zxQuadrant];
    Point3D *pyz = self.arr_zyoffsets[yzQuadrant];
    
    [_lblDebug setText:[NSString stringWithFormat:@"Qxy %d, Qyz %d, Qzx %d\n%.3f %.3f %.3f %.3f %.3f %.3f", xyQuadrant, yzQuadrant, zxQuadrant, pxy.x, pxz.x, pxy.y, pyz.y, pxz.z, pyz.z]];
    
    
    
//    int currIx = sampleCounter%avgWindowSize;
//    self.arrWindow[currIx] = @(gVec);
    
//    if (sampleCounter > avgWindowSize) {
//        double sum = 0;
//        for (int ix = 0; ix < avgWindowSize; ix++) {
//            sum += [self.arrWindow[ix] doubleValue];
//        }
//        avg = sum / avgWindowSize;
        [self.lblGVec setText:[NSString stringWithFormat:@"%.3f", gVec]];
        [self.lblGVecAvg setText:[NSString stringWithFormat:@"%.3f", avg]];
//    }
    
    
    sampleCounter += 1;
}

- (int) quadrant:(double) theta {
    int q_found = -1;
    static double sliceSize = M_PI_2 / resolution;
    int rndResolution = (int)round(resolution);
    double fixedTheta = theta;
    int q_0;
    double startQComparator;
    
    if (theta < 0) {
        fixedTheta = 2 * M_PI + theta;
        q_0 = 2 * rndResolution;
        startQComparator = sliceSize + M_PI;
    } else {
        fixedTheta = theta;
        startQComparator = sliceSize;
        q_0 = 0;
    }
    
    double currSliceTopLimit = startQComparator;
    
    // searching half space
    for (int q_ix = 1; q_ix < 2 * rndResolution; q_ix++) {
        
        
        if (fixedTheta < currSliceTopLimit) {
            q_found = q_ix - 1;
            break;
        }
        
        currSliceTopLimit += sliceSize;
    }
    
    if (q_found == -1) {
        // Not found, lat slice of last quadrant
        q_found = 2*rndResolution - 1;
    }
    
    q_found += q_0; // Fix if it's second half of space.
    
    return q_found;
}


- (void)stopUpdates
{
    CMMotionManager *mManager = [(APLAppDelegate *)[[UIApplication sharedApplication] delegate] sharedManager];

    if ([mManager isAccelerometerActive] == YES) {
        [mManager stopAccelerometerUpdates];
    }
}

- (void) resetAvg {
    //http://iphonedevwiki.net/index.php/AudioServices
    AudioServicesPlaySystemSound (1001);

    
    sampleCounter = 0;
}

- (IBAction)btnResetAvgAction:(id)sender {
    AudioServicesPlaySystemSound (1104);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self resetAvg];
    });
}


@end
