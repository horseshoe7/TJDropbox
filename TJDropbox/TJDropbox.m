//
//  TJDropbox.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropbox.h"

NSString *const TJDropboxErrorDomain = @"TJDropboxErrorDomain";
NSString *const TJDropboxErrorUserInfoKeyResponse = @"response";
NSString *const TJDropboxErrorUserInfoKeyDropboxError = @"dropboxError";
NSString *const TJDropboxErrorUserInfoKeyErrorString = @"errorString";

@implementation TJDropbox

#pragma mark - Authentication

+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *const)redirectURL
{
    // https://www.dropbox.com/developers/documentation/http/documentation#auth
    
    NSURLComponents *const components = [NSURLComponents componentsWithURL:[NSURL URLWithString:@"https://www.dropbox.com/1/oauth2/authorize"] resolvingAgainstBaseURL:NO];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
        [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURL.absoluteString],
        [NSURLQueryItem queryItemWithName:@"response_type" value:@"token"]
    ];
    return components.URL;
}

+ (nullable NSString *)accessTokenFromURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL
{
    NSString *accessToken = nil;
    if ([url.absoluteString hasPrefix:redirectURL.absoluteString]) {
        NSString *const fragment = url.fragment;
        NSURLComponents *const components = [NSURLComponents new];
        components.query = fragment;
        for (NSURLQueryItem *const item in components.queryItems) {
            if ([item.name isEqualToString:@"access_token"]) {
                accessToken = item.value;
                break;
            }
        }
    }
    return accessToken;
}

+ (NSURL *)dropboxAppAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier
{
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L288-L303
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L274-L282
    
    NSURLComponents *const components = [NSURLComponents componentsWithString:@"dbapi-2://1/connect"];
    NSString *const nonce = [[NSUUID UUID] UUIDString];
    NSString *const stateString = [NSString stringWithFormat:@"oauth2:%@", nonce];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"k" value:clientIdentifier],
        [NSURLQueryItem queryItemWithName:@"s" value:@""],
        [NSURLQueryItem queryItemWithName:@"state" value:stateString]
    ];
    return components.URL;
}

+ (nullable NSString *)accessTokenFromDropboxAppAuthenticationURL:(NSURL *const)url
{
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L360-L383
    
    NSString *accessToken = nil;
    if ([url.scheme hasPrefix:@"db-"] && [url.host isEqualToString:@"1"] && [url.path isEqualToString:@"/connect"]) {
        NSURLComponents *const components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"oauth_token_secret"] && queryItem.value.length > 0) {
                accessToken = queryItem.value;
                break;
            }
        }
    }
    return accessToken;
}

+ (void)migrateV1TokenToV2Token:(NSString *const)accessToken accessTokenSecret:(NSString *const)accessTokenSecret appKey:(NSString *const)appKey appSecret:(NSString *const)appSecret completion:(void (^const)(NSString *_Nullable, NSError *_Nullable))completion
{
    // https://www.dropbox.com/developers/reference/migration-guide#authentication
    // https://www.dropbox.com/developers-v1/core/docs#oa2-from-oa1
    // https://www.dropboxforum.com/hc/en-us/community/posts/204375656-Migrating-oauth1-to-oauth2-using-token-from-oauth1-
    // https://blogs.dropbox.com/developers/2012/07/using-oauth-1-0-with-the-plaintext-signature-method/
    
    NSMutableURLRequest *const request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.dropbox.com/1/oauth2/token_from_oauth1"]];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"OAuth oauth_version=\"1.0\", oauth_signature=\"PLAINTEXT\", oauth_consumer_key=\"%@\", oauth_token=\"%@\", oauth_signature=\"%@&%@\"", appKey, accessToken, appSecret, accessTokenSecret] forHTTPHeaderField:@"Authorization"];
    [self performAPIRequest:request withCompletion:^(NSDictionary *parsedResponse, NSError *error) {
        completion(parsedResponse[@"access_token"], error);
    }];
}

#pragma mark - Generic

+ (NSMutableURLRequest *)requestWithBaseURLString:(NSString *const)baseURLString path:(NSString *const)path accessToken:(NSString *const)accessToken
{
    NSURLComponents *const components = [[NSURLComponents alloc] initWithString:baseURLString];
    components.path = path;
    
    NSMutableURLRequest *const request = [[NSMutableURLRequest alloc] initWithURL:components.URL];
    request.HTTPMethod = @"POST";
    NSString *const authorization = [NSString stringWithFormat:@"Bearer %@", accessToken];
    [request addValue:authorization forHTTPHeaderField:@"Authorization"];
    
    return request;
}

+ (NSData *)parameterDataForParameters:(NSDictionary<NSString *, NSString *> *)parameters
{
    NSData *parameterData = nil;
    if (parameters.count > 0) {
        NSError *error = nil;
        parameterData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&error];
        if (error) {
            NSLog(@"[TJDropbox] - Error in %s: %@", __PRETTY_FUNCTION__, error);
        }
    }
    return parameterData;
}

+ (NSURLRequest *)apiRequestWithPath:(NSString *const)path accessToken:(NSString *const)accessToken parameters:(NSDictionary<NSString *, NSString *> *const)parameters
{
    NSMutableURLRequest *const request = [self requestWithBaseURLString:@"https://api.dropboxapi.com" path:path accessToken:accessToken];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [self parameterDataForParameters:parameters];
    return request;
}

+ (NSMutableURLRequest *)contentRequestWithPath:(NSString *const)path accessToken:(NSString *const)accessToken parameters:(NSDictionary<NSString *, NSString *> *const)parameters
{
    NSMutableURLRequest *const request = [self requestWithBaseURLString:@"https://content.dropboxapi.com" path:path accessToken:accessToken];
    NSData *const parameterData = [self parameterDataForParameters:parameters];
    if (parameterData) {
        NSString *const parameterString = [[NSString alloc] initWithData:parameterData encoding:NSUTF8StringEncoding];
        [request setValue:parameterString forHTTPHeaderField:@"Dropbox-API-Arg"];
    }
    return request;
}

+ (NSURLSession *)session
{
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    });
    return session;
}

+ (NSHashTable<NSURLSessionTask *> *)tasks
{
    static NSHashTable<NSURLSessionTask *> *hashTable = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hashTable = [NSHashTable weakObjectsHashTable];
    });
    return hashTable;
}

+ (void)performAPIRequest:(NSURLRequest *)request withCompletion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLSessionTask *const task = [[self session] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *parsedResult = nil;
        [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
        completion(parsedResult, error);
    }];
    [[self tasks] addObject:task];
    [task resume];
}

+ (NSData *)resultDataForContentRequestResponse:(NSURLResponse *const)response
{
    NSHTTPURLResponse *const httpURLResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    NSString *const resultString = httpURLResponse.allHeaderFields[@"Dropbox-API-Result"];
    NSData *const resultData = [resultString dataUsingEncoding:NSUTF8StringEncoding];
    return resultData;
}

+ (BOOL)processResultJSONData:(NSData *const)data response:(NSURLResponse *const)response error:(inout NSError **)error parsedResult:(out NSDictionary **)parsedResult
{
    NSString *errorString = nil;
    if (data.length > 0) {
        id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([result isKindOfClass:[NSDictionary class]]) {
            *parsedResult = result;
        } else {
            errorString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }
    
    // Things leading to errors
    // 1. error returned to this block
    // 2. dropboxAPIErrorDictionary populated
    // 3. Status code >= 400
    // 4. errorString populated
    
    NSHTTPURLResponse *const httpURLResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    const NSInteger statusCode = [httpURLResponse statusCode];
    NSDictionary *const dropboxAPIErrorDictionary = [*parsedResult objectForKey:@"error"];
    
    if (!*error) {
        if (statusCode >= 400 || dropboxAPIErrorDictionary || !*parsedResult) {
            NSMutableDictionary *const userInfo = [NSMutableDictionary new];
            if (response) {
                [userInfo setObject:response forKey:TJDropboxErrorUserInfoKeyResponse];
            }
            if (dropboxAPIErrorDictionary) {
                [userInfo setObject:dropboxAPIErrorDictionary forKey:TJDropboxErrorUserInfoKeyDropboxError];
            }
            if (errorString) {
                [userInfo setObject:errorString forKey:TJDropboxErrorUserInfoKeyErrorString];
            }
            *error = [NSError errorWithDomain:TJDropboxErrorDomain code:0 userInfo:userInfo];
        }
    }
    
    return *error == nil;
}

#pragma mark - File Inspection

+ (NSURLRequest *)listFolderRequestWithPath:(NSString *const)filePath
                                accessToken:(NSString *const)accessToken
                             includeDeleted:(BOOL)includeDeleted
                                     cursor:(nullable NSString *const)cursor
{
    NSString *const urlPath = cursor.length > 0 ? @"/2/files/list_folder/continue" : @"/2/files/list_folder";
    NSMutableDictionary *const parameters = [NSMutableDictionary new];
    if (cursor.length > 0) {
        [parameters setObject:cursor forKey:@"cursor"];
    } else {
        [parameters setObject:filePath forKey:@"path"];
    }
    
    [parameters setObject:@(includeDeleted) forKey:@"include_deleted"];
    
    return [self apiRequestWithPath:urlPath accessToken:accessToken parameters:parameters];
}

+ (void)listFolderWithPath:(NSString *const)path
               accessToken:(NSString *const)accessToken
            includeDeleted:(BOOL)includeDeleted
                completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    [self listFolderWithPath:path cursor:nil accessToken:accessToken includeDeleted:includeDeleted completion:completion];
}

+ (void)listFolderWithPath:(NSString *const)path
                    cursor:(nullable NSString *const)cursor
               accessToken:(NSString *const)accessToken
            includeDeleted:(BOOL)includeDeleted
                completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    [self listFolderWithPath:path accessToken:accessToken cursor:cursor includeDeleted:includeDeleted accumulatedFiles:nil completion:completion];
}

+ (void)listFolderWithPath:(NSString *const)path
               accessToken:(NSString *const)accessToken
                    cursor:(NSString *const)cursor
            includeDeleted:(BOOL)includeDeleted
          accumulatedFiles:(NSArray *const)accumulatedFiles
                completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self listFolderRequestWithPath:path accessToken:accessToken includeDeleted:includeDeleted cursor:cursor];
    [self performAPIRequest:request withCompletion:^(NSDictionary *parsedResponse, NSError *error) {
        if (!error) {
            NSArray *const files = [parsedResponse objectForKey:@"entries"];
            NSArray *const newlyAccumulatedFiles = accumulatedFiles.count > 0 ? [accumulatedFiles arrayByAddingObjectsFromArray:files] : files;
            const BOOL hasMore = [[parsedResponse objectForKey:@"has_more"] boolValue];
            NSString *const cursor = [parsedResponse objectForKey:@"cursor"];
            if (hasMore) {
                if (cursor) {
                    // Fetch next page
                    [self listFolderWithPath:path accessToken:accessToken cursor:cursor includeDeleted:includeDeleted accumulatedFiles:newlyAccumulatedFiles completion:completion];
                } else {
                    // We can't load more without a cursor
                    completion(nil, nil, error);
                }
            } else {
                // All files fetched, finish.
                completion(newlyAccumulatedFiles, cursor, error);
            }
        } else {
            completion(nil, nil, error);
        }
    }];
}

+ (void)getFileInfoAtPath:(NSString *const)remotePath
              accessToken:(NSString *const)accessToken
               completion:(void (^const)(NSDictionary *_Nullable entry,
                                         NSError *_Nullable error))completion
{
    NSDictionary *parameters = @{@"path" : remotePath};
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/get_metadata" accessToken:accessToken parameters:parameters];
    
    [self performAPIRequest:request
             withCompletion:completion];
    
    /*
     EXAMPLE RESPONSE:
     {
     ".tag": "file",
     "name": "Prime_Numbers.txt",
     "path_lower": "/homework/math/prime_numbers.txt",
     "path_display": "/Homework/math/Prime_Numbers.txt",
     "id": "id:a4ayc_80_OEAAAAAAAAAXw",
     "client_modified": "2015-05-12T15:50:38Z",
     "server_modified": "2015-05-12T15:50:38Z",
     "rev": "a1c10ce0dd78",
     "size": 7212,
     "sharing_info": {
     "read_only": true,
     "parent_shared_folder_id": "84528192421",
     "modified_by": "dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc"
     },
     "has_explicit_shared_members": false
     }
     */
}


#pragma mark - File Manipulation

+ (void)downloadFileAtPath:(NSString *const)remotePath
                    toPath:(NSString *const)localPath
               accessToken:(NSString *const)accessToken
                parameters:(nullable NSDictionary*)parameters
                completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSMutableDictionary *fullParameters = @{@"path" : remotePath}.mutableCopy;
    if (parameters) {
        [fullParameters addEntriesFromDictionary:parameters];
    }
    
    NSURLRequest *const request = [self contentRequestWithPath:@"/2/files/download" accessToken:accessToken parameters:fullParameters];
    
    NSURLSessionTask *const task = [[self session] downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *parsedResult = nil;
        NSData *const resultData = [self resultDataForContentRequestResponse:response];
        [self processResultJSONData:resultData response:response error:&error parsedResult:&parsedResult];
        
        if (!error && location) {
            // Move file into place
            if ([[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:localPath error:&error];
                
                if (error) {
                    NSLog(@"Problem moving downloaded file: %@", error.localizedDescription);
                }
                error = nil;
            }
            
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath] error:&error];
        }
        
        completion(parsedResult, error);
    }];
    [[self tasks] addObject:task];
    [task resume];
}

+ (void)uploadFileAtPath:(NSString *const)localPath
                  toPath:(NSString *const)remotePath
             accessToken:(NSString *const)accessToken
              parameters:(nullable NSDictionary*)parameters
              completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    
    
    NSMutableDictionary *fullParameters = @{@"path" : remotePath}.mutableCopy;
    if (parameters) {
        [fullParameters addEntriesFromDictionary:parameters];
    }
    
    
    NSMutableURLRequest *const request = [self contentRequestWithPath:@"/2/files/upload" accessToken:accessToken parameters:fullParameters];
    
    NSURLSessionTask *const task = [[self session] uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:localPath] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *parsedResult = nil;
        [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
        
        completion(parsedResult, error);
    }];
    [[self tasks] addObject:task];
    [task resume];
}

+ (void)moveFileAtPath:(NSString *const)fromPath
                toPath:(NSString *const)toPath
           accessToken:(NSString *const)accessToken
            parameters:(nullable NSDictionary*)parameters
            completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    if (!fromPath || !toPath) {
        NSLog(@"You can't move a file if you don't provide paths!");
        if (completion) {
            
            NSError *pathError = [NSError errorWithDomain:TJDropboxErrorDomain
                                                     code:-1
                                                 userInfo:@{NSLocalizedDescriptionKey : @"You can't move a file if you don't provide for/to paths!"}];
            
            completion(nil, pathError);
        }
        return;
    }
    
    NSMutableDictionary *fullParameters = @{@"from_path" : fromPath,
                                            @"to_path" : toPath}.mutableCopy;
    if (parameters) {
        [fullParameters addEntriesFromDictionary:parameters];
    }
    
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/move" accessToken:accessToken parameters:fullParameters];
    
    [self performAPIRequest:request withCompletion:completion];
}

+ (void)deleteFileAtPath:(NSString *const)path
             accessToken:(NSString *const)accessToken
              parameters:(nullable NSDictionary*)parameters
              completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSMutableDictionary *fullParameters = @{@"path" : path}.mutableCopy;
    if (parameters) {
        [fullParameters addEntriesFromDictionary:parameters];
    }
    
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/delete" accessToken:accessToken parameters:fullParameters];
    
    [self performAPIRequest:request withCompletion:completion];
}

#pragma mark - Sharing

+ (void)getSharedLinkForFileAtPath:(NSString *const)path
                       accessToken:(NSString *const)accessToken
                        parameters:(nullable NSDictionary*)parameters
                        completion:(void (^const)(NSString *_Nullable urlString))completion
{
    NSMutableDictionary *fullParameters = @{@"path" : path}.mutableCopy;
    if (parameters) {
        [fullParameters addEntriesFromDictionary:parameters];
    }
    
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/sharing/create_shared_link_with_settings" accessToken:accessToken parameters:fullParameters];
    [self performAPIRequest:request withCompletion:^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        completion(parsedResponse[@"url"]);
    }];
}

#pragma mark - Request Management

+ (void)cancelAllRequests
{
    for (NSURLSessionTask *const task in [self tasks]) {
        [task cancel];
    }
}

@end
