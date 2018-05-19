//
//  BAStreamFileMerger.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/12.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BAStreamFileMerger : NSObject

+ (void)mergeFiles:(NSArray <NSString *> *)slicesPaths into:(NSString *)targetPath finishedBlock:(void(^)(NSError *error))finishedBlock;

@end
