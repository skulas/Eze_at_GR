//
//  GRAccelerometerOffsetDetector.h
//  MotionGraphs
//
//  Created by Ezequiel Lowi on 12/8/16.
//
//

#import <Foundation/Foundation.h>
typedef struct _GRVector {
    double x;
    double y;
    double z;
    double value;
} GRVector;

@interface GRAccelerometerOffsetDetector : NSObject

+ (instancetype) sharedDetector;
- (void) insertNewSample:(GRVector)vector;
- (GRVector) getFixedVectorWithG:(GRVector)vector;

@end
