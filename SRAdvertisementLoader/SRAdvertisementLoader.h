//
//  SRAdvertisementLoader.h
//  SRAdvertisementLoaderDemo
//
//  Created by https://github.com/guowilling on 2018/3/2.
//  Copyright © 2018年 SR. All rights reserved.
//

#import <UIKit/UIKit.h>

/**
 The URL to get your advertisement data.
 */
#define SRAdDataURL @"http://easy-auction.arhieasoncs.com/api/advertising"

@interface SRAdvertisementLoader : NSObject

/**
 The time the ad shows, default is 3.0s.
 */
@property (nonatomic, assign) NSInteger countdown;

/**
 default is YES.
 */
@property (nonatomic, assign) BOOL onlyLaunchShowAd;

/**
 The maximum size of cached ad images, cleaning the cache when the current cache size is larger than this, default is 10.0MB.
 */
@property (nonatomic, assign) CGFloat cachedAdImagesMaxSize;

@property (nonatomic, copy) void(^tapAdBlock)(NSString *adURLString);

+ (instancetype)sharedAdvertisementLoader;

@end
