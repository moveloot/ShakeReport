//
//  SRReporter.m
//  ShakeReport
//
//  Created by Jeremy Templier on 5/29/13.
//  Copyright (c) 2013 Jayztemplier. All rights reserved.
//

#import "SRReporter.h"
#import "SRReporter+Private.h"
#import "SRMethodSwizzler.h"
#import "UIWindow+SRReporter.h"
#import "NSData+Base64.h"
#import "NSString+HTML.h"
#import <QuartzCore/QuartzCore.h>

#define kCrashFlag @"kCrashFlag"

void uncaughtExceptionHandler(NSException *exception) {
    NSMutableString *crashString = [NSMutableString string];
    [crashString appendString:@"-------------- CRASH --------------\n"];
    [crashString appendFormat:@"CRASH: %@", exception];
    [crashString appendFormat:@"Stack Trace: %@", [exception callStackSymbols]];
    [crashString appendString:@"-----------------------------------"];
    [[SRReporter reporter] saveToCrashFile:crashString];
}

static NSString * SRBase64EncodedStringFromString(NSString *string) {
    NSData *data = [NSData dataWithBytes:[string UTF8String] length:[string lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    NSUInteger length = [data length];
    NSMutableData *mutableData = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    
    uint8_t *input = (uint8_t *)[data bytes];
    uint8_t *output = (uint8_t *)[mutableData mutableBytes];
    
    for (NSUInteger i = 0; i < length; i += 3) {
        NSUInteger value = 0;
        for (NSUInteger j = i; j < (i + 3); j++) {
            value <<= 8;
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }
        
        static uint8_t const kAFBase64EncodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        
        NSUInteger idx = (i / 3) * 4;
        output[idx + 0] = kAFBase64EncodingTable[(value >> 18) & 0x3F];
        output[idx + 1] = kAFBase64EncodingTable[(value >> 12) & 0x3F];
        output[idx + 2] = (i + 1) < length ? kAFBase64EncodingTable[(value >> 6)  & 0x3F] : '=';
        output[idx + 3] = (i + 2) < length ? kAFBase64EncodingTable[(value >> 0)  & 0x3F] : '=';
    }
    
    return [[NSString alloc] initWithData:mutableData encoding:NSASCIIStringEncoding];
}

@interface SRReporter ()
@property (nonatomic,  strong) MFMailComposeViewController *mailController;
@end

@implementation SRReporter
@synthesize mailController;

+ (id)reporter {
    static SRReporter *__sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __sharedInstance = [[self alloc] init];
    });
    return __sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)startListenerConnectedToBackendURL:(NSURL *)url
{
    _backendURL = url;
    [self startListener];
}



- (void)startListener
{
    [self startLog2File];
    [self startCrashExceptionHandler];
    SwizzleInstanceMethod([UIWindow class], @selector(motionEnded:withEvent:), @selector(SR_motionEnded:withEvent:));
}

#pragma mark Logs
- (void)startLog2File
{
#if TARGET_IPHONE_SIMULATOR == 0
    NSString *logPath = [self logFilePath];
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    freopen([logPath cStringUsingEncoding:NSASCIIStringEncoding],"a+",stderr);
#endif
}

- (NSString *)logFilePath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"console.log"];
    return logPath;
}

- (NSString *)logs
{
    NSString *logPath = [self logFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        NSString *logs = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        return logs;
    }
    return @"";
}

#pragma mark Report
- (void)sendNewReport
{
    if(SR_LOGS_ENABLED) NSLog(@"Send New Report");
    if (_backendURL) {
        [self sendToServer];
    } else {
        [self showMailComposer];
    }
}

#pragma Crash Report
- (void)startCrashExceptionHandler
{
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
}

- (void)setCrashFlag:(BOOL)flag
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:flag forKey:kCrashFlag];
    [userDefaults synchronize];
    if (!flag) {
        NSString *filePath = [self crashFilePath];
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
}

- (BOOL)crashFlag
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    return [userDefaults boolForKey:kCrashFlag];
}

- (NSString *)crashReport
{
    NSString *crashFilePath = [self crashFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:crashFilePath]) {
        NSString *crash = [NSString stringWithContentsOfFile:crashFilePath encoding:NSUTF8StringEncoding error:nil];
        [self setCrashFlag:NO];
        return crash;
    }
    return nil;
}

- (void)saveToCrashFile:(NSString *)crashContent
{
    if (crashContent) {
        NSString *filePath = [self crashFilePath];
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        [crashContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [self setCrashFlag:YES];
    }
}

- (NSString *)crashFilePath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"crash.log"];
    return logPath;
}
#pragma mark Screenshot
- (UIImage *)screenshot
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, [UIScreen mainScreen].scale);
    else
        UIGraphicsBeginImageContext(window.bounds.size);

    [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark View Hierarchy
- (NSString *)viewHierarchy
{
    NSString *dump = [NSString stringWithFormat:@"%@", [[[UIApplication sharedApplication] keyWindow] performSelector:@selector(recursiveDescription)]];
    return dump;
}


#pragma mark Custom Information
- (void)setCustomInformationBlock:(NSString* (^)())block
{
    _customInformationBlock = block;
}


- (NSString *)customInformation
{
    if (_customInformationBlock) {
        return _customInformationBlock();
    }
    return nil;
}

#pragma mark Mail Composer
- (void)showMailComposer
{
    if (mailController) {
        return;
    }
    mailController = [[MFMailComposeViewController alloc] init];
    mailController.mailComposeDelegate = self;
    mailController.delegate = self;
    [mailController setSubject:@"[SRReporter] New Report"];
    if (_defaultEmailAddress) {
        [mailController setToRecipients:@[_defaultEmailAddress]];
    }
    mailController.modalPresentationStyle = UIModalPresentationPageSheet;
    
    // Fetch Screenshot data
    UIImage *screenshot = [self screenshot];
    NSData *imageData = UIImageJPEGRepresentation(screenshot ,1.0);

    // Logs
    NSString *logs = [self logs];
    NSData* logsData = [logs dataUsingEncoding:NSUTF8StringEncoding];
    
    // View Hierarchy (Root=Window)
    NSString *viewDump = [self viewHierarchy];
    NSData* viewData = [viewDump dataUsingEncoding:NSUTF8StringEncoding];
    
    // Crash Report if we registered a crash
    NSString *crashReport = [self crashReport];
    if (!crashReport) {
        crashReport = @"No Crash";
    }
    NSData* crashData = [crashReport dataUsingEncoding:NSUTF8StringEncoding];
    
    
    // We attache all the information to the email
    [mailController addAttachmentData:imageData mimeType:@"image/jpeg" fileName:@"screenshot.jpeg"];
    [mailController addAttachmentData:logsData mimeType:@"text/plain" fileName:@"console.log"];
    [mailController addAttachmentData:viewData mimeType:@"text/plain" fileName:@"viewDump.log"];
    [mailController addAttachmentData:crashData mimeType:@"text/plain" fileName:@"crash.log"];
    [mailController setMessageBody:@"Hey! I noticed something wrong with the app, here is some information." isHTML:NO];

    //Custom Information
    NSString *additionalInformation = [self customInformation];
    if (additionalInformation) {
        NSData* additionalInformationData = [additionalInformation dataUsingEncoding:NSUTF8StringEncoding];
        [mailController addAttachmentData:additionalInformationData mimeType:@"text/plain" fileName:@"additionalInformation.log"];
    }
    
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    [window.rootViewController presentViewController:mailController animated:YES completion:NO];
}

- (void)mailComposeController:(MFMailComposeViewController*)mailController didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    if (self.mailController) {
        [self.mailController dismissViewControllerAnimated:YES completion:nil];
        self.mailController = nil;
    }
}

#pragma mark ShareReport Server API
- (void)setAuthenticationParamsToRequest:(NSMutableURLRequest*)request
{
    if (_username && _password) {
        NSString *basicAuthCredentials = [NSString stringWithFormat:@"%@:%@", _username, _password];
        [request addValue:[NSString stringWithFormat:@"Basic %@", SRBase64EncodedStringFromString(basicAuthCredentials)] forHTTPHeaderField:@"Authorization"];
    }
}

- (void)sendToServer
{
    if (!_backendURL) {
        return;
    }
    
    UIImage *screenshot = [self screenshot];
    NSData *imageData = UIImageJPEGRepresentation(screenshot ,1.0);
    NSString *base64ImageString = [imageData base64EncodingWithLineLength:imageData.length];
    NSString *logs = [self logs];
    NSString *viewDump = [self viewHierarchy];
    NSString *crashReport = [self crashReport];
    
    // let's construct the URL
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_backendURL];
    NSMutableDictionary *reportParams = [NSMutableDictionary dictionary];
    [reportParams setObject:base64ImageString forKey:@"screenshot"];
    [reportParams setObject:logs forKey:@"logs"];
    [reportParams setObject:viewDump forKey:@"dumped_view"];
    if (crashReport) {
        [reportParams setObject:crashReport forKey:@"crash_logs"];
    }
    NSDictionary *params = @{@"report": reportParams};
    NSString *paramsString = [params JSONString];
    NSData *requestData = [NSData dataWithBytes:[paramsString UTF8String] length:[paramsString length]];
    [request setHTTPBody:requestData];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // Authentication
    [self setAuthenticationParamsToRequest:request];
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 201) {
            UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"Report sent" message:@"Thank you for your help." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alert show];
        }
        if(SR_LOGS_ENABLED) {
            NSLog(@"[Shake Report] Report status:");
            NSLog(@"[Shake Report] HTTP Status Code: %d", httpResponse.statusCode);
            if (data) {
                NSLog(@"[Shake Report] Response Body: %@", [data objectFromJSONData]);
            }
            NSLog(@"[Shake Report] Error: %@", error);
        }
    }];
}
@end
