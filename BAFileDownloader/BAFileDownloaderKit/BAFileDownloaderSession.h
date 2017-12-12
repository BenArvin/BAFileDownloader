//
//  BAFileDownloaderSession.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/6.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BAFileDownloaderSession : NSObject

+ (NSURLSession *)sharedSession;

@end
