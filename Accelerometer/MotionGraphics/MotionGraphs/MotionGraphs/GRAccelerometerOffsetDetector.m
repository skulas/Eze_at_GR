//
//  GRAccelerometerOffsetDetector.m
//  Axlrator manipulations
//
//  Created by Ezequiel Lowi on 12/8/16.
//
//

#import "GRAccelerometerOffsetDetector.h"


#pragma mark - Internals

typedef NS_ENUM(NSInteger, GRPlaneSelect) {
    GRPLaneNotSet,
    GRPlaneXY,
    GRPlaneYZ,
    GRPlaneZX
};

//typedef NS_ENUM(NSInteger, GRAxisSelect) {
//    GRAxisNotSet,
//    GRAxisX,
//    GRAxisY,
//    GRAxisZ
//};
//

typedef NS_ENUM(NSInteger, GRWorkMode) {
    GRWorkModeNotSet,
    GRWorkModeInserValue,
    GRWorkModeFixInput
};


#pragma mark Constants

// Minimal number of samples to start using the average of samples
static const int kMinNumberOfSamples = 300; // after 3 seconds at 25 samples per second.

// number of areas to split each of the 4 quadrants
// 2: 0<|x|<0.5 or 0.5<|x|<1
static const int kSliceResolution = 2;
static const int kNumberOfQuadrantsInSpace = 4;
static const int kNumberOfSpacePlanes = 3;
static const int kNumberOfSlices = kSliceResolution * kNumberOfQuadrantsInSpace;
static const int kNumberOfSectors = kNumberOfSpacePlanes * kNumberOfSlices;
static const int kNumberOfSectorsForEachAxis = 2 * kNumberOfSlices;

/*
 Any sample of G vector that the module of the vector (the size) exeeds these limits
 too small or too large, the sample will be ignored.
 NOTE:
 If an accelerometer has an offset bigger than these values the detection will truncate the offset value.
 */
static const double kLowGThresFirstValue = 0.9;
static const double kHighGThresFirstValue = 1.1;

static double _lowGThreshold = kLowGThresFirstValue;
static double _highGThreshold = kHighGThresFirstValue;
//static long _thresholdRefreshSamplesCounter = 0;
//static long kNumberOfSamplesToRefreshThreshold = 200; // 2 seconds at 25 samples per second
static const long kMaxNumberOfSamplesForRegression = 2000;



#pragma mark Internal Classes

@interface Point2D : NSObject

@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;

+ (instancetype) point2dWithX : (double) x andY : (double) y;
@end

@implementation Point2D

+ (instancetype) point2dWithX : (double) x andY : (double) y {
    Point2D* point = [[Point2D alloc] init];
    
    point.x = x;
    point.y = y;
    
    return point;
}

@end


@interface Point3D : NSObject

@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;
@property (nonatomic, assign) double z;

+ (Point3D*) Zeroes;
- (instancetype) initWithPoint : (Point3D*) point;

- (void) updateWithPoint : (Point3D*) point;

@end

@implementation Point3D

+ (Point3D*) Zeroes {
    Point3D *zeroes = [[Point3D alloc] init];
    
    zeroes.x = 0;
    zeroes.y = 0;
    zeroes.z = 0;
    
    return zeroes;
}

- (instancetype) initWithPoint : (Point3D*) point {
    Point3D *newPoint = [[Point3D alloc] init];
    newPoint.x = point.x;
    newPoint.y = point.y;
    newPoint.z = point.z;
    
    return newPoint;
}

- (void) updateWithPoint : (Point3D*) point {
    self.x = point.x;
    self.y = point.y;
    self.z = point.z;
}

@end


@interface GRAccelerometerOffsetDetector ()

@property (nonatomic, strong) NSMutableArray *arr_xyoffsets;
@property (nonatomic, strong) NSMutableArray *arr_xyCounters;
@property (nonatomic, strong) NSMutableArray *arr_xzoffsets;
@property (nonatomic, strong) NSMutableArray *arr_xzCounters;
@property (nonatomic, strong) NSMutableArray *arr_zyoffsets;
@property (nonatomic, strong) NSMutableArray *arr_zyCounters;

@property (nonatomic, strong) NSMutableArray *arr_X_RegressionValues;
@property (nonatomic, strong) NSMutableArray *arr_X_RegressionIndices;
@property (nonatomic, strong) NSMutableArray *arr_Y_RegressionValues;
@property (nonatomic, strong) NSMutableArray *arr_Y_RegressionIndices;
@property (nonatomic, strong) NSMutableArray *arr_Z_RegressionValues;
@property (nonatomic, strong) NSMutableArray *arr_Z_RegressionIndices;


@end


#pragma mark - Begin Implementation

@implementation GRAccelerometerOffsetDetector


#pragma mark - life cycle

- (instancetype) init {
    NSLog(@"Error: Don't instantiate. Get the unique reference using [GRAccelerometerOffsetDetector sharedDetector");
    
    return nil;
}

- (instancetype) init:(int)flagToMakeItPrivate {
    if (self = [super init]) {
        self.arr_xyoffsets = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_xyCounters = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_xzoffsets = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_xzCounters = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_zyoffsets = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_zyCounters = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        
        self.arr_X_RegressionValues = [NSMutableArray arrayWithCapacity:kNumberOfSectorsForEachAxis];
        self.arr_Y_RegressionValues = [NSMutableArray arrayWithCapacity:kNumberOfSectorsForEachAxis];
        self.arr_Z_RegressionValues = [NSMutableArray arrayWithCapacity:kNumberOfSectorsForEachAxis];
        self.arr_X_RegressionIndices = [NSMutableArray arrayWithCapacity:kNumberOfSectorsForEachAxis];
        self.arr_Y_RegressionIndices = [NSMutableArray arrayWithCapacity:kNumberOfSectorsForEachAxis];
        self.arr_Z_RegressionIndices = [NSMutableArray arrayWithCapacity:kNumberOfSectorsForEachAxis];
        
        for (int ix = 0; ix < kNumberOfSlices; ix++) {
            self.arr_xyoffsets[ix] = [Point3D Zeroes];
            self.arr_xzoffsets[ix] = [Point3D Zeroes];
            self.arr_zyoffsets[ix] = [Point3D Zeroes];
            
            self.arr_xyCounters[ix] = @(0);
            self.arr_xzCounters[ix] = @(0);
            self.arr_zyCounters[ix] = @(0);
        }
        
        for (int ix = 0; ix < kNumberOfSectorsForEachAxis; ix++) {
            self.arr_X_RegressionValues[ix] = [NSMutableArray arrayWithCapacity:kMaxNumberOfSamplesForRegression];
            self.arr_Y_RegressionValues[ix] = [NSMutableArray arrayWithCapacity:kMaxNumberOfSamplesForRegression];
            self.arr_Z_RegressionValues[ix] = [NSMutableArray arrayWithCapacity:kMaxNumberOfSamplesForRegression];
            
            self.arr_X_RegressionIndices[ix] = @(0);
            self.arr_Y_RegressionIndices[ix] = @(0);
            self.arr_Z_RegressionIndices[ix] = @(0);
        }
    }
    
    return self;
}


#pragma mark Common Calculations

// Build as averages for each segment of each quadrant separately.
// Use infinite avg (the comment out) and not sliding windows.
- (double) avgCalcNewValue:(double) newVal currentAvg: (double) currAvg numberOfsamples: (long) currSampleCounter {
    double result = (currAvg * currSampleCounter + newVal) / (currSampleCounter + 1);
    
    return result;
}

- (double) choseBestOptionA : (double) optA optionB : (double) optB {
    double choice = fabs(optB) > fabs(optA) ? optB : optA;
    
    return choice;
}

- (int) sliceIndexInPlane : (double) theta {
    int q_found = -1;
    static double sliceSize = M_PI_2 / kSliceResolution;
    int rndResolution = kSliceResolution;
    double fixedTheta = theta;
    int q_0;
    double startQComparator, currSliceTopLimit;
    
    if (theta < 0) {
        fixedTheta = 2 * M_PI + theta;
        q_0 = 2 * rndResolution;
        startQComparator = sliceSize + M_PI;
    } else {
        fixedTheta = theta;
        startQComparator = sliceSize;
        q_0 = 0;
    }
    
    currSliceTopLimit = startQComparator;
    
    // searching half space
    int kNumberOfQuadrantsToScan = 2;
    int kNumberOfSlicesToCheck = kNumberOfQuadrantsToScan * rndResolution;
    for (int q_ix = 1; q_ix < kNumberOfSlicesToCheck; q_ix++) {
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

/** Calculate three separate avg for newPoint values
 * @param newPoint: NormGVec - UnitVec in the same direction (x,y,z)
 * @param plane: Select which plane (xy, yz, zx) you are currently working on.
 * @param quadrantSliceIx: Which section of the spce (resolution * 4 sections. 4 as there are 4 quadrants (++, -+, -- , +-)
 *
 */
- (Point3D*) updateAvgSpaceSelect : (GRPlaneSelect) plane newPoint : (Point3D*) p3d quadrantSliceIx : (int) currSliceInQuadrant {
    NSMutableArray *currOffsetArr = nil;
    NSMutableArray *currCountersArr = nil;
    Point3D *newVal = [Point3D Zeroes];
    long currCounter;
    
    switch (plane) {
        case GRPlaneXY:
        {
            currOffsetArr = self.arr_xyoffsets;
            currCountersArr = self.arr_xyCounters;
            Point3D *currVal = currOffsetArr[currSliceInQuadrant];
            currCounter = [currCountersArr[currSliceInQuadrant] longValue];
            
            newVal.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:currCounter];
            newVal.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:currCounter];
        }
            
            break;
        case GRPlaneZX:
        {
            currOffsetArr = self.arr_xzoffsets;
            currCountersArr = self.arr_xzCounters;
            Point3D *currVal = currOffsetArr[currSliceInQuadrant];
            currCounter = [currCountersArr[currSliceInQuadrant] longValue];
            
            newVal.x = [self avgCalcNewValue:p3d.x currentAvg:currVal.x numberOfsamples:currCounter];
            newVal.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:currCounter];
        }
            
            break;
        case GRPlaneYZ:
        {
            currOffsetArr = self.arr_zyoffsets;
            currCountersArr = self.arr_zyCounters;
            Point3D *currVal = currOffsetArr[currSliceInQuadrant];
            currCounter = [currCountersArr[currSliceInQuadrant] longValue];
            
            newVal.y = [self avgCalcNewValue:p3d.y currentAvg:currVal.y numberOfsamples:currCounter];
            newVal.z = [self avgCalcNewValue:p3d.z currentAvg:currVal.z numberOfsamples:currCounter];
        }
            
            break;
        default:
            NSLog(@"WRONG SPACE");
            return newVal;
            break;
    }
    
    currCountersArr[currSliceInQuadrant] = @(currCounter + 1);
    currOffsetArr[currSliceInQuadrant] = newVal;
    
    return newVal;
}

- (long) readAvgSpaceSelect : (GRPlaneSelect) plane outputPoint : (Point3D*) outPoint quadrantSliceIx : (int) currSliceInQuadrant {
    NSMutableArray *currOffsetArr = nil;
    NSMutableArray *currCountersArr = nil;
    Point3D *currVal;
    long currCounter;
    
    switch (plane) {
        case GRPlaneXY:
            currOffsetArr = self.arr_xyoffsets;
            currCountersArr = self.arr_xyCounters;
            
            break;
        case GRPlaneZX:
            currOffsetArr = self.arr_xzoffsets;
            currCountersArr = self.arr_xzCounters;
            
            break;
        case GRPlaneYZ:
            currOffsetArr = self.arr_zyoffsets;
            currCountersArr = self.arr_zyCounters;
            
            break;
        default:
            NSLog(@"WRONG SPACE");
            return -0xBAD;
            break;
    }
    
    currVal = currOffsetArr[currSliceInQuadrant];
    currCounter = [currCountersArr[currSliceInQuadrant] longValue];
    
    [outPoint updateWithPoint:currVal];
    
    return currCounter;
}


- (Point3D*) action:(GRWorkMode)action WithX:(double)x y:(double)y z:(double)z {
    double gVecModule = sqrt(pow(x, 2)+pow(y, 2)+pow(z, 2));
    Point3D* result = nil;

    [self TEST_REGRESSION];

    
    //
    // If values exceed some logical threshold ignore the sample
    //
    
    if ( (action == GRWorkModeInserValue) && ( (gVecModule < _lowGThreshold) || (_highGThreshold < gVecModule) ) ) {
        return result;
    }
    
    
    //
    // Find theta and phi angles
    //
    
    double gVec_xy = sqrt(pow(x, 2)+pow(y, 2));
    double theta_xy = atan2(y,x);
    double theta_zx = atan2(x,z);
    double theta_yz = atan2(z,y);
    double sin_phi = gVec_xy / gVecModule; // Always +
    double phi = asin(sin_phi);     // Always +
    
    // Fix phi
    if (z < 0) {
        if (theta_xy > 0)
            phi = M_PI - phi;
        else
            phi = phi - M_PI;
    } else {
        if (theta_xy < 0)
            phi = - phi;
    }
    
    
    
    //
    // Detect Offstes for each axis
    //
    
    // Calculate componets of unit vector in the direction of given G vector
    double oneX = sin_phi * cos(theta_xy);
    double oneY = sin_phi * sin(theta_xy);
    double oneZ = cos(phi);
    

    // Find G quadrant for each plane
    int xySliceIxInPlane = [self sliceIndexInPlane:theta_xy];
    int zxSliceIxInPlane = [self sliceIndexInPlane:theta_zx];
    int yzSliceIxInPlane = [self sliceIndexInPlane:theta_yz];

    if (action == GRWorkModeInserValue) {
        // Calculate the offset for each component from the ideal unit vector
        Point3D *Unit_minus_actual = [[Point3D alloc] init];
        Unit_minus_actual.x = oneX - x;
        Unit_minus_actual.y = oneY - y;
        Unit_minus_actual.z = oneZ - z;

        // Add a sample to each average according to
        [self updateAvgSpaceSelect:GRPlaneXY newPoint:Unit_minus_actual quadrantSliceIx:xySliceIxInPlane];
        [self updateAvgSpaceSelect:GRPlaneZX newPoint:Unit_minus_actual quadrantSliceIx:zxSliceIxInPlane];
        [self updateAvgSpaceSelect:GRPlaneYZ newPoint:Unit_minus_actual quadrantSliceIx:yzSliceIxInPlane];
        
        [self addSampleForRegressionX:x y:y z:z ux:oneX uy:oneY uz:oneZ planeSelect:GRPlaneXY slice:xySliceIxInPlane];
        [self addSampleForRegressionX:x y:y z:z ux:oneX uy:oneY uz:oneZ planeSelect:GRPlaneYZ slice:yzSliceIxInPlane];
        [self addSampleForRegressionX:x y:y z:z ux:oneX uy:oneY uz:oneZ planeSelect:GRPlaneZX slice:zxSliceIxInPlane];
        
        // Update Threshoulds
        //        if (_thresholdRefreshSamplesCounter > kNumberOfSamplesToRefreshThreshold) {
        //            _thresholdRefreshSamplesCounter = 0;
        //            [self refreshThresholds];
        //        }
        //        _thresholdRefreshSamplesCounter++;
        
    } else {
        double offsetX = 0.0, offsetY = 0.0, offsetZ = 0.0;
        Point3D *currVal = [Point3D Zeroes];
        long currCounter = [self readAvgSpaceSelect:GRPlaneXY outputPoint:currVal quadrantSliceIx:xySliceIxInPlane];
        
        if (currCounter > kMinNumberOfSamples) {
            offsetX = currVal.x;
            offsetY = currVal.y;
        }

        currVal = [Point3D Zeroes];
        currCounter = [self readAvgSpaceSelect:GRPlaneYZ outputPoint:currVal quadrantSliceIx:yzSliceIxInPlane];
        
        if (currCounter > kMinNumberOfSamples) {
            offsetZ = currVal.z;
            offsetY = [self choseBestOptionA:currVal.y optionB:offsetY];
        }
        
        currVal = [Point3D Zeroes];
        currCounter = [self readAvgSpaceSelect:GRPlaneZX outputPoint:currVal quadrantSliceIx:zxSliceIxInPlane];
        
        if (currCounter > kMinNumberOfSamples) {
            offsetZ = [self choseBestOptionA:offsetZ optionB:currVal.z];
            offsetX = [self choseBestOptionA:currVal.x optionB:offsetX];
        }
        
        result = [[Point3D alloc] init];
        result.x = x - offsetX;
        result.y = y - offsetY;
        result.z = z - offsetZ;
    }
    
    return result;
}

- (void) refreshThresholds {
    double currentUpperThrsDelta = _highGThreshold - 1; // Always positive
    double currentLowerThrsDelta = _lowGThreshold - 1; // Always negative
    double possitiveOffsetsAvg = 0;
    double negativeOffsetsAvg = 0;
    
    for (int sliceIx = 0; sliceIx < kNumberOfSlices; sliceIx++) {
        double xFix = -100.0, yFix = -100.0, zFix = -100.0;
        
        // XY
        long currCounter = [self.arr_xyCounters[sliceIx] longValue];
        
        if (currCounter > kMinNumberOfSamples) {
            Point3D *xyPoint = self.arr_xyoffsets[sliceIx];
            xFix = xyPoint.x;
            yFix = xyPoint.y;
        }
        
        
        // YZ
        currCounter = [self.arr_zyCounters[sliceIx] longValue];
        
        if (currCounter > kMinNumberOfSamples) {
            Point3D *zyPoint = self.arr_zyoffsets[sliceIx];
            yFix = [self choseBestOptionA:yFix optionB:zyPoint.y];
            zFix = zyPoint.z;
        }
        
        
        // XZ
        currCounter = [self.arr_xzCounters[sliceIx] longValue];
        
        if (currCounter > kMinNumberOfSamples) {
            Point3D *xzPoint = self.arr_xzoffsets[sliceIx];
            xFix = [self choseBestOptionA:xFix optionB:xzPoint.x];
            zFix = [self choseBestOptionA:zFix optionB:xzPoint.z];
        }
        
        NSLog(@"xfix = %.4f, yfix = %.4f, zfix = %.4f", xFix, yFix, zFix);
        [self updatePosAvg:&possitiveOffsetsAvg andNegPos:&negativeOffsetsAvg withFix:xFix currUp:currentUpperThrsDelta currLow:currentLowerThrsDelta];
        [self updatePosAvg:&possitiveOffsetsAvg andNegPos:&negativeOffsetsAvg withFix:yFix currUp:currentUpperThrsDelta currLow:currentLowerThrsDelta];
        [self updatePosAvg:&possitiveOffsetsAvg andNegPos:&negativeOffsetsAvg withFix:zFix currUp:currentUpperThrsDelta currLow:currentLowerThrsDelta];
    }
    
    
//    NSLog(@"Upper delta before: %.4f", currentUpperThrsDelta);
    currentUpperThrsDelta = (currentUpperThrsDelta + possitiveOffsetsAvg) / 2;
    _highGThreshold = 1 + currentUpperThrsDelta;
//    NSLog(@"Upper delta after: %.4f", currentUpperThrsDelta);
    
//    NSLog(@"Lower delta before: %.4f", currentLowerThrsDelta);
    currentLowerThrsDelta = (currentLowerThrsDelta + negativeOffsetsAvg) / 2;
    _lowGThreshold = 1 + currentLowerThrsDelta;
    //    NSLog(@"Lower delta after: %.4f", currentLowerThrsDelta);
//    NSLog(@"Lower delta after: %.4f", currentLowerThrsDelta);
    
//    NSLog(@"Updated Up Thr: %.3f --- Low Thr: %.3f", _highGThreshold, _lowGThreshold);
}

- (void) updatePosAvg : (double*) possitiveAvg andNegPos : (double*) negAvg withFix : (double) fix currUp : (double) currentUpperThrsDelta currLow : (double) currentLowerThrsDelta {
    static double defaultLowValue = (kLowGThresFirstValue - 1.0) / kNumberOfSectors;
    static double defaultHighValue = (kHighGThresFirstValue - 1.0) / kNumberOfSectors;
    
    if (fix < -90) { // Detect there's no value. Conserve current value
        *possitiveAvg += defaultHighValue;
        *negAvg += defaultLowValue;
    } else if (fix > 0) {
        *possitiveAvg += fix / kNumberOfSectors;
//        *negAvg += defaultLowValue;
    } else if (fix < 0) {
//        *possitiveAvg += defaultHighValue;
        *negAvg += fix / kNumberOfSectors;
    }
}


- (void) TEST_REGRESSION {
    NSMutableArray *points = [NSMutableArray arrayWithCapacity:200];
    
    for (int i = 0; i < 201; i++) {
        Point3D *point = [Point3D Zeroes];
        
        double a = 8.0 - arc4random_uniform(14);
        double b = 1.05;
        point.x = i;
        point.y = b * point.x + a;
        
        [points addObject:point];
    }
    
    [self linearRegressionOfUserAcceleration:points planeSelect:GRPlaneXY]; // Expected B = 1.05 A = 1
}

- (void) addSampleForRegressionX : (double) x
                               y : (double) y
                               z : (double) z
                              ux : (double) ux
                              uy : (double) uy
                              uz : (double) uz
                     planeSelect : (GRPlaneSelect) plane slice : (NSUInteger) sliceIx {
    //    NSMutableArray *v1, *v2;
    NSUInteger ix1, ix2;
    NSUInteger secondIx = sliceIx + kNumberOfSlices;
    
    switch (plane) {
        case GRPlaneXY:
            ix1 = [self.arr_X_RegressionIndices[sliceIx] longValue];
            ix2 = [self.arr_Y_RegressionIndices[secondIx] longValue];
            
            self.arr_X_RegressionValues[ix1] = [Point2D point2dWithX:ux andY:x];
            self.arr_Y_RegressionValues[ix2] = [Point2D point2dWithX:uy andY:y];
            
            self.arr_X_RegressionIndices[sliceIx] = @((ix1 + 1) % kMaxNumberOfSamplesForRegression);
            self.arr_Y_RegressionIndices[secondIx] = @((ix2 + 1) % kMaxNumberOfSamplesForRegression);

            
            break;
        case GRPlaneYZ:
            ix1 = [self.arr_Y_RegressionIndices[sliceIx] longValue];
            ix2 = [self.arr_Z_RegressionIndices[secondIx] longValue];
            
            self.arr_Y_RegressionValues[ix1] = [Point2D point2dWithX:uy andY:y];
            self.arr_Z_RegressionValues[ix2] = [Point2D point2dWithX:uz andY:z];
            
            self.arr_Y_RegressionIndices[sliceIx] = @((ix1 + 1) % kMaxNumberOfSamplesForRegression);
            self.arr_Z_RegressionIndices[secondIx] = @((ix2 + 1) % kMaxNumberOfSamplesForRegression);
            
            
            break;
        case GRPlaneZX:
            ix1 = [self.arr_Z_RegressionIndices[sliceIx] longValue];
            ix2 = [self.arr_X_RegressionIndices[secondIx] longValue];
            
            self.arr_Z_RegressionValues[ix1] = [Point2D point2dWithX:uz andY:z];
            self.arr_X_RegressionValues[ix2] = [Point2D point2dWithX:ux andY:x];
            
            self.arr_Z_RegressionIndices[sliceIx] = @((ix1 + 1) % kMaxNumberOfSamplesForRegression);
            self.arr_X_RegressionIndices[secondIx] = @((ix2 + 1) % kMaxNumberOfSamplesForRegression);
            
            
            break;
        default:
            break;
    }
    
}

- (void) linearRegressionOfUserAcceleration : (NSArray*) pointsArray planeSelect : (GRPlaneSelect) plane
{
    NSUInteger n = pointsArray.count;
    double ax, ay, sX = 0, sY = 0, ssX = 0, ssY = 0, ssXY = 0, avgX, avgY;
    
    // Sum of squares X, Y & X*Y
    for (NSUInteger i = 0; i < n; i++)
    {
        Point3D *currPoint = pointsArray[i];
        
        switch (plane) {
            case GRPlaneXY:
                ax = currPoint.x;
                ay = currPoint.y;
                break;
            case GRPlaneYZ:
                ax = currPoint.y;
                ay = currPoint.z;
                break;
            case GRPlaneZX:
                ax = currPoint.z;
                ay = currPoint.x;
                break;
            default:
                ax = 0;
                ay = 0;
                break;
        }
        
        sX += ax;
        sY += ay;
        ssX += ax * ax;
        ssY += ay * ay;
        ssXY += ax * ay;
    }
    
    avgX = sX / n;
    avgY = sY / n;
    // radius = hypot(avgX, avgY);
    ssX = ssX - n * (avgX * avgX);
    ssY = ssY - n * (avgY * avgY);
    ssXY = ssXY - n * avgX * avgY;
    
    // Best fit of line y_i = a + b * x_i
    double b = ssXY / ssX;
    double a = (avgY - b * avgX);
  //  double theta = atan2(1, b);
    
    
    // Correlationcoefficent gives the quality of the estimate: 1 = perfect to 0 = no fit
    double corCoeff = (ssXY * ssXY) / (ssX * ssY);
    
    NSLog(@"n: %lu, a: %f --- b: %f --- cor: %f   --- avgX: %f -- avgY: %f --- ssX: %f - ssY: %f - ssXY: %f", (unsigned long)n, a, b, corCoeff, avgX, avgY, ssX, ssY, ssXY);
}


#pragma mark - Interface

+ (instancetype) sharedDetector {
    static GRAccelerometerOffsetDetector* sharedDetector = nil;
    static dispatch_once_t onceToken;
    
    if (sharedDetector == nil) {
        dispatch_once(&onceToken, ^{
            sharedDetector = [[GRAccelerometerOffsetDetector alloc] init:0];
        });
    }
    
    return sharedDetector;
}

- (void) insertNewSample:(GRVector)vector {
    [self action:GRWorkModeInserValue WithX:vector.x y:vector.y z:vector.z];
}

- (GRVector) getFixedVectorWithG:(GRVector)vector {
    Point3D *fixed = [self action:GRWorkModeFixInput WithX:vector.x y:vector.y z:vector.z];
    GRVector fixedGVecOut = {fixed.x, fixed.y, fixed.z};
    
    return fixedGVecOut;
}



@end


