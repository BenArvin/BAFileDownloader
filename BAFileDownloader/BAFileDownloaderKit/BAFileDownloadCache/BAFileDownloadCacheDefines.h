//
//  BAFileDownloadCacheDefines.h
//  BAFileDownloader
//
//  Created by BenArvin on 2018/7/4.
//  Copyright © 2018年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BAFileDownloadCacheState) {
    BAFileDownloadCacheStateNull = 0,
    BAFileDownloadCacheStatePart,
    BAFileDownloadCacheStateFull,
};
