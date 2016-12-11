//
//  HSDLProxyManager.m
//  HelloSDL
//
//  Created by Ford Developer on 10/5/15.
//  Copyright © 2015 Ford. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HSDLProxyManager.h"
@import SmartDeviceLink_iOS;
#import "GREventsGenerator.h"

// Boot order
typedef NS_OPTIONS(NSUInteger, GRBootSteps) {
    GRBootNotStarted            = 0,
    GRBootStepAppInterface      = 1 << 0,
    GRBootStepHMIStatus         = 1 << 1
};

static const GRBootSteps kBootStatusReady = GRBootStepHMIStatus | GRBootStepAppInterface;
static GRBootSteps bootStatus = GRBootNotStarted;

// Delay between auto generated events.
static const double kDelayBetweenEvents = 4;
static const double kDelayToResetToDriving = 6;


// TCP/IP (Emulator) configuration
static NSString *const RemotePort = @"12345";

// App configuration
static NSString *const AppName = @"GreenRoad SDL";
static NSString *const AppId = @"8675309";
static const BOOL AppIsMediaApp = NO;
static NSString *const ShortAppName = @"GreenRoad";
static NSString *const AppVrSynonym = @"Hello S D L";
static NSString *const IconFile = @"green_road_logo"; // @"sdl_icon.png";
static const NSUInteger AppIconIdInt = 0xA96A;

// Welcome message
static NSString *const WelcomeShow = @"Welcome to GreenRoad";
static NSString *const WelcomeSpeak = @"Welcome to Green Road";
// Sample AddCommand
static NSString *const TestCommandName = @"Test Command";
static const NSUInteger TestCommandID = 1;

// Begin Drive Command
static NSString *const BeginDriveCommandName = @"Begin Drive";
static const NSUInteger BeginDriveCommandID = 2;
static NSString *const strBeginTripText = @"GreenRoad trip started";
static NSString *const strBeginTripVoice = @"GreenRoad trip started";

// Drive States
static NSString *const strCorneringText = @"Cornering";
static NSString *const strCorneringVoice = @"Cornering";

// Test Alert
static const NSUInteger TestAlertButtonID = 0xB52;

/**
        IMAGES
 **/
// Events
static NSString *const imgEventAxl = @"event_axl";
static NSString *const imgEventBrake = @"event_brake";
static NSString *const imgEventCornerRight = @"event_corner_right";
static NSString *const imgEventCornerLeft = @"event_corner_left";
static NSString *const imgDrivingGreenImgFilename = @"DrivingGreen";
static NSString *const imgDrivingYellowImgFilename = @"DrivingYellow";
static NSString *const imgDrivingRedImgFilename = @"DrivingRed";
static NSString *const imgDriveSafeGreen = @"DriveSafeGreen";
static NSString *const imgCorneringGreen = @"CorneringGreen";

static const int imgIdDrivingGreen = 15894239;
static const int imgIdDrivingYellow = 15894240;
static const int imgIdDrivingRed = 15894241;
static const int imgIdDriveSafe = 0xD65173;
static const int imgIdEmpty = 4321234;
static const int imgIdAxl = 0xBADA55;
static const int imgIdBrake = 0xBEAC5;
static const int imgIdCornerLeft = 0x7EF7;
static const int imgIdCornerRight = 0x17E1;
static const int imgIdCorneringGreen = 0x5AD0;


static const int scoreButtonId = 0xB077;


// Notifications used to show/hide lockscreen in the AppDelegate
NSString *const HSDLDisconnectNotification = @"com.sdl.notification.sdldisconnect";
NSString *const HSDLLockScreenStatusNotification = @"com.sdl.notification.sdlchangeLockScreenStatus";
NSString *const HSDLNotificationUserInfoObject = @"com.sdl.notification.keys.sdlnotificationObject";

@interface HSDLProxyManager () <SDLProxyListener, GREventsGeneratorDelegate>

@property (nonatomic, strong) SDLProxy *proxy;
@property (nonatomic, assign) NSUInteger correlationID;
@property (nonatomic, strong) NSNumber *appIconId;
@property (nonatomic, strong) NSMutableSet *remoteImages;
@property (nonatomic, assign, getter=isGraphicsSupported) BOOL graphicsSupported;
@property (nonatomic, assign, getter=isFirstHmiFull) BOOL firstHmiFull;
@property (nonatomic, assign, getter=isFirstHmiNotNone) BOOL firstHmiNotNone;
@property (nonatomic, assign, getter=isVehicleDataSubscribed) BOOL vehicleDataSubscribed;
@property(nonatomic, strong) NSString *RemoteIpAddress;
@property (nonatomic, strong) NSMutableArray *uploadsQueue;

@property (nonatomic, assign) BOOL tripStarted;

@property (nonatomic, strong) NSString *strTiresStatus;
@property (nonatomic, strong) SDLImage *sdlImgCurrentImage;
@property (nonatomic, strong) NSString *strStickyFirstLine;

@end

@implementation HSDLProxyManager

#pragma mark Lifecycle

/**
 *  Singleton method.
 */
+ (instancetype)manager {
    static HSDLProxyManager *proxyManager = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      proxyManager = [[self alloc] init];
    });

    return proxyManager;
}

- (instancetype)init {
    if (self = [super init]) {
        _correlationID = 1;
        _graphicsSupported = NO;
        _firstHmiFull = YES;
        _firstHmiNotNone = YES;
        _remoteImages = [[NSMutableSet alloc] init];
        _vehicleDataSubscribed = NO;
        
        self.tripStarted = NO;
        self.sdlImgCurrentImage = nil;
        self.strStickyFirstLine = @"";
        
        self.uploadsQueue = [NSMutableArray arrayWithArray:@[@[@(imgIdDriveSafe), imgDriveSafeGreen], // This must be the first no matter what
                                                             @[@(imgIdDrivingGreen), imgDrivingGreenImgFilename],
                                                             @[@(imgIdDrivingYellow), imgDrivingYellowImgFilename],
                                                             @[@(imgIdDrivingRed), imgDrivingRedImgFilename],
                                                             @[@(imgIdCorneringGreen), imgCorneringGreen],
                                                             @[@(imgIdEmpty), @"emptyImg"],
                                                             @[@(imgIdAxl), imgEventAxl],
                                                             @[@(imgIdBrake), imgEventBrake],
                                                             @[@(imgIdCornerLeft), imgEventCornerLeft],
                                                             @[@(imgIdCornerRight), imgEventCornerRight]]];

        // Get IP from defaults
        NSString *ipStr = [[NSUserDefaults standardUserDefaults] stringForKey:@"IP_preference"];
        NSLog(@"IP is %@", ipStr);
        if (ipStr == nil) {
            self.RemoteIpAddress = @"192.168.1.118";
        } else {
            self.RemoteIpAddress = ipStr;
        }
    }
    return self;
}

/**
 *  Posts SDL notifications.
 *
 *  @param name The name of the SDL notification
 *  @param info The data associated with the notification
 */
- (void)hsdl_postNotification:(NSString *)name info:(id)info {
    NSDictionary *userInfo = nil;
    if (info != nil) {
        userInfo = @{
            HSDLNotificationUserInfoObject : info
        };
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:userInfo];
}

#pragma mark Proxy Lifecycle

/**
 *  Start listening for SDL connections. Use only one of the following connection methods.
 */
- (void)startProxy {
    NSLog(@"startProxy");
    
    // If connecting via USB (to a vehicle).
//    self.proxy = [SDLProxyFactory buildSDLProxyWithListener:self];

    // If connecting via TCP/IP (to an emulator).
    self.proxy = [SDLProxyFactory buildSDLProxyWithListener:self tcpIPAddress:self.RemoteIpAddress tcpPort:RemotePort];
}

/**
 *  Disconnect and destroy the current proxy.
 */
- (void)disposeProxy {
    NSLog(@"disposeProxy");
    [self.proxy dispose];
    self.proxy = nil;
}

/**
 *  Delegate method that runs on SDL connect.
 */
- (void)onProxyOpened {
    NSLog(@"SDL Connect");

    // Build and send RegisterAppInterface request
    SDLRegisterAppInterface *raiRequest = [SDLRPCRequestFactory buildRegisterAppInterfaceWithAppName:AppName languageDesired:[SDLLanguage EN_US] appID:AppId];
    raiRequest.isMediaApplication = @(AppIsMediaApp);
    raiRequest.ngnMediaScreenAppName = ShortAppName;
    raiRequest.vrSynonyms = [NSMutableArray arrayWithObject:AppVrSynonym];
    NSMutableArray *ttsName = [NSMutableArray arrayWithObject:[SDLTTSChunkFactory buildTTSChunkForString:AppName type:SDLSpeechCapabilities.TEXT]];
    raiRequest.ttsName = ttsName;
    [self.proxy sendRPC:raiRequest];
}

/**
 *  Delegate method that runs on disconnect from SDL.
 */
- (void)onProxyClosed {
    NSLog(@"SDL Disconnect");

    // Reset state variables
    self.firstHmiFull = YES;
    self.firstHmiNotNone = YES;
    self.graphicsSupported = NO;
    [self.remoteImages removeAllObjects];
    self.vehicleDataSubscribed = NO;
    self.appIconId = nil;

    // Notify the app delegate to clear the lockscreen
    [self hsdl_postNotification:HSDLDisconnectNotification info:nil];

    // Cycle the proxy
    [self disposeProxy];
    [self startProxy];
}

/**
 *  Delegate method that runs when the registration response is received from SDL.
 */
- (void)onRegisterAppInterfaceResponse:(SDLRegisterAppInterfaceResponse *)response {
    NSLog(@"RegisterAppInterface response from SDL: %@ with info :%@", response.resultCode, response.info);

    if (!response || [response.success isEqual:@0]) {
        NSLog(@"Failed to register with SDL: %@", response);
        return;
    }

    // Check for graphics capability, and upload persistent graphics (app icon) if available
    if (response.displayCapabilities) {
        if (response.displayCapabilities.graphicSupported) {
            self.graphicsSupported = [response.displayCapabilities.graphicSupported boolValue];
        }
    }
    if (self.isGraphicsSupported) {
        [self hsdl_uploadImages];
        
        BOOL uploadImages = NO;
        @synchronized (self) {
            bootStatus |= GRBootStepAppInterface;
            
            uploadImages = (bootStatus == kBootStatusReady);
        }
        if (uploadImages) {
            [self uploadImageFromQueue];
        }
    }
}

/**
 *  Auto-increment and return the next correlation ID for an RPC.
 *
 *  @return The next correlation ID as an NSNumber.
 */
- (NSNumber *)hsdl_getNextCorrelationId {
    return [NSNumber numberWithUnsignedInteger:++self.correlationID];
}


#pragma mark HMI

/**
 *  Delegate method that runs when the app's HMI state on SDL changes.
 */
- (void)onOnHMIStatus:(SDLOnHMIStatus *)notification {
    NSLog(@"HMIStatus notification from SDL");

    // Send welcome message on first HMI FULL
    if ([[SDLHMILevel FULL] isEqualToEnum:notification.hmiLevel]) {
        NSLog(@"HMIStatus = FULL");
        
        [self hsdl_subscribeVehicleData];
        
        BOOL uploadImages = NO;
        @synchronized (self) {
            bootStatus |= GRBootStepHMIStatus;
            
            uploadImages = (bootStatus == kBootStatusReady);
        }
        if (uploadImages) {
            [self uploadImageFromQueue];
        }
        


        // Other HMI (Show, PerformInteraction, etc.) would go here
    }

    // Send AddCommands in first non-HMI NONE state (i.e., FULL, LIMITED, BACKGROUND)
    if ([[SDLHMILevel NONE] isEqualToEnum:notification.hmiLevel]) {
        NSLog(@"HMIStatus = NONE");
    } else {
        if (self.isFirstHmiNotNone) {
            self.firstHmiNotNone = NO;
            [self hsdl_addCommands];

            // Other app setup (SubMenu, CreateChoiceSet, etc.) would go here
        }
    }
    
    if ([[SDLHMILevel BACKGROUND] isEqualToEnum:notification.hmiLevel]) {
        NSLog(@"HMIStatus = Background");
    }

    if ([[SDLHMILevel LIMITED] isEqualToEnum:notification.hmiLevel]) {
        NSLog(@"HMIStatus = Limited");
    }
}

/**
 *  Send welcome message (Speak and Show).
 */
- (void)hsdl_performWelcomeMessage {
    NSLog(@"Send welcome message");
    SDLImage *driveSafeImg = [self sdlImgByName:imgDriveSafeGreen];
    SDLShow *show = [[SDLShow alloc] init];
    show.mainField1 = WelcomeShow;
    show.alignment = [SDLTextAlignment CENTERED];
    show.correlationID = [self hsdl_getNextCorrelationId];
    show.graphic = driveSafeImg;
    [self.proxy sendRPC:show];

    SDLSpeak *speak = [SDLRPCRequestFactory buildSpeakWithTTS:WelcomeSpeak correlationID:[self hsdl_getNextCorrelationId]];
    [self.proxy sendRPC:speak];
}

/**
 *  Delegate method that runs when driver distraction mode changes.
 */
- (void)onOnDriverDistraction:(SDLOnDriverDistraction *)notification {
    NSLog(@"OnDriverDistraction notification from SDL");
    // Some RPCs (depending on region) cannot be sent when driver distraction is active.
}

#pragma mark AppIcon

/**
 *  Requests list of images to SDL, and uploads images that are missing.
 *      Called automatically by the onRegisterAppInterfaceResponse method.
 *      Note: Don't need to check for graphics support here; it is checked by the caller.
 */
- (void)hsdl_uploadImages {
    NSLog(@"hsdl_uploadImages");
    [self.remoteImages removeAllObjects];

    // Perform a ListFiles RPC to check which files are already present on SDL
    SDLListFiles *list = [[SDLListFiles alloc] init];
    list.correlationID = [self hsdl_getNextCorrelationId];
    [self.proxy sendRPC:list];
}

/**
 *  Delegate method that runs when the list files response is received from SDL.
 */
- (void)onListFilesResponse:(SDLListFilesResponse *)response {
    NSLog(@"ListFiles response from SDL: %@ with info: %@", response.resultCode, response.info);

    if (response.success) {
        for (NSString *filename in response.filenames) {
            [self.remoteImages addObject:filename];
        }
    }

    // Check the mutable set for the AppIcon
    // If not present, upload the image
    if (![self.remoteImages containsObject:IconFile]) {
        self.appIconId = @(AppIconIdInt);
        [self hsdl_uploadImage:IconFile withCorrelationID:self.appIconId];
    } else {
        // If the file is already present, send the SetAppIcon request
        [self hsdl_setAppIcon];
    }
}

- (void) uploadImageFromQueue {
    NSLog(@"Number of images pending download: %lu", (unsigned long)[self.uploadsQueue count]);
    
    if ([self.uploadsQueue count] > 0) {
        NSArray *poped = [self.uploadsQueue lastObject];
        
        if (![self conditionalUpload: poped[1] existingFiles: self.remoteImages correlationID:poped[0]]) {
            [self.uploadsQueue removeLastObject];
            [self uploadImageFromQueue];
        }
    } else {
        NSLog(@"Upload QUEUE depleted");
    }
}

- (BOOL) conditionalUpload : (NSString*) imgName existingFiles : (NSMutableSet*) filesArray correlationID : (NSNumber*) corrId {
    if (![filesArray containsObject:imgName]) {
        NSLog(@"Image %@ (%@) not found, uploading it", imgName, corrId);
        [self hsdl_uploadImage:imgName withCorrelationID:corrId];
        return YES;
    }
    
    return NO;
}

/**
 *  Upload a persistent PNG image to SDL.
 *      The correlation ID can be used in the onPutFileResponse delegate method
 *      to determine when the upload is complete.
 *
 *  @param imageName The name of the image in the Assets catalog.
 *  @param corrId    The correlation ID used in the request.
 */
- (void)hsdl_uploadImage:(NSString *)imageName withCorrelationID:(NSNumber *)corrId {
    NSLog(@"hsdl_uploadImage: %@", imageName);
    if (imageName) {
//        UIImage *pngImage = [UIImage imageNamed:IconFile];
        UIImage *pngImage = ([imageName isEqualToString:@"emptyImg"] ? [self emptyImage]:[UIImage imageNamed:imageName]);
        if (pngImage) {
            NSData *pngData = UIImagePNGRepresentation(pngImage);
            if (pngData) {
                SDLPutFile *putFile = [[SDLPutFile alloc] init];
                putFile.syncFileName = imageName;
                putFile.fileType = [SDLFileType GRAPHIC_PNG];
                putFile.persistentFile = @YES;
                putFile.systemFile = @NO;
                putFile.offset = @0;
                putFile.length = [NSNumber numberWithUnsignedLong:pngData.length];
                putFile.bulkData = pngData;
                putFile.correlationID = corrId;
                
                [self.proxy sendRPC:putFile];
            }
        }
    }
}
                                                                        

- (UIImage*) emptyImage {
    CGRect imageRect = CGRectMake(0.0, 0.0, 138.0, 138.0);
    UIGraphicsBeginImageContext(imageRect.size);
    struct CGContext *grcContext = UIGraphicsGetCurrentContext();
    UIColor *transparentColod = [UIColor colorWithWhite:1.0 alpha:0.0];
    CGContextSetFillColorWithColor(grcContext, transparentColod.CGColor);
    CGContextFillRect(grcContext, imageRect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

/**
 *  Delegate method that runs when a PutFile is complete.
 */
- (void)onPutFileResponse:(SDLPutFileResponse *)response {
    NSLog(@"PutFile response from SDL: %@, correrlation ID: %@ with info: %@", response.resultCode, response.correlationID, response.info);

    // On success and matching app icon correlation ID, send a SetAppIcon request
    if ([response.success intValue] == 1) {
        int imgId = [response.correlationID intValue];
        NSString *imgName = nil;
        BOOL pop = YES;
        
        switch (imgId) {
            case imgIdDriveSafe: {
                imgName = @"DriveSafeGreen";
                
                if (self.isFirstHmiFull) {
                    self.firstHmiFull = NO;
                    
                    [self hsdl_performWelcomeMessage];
                }
            }
                break;
            case imgIdDrivingGreen:
                imgName = @"DrivingGreen";
                break;
            case imgIdDrivingYellow:
                imgName = @"DrivingYellow";
                break;
            case imgIdDrivingRed:
                imgName = @"DrivingRed";
                break;
            case imgIdCorneringGreen:
                imgName = @"Cornering Green";
                break;
            case imgIdAxl:
                imgName = @"Acceleration event";
                break;
            case imgIdBrake:
                imgName = @"Brake event";
                break;
            case imgIdCornerRight:
                imgName = @"Corner Right event";
                break;
            case imgIdCornerLeft:
                imgName = @"Corner Left event";
                break;
            case imgIdEmpty:
                imgName = @"EMPTY img";
                break;
            case AppIconIdInt:
                imgName = @"App Icon";
                pop = NO;
                break;
            default:
                pop = NO;
                break;
        }
        
        NSLog(@"Image Uploaded (%d): %@", imgId, imgName);
        if ([response.correlationID isEqual:self.appIconId]) {
            [self hsdl_setAppIcon];
        }
        
        // Upload successfull, remove object from queue.
        if (pop) {
            [self.uploadsQueue removeLastObject];
        }
        [self uploadImageFromQueue];

    } else {
        NSArray *pop = [self.uploadsQueue lastObject];
        NSLog(@"Failure uploading image %@, WAITING FOR HMISTATUS = FULL", pop[0]);
    }
}

/**
 *  Send the SetAppIcon request to SDL.
 *      Called automatically in the OnPutFileResponse method.
 */
- (void)hsdl_setAppIcon {
    NSLog(@"hsdl_setAppIcon");
    SDLSetAppIcon *setIcon = [[SDLSetAppIcon alloc] init];
    setIcon.syncFileName = IconFile;
    setIcon.correlationID = [self hsdl_getNextCorrelationId];
    [self.proxy sendRPC:setIcon];
}

#pragma mark Lockscreen

/**
 *  Delegate method that runs when lockscreen status changes.
 */
- (void)onOnLockScreenNotification:(SDLLockScreenStatus *)notification {
    NSLog(@"OnLockScreen notification from SDL");
//    
    SDLOnLockScreenStatus *lockScreenStatus = (SDLOnLockScreenStatus*)notification;
    
    if (notification && [lockScreenStatus.lockScreenStatus isEqualToEnum:[SDLLockScreenStatus OFF]]) {
        [[GREventsGenerator sharedInstance] stop];
    }
    
    // Notify the app delegate
    [self hsdl_postNotification:HSDLLockScreenStatusNotification info:notification];
}

#pragma mark Commands

/**
 *  Add commands for the app on SDL.
 */
- (void)hsdl_addCommands {
    NSLog(@"hsdl_addCommands");
    SDLMenuParams *menuParams = [[SDLMenuParams alloc] init];
    menuParams.menuName = TestCommandName;
    SDLAddCommand *command = [[SDLAddCommand alloc] init];
    command.vrCommands = [NSMutableArray arrayWithObject:TestCommandName];
    command.menuParams = menuParams;
    command.cmdID = @(TestCommandID);
    [self.proxy sendRPC:command];
    
    SDLMenuParams *menuParams2 = [[SDLMenuParams alloc] init];
    menuParams2.menuName = BeginDriveCommandName;
    SDLAddCommand *command2 = [[SDLAddCommand alloc] init];
    command2.vrCommands = [NSMutableArray arrayWithObject:BeginDriveCommandName];
    command2.menuParams = menuParams2;
    command2.cmdID = @(BeginDriveCommandID);
    [self.proxy sendRPC:command2];
    
}

/**
 *  Delegate method that runs when the add command response is received from SDL.
 */
- (void)onAddCommandResponse:(SDLAddCommandResponse *)response {
    NSLog(@"AddCommand response from SDL: %@ with info: %@", response.resultCode, response.info);
}

/**
 *  Delegate method that runs when a command is triggered on SDL.
 */
- (void)onOnCommand:(SDLOnCommand *)notification {
    NSLog(@"OnCommand notification from SDL");

    // Handle sample command when triggered
    if ([notification.cmdID isEqual:@(TestCommandID)]) {
        SDLShow *show = [[SDLShow alloc] init];
        show.mainField1 = @"Test Command";
        show.alignment = [SDLTextAlignment CENTERED];
        show.correlationID = [self hsdl_getNextCorrelationId];
        [self.proxy sendRPC:show];

        SDLSpeak *speak = [SDLRPCRequestFactory buildSpeakWithTTS:@"Test Command" correlationID:[self hsdl_getNextCorrelationId]];
        [self.proxy sendRPC:speak];
    } else if ([notification.cmdID isEqual:@(BeginDriveCommandID)]) {
        SDLImage *DrivingGreenImg = [self sdlImgByName:imgDrivingGreenImgFilename];
        
        SDLShow *show = [[SDLShow alloc] init];
        show.mainField1 = @"Starting Trip";
        show.mainField2 = @"Drive Save,  Enjoy your drive";
        NSLog(@"Adding DrivingGreen IMAGE");
        show.graphic = DrivingGreenImg;
        show.statusBar = @"Uh - Statusbar";
        show.alignment = [SDLTextAlignment CENTERED];
        show.correlationID = [self hsdl_getNextCorrelationId];
        [self.proxy sendRPC:show];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//            SDLShow *showBye = [[SDLShow alloc] init];
//            showBye.mainField1 = @"BYE";
//            showBye.mainField2 = @"";
//            showBye.statusBar = @"Bye Status Bar";
//            
//            NSLog(@"BYE BYE DrivingGreen");
//            showBye.correlationID = [self hsdl_getNextCorrelationId];
//            [self.proxy sendRPC:showBye];
//            
//            // Try playing Pre recorded alert sounds
////            SDLTTSChunk *simpleChunk = [[SDLTTSChunk alloc] init];
////            simpleChunk = ttsText;
////            simpleChunk.type = SDLSpeechCapabilities.PRE_RECORDED;
////            NSArray *ttsChunks = [NSMutableArray arrayWithObject:simpleChunk];
//
//            
//            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"BYE BYE DrivingGreen");
                [self testAlert];
                [self clearDisplay];
//            });
        });
        
        
//        NSLog(@"SHOWING THE IMAGE???");
//        SDLShow *imgShow = [[SDLShow alloc] init];
//        imgShow.graphic = DrivingGreenImg;
//        imgShow.correlationID = @(DrivingGreenImgId);
//        [self.proxy sendRPC:imgShow];
//        NSLog(@"SHOWED THE IMAGE???");
        
        SDLSpeak *speak = [SDLRPCRequestFactory buildSpeakWithTTS:@"Begin Trip" correlationID:[self hsdl_getNextCorrelationId]];
        [self.proxy sendRPC:speak];
        
    }
}

- (void) testAlert {
    SDLAlert *testAlert = [[SDLAlert alloc] init];
    testAlert.alertText1 = @"Driving Events";
    testAlert.alertText2 = @"Starting driving events simulation.";
    testAlert.duration = @(3000);
    testAlert.ttsChunks = [NSMutableArray arrayWithObject:[SDLTTSChunkFactory buildTTSChunkForString:@"Acceleration" type:SDLSpeechCapabilities.TEXT]];
    testAlert.playTone = @(YES);
    
    SDLSoftButton *sftBtn = [[SDLSoftButton alloc] init];
    SDLImage *btnIng = [self sdlImgByName:imgEventAxl];
    sftBtn.image = btnIng;
    sftBtn.type = [SDLSoftButtonType IMAGE];
    sftBtn.isHighlighted = @(NO);
    sftBtn.softButtonID = @(TestAlertButtonID);
    testAlert.softButtons = [NSMutableArray arrayWithArray:@[sftBtn]];
    
    testAlert.correlationID = [self hsdl_getNextCorrelationId];
    
    [self.proxy sendRPC:testAlert];
}

- (SDLImage*) sdlImgByName : (NSString *) name {
    SDLImage *sdlImg = [[SDLImage alloc] init];
    sdlImg.value = name;
    sdlImg.imageType = SDLImageType.DYNAMIC;
   
    return sdlImg;
}

- (void) clearDisplay {
    SDLShow *showNothing = [[SDLShow alloc] init];
    showNothing.mainField1 = self.strStickyFirstLine;
    showNothing.mainField2 = @"";
    showNothing.mainField3 = @"";
    showNothing.mainField4 = self.strTiresStatus;
    
//    [self addStandardButtonsToShow:showNothing];
    
    SDLImage *emptyImg = [self sdlImgByName:@"emptyImg"];

    if (self.sdlImgCurrentImage == nil) {
        showNothing.graphic = emptyImg;
    } else {
        showNothing.graphic = self.sdlImgCurrentImage;
    }

    NSLog(@"Clearing display");
    showNothing.correlationID = [self hsdl_getNextCorrelationId];
    [self.proxy sendRPC:showNothing];
}

- (void) addStandardButtonsToShow : (SDLShow*) show {
    NSString *strScore = @"Score";
    
    SDLSoftButton *softButton = [[SDLSoftButton alloc] init];
    softButton.text = strScore;
    softButton.type = [SDLSoftButtonType TEXT];
    softButton.isHighlighted = @(NO);
    softButton.softButtonID = @(scoreButtonId);
    
    show.softButtons = [NSMutableArray arrayWithArray:@[softButton]];
    
    // No need to subscribe UI buttons (AFAI see)
//    SDLSubscribeButton *subscribe = [[SDLSubscribeButton alloc] init];
//    subscribe.correlationID = [self hsdl_getNextCorrelationId];
//    subscribe.buttonName = [SDLButtonName CUSTOM_BUTTON];
    
//    [self.proxy sendRPC:subscribe];
}


#pragma mark - GreenRoad events

- (void) sendEventToSDLWithImage : (NSString*) imageName eventName : (NSString*) eventName {
    SDLShow *show = [[SDLShow alloc] init];

    if (nil != imageName) {
        SDLImage *DrivingGreenImg = [self sdlImgByName:imageName];
        show.graphic = DrivingGreenImg;
    }
    
    show.mainField1 = eventName;
    show.mainField4 = self.strTiresStatus;
    show.statusBar = eventName;
    show.alignment = [SDLTextAlignment CENTERED];
    show.correlationID = [self hsdl_getNextCorrelationId];
    [self.proxy sendRPC:show];


    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self clearDisplay];
    });
    
    SDLSpeak *speak = [SDLRPCRequestFactory buildSpeakWithTTS:eventName correlationID:[self hsdl_getNextCorrelationId]];
    [self.proxy sendRPC:speak];
}

- (void) displayEvent : (GREventType) eventType {
    NSString *eventName = nil;
    NSString *imgName = nil;
    
    switch (eventType) {
        case GREventAccelerate:
            eventName = @"Acceleration";
            imgName = imgEventAxl;
            break;
        case GREventBrake:
            eventName = @"Brake";
            imgName = imgEventBrake;
            break;
        case GREventCornerRight:
            eventName = @"Cornering right";
            imgName = imgEventCornerRight;
            break;
        case GREventCornerLeft:
            eventName = @"Cornering left";
            imgName = imgEventCornerLeft;
            break;
        case GREventUIShowScore:
            eventName = @"Doing well!";
            imgName = nil;
            break;
        default:
            NSLog(@"*** ERROR *** Event Not Recognized");
            break;
    }
    
    if (nil != eventName) {
        NSLog(@"Displaying event: %@", eventName);
        [self sendEventToSDLWithImage: imgName eventName:eventName];
    }
}

- (void) driveEvent : (GREventsGenerator*) eventGenerator eventType:(GREventType) eventType {
    [self displayEvent:eventType];
}



#pragma mark GreenRoad States

- (double) delay {
    int delayVariant = arc4random_uniform(4);
    double delay = kDelayBetweenEvents + delayVariant;
    
    return delay;
}

- (void) beginTrip {
    if (!self.tripStarted) {
        self.tripStarted = YES;
        NSLog(@"Begin Trip");
        
        SDLImage *sdlImgDriving = [self sdlImgByName:imgDrivingGreenImgFilename];
        SDLShow *show = [[SDLShow alloc] init];
        show.mainField1 = strBeginTripText;
        show.alignment = [SDLTextAlignment CENTERED];
        show.correlationID = [self hsdl_getNextCorrelationId];
        show.graphic = sdlImgDriving;
        [self.proxy sendRPC:show];
        
        SDLSpeak *speak = [SDLRPCRequestFactory buildSpeakWithTTS:strBeginTripVoice correlationID:[self hsdl_getNextCorrelationId]];
        [self.proxy sendRPC:speak];
        
        self.sdlImgCurrentImage = sdlImgDriving;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self clearDisplay];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self delay] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self cornering];
            });
        });
    }
}

- (void) cornering {
    NSLog(@"Cornering");
    
    SDLImage *sdlImgCornering = [self sdlImgByName:imgCorneringGreen];
    SDLShow *show = [[SDLShow alloc] init];
    show.mainField1 = strCorneringText;
    show.alignment = [SDLTextAlignment CENTERED];
    show.correlationID = [self hsdl_getNextCorrelationId];
    show.graphic = sdlImgCornering;
    [self.proxy sendRPC:show];
    
    SDLSpeak *speak = [SDLRPCRequestFactory buildSpeakWithTTS:strCorneringVoice correlationID:[self hsdl_getNextCorrelationId]];
    [self.proxy sendRPC:speak];
    
    self.strStickyFirstLine = strCorneringText;
    self.sdlImgCurrentImage = sdlImgCornering;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDelayToResetToDriving * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self resetToDriving:0];
    });
}

- (void) resetToDriving : (int) level {
    NSString *imgName;
    
    switch (level) {
        case 0:
            imgName = imgDrivingGreenImgFilename;
            break;
        case 1:
            imgName = imgDrivingYellowImgFilename;
            break;
        case 2:
            imgName = imgDrivingRedImgFilename;
            break;
        default:
            break;
    }

    SDLImage *sdlImgDrivingImg = [self sdlImgByName:imgName];
//    SDLShow *show = [[SDLShow alloc] init];
//    show.mainField1 = @"";
//    show.correlationID = [self hsdl_getNextCorrelationId];
//    show.graphic = sdlImgDrivingImg;
//    [self.proxy sendRPC:show];
    
    self.sdlImgCurrentImage = sdlImgDrivingImg;
    self.strStickyFirstLine = @"";
    [self clearDisplay];
}



#pragma mark - VehicleData

// vehicle data Area

/**
 *  Delegate method that runs when the app's permissions change on SDL.
 */
- (void)onOnPermissionsChange:(SDLOnPermissionsChange *)notification {
    NSLog(@"OnPermissionsChange notification from SDL");

    // Check for permission to subscribe to vehicle data before sending the request
    NSMutableArray *permissionArray = notification.permissionItem;
    for (SDLPermissionItem *item in permissionArray) {
        if ([item.rpcName isEqualToString:@"SubscribeVehicleData"]) {
            if (item.hmiPermissions.allowed && item.hmiPermissions.allowed.count > 0) {
                // Moved to other callback: [self hsdl_subscribeVehicleData];
            }
        }
    }
}


/**
 *  Subscribe to (periodic) vehicle data updates from SDL.
 */
- (void)hsdl_subscribeVehicleData {
    NSLog(@"hsdl_subscribeVehicleData");
    if (!self.isVehicleDataSubscribed) {
        SDLSubscribeVehicleData *subscribe = [[SDLSubscribeVehicleData alloc] init];
        subscribe.correlationID = [self hsdl_getNextCorrelationId];

        subscribe.accPedalPosition = @YES;
        subscribe.speed = @YES;
        subscribe.gps = @YES;
        subscribe.tirePressure = @YES;
//        subscribe.instantFuelConsumption = @YES;
        subscribe.beltStatus = @YES;
        subscribe.bodyInformation = @YES;
        subscribe.deviceStatus = @YES;
//        subscribe.airbagStatus = @YES;
//        subscribe.emergencyEvent = @YES;
//        subscribe.myKey = @YES;
        

        [self.proxy sendRPC:subscribe];
    }
}

/**
 *  Delegate method that runs when the subscribe vehicle data response is received from SDL.
 */
- (void)onSubscribeVehicleDataResponse:(SDLSubscribeVehicleDataResponse *)response {
    NSLog(@"SubscribeVehicleData response from SDL: %@ with info: %@", response.resultCode, response.info);

    if (response && [[SDLResult SUCCESS] isEqualToEnum:response.resultCode]) {
        NSLog(@"Vehicle data subscribed!");
        self.vehicleDataSubscribed = YES;
    }
}

/**
 *  Delegate method that runs when new vehicle data is received from SDL.
 */
- (void)onOnVehicleData:(SDLOnVehicleData *)notification {
    NSLog(@"OnVehicleData notification from SDL");

    NSLog(@"Speed: %@", notification.speed);
    NSLog(@"Tire Pressure left front: %@",notification.tirePressure.leftFront.status);
    NSLog(@"Tire Pressure left rear: %@",notification.tirePressure.leftRear);
    NSMutableString *badTires = [NSMutableString stringWithString:@""];
    if (notification.tirePressure) {
        if ([self tirePreasureIsBad:notification.tirePressure.leftFront]) {
            [badTires appendString:@" Left Front"];
        }
        if ([self tirePreasureIsBad:notification.tirePressure.leftRear]) {
            [badTires appendString:@" Left Rear"];
        }
        if ([self tirePreasureIsBad:notification.tirePressure.rightRear]) {
            [badTires appendString:@" Right Rear"];
        }
        if ([self tirePreasureIsBad:notification.tirePressure.rightFront]) {
            [badTires appendString:@" Right Front"];
        }
        
        if (badTires.length > 1) {
            self.strTiresStatus = [NSString stringWithFormat:@"Check your tires: %@", badTires];
        } else {
            self.strTiresStatus = @"";
        }
        [self clearDisplay];
    } else if (notification.accPedalPosition) {
        double pedalPosition = [notification.accPedalPosition doubleValue];
        if (pedalPosition > 20) {
            [self beginTrip];
        }
    }
}

- (BOOL) tirePreasureIsBad : (SDLSingleTireStatus*) tireStatus {
    BOOL tireIsAreBad = NO;
    
    if (tireStatus) {
        tireIsAreBad = [tireStatus.status isEqual:[SDLComponentVolumeStatus LOW]] || [tireStatus.status isEqual:[SDLComponentVolumeStatus ALERT]] || [tireStatus.status isEqual:[SDLComponentVolumeStatus FAULT]]; // Not sure fault is bad.
    }
    
    return tireIsAreBad;
}

/*
 
 */


#pragma mark Notification callbacks

- (void)onOnAppInterfaceUnregistered:(SDLOnAppInterfaceUnregistered *)notification {
    NSLog(@"onAppInterfaceUnregistered notification from SDL");
}

- (void)onOnAudioPassThru:(SDLOnAudioPassThru *)notification {
    NSLog(@"onAudioPassThru notification from SDL");
}

- (void)onOnButtonEvent:(SDLOnButtonEvent *)notification {
    NSNumber *customButtonID = notification.customButtonID;
    int customButtonIDInt = [customButtonID intValue];
    
    NSLog(@"onOnButtonEvent: notification.from: %@", customButtonID);
    
    switch (customButtonIDInt) {
        case TestAlertButtonID: {
            NSLog(@"START Events generator");
            SDLShow *buttons = [[SDLShow alloc] init];
            [self addStandardButtonsToShow:buttons];
            [self.proxy sendRPC:buttons];
            
            [[GREventsGenerator sharedInstance] setEventsListener:self];
            [[GREventsGenerator sharedInstance] start];
        }
            break;
        case scoreButtonId:
            NSLog(@"Showing Driver Score");
            [self displayEvent:GREventUIShowScore];
            
            break;
        default:
            break;
    }
}

- (void)onOnButtonPress:(SDLOnButtonPress *)notification {
    NSLog(@"onButtonPress notification from SDL");
}

- (void)onOnEncodedSyncPData:(SDLOnEncodedSyncPData *)notification {
    NSLog(@"onEncodedSyncPData from SDL");
}

- (void)onOnHashChange:(SDLOnHashChange *)notification {
    NSLog(@"onHashChange notification from SDL");
}

- (void)onOnLanguageChange:(SDLOnLanguageChange *)notification {
    NSLog(@"onLanguageChange notification from SDL");
}

- (void)onOnSyncPData:(SDLOnSyncPData *)notification {
    NSLog(@"onSyncPData notification from SDL");
}

- (void)onOnSystemRequest:(SDLOnSystemRequest *)notification {
    NSLog(@"onSystemRequest notification from SDL");
}

- (void)onOnTBTClientState:(SDLOnTBTClientState *)notification {
    NSLog(@"onTBTClientState notification from SDL");
}

- (void)onOnTouchEvent:(SDLOnTouchEvent *)notification {
    NSLog(@"onTouchEvent notification from SDL");
}


#pragma mark Other callbacks

- (void)onAddSubMenuResponse:(SDLAddSubMenuResponse *)response {
    NSLog(@"AddSubMenu response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onAlertManeuverResponse:(SDLAlertManeuverResponse *)request {
    NSLog(@"AlertManeuver response from SDL with result code: %@ and info: %@", request.resultCode, request.info);
}

- (void)onAlertResponse:(SDLAlertResponse *)response {
    NSLog(@"Alert response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onChangeRegistrationResponse:(SDLChangeRegistrationResponse *)response {
    NSLog(@"ChangeRegistration response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onCreateInteractionChoiceSetResponse:(SDLCreateInteractionChoiceSetResponse *)response {
    NSLog(@"CreateInteractionChoiceSet response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onDeleteCommandResponse:(SDLDeleteCommandResponse *)response {
    NSLog(@"DeleteCommand response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onDeleteFileResponse:(SDLDeleteFileResponse *)response {
    NSLog(@"DeleteFile response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onDeleteInteractionChoiceSetResponse:(SDLDeleteInteractionChoiceSetResponse *)response {
    NSLog(@"DeleteInteractionChoiceSet response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onDeleteSubMenuResponse:(SDLDeleteSubMenuResponse *)response {
    NSLog(@"DeleteSubMenu response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onDiagnosticMessageResponse:(SDLDiagnosticMessageResponse *)response {
    NSLog(@"DiagnosticMessage response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onDialNumberResponse:(SDLDialNumberResponse *)request {
    NSLog(@"DialNumber response from SDL with result code: %@ and info: %@", request.resultCode, request.info);
}

- (void)onEncodedSyncPDataResponse:(SDLEncodedSyncPDataResponse *)response {
    NSLog(@"EncodedSyncPData response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onEndAudioPassThruResponse:(SDLEndAudioPassThruResponse *)response {
    NSLog(@"EndAudioPassThru response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onError:(NSException *)e {
    NSLog(@"Error response from SDL with name: %@ and reason: %@", e.name, e.reason);
}

- (void)onGenericResponse:(SDLGenericResponse *)response {
    NSLog(@"Generic response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onGetDTCsResponse:(SDLGetDTCsResponse *)response {
    NSLog(@"GetDTCs response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onGetVehicleDataResponse:(SDLGetVehicleDataResponse *)response {
    NSLog(@"GetVehicleData response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onReceivedLockScreenIcon:(UIImage *)icon {
    NSLog(@"ReceivedLockScreenIcon notification from SDL");
}

- (void)onPerformAudioPassThruResponse:(SDLPerformAudioPassThruResponse *)response {
    NSLog(@"PerformAudioPassThru response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onPerformInteractionResponse:(SDLPerformInteractionResponse *)response {
    NSLog(@"PerformInteraction response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onReadDIDResponse:(SDLReadDIDResponse *)response {
    NSLog(@"ReadDID response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onResetGlobalPropertiesResponse:(SDLResetGlobalPropertiesResponse *)response {
    NSLog(@"ResetGlobalProperties response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onScrollableMessageResponse:(SDLScrollableMessageResponse *)response {
    NSLog(@"ScrollableMessage response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSendLocationResponse:(SDLSendLocationResponse *)request {
    NSLog(@"SendLocation response from SDL with result code: %@ and info: %@", request.resultCode, request.info);
}

- (void)onSetAppIconResponse:(SDLSetAppIconResponse *)response {
    NSLog(@"SetAppIcon response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSetDisplayLayoutResponse:(SDLSetDisplayLayoutResponse *)response {
    NSLog(@"SetDisplayLayout response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSetGlobalPropertiesResponse:(SDLSetGlobalPropertiesResponse *)response {
    NSLog(@"SetGlobalProperties response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSetMediaClockTimerResponse:(SDLSetMediaClockTimerResponse *)response {
    NSLog(@"SetMediaClockTimer response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onShowConstantTBTResponse:(SDLShowConstantTBTResponse *)response {
    NSLog(@"ShowConstantTBT response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onShowResponse:(SDLShowResponse *)response {
    NSLog(@"Show response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSliderResponse:(SDLSliderResponse *)response {
    NSLog(@"Slider response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSpeakResponse:(SDLSpeakResponse *)response {
    NSLog(@"Speak response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSubscribeButtonResponse:(SDLSubscribeButtonResponse *)response {
    NSLog(@"SubscribeButton response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onSyncPDataResponse:(SDLSyncPDataResponse *)response {
    NSLog(@"SyncPData response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onUpdateTurnListResponse:(SDLUpdateTurnListResponse *)response {
    NSLog(@"UpdateTurnList response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onUnregisterAppInterfaceResponse:(SDLUnregisterAppInterfaceResponse *)response {
    NSLog(@"UnregisterAppInterface response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onUnsubscribeButtonResponse:(SDLUnsubscribeButtonResponse *)response {
    NSLog(@"UnsubscribeButton response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

- (void)onUnsubscribeVehicleDataResponse:(SDLUnsubscribeVehicleDataResponse *)response {
    NSLog(@"UnsubscribeVehicleData response from SDL with result code: %@ and info: %@", response.resultCode, response.info);
}

@end
