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
// static const int kMinNumberOfSamples = 300; // after 3 seconds at 25 samples per second.

// number of areas to split each of the 4 quadrants
// 2: 0<|x|<0.5 or 0.5<|x|<1
static const int kSliceResolution = 2;
static const int kNumberOfQuadrantsInSpace = 4;
//static const int kNumberOfSpacePlanes = 3;
static const int kNumberOfSlices = kSliceResolution * kNumberOfQuadrantsInSpace;
//static const int kNumberOfAxisParts = 2 * kSliceResolution;
//static const int kNumberOfSectors = kNumberOfSpacePlanes * kNumberOfSlices;
//static const int kNumberOfSectorsForEachAxis = 2 * kNumberOfSlices;

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
static long _thresholdRefreshSamplesCounter = 0;
static long kNumberOfSamplesToRefreshThreshold = 200; // 2 seconds at 25 samples per second
static const long kMaxNumberOfSamplesForRegression = 3000;



#pragma mark Internal Classes

@interface MutableArrayWithCounter : NSObject

@property (nonatomic, assign, readonly) NSUInteger numberOfRealValues;
@property (nonatomic, assign, readonly) NSUInteger currentWriteIndex;
@property (nonatomic, assign, readonly) NSUInteger currentReadIndex;
@property (nonatomic, assign, readonly) NSUInteger kMaxNumberOfItems;
@property (nonatomic, strong) NSMutableArray *dotsArray;

- (instancetype) initWithCapacity : (NSUInteger) capacity;

- (void) addObjectToRing:(id)anObject;
- (void) addObject : (id) obj;
- (id) objectAtIx : (NSUInteger) ix;

@end

@implementation MutableArrayWithCounter

- (instancetype) initWithCapacity : (NSUInteger) capacity {
    if (self = [super init]) {
        self.dotsArray = [[NSMutableArray alloc] initWithCapacity:capacity];
        _numberOfRealValues = 0;
        _currentWriteIndex = 0;
        _currentReadIndex = 0;
        _kMaxNumberOfItems = capacity;
    }
    
    return self;
}

- (void) addObject : (id) obj {
    [self.dotsArray addObject:obj];
}

- (void) addObjectToRing:(id)anObject {
    self.dotsArray[self.currentWriteIndex] = anObject;
    if (self.numberOfRealValues < self.currentWriteIndex) {
        _numberOfRealValues = self.currentWriteIndex;
    }
    
    // Update indices for next value
    _currentReadIndex = _currentWriteIndex;
    _currentWriteIndex = _currentWriteIndex == self.kMaxNumberOfItems ? 0 : _currentWriteIndex+1;
}

- (id) objectAtIx : (NSUInteger) ix {
    return self.dotsArray[ix];
}

@end


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



#pragma mark - Private Members

@interface GRAccelerometerOffsetDetector ()

@property (nonatomic, strong) NSArray *arr_X_RegressionValues;
@property (nonatomic, strong) NSArray *arr_Y_RegressionValues;
@property (nonatomic, strong) NSArray *arr_Z_RegressionValues;


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
        NSMutableArray *xArr = [[NSMutableArray alloc] initWithCapacity:kNumberOfSlices];
        NSMutableArray *yArr = [[NSMutableArray alloc] initWithCapacity:kNumberOfSlices];
        NSMutableArray *zArr = [[NSMutableArray alloc] initWithCapacity:kNumberOfSlices];

        for (int ix = 0; ix < kNumberOfSlices; ix++) {
            
            [xArr addObject:[[MutableArrayWithCounter alloc] initWithCapacity:kMaxNumberOfSamplesForRegression]];
            [yArr addObject:[[MutableArrayWithCounter alloc] initWithCapacity:kMaxNumberOfSamplesForRegression]];
            [zArr addObject:[[MutableArrayWithCounter alloc] initWithCapacity:kMaxNumberOfSamplesForRegression]];
        }
      
        self.arr_X_RegressionValues = xArr;
        self.arr_Y_RegressionValues = yArr;
        self.arr_Z_RegressionValues = zArr;
    }
    
    return self;
}


#pragma mark Common Calculations

// Find in which segment based on the resoltion, is the given unit vector component found
- (int) segmentIndexInUnityAxis : (double) unitVectorComponent {
    static const double kResolutionSegmentSize = 1.0 / kSliceResolution; // 1/2
    
    for (int i = -(kSliceResolution - 1), ix = 0; i < (kSliceResolution + 1); i++, ix++) {
        if (unitVectorComponent < (kResolutionSegmentSize * i)) {
            return ix;
        }
    }
    
    return 1; // ERROR
}

/**
 Use this function is used in one of two modes:

 - Log a new meassurement for calculations

 - Calculate a fixed sample based

 @param action Select GRWorkMode insert new sample or get a fix of an input based on history data
 @param x Measured Ax
 @param y Measured Ay
 @param z Measured Az
 @return A point with fixed Ax, Ay, Az
 */
- (Point3D*) action:(GRWorkMode)action WithX:(double)x y:(double)y z:(double)z {
    double gVecModule = sqrt(pow(x, 2)+pow(y, 2)+pow(z, 2));
    Point3D* result = nil;

    
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
    
    
    // DEBUG PRINTOUTS FOR JUMPS DETECTION
    /*
    if (oneX * x < 0) {
        NSLog(@"Different SIGN!!! X");
    }
    if (oneY * y < 0) {
        NSLog(@"Different SIGN!!! Y");
    }
    if (oneZ * z < 0) {
        NSLog(@"Different SIGN!!! Z");
    }
    if (fabs(oneX - x) > fabs(gVecModule - 1)) {
        NSLog(@"DIFFERENT SIZE!!! x");
    }
    if (fabs(oneY - y) > fabs(gVecModule - 1)) {
        NSLog(@"DIFFERENT SIZE!!! y");
    }
    if (fabs(oneZ - z) > fabs(gVecModule - 1)) {
        NSLog(@"DIFFERENT SIZE!!! z");
    }
    */


    if (action == GRWorkModeInserValue) {
        // Calculate the offset for each component from the ideal unit vector
        Point3D *Unit_minus_actual = [[Point3D alloc] init];
        Unit_minus_actual.x = oneX - x;
        Unit_minus_actual.y = oneY - y;
        Unit_minus_actual.z = oneZ - z;
        
        // Save samples to regression vectors
        [self addSampleForRegressionX:x y:y z:z ux:oneX uy:oneY uz:oneZ planeSelect:GRPlaneXY];
        [self addSampleForRegressionX:x y:y z:z ux:oneX uy:oneY uz:oneZ planeSelect:GRPlaneYZ];
        [self addSampleForRegressionX:x y:y z:z ux:oneX uy:oneY uz:oneZ planeSelect:GRPlaneZX];
        
        // Update Threshoulds
        if (_thresholdRefreshSamplesCounter > kNumberOfSamplesToRefreshThreshold) {
            _thresholdRefreshSamplesCounter = 0;
//            [self refreshThresholds];
            // Calculate regression for X accelerator based on plane XY
            NSLog(@"X on XY");
            [self calculateRegressionInPlane:GRPlaneXY referenceUnitVec:oneX useVerticalAxis:NO];
            // Calculate regression for X accelerator based on plan ZX
        }
        _thresholdRefreshSamplesCounter++;
        
    } else {
        
        result = [[Point3D alloc] init];
        // Fix it using linear regression coefficients
        result.x = x;
        result.y = y;
        result.z = z;
    }
    
    return result;
}

- (void) refreshThresholds {
    double currentUpperThrsDelta = _highGThreshold - 1; // Always positive
    double currentLowerThrsDelta = _lowGThreshold - 1; // Always negative
    double possitiveOffsetsAvg = 0;
    double negativeOffsetsAvg = 0;
    
    for (int sliceIx = 0; sliceIx < kNumberOfSlices; sliceIx++) {
        //        double xFix = -100.0, yFix = -100.0, zFix = -100.0;
        
        // XY
        
        
        // YZ
        
        
        // XZ
        
        //        NSLog(@"xfix = %.4f, yfix = %.4f, zfix = %.4f", xFix, yFix, zFix);
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


- (void) TEST_REGRESSION {
    MutableArrayWithCounter *points = [[MutableArrayWithCounter alloc] initWithCapacity:400];
    
    for (int i = 0; i < 201; i++) {
        Point2D *point = [[Point2D alloc] init];
        
        double a = 8.0 - arc4random_uniform(14);
        double b = 1.05;
        point.x = i;
        point.y = b * point.x + a;
        
        [points addObjectToRing:point];
    }
    
    double bias, gain;
    [self linearRegressionOfUserAcceleration:points biasOut:&bias gainOut:&gain];//] planeSelect:GRPlaneXY]; // Expected B = 1.05 A = 1
    NSLog(@"Bias = %.4f, Gain = %.4f", bias, gain);
}

///*
// Planes can be XY, YZ, ZX
// secondAxis ? Y : X   // secondAxis ? X : Z  // secondAxis ? Z : Y
//
// */
- (MutableArrayWithCounter*) dotsArrayForPlane : (GRPlaneSelect) plane
                              absolutSegmentIx : (int) absoluteSegmentIx
                                 getSecondAxis : (BOOL) secondAxis {
//
    MutableArrayWithCounter *arrOut;
    NSArray *axisArr;

    switch (plane) {
        case GRPlaneXY:
            axisArr = secondAxis ? self.arr_Y_RegressionValues : self.arr_X_RegressionValues;
            break;
        case GRPlaneYZ:
            axisArr = secondAxis ? self.arr_Z_RegressionValues : self.arr_Y_RegressionValues;
            break;
        case GRPlaneZX:
            axisArr = secondAxis ? self.arr_X_RegressionValues : self.arr_Z_RegressionValues;
            break;
        default:
            axisArr = nil;
            break;
    }
//
//    
//    if (axisArr != nil) {
//        int quadrantIxFix = secondAxis ? kSliceResolution : 0;
//        int arrIx = (quadrantIx + quadrantIxFix) % kNumberOfAxisParts;
//        
//        
//        arrOut = axisArr[arrIx];
//    }

    int segmentIx;
    if (secondAxis) {
        segmentIx = absoluteSegmentIx + 2 * kSliceResolution;
    } else {
        segmentIx = absoluteSegmentIx;
    }
    
    arrOut = axisArr[segmentIx];
    return arrOut;
}

// Always send first the horizontal Axis (XY -> X, YZ -> Y, ZX -> Z)
- (void) simpleInsertgValue1 : (double) gValue1
                      unit1 : (double) unit1
                    gValue2 : (double) gValue2
                      unit2 : (double) unit2
                 planeSelect : (GRPlaneSelect) plane {
    
    int segment1Ix = [self segmentIndexInUnityAxis:unit1];
    int segment2Ix = [self segmentIndexInUnityAxis:unit2];
    
    MutableArrayWithCounter *dotsArr1 = [self dotsArrayForPlane:plane absolutSegmentIx:segment1Ix getSecondAxis:NO];
    MutableArrayWithCounter *dotsArr2 = [self dotsArrayForPlane:plane absolutSegmentIx:segment2Ix getSecondAxis:YES];
    
    [dotsArr1 addObjectToRing:[Point2D point2dWithX:unit1 andY:gValue1]];
    [dotsArr2 addObjectToRing:[Point2D point2dWithX:unit2 andY:gValue2]];
}

- (void) addSampleForRegressionX : (double) x
                               y : (double) y
                               z : (double) z
                              ux : (double) ux
                              uy : (double) uy
                              uz : (double) uz
                     planeSelect : (GRPlaneSelect) plane {
    
    switch (plane) {
        case GRPlaneXY:
            [self simpleInsertgValue1:x
                                unit1:ux
                              gValue2:y
                                unit2:uy
                          planeSelect:plane];
            
            break;
        case GRPlaneYZ:
            [self simpleInsertgValue1:y
                                unit1:uy
                              gValue2:z
                                unit2:uz
                          planeSelect:plane];
            
            break;
        case GRPlaneZX:
            [self simpleInsertgValue1:z
                                unit1:uz
                              gValue2:x
                                unit2:ux
                          planeSelect:plane];
            
            
            break;
        default:
            break;
    }
}

/** calculateRegressionInPlane
 @brief
 Calculates the Regression of an array of (x,y) pairs. Needs a plane (xy, yz, zx) and a axis selector to chose acceleromeeter.

 A unity vector componet on the desired axis is required to select the range of the accelerometer to calculate the regression.

 Ax Through XY, Ux, FALSE is the same as ZX, Ux, TRUE. Both address the same collection of values (assuming using the same Ux)
 
 @param plane GRPlaneSelect <XY | YZ | ZX> Select a pair of axis
 @param referenceUnitVector Use it to decide the range of the accelerometer (for resolution = 2 there are four ranges: [-1,-0.5], [-0.5,0], [0,0.5], [0.5,1]
 @param verticalAxis Chose which accelerometer in the selected plane. If TRUE: XY => Y, YZ => Z, ZX => X
 */
- (void) calculateRegressionInPlane : (GRPlaneSelect) plane
                   referenceUnitVec : (double) referenceUnitVector
                    useVerticalAxis : (BOOL) verticalAxis {
    
    int absoluteSegmentInAxis = [self segmentIndexInUnityAxis:referenceUnitVector];
    MutableArrayWithCounter *mutableArrayMngr = [self dotsArrayForPlane:plane
                                                            absolutSegmentIx:absoluteSegmentInAxis
                                                         getSecondAxis:verticalAxis];

    double bias, gain;
    [self linearRegressionOfUserAcceleration:mutableArrayMngr
                                     biasOut:&bias
                                     gainOut:&gain];
    
    // Data print outs for debugging
    NSLog(@"Segm: %d. N = %lu. Bias = %.4f, gain = %.4f", (verticalAxis ? absoluteSegmentInAxis + kSliceResolution*2 : absoluteSegmentInAxis), (unsigned long)mutableArrayMngr.numberOfRealValues, bias, gain);
    /*
    if (fabs(bias) > 0.2) {
        NSMutableString *printStr = [NSMutableString stringWithFormat:@"bias = %.4f\n", bias];
        
        for (int ix = 0; ix < mutableArrayMngr.numberOfRealValues; ix++) {
            Point2D *currPoint = [mutableArrayMngr objectAtIx:ix];
            [printStr appendFormat:@" (x,ux) = %.4f,%.4f \n", currPoint.y, currPoint.x];
        }
        NSLog(@"%@", printStr);
        NSLog(@"----");
    }
     */
    
}

- (void) linearRegressionOfUserAcceleration : (MutableArrayWithCounter*) pointsArray biasOut : (double*) outBias gainOut : (double*) outGain
{
    NSUInteger n = pointsArray.numberOfRealValues;
    double ax, ay, sX = 0, sY = 0, ssX = 0, ssY = 0, ssXY = 0, avgX, avgY;
    
    if (n ==0) {
        *outBias = -1234;
        *outGain = -1234;
        return;
    }
    
    // Sum of squares X, Y & X*Y
    for (NSUInteger i = 0; i < n; i++)
    {
        Point2D *currPoint = [pointsArray objectAtIx:i];
        
        ax = currPoint.x;
        ay = currPoint.y;
        
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
    
    *outGain = b;
    *outBias = a;
  //  double theta = atan2(1, b);
    
    
    // Correlationcoefficent gives the quality of the estimate: 1 = perfect to 0 = no fit
//    double corCoeff = (ssXY * ssXY) / (ssX * ssY);
//    
//    NSLog(@"n: %lu, a: %f --- b: %f --- cor: %f   --- avgX: %f -- avgY: %f --- ssX: %f - ssY: %f - ssXY: %f", (unsigned long)n, a, b, corCoeff, avgX, avgY, ssX, ssY, ssXY);
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


