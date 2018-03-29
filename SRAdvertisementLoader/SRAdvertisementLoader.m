//
//  SRAdvertisementLoader.m
//  SRAdvertisementLoaderDemo
//
//  Created by https://github.com/guowilling on 2018/3/2.
//  Copyright © 2018年 SR. All rights reserved.
//

#import "SRAdvertisementLoader.h"
#import <UIKit/UIKit.h>

#define SRAdImagesDirectory [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] \
stringByAppendingPathComponent:NSStringFromClass([self class])]

#define SRAdImageName(URLString) [URLString lastPathComponent]

#define SRAdImagePath(URLString) [SRAdImagesDirectory stringByAppendingPathComponent:SRAdImageName(URLString)]

#define SRAdPlistPath [SRAdImagesDirectory stringByAppendingPathComponent:@"SRAdPlistPath.plist"]

#define kLastAdImageURLKey @"lastAdImageURLKey"

@interface SRAdvertisementLoader ()

@property (nonatomic, strong) UIWindow *adWindow;

@property (nonatomic, strong) UIButton *countdownBtn;

@property (nonatomic, assign) NSInteger countdownTimer;

@end

@implementation SRAdvertisementLoader

// through the load: method can be done without any code invasion
+ (void)load {
    [self createImagesDirectory];
    
    [self sharedAdvertisementLoader];
}

+ (void)createImagesDirectory {
    NSString *imagesDirectory = SRAdImagesDirectory;
    BOOL isDirectory = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isExists = [fileManager fileExistsAtPath:imagesDirectory isDirectory:&isDirectory];
    if (!isExists || !isDirectory) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:imagesDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"createDirectoryAtPath error: %@", error);
        }
    }
}

+ (instancetype)sharedAdvertisementLoader {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _countdown = 3.0;
        _onlyLaunchShowAd = YES;
        _cachedAdImagesMaxSize = 10.0;
     
        // register notifications
        // after application launch, keywindow and rootViewController already there, the system will post UIApplicationDidFinishLaunchingNotification notification
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            [self requestAdData];
            if ([self isFirstLaunchApp]) {
                return;
            }
            [self showAdvertisement];
        }];
        
        // into the background notification
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            [self requestAdData];
        }];
        
        // into the foreground notification(application launch does not post this notification)
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            if (!self.onlyLaunchShowAd) {
                [self showAdvertisement];
            }
        }];
    }
    return self;
}

- (void)requestAdData {
    NSURLSessionDataTask *getAdTask = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:SRAdDataURL]
                                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                      if (error) {
                                                                          NSLog(@"error: %@", error);
                                                                          return;
                                                                      }
                                                                      NSDictionary *respData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
                                                                      
                                                                      NSString *adImageURLString = respData[@"data"][@"advertising_url"];
                                                                      [self downloadAdImageURLString:adImageURLString];
                                                                      
                                                                      NSString *adURLString = respData[@"data"][@"data_url"];
                                                                      NSMutableDictionary *adPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SRAdPlistPath] ?: [NSMutableDictionary dictionary];
                                                                      adPlist[adImageURLString] = adURLString;
                                                                      [adPlist writeToFile:SRAdPlistPath atomically:YES];
                                                                      
                                                                      [[NSUserDefaults standardUserDefaults] setObject:adImageURLString forKey:kLastAdImageURLKey];
                                                                  }];
    [getAdTask resume];
}

- (void)showAdvertisement {
    NSString *adImageURLString = [[NSUserDefaults standardUserDefaults] objectForKey:kLastAdImageURLKey];
    UIImage *adImage = [self adImageFromSandboxWithImageURLString:adImageURLString];
    if (!adImage) {
        return;
    }
    
    // create a new window, so that the original view without interference
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.rootViewController = [UIViewController new];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];
    window.rootViewController.view.userInteractionEnabled = NO;
    // set the window to the top, to prevent the UIAlertView popup cover
    window.windowLevel = UIWindowLevelStatusBar + 1;
    
    // the hidden value of window defaults is YES
    window.hidden = NO;
    window.alpha = 1;
    
    // manually held to prevent release
    self.adWindow = window;
    
    // layout advertising view
    UIImageView *adImageView = [[UIImageView alloc] initWithFrame:self.adWindow.bounds];
    adImageView.image = adImage;
    adImageView.userInteractionEnabled = YES;
    [adImageView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAdvertisement)]];
    [self.adWindow addSubview:adImageView];
    
    _countdownBtn = [[UIButton alloc] initWithFrame:CGRectMake(self.adWindow.bounds.size.width - 60 - 10, 20, 60, 30)];
    _countdownBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    _countdownBtn.layer.cornerRadius = 15;
    _countdownBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    _countdownBtn.layer.borderWidth = 1.0;
    _countdownBtn.titleLabel.font = [UIFont systemFontOfSize:12.5];
    [_countdownBtn addTarget:self action:@selector(dismissAdvertisement) forControlEvents:UIControlEventTouchUpInside];
    [self.adWindow addSubview:_countdownBtn];
    
    // reset countdown timer then start countdown
    self.countdownTimer = self.countdown;
    [self startCountdown];
}

- (void)startCountdown {
    [self.countdownBtn setTitle:[NSString stringWithFormat:@"跳过:%zd", self.countdownTimer] forState:UIControlStateNormal];
    
    if (self.countdownTimer == 0) {
        [self dismissAdvertisement];
    } else {
        self.countdownTimer--;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startCountdown];
        });
    }
}

- (void)tapAdvertisement {
    NSMutableDictionary *adPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SRAdPlistPath];
    NSString *adImageURLString = [[NSUserDefaults standardUserDefaults] objectForKey:kLastAdImageURLKey];
    if (self.tapAdBlock) {
        self.tapAdBlock(adPlist[adImageURLString]);
    } else {
        NSURL *adURL = [NSURL URLWithString:adPlist[adImageURLString]];
        if ([[UIApplication sharedApplication] canOpenURL:adURL]) {
            [[UIApplication sharedApplication] openURL:adURL];
        }
    }
    [self dismissAdvertisement];
}

- (void)dismissAdvertisement {
    [UIView animateWithDuration:0.5 animations:^{
        self.adWindow.alpha = 0;
    } completion:^(BOOL finished) {
        [self.adWindow.subviews.copy enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [obj removeFromSuperview];
        }];
        self.adWindow = nil;
    }];
}

#pragma mark - Assist Methods

- (BOOL)isFirstLaunchApp {
    NSString *lastVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"CFBundleShortVersionString"];  // the app version in the sandbox
    NSString *currentVersion = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"]; // the current app version
    if ([currentVersion isEqualToString:lastVersion]) {
        return NO;
    } else {
        // not recommended to take keyWindow directly, because when UIAlertView or keyboard pop-up, the keyWindow is not accurate
        //UIViewController *rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
        [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"CFBundleShortVersionString"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return YES;
    }
}

- (UIImage *)adImageFromSandboxWithImageURLString:(NSString *)imageURLString {
    NSString *imagePath = SRAdImagePath(imageURLString);
    NSData *data = [NSData dataWithContentsOfFile:imagePath];
    if (data.length > 0 ) {
        return [UIImage imageWithData:data];
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:imagePath error:NULL];
    }
    return nil;
}

- (void)downloadAdImageURLString:(NSString *)imageURLString {
    UIImage *image = [self adImageFromSandboxWithImageURLString:imageURLString];
    if (image) {
        return;
    }
    if ([self cachedAdImagesSize] > 10.0) {
        [self clearCachedAdImages];
    }
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:imageURLString]
                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                     dispatch_async(dispatch_get_main_queue(), ^{
                                         if (error) {
                                             NSLog(@"download ad image error: %@", error);
                                             return;
                                         }
                                         UIImage *image = [UIImage imageWithData:data];
                                         if (!image) {
                                             return;
                                         }
                                         [self saveImageWithData:data imageURLString:imageURLString];
                                     });
                                 }] resume];
}

- (void)saveImageWithData:(NSData *)data imageURLString:(NSString *)imageURLString {
    NSError *error = nil;
    if (![data writeToFile:SRAdImagePath(imageURLString) options:NSDataWritingFileProtectionNone error:&error]) {
        NSLog(@"save ad image error: %@", error);
        [SRAdvertisementLoader createImagesDirectory];
        if (![data writeToFile:SRAdImagePath(imageURLString) options:NSDataWritingFileProtectionNone error:&error]) {
            NSLog(@"save ad image error: %@", error);
        } else {
            NSLog(@"save ad image success");
        }
    } else {
        NSLog(@"save ad image success");
    }
}

- (CGFloat)cachedAdImagesSize {
    long long directorySize = 0;
    NSString *fileName = nil;
    NSDirectoryEnumerator *childFilesEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:SRAdImagesDirectory];
    while ((fileName = [childFilesEnumerator nextObject]) != nil) {
        NSString *filePath = [SRAdImagesDirectory stringByAppendingPathComponent:fileName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            CGFloat fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
            directorySize += fileSize;
        }
    }
    return directorySize / (1024.0 * 1024.0);
}

- (void)clearCachedAdImages {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *fileNames = [fileManager contentsOfDirectoryAtPath:SRAdImagesDirectory error:nil];
    for (NSString *fileName in fileNames) {
        NSError *error = nil;
        if (![fileManager removeItemAtPath:[SRAdImagesDirectory stringByAppendingPathComponent:fileName] error:&error]) {
            NSLog(@"removeItemAtPath error: %@", error);
        }
    }
}

@end
