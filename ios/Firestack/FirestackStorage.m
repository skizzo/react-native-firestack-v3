//
//  FirestackStorage.m
//  Firestack
//
//  Created by Ari Lerner on 8/24/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import "FirestackStorage.h"
#import "FirestackEvents.h"

#import <Photos/Photos.h>

@implementation FirestackStorage

RCT_EXPORT_MODULE(FirestackStorage);

// Run on a different thread
- (dispatch_queue_t)methodQueue
{
  return dispatch_queue_create("io.fullstack.firestack.storage", DISPATCH_QUEUE_SERIAL);
}

RCT_EXPORT_METHOD(delete: (NSString *) path
                  callback:(RCTResponseSenderBlock) callback)
{
    
    FIRStorageReference *fileRef = [self getReference:path];
    [fileRef deleteWithCompletion:^(NSError * _Nullable error) {
        if (error == nil) {
            NSDictionary *resp = @{
                                   @"status": @"success",
                                   @"path": path
                                   };
            callback(@[[NSNull null], resp]);
        } else {
            NSDictionary *evt = @{
                                  @"status": @"error",
                                  @"path": path,
                                  @"message": [error debugDescription]
                                  };
            callback(@[evt]);
        }
    }];
}

RCT_EXPORT_METHOD(getDownloadURL: (NSString *) path
                  callback:(RCTResponseSenderBlock) callback)
{
    FIRStorageReference *fileRef = [self getReference:path];
    [fileRef downloadURLWithCompletion:^(NSURL * _Nullable URL, NSError * _Nullable error) {
        if (error != nil) {
            NSDictionary *evt = @{
                                  @"status": @"error",
                                  @"path": path,
                                  @"message": [error debugDescription]
                                  };
            callback(@[evt]);
        } else {
            callback(@[[NSNull null], [URL absoluteString]]);
        }
    }];
}

RCT_EXPORT_METHOD(getMetadata: (NSString *) path
                    callback:(RCTResponseSenderBlock) callback)
{
    FIRStorageReference *fileRef = [self getReference:path];
    [fileRef metadataWithCompletion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
        if (error != nil) {
            NSDictionary *evt = @{
                                  @"status": @"error",
                                  @"path": path,
                                  @"message": [error debugDescription]
                                  };
            callback(@[evt]);
        } else {
            NSDictionary *resp = [metadata dictionaryRepresentation];
            callback(@[[NSNull null], resp]);
        }
    }];
}

RCT_EXPORT_METHOD(updateMetadata: (NSString *) path
                        metadata:(NSDictionary *) metadata
                        callback:(RCTResponseSenderBlock) callback)
{
    FIRStorageReference *fileRef = [self getReference:path];
    FIRStorageMetadata *firmetadata = [[FIRStorageMetadata alloc] initWithDictionary:metadata];
    [fileRef updateMetadata:firmetadata completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
        if (error != nil) {
            NSDictionary *evt = @{
                                  @"status": @"error",
                                  @"path": path,
                                  @"message": [error debugDescription]
                                  };
            callback(@[evt]);
        } else {
            NSDictionary *resp = [metadata dictionaryRepresentation];
            callback(@[[NSNull null], resp]);
        }
    }];
}

RCT_EXPORT_METHOD(downloadFile: (NSString *) path
                  localPath:(NSString *) localPath
                  callback:(RCTResponseSenderBlock) callback)
{
    FIRStorageReference *fileRef = [self getReference:path];
    NSURL *localFile = [NSURL fileURLWithPath:localPath];
    
    FIRStorageDownloadTask *downloadTask = [fileRef writeToFile:localFile];
    // Listen for state changes, errors, and completion of the download.
    [downloadTask observeStatus:FIRStorageTaskStatusResume handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Download resumed, also fires when the upload starts
        NSDictionary *event = [self getDownloadTaskAsDictionary:snapshot];
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_STATE_CHANGED props:event];
    }];
    
    [downloadTask observeStatus:FIRStorageTaskStatusPause handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Download paused
        NSDictionary *event = [self getDownloadTaskAsDictionary:snapshot];
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_STATE_CHANGED props:event];
    }];
    [downloadTask observeStatus:FIRStorageTaskStatusProgress handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Download reported progress
        NSDictionary *event = [self getDownloadTaskAsDictionary:snapshot];
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_STATE_CHANGED props:event];
    }];
    
    [downloadTask observeStatus:FIRStorageTaskStatusSuccess handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Download completed successfully
        NSDictionary *resp = [self getDownloadTaskAsDictionary:snapshot];
        
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_DOWNLOAD_SUCCESS props:resp];
        callback(@[[NSNull null], resp]);
    }];
    
    [downloadTask observeStatus:FIRStorageTaskStatusFailure handler:^(FIRStorageTaskSnapshot *snapshot) {
        if (snapshot.error != nil) {
            NSDictionary *errProps = [[NSMutableDictionary alloc] init];
            NSLog(@"Error in download: %@", snapshot.error);
            
            switch (snapshot.error.code) {
                case FIRStorageErrorCodeObjectNotFound:
                    // File doesn't exist
                    [errProps setValue:@"File does not exist" forKey:@"message"];
                    break;
                case FIRStorageErrorCodeUnauthorized:
                    // User doesn't have permission to access file
                    [errProps setValue:@"You do not have permissions" forKey:@"message"];
                    break;
                case FIRStorageErrorCodeCancelled:
                    // User canceled the upload
                    [errProps setValue:@"Download canceled" forKey:@"message"];
                    break;
                case FIRStorageErrorCodeUnknown:
                    // Unknown error occurred, inspect the server response
                    [errProps setValue:@"Unknown error" forKey:@"message"];
                    break;
            }
            
            //TODO: Error event
            callback(@[errProps]);
        }}];
}


RCT_EXPORT_METHOD(putFile:(NSString *) path
                  localPath:(NSString *)localPath
                  metadata:(NSDictionary *)metadata
                  callback:(RCTResponseSenderBlock) callback)
{
    FIRStorageReference *fileRef = [self getReference:path];
    FIRStorageMetadata *firmetadata = [[FIRStorageMetadata alloc] initWithDictionary:metadata];

    if ([localPath hasPrefix:@"assets-library://"]) {
        NSURL *localFile = [[NSURL alloc] initWithString:localPath];
        PHFetchResult* assets = [PHAsset fetchAssetsWithALAssetURLs:@[localFile] options:nil];
        PHAsset *asset = [assets firstObject];

        [[PHImageManager defaultManager] requestImageDataForAsset:asset
                                                          options:nil
                                                    resultHandler:^(NSData * imageData, NSString * dataUTI, UIImageOrientation orientation, NSDictionary * info) {
                                                        FIRStorageUploadTask *uploadTask = [fileRef putData:imageData
                                                                                                   metadata:firmetadata];
                                                        [self addUploadObservers:uploadTask
                                                                            path:path
                                                                        callback:callback];
                                                    }];
    } else {
        NSURL *imageFile = [NSURL fileURLWithPath:localPath];
        FIRStorageUploadTask *uploadTask = [fileRef putFile:imageFile
                                                   metadata:firmetadata];
        
        [self addUploadObservers:uploadTask
                            path:path
                        callback:callback];
    }

}

- (void) addUploadObservers:(FIRStorageUploadTask *) uploadTask
                       path:(NSString *) path
                   callback:(RCTResponseSenderBlock) callback
{
    // Listen for state changes, errors, and completion of the upload.
    [uploadTask observeStatus:FIRStorageTaskStatusResume handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Upload resumed, also fires when the upload starts
        NSDictionary *event = [self getUploadTaskAsDictionary:snapshot];
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_STATE_CHANGED props:event];
    }];

    [uploadTask observeStatus:FIRStorageTaskStatusPause handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Upload paused
        NSDictionary *event = [self getUploadTaskAsDictionary:snapshot];
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_STATE_CHANGED props:event];
    }];
    [uploadTask observeStatus:FIRStorageTaskStatusProgress handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Upload reported progress
        NSDictionary *event = [self getUploadTaskAsDictionary:snapshot];
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_STATE_CHANGED props:event];
    }];

    [uploadTask observeStatus:FIRStorageTaskStatusSuccess handler:^(FIRStorageTaskSnapshot *snapshot) {
        // Upload completed successfully
        NSDictionary *resp = [self getUploadTaskAsDictionary:snapshot];
        
        [self sendJSEvent:STORAGE_EVENT path:path title:STORAGE_UPLOAD_SUCCESS props:resp];
        callback(@[[NSNull null], resp]);
    }];

    [uploadTask observeStatus:FIRStorageTaskStatusFailure handler:^(FIRStorageTaskSnapshot *snapshot) {
        if (snapshot.error != nil) {
            NSDictionary *errProps = [[NSMutableDictionary alloc] init];

            switch (snapshot.error.code) {
                case FIRStorageErrorCodeObjectNotFound:
                    // File doesn't exist
                    [errProps setValue:@"File does not exist" forKey:@"message"];
                    break;
                case FIRStorageErrorCodeUnauthorized:
                    // User doesn't have permission to access file
                    [errProps setValue:@"You do not have permissions" forKey:@"message"];
                    break;
                case FIRStorageErrorCodeCancelled:
                    // User canceled the upload
                    [errProps setValue:@"Upload cancelled" forKey:@"message"];
                    break;
                case FIRStorageErrorCodeUnknown:
                    // Unknown error occurred, inspect the server response
                    [errProps setValue:@"Unknown error" forKey:@"message"];
                    break;
            }

            //TODO: Error event
            callback(@[errProps]);
        }}];
}

//Firebase.Storage methods
RCT_EXPORT_METHOD(setMaxDownloadRetryTime:(NSNumber *) milliseconds)
{
    [[FIRStorage storage] setMaxDownloadRetryTime:[milliseconds doubleValue]];
}

RCT_EXPORT_METHOD(setMaxOperationRetryTime:(NSNumber *) milliseconds)
{
    [[FIRStorage storage] setMaxOperationRetryTime:[milliseconds doubleValue]];
}

RCT_EXPORT_METHOD(setMaxUploadRetryTime:(NSNumber *) milliseconds)
{
    [[FIRStorage storage] setMaxUploadRetryTime:[milliseconds doubleValue]];
}

- (FIRStorageReference *)getReference:(NSString *)path
{
    if ([path hasPrefix:@"url::"]) {
        NSString *url = [path substringFromIndex:5];
        return [[FIRStorage storage] referenceForURL:url];
    } else {
        return [[FIRStorage storage] referenceWithPath:path];
    }
}

- (NSDictionary *)getDownloadTaskAsDictionary:(FIRStorageTaskSnapshot *)task {
    return @{
             @"bytesTransferred": @(task.progress.completedUnitCount),
             @"ref": task.reference.fullPath,
             @"status": [self getTaskStatus:task.status],
             @"totalBytes": @(task.progress.totalUnitCount)
             };
}

- (NSDictionary *)getUploadTaskAsDictionary:(FIRStorageTaskSnapshot *)task
{
    NSString *downloadUrl = [task.metadata.downloadURL absoluteString];
    FIRStorageMetadata *metadata = [task.metadata dictionaryRepresentation];
    return @{
             @"bytesTransferred": @(task.progress.completedUnitCount),
             @"downloadUrl": downloadUrl != nil ? downloadUrl : [NSNull null],
             @"metadata": metadata != nil ? metadata : [NSNull null],
             @"ref": task.reference.fullPath,
             @"state": [self getTaskStatus:task.status],
             @"totalBytes": @(task.progress.totalUnitCount)
             };
}

- (NSString *)getTaskStatus:(FIRStorageTaskStatus)status
{
    if (status == FIRStorageTaskStatusResume || status == FIRStorageTaskStatusProgress) {
        return @"RUNNING";
    } else if (status == FIRStorageTaskStatusPause) {
        return @"PAUSED";
    } else if (status == FIRStorageTaskStatusSuccess) {
        return @"SUCCESS";
    } else if (status == FIRStorageTaskStatusFailure) {
        return @"ERROR";
    } else {
        return @"UNKNOWN";
    }
}

// This is just too good not to use, but I don't want to take credit for
// this work from RNFS
// https://github.com/johanneslumpe/react-native-fs/blob/master/RNFSManager.m
- (NSString *)getPathForDirectory:(int)directory
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
  return [paths firstObject];
}

- (NSDictionary *)constantsToExport
{
  return @{
           @"MAIN_BUNDLE_PATH": [[NSBundle mainBundle] bundlePath],
           @"CACHES_DIRECTORY_PATH": [self getPathForDirectory:NSCachesDirectory],
           @"DOCUMENT_DIRECTORY_PATH": [self getPathForDirectory:NSDocumentDirectory],
           @"EXTERNAL_DIRECTORY_PATH": [NSNull null],
           @"EXTERNAL_STORAGE_DIRECTORY_PATH": [NSNull null],
           @"TEMP_DIRECTORY_PATH": NSTemporaryDirectory(),
           @"LIBRARY_DIRECTORY_PATH": [self getPathForDirectory:NSLibraryDirectory],
           @"FILETYPE_REGULAR": NSFileTypeRegular,
           @"FILETYPE_DIRECTORY": NSFileTypeDirectory
           };
}

// Not sure how to get away from this... yet
- (NSArray<NSString *> *)supportedEvents {
    return @[STORAGE_EVENT, STORAGE_ERROR];
}

- (void) sendJSError:(NSError *) error
                      withPath:(NSString *) path
{
    NSDictionary *evt = @{
                          @"path": path,
                          @"message": [error debugDescription]
                          };
    [self sendJSEvent:STORAGE_ERROR path:path title:STORAGE_ERROR props: evt];
}

- (void) sendJSEvent:(NSString *)type
                path:(NSString *)path
               title:(NSString *)title
               props:(NSDictionary *)props
{
    @try {
        [self sendEventWithName:type
                            body:@{
                                   @"eventName": title,
                                   @"path": path,
                                   @"body": props
                                   }];
        
    }
    @catch (NSException *err) {
        NSLog(@"An error occurred in sendJSEvent: %@", [err debugDescription]);
        NSLog(@"Tried to send: %@ with %@", title, props);
    }
}


@end
