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
    GRPlaneZX,
};

typedef NS_ENUM(NSInteger, GRWorkMode) {
    GRWorkModeNotSet,
    GRWorkModeInserValue,
    GRWorkModeFixInput
};


#pragma mark Constants

// number of areas to split each of the 4 quadrants
// 2: 0<|x|<0.5 or 0.5<|x|<1
static const int kSliceResolution = 2;


/*
 Any sample of G vector that the module of the vector (the size) exeeds these limits
 too small or too large, the sample will be ignored.
 NOTE:
 If an accelerometer has an offset bigger than these values the detection will truncate the offset value.
 */
static const double kLowGThreshold = 0.9;
static const double kHighGThreshold = 1.1;



#pragma mark Internal Classes

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
        int kNumberOfQuadrantsInSpace = 4;
        int kNumberOfSlices = kSliceResolution * kNumberOfQuadrantsInSpace;
        
        self.arr_xyoffsets = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_xyCounters = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_xzoffsets = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_xzCounters = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_zyoffsets = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        self.arr_zyCounters = [NSMutableArray arrayWithCapacity:kNumberOfSlices];
        
        for (int ix = 0; ix < kNumberOfSlices; ix++) {
            self.arr_xyoffsets[ix] = [Point3D Zeroes];
            self.arr_xzoffsets[ix] = [Point3D Zeroes];
            self.arr_zyoffsets[ix] = [Point3D Zeroes];
            self.arr_xyCounters[ix] = @(0);
            self.arr_xzCounters[ix] = @(0);
            self.arr_zyCounters[ix] = @(0);
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
    //
    // If values exceed some logical threshold ignore the sample
    //
    
    if ( (action == GRWorkModeInserValue) && ( (gVecModule < kLowGThreshold) || (kHighGThreshold < gVecModule) ) ) {
        NSLog(@"Strong force detected, skipping sample");
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
    
    // Calculate the offset for each component from the ideal unit vector
    Point3D *Unit_minus_actual = [[Point3D alloc] init];
    Unit_minus_actual.x = oneX - x;
    Unit_minus_actual.y = oneY - y;
    Unit_minus_actual.z = oneZ - z;

    // Find G quadrant for each plane
    int xyQuadrant = [self sliceIndexInPlane:theta_xy];
    int zxQuadrant = [self sliceIndexInPlane:theta_zx];
    int yzQuadrant = [self sliceIndexInPlane:theta_yz];

    if (action == GRWorkModeInserValue) {
        // Add a sample to each average according to
        [self updateAvgSpaceSelect:GRPlaneXY newPoint:Unit_minus_actual quadrantSliceIx:xyQuadrant];
        [self updateAvgSpaceSelect:GRPlaneZX newPoint:Unit_minus_actual quadrantSliceIx:zxQuadrant];
        [self updateAvgSpaceSelect:GRPlaneYZ newPoint:Unit_minus_actual quadrantSliceIx:yzQuadrant];
    } else {
        static const int kMinNumberOfSamples = 1000;
        double offsetX = 0.0, offsetY = 0.0, offsetZ = 0.0;
        Point3D *currVal = [Point3D Zeroes];
        long currCounter = [self readAvgSpaceSelect:GRPlaneXY outputPoint:currVal quadrantSliceIx:xyQuadrant];
        
        if (currCounter > kMinNumberOfSamples) {
            offsetX = currVal.x;
            offsetY = currVal.y;
        }

        currVal = [Point3D Zeroes];
        currCounter = [self readAvgSpaceSelect:GRPlaneYZ outputPoint:currVal quadrantSliceIx:yzQuadrant];
        
        if (currCounter > kMinNumberOfSamples) {
            offsetZ = currVal.z;
            offsetY = fabs(currVal.y) > fabs(offsetY) ? currVal.y : offsetY; // Use the biggest offset.
        }
        
        currVal = [Point3D Zeroes];
        currCounter = [self readAvgSpaceSelect:GRPlaneZX outputPoint:currVal quadrantSliceIx:zxQuadrant];
        
        if (currCounter > kMinNumberOfSamples) {
            offsetZ = fabs(currVal.z) > fabs(offsetZ) ? currVal.z : offsetZ; // Use the biggest offset.
            offsetX = fabs(currVal.x) > fabs(offsetX) ? currVal.x : offsetX; // Use the biggest offset.
        }
        
        result = [[Point3D alloc] init];
        result.x = x - offsetX;
        result.y = y - offsetY;
        result.z = z - offsetZ;
    }
    
    return result;
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


