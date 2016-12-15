
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
#import "GRAccelerometerOffsetDetector.h"

static const NSTimeInterval accelerometerMin = 0.01;
static const NSTimeInterval UI_REFRESH_RATE = 0.75;

// number of areas to split each of the 4 quadrants
// 2: 0<|x|<0.5 or 0.5<|x|<1
static const double resolution = 2.0; // Use Natural numbers. Using double for performance
//static const int avgWindowSize = 20;

@interface Point3D__ : NSObject

@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;
@property (nonatomic, assign) double z;

+ (Point3D__*) Zeroes;

@end

@implementation Point3D__

+ (Point3D__*) Zeroes {
    Point3D__ *zeroes = [[Point3D__ alloc] init];
    
    zeroes.x = 0;
    zeroes.y = 0;
    zeroes.z = 0;
    
    return zeroes;
}

@end


@interface APLAccelerometerGraphViewController ()

@property (nonatomic, weak) IBOutlet APLGraphView *graphView;
@property (weak, nonatomic) IBOutlet UIView *viewAllData;
@property (weak, nonatomic) IBOutlet UILabel *lblAllDataXY;
@property (weak, nonatomic) IBOutlet UILabel *lblAllDataYZ;
@property (weak, nonatomic) IBOutlet UILabel *lblAllDataZX;

@property (weak, nonatomic) IBOutlet UILabel *lblGVec;
@property (weak, nonatomic) IBOutlet UILabel *lblGVecAvg;
//@property (nonatomic, strong) NSMutableArray *arrWindow;
@property (weak, nonatomic) IBOutlet UILabel *lblXY_Quadrant;
@property (weak, nonatomic) IBOutlet UILabel *lblZX_Quadrant;
@property (weak, nonatomic) IBOutlet UILabel *lblYZ_Quadrant;
@property (weak, nonatomic) IBOutlet UILabel *lblDebug;

@property (nonatomic, strong) NSMutableArray *arr_xyoffsets;
@property (nonatomic, strong) NSMutableArray *arr_xyCounters;
@property (nonatomic, strong) NSMutableArray *arr_xzoffsets;
@property (nonatomic, strong) NSMutableArray *arr_xzCounters;
@property (nonatomic, strong) NSMutableArray *arr_zyoffsets;
@property (nonatomic, strong) NSMutableArray *arr_zyCounters;

@property (nonatomic, assign) BOOL allDataVisible;
@property (nonatomic, assign) BOOL graphEnabled;

@property (nonatomic, strong) NSDate *dateLastUIRefresh;

@property (nonatomic, strong) dispatch_queue_t calculations_queue;

@end


@implementation APLAccelerometerGraphViewController {
    unsigned long sampleCounter;
}

- (void) viewDidLoad {
    [super viewDidLoad];
    
    self.calculations_queue = dispatch_queue_create("com.gr.averages", DISPATCH_QUEUE_SERIAL);
    
    sampleCounter = 0;
    self.dateLastUIRefresh = [NSDate date];
    self.graphEnabled = YES;
    self.allDataVisible = !self.viewAllData.hidden;
    self.arr_xyoffsets = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_xyCounters = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_xzoffsets = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_xzCounters = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_zyoffsets = [NSMutableArray arrayWithCapacity:resolution*4];
    self.arr_zyCounters = [NSMutableArray arrayWithCapacity:resolution*4];
    
    
    
    for (int ix = 0; ix < resolution*4; ix++) {
        self.arr_xyoffsets[ix] = [Point3D__ Zeroes];
        self.arr_xzoffsets[ix] = [Point3D__ Zeroes];
        self.arr_zyoffsets[ix] = [Point3D__ Zeroes];
        self.arr_xyCounters[ix] = @(0);
        self.arr_xzCounters[ix] = @(0);
        self.arr_zyCounters[ix] = @(0);
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
            if (self.graphEnabled) {
                [weakSelf.graphView addX:accelerometerData.acceleration.x y:accelerometerData.acceleration.y z:accelerometerData.acceleration.z];
            }
            
            dispatch_async(self.calculations_queue, ^{
                [self updateGWithX:accelerometerData.acceleration.x
                                     y:accelerometerData.acceleration.y
                                     z:accelerometerData.acceleration.z];
            });
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


//   0 - XY, 1 - XZ, 2 - ZY
/** Calculate three separate avg for newPoint values
 * @param newPoint: NormGVec - UnitVec in the same direction (x,y,z)
 * @param space: 0 - XY, 1 - ZX, 2 - YZ
 * @param quadrantSliceIx: Which section of the spce (resolution * 4 sections. 4 as there are 4 quadrants (++, -+, -- , +-)
 *
 */
- (void) updateAvgSpaceSelect : (int) space newPoint : (Point3D__*) p3d quadrantSliceIx : (int) currSliceInQuadrant {
    NSMutableArray *currOffsetArr = nil;
    NSMutableArray *currCountersArr = nil;
    Point3D__ *newVal = [Point3D__ Zeroes];
    long currCounter;
    
    switch (space) {
        case 0:
        {
            currOffsetArr = self.arr_xyoffsets;
            currCountersArr = self.arr_xyCounters;
            Point3D__ *currVal = currOffsetArr[currSliceInQuadrant];
            currCounter = [currCountersArr[currSliceInQuadrant] longValue];
            
            newVal.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:currCounter];
            newVal.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:currCounter];
        }
            
            break;
        case 1:
        {
            currOffsetArr = self.arr_xzoffsets;
            currCountersArr = self.arr_xzCounters;
            Point3D__ *currVal = currOffsetArr[currSliceInQuadrant];
            currCounter = [currCountersArr[currSliceInQuadrant] longValue];
            
            newVal.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:currCounter];
            newVal.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:currCounter];
        }
            
            break;
        case 2:
        {
            currOffsetArr = self.arr_zyoffsets;
            currCountersArr = self.arr_zyCounters;
            Point3D__ *currVal = currOffsetArr[currSliceInQuadrant];
            currCounter = [currCountersArr[currSliceInQuadrant] longValue];

            newVal.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:currCounter];
            newVal.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:currCounter];
        }
            break;
        default:
            NSLog(@"WRONG SPACE: 0 - XY, 1 - XZ, 2 - ZY");
            return;
            break;
    }
    
    currCountersArr[currSliceInQuadrant] = @(currCounter + 1);
    
    currOffsetArr[currSliceInQuadrant] = newVal;
}

// NOT GOOD FOR LOW G VALUES
//- (BOOL) isGVecIntertialX: (double) x Y: (double) y Z: (double) z {
//    static double gLowThres = 0.9;
//    static double gHighThres = 1.1;
//    BOOL isNOTInertial = ( (x > gHighThres) || (y > gHighThres) || (z > gHighThres) ||
//                          (x < -gHighThres) || (y < -gHighThres) || (z < -gHighThres) );
//    
//    if (!isNOTInertial) {
//        isNOTInertial = ((x > -gLowThres) && (x < gLowThres)) ||
//        ((y > -gLowThres) && (y < gLowThres)) ||
//        ((z > -gLowThres) && (z < gLowThres));
//    }
//    
//    return !isNOTInertial;
//    
//}

- (void) updateGWithX:(double)x y:(double)y z:(double)z {
    static double avg = 0;
    double gVecModule = sqrt(pow(x, 2)+pow(y, 2)+pow(z, 2));
    static double low_g_thres = 0.9;
    static double hig_g_thres = 1.1;
    
    ///// TEST ///////
    GRVector gInVec = {x, y, z};
    [[GRAccelerometerOffsetDetector sharedDetector] insertNewSample:gInVec];
    /////
    
    
    if ( (gVecModule < low_g_thres) || (hig_g_thres < gVecModule) ) {
//        NSLog(@"Strong force detected, skipping sample");
        return;
    }
    
//    unsigned long test = ULONG_MAX;// LONG_MAX * 2 + 1; // twos complement for unsigned
//    test += 1; // after many cycles the long will wrap around and the avg will be distorted a bit.
    
    avg = [self avgCalcNewValue:gVecModule currentAvg:avg numberOfsamples:sampleCounter];

    double gVec_xy = sqrt(pow(x, 2)+pow(y, 2));
//    double gVec_zx = sqrt(pow(x, 2)+pow(z, 2));
//    double gVec_yz = sqrt(pow(y, 2)+pow(z, 2));
    
    double theta_xy = atan2(y,x);
    double theta_zx = atan2(x,z);
    double theta_yz = atan2(z,y);
    double sin_phi = gVec_xy / gVecModule; // Always +
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
    
    Point3D__ *Unit_minus_actual = [[Point3D__ alloc] init];
    Unit_minus_actual.x = oneX - x;
    Unit_minus_actual.y = oneY - y;
    Unit_minus_actual.z = oneZ - z;
    //    Unit_minus_actual.x = fabs(oneX - x);
    //    Unit_minus_actual.y = fabs(oneY - y);
    //    Unit_minus_actual.z = fabs(oneZ - z);
    
    //    Point3D *currVal = self.arr_xyoffsets[xyQuadrant];
    //    p3d.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:sampleCounter];
    //    p3d.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:sampleCounter];
    //    p3d.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:sampleCounter];
    //    self.arr_xyoffsets[xyQuadrant] = p3d;
    [self updateAvgSpaceSelect:0 newPoint:Unit_minus_actual quadrantSliceIx:xyQuadrant];
    [self updateAvgSpaceSelect:1 newPoint:Unit_minus_actual quadrantSliceIx:zxQuadrant];
    [self updateAvgSpaceSelect:2 newPoint:Unit_minus_actual quadrantSliceIx:yzQuadrant];
    
    
    
    // UI Updates
    if ([[NSDate date] timeIntervalSinceDate:self.dateLastUIRefresh] > UI_REFRESH_RATE) {
        if (self.allDataVisible) {
            int numOfGroups = resolution * 4;
            NSMutableString *xyStr = [NSMutableString stringWithCapacity:200];
            NSMutableString *yzStr = [NSMutableString stringWithCapacity:200];
            NSMutableString *zxStr = [NSMutableString stringWithCapacity:200];
            NSString *strFormat = @"\n%d\n%@=%.2f %@=%.2f\n";
            
            for (int txtIx = 0; txtIx < numOfGroups; txtIx++) {
                int counterVal = [self.arr_xyCounters[txtIx] intValue];
                Point3D__ *currSlice = self.arr_xyoffsets[txtIx];
                NSString *currStr = [NSString stringWithFormat:strFormat, counterVal, @"x", currSlice.x, @"y", currSlice.y];
                [xyStr appendString:currStr];
                
                counterVal = [self.arr_zyCounters[txtIx] intValue];
                currSlice = self.arr_zyoffsets[txtIx];
                currStr = [NSString stringWithFormat:strFormat, counterVal, @"y", currSlice.y, @"z", currSlice.z];
                [yzStr appendString:currStr];
                
                counterVal = [self.arr_xzCounters[txtIx] intValue];
                currSlice = self.arr_xzoffsets[txtIx];
                currStr = [NSString stringWithFormat:strFormat, counterVal, @"z", currSlice.z, @"x", currSlice.x];
                [zxStr appendString:currStr];
            }
            
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.lblAllDataXY setText:xyStr];
                [self.lblAllDataYZ setText:yzStr];
                [self.lblAllDataZX setText:zxStr];
            });
        } else {
            GRVector newCopy = gInVec;
            GRVector fixed = [[GRAccelerometerOffsetDetector sharedDetector] getFixedVectorWithG:newCopy];
            dispatch_async(dispatch_get_main_queue(), ^{

                [self setLabelValueX:x y:y z:z];

                [self.lblXY_Quadrant setText:[NSString stringWithFormat:@"%.3f", oneX]];
                [self.lblZX_Quadrant setText:[NSString stringWithFormat:@"%.3f", oneY]];
                [self.lblYZ_Quadrant setText:[NSString stringWithFormat:@"%.3f", oneZ]];
                
//                Point3D__ *pxy = self.arr_xyoffsets[xyQuadrant];
//                Point3D__ *pxz = self.arr_xzoffsets[zxQuadrant];
//                Point3D__ *pyz = self.arr_zyoffsets[yzQuadrant];
//                
//                [_lblDebug setText:[NSString stringWithFormat:@"Qxy %d, Qyz %d, Qzx %d\n(%.2f,%.2f) (%.2f,%.2f) (%.2f,%.2f)", xyQuadrant, yzQuadrant, zxQuadrant, pxy.x, pxy.y, pyz.y, pyz.z, pxz.z, pxz.x]];
                [_lblDebug setText:[NSString stringWithFormat:@"x=%.3f,fx=%.3f\ty=%.3f,fy=%.3f\nz=%.3f,fz=%.3f", x, fixed.x, y, fixed.y, z, fixed.z]];
                
                [self.lblGVec setText:[NSString stringWithFormat:@"%.3f", gVecModule]];
                [self.lblGVecAvg setText:[NSString stringWithFormat:@"%.3f", avg]];
            });
        }
        
        self.dateLastUIRefresh = [NSDate date];
    }
    
    
    
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

- (IBAction)btnShowAVGS:(id)sender {
    [self.viewAllData setHidden:NO];
    self.allDataVisible = YES;
}


- (IBAction)btnHideAVGS:(id)sender {
    [self.viewAllData setHidden:YES];
    self.allDataVisible = NO;
}

- (IBAction)btnPauseGraph:(id)sender {
    self.graphEnabled = !self.graphEnabled;
}

@end
