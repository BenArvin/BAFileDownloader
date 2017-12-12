//
//  BAFileDownloadOperation.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BAFileDownloadTask;
@class BAFileDownloadOperation;

@protocol BAFileDownloadOperationDelegate <NSObject>
@optional
- (void)fileDownloadOperation:(BAFileDownloadOperation *)operation finished:(NSError *)error;

@end

@interface BAFileDownloadOperation : NSObject

@property (nonatomic, weak) id <BAFileDownloadOperationDelegate> delegate;
@property (nonatomic, readonly) NSString *URL;

- (void)addTask:(BAFileDownloadTask *)task;
- (void)removeTask:(BAFileDownloadTask *)task;

- (void)start;//async
- (void)pause;//async

@end
