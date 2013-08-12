//
//  MGTwitterEngine+TH.m
//  TwitHunter
//
//  Created by Nicolas Seriot on 5/1/10.
//  Copyright 2010 seriot.ch. All rights reserved.
//

#import "STTwitterOS.h"
#import <Social/Social.h>
#import <Accounts/Accounts.h>

@interface STTwitterOS ()
@property (nonatomic, retain) ACAccountStore *accountStore; // the ACAccountStore must be kept alive for as long as we need an ACAccount instance, see WWDC 2011 Session 124 for more info
@property (nonatomic, retain) NSString *oauthAccessToken;
@property (nonatomic, retain) NSString *oauthAccessTokenSecret;
@end

@implementation STTwitterOS

- (id)init {
    self = [super init];
    self.accountStore = [[[ACAccountStore alloc] init] autorelease];
    return self;
}

- (void)dealloc {
    [_accountStore release];
    [_oauthAccessToken release];
    [_oauthAccessTokenSecret release];
    [super dealloc];
}

- (BOOL)canVerifyCredentials {
    return YES;
}

- (BOOL)hasAccessToTwitter {
#if TARGET_OS_IPHONE
    return [SLComposeViewController isAvailableForServiceType:SLServiceTypeTwitter];
#else
    return YES; // error will be detected later..
#endif
}

- (NSString *)username {
    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];
    ACAccount *twitterAccount = [accounts lastObject];
    return twitterAccount.username;
}

- (void)verifyCredentialsWithSuccessBlock:(void(^)(NSString *username))successBlock errorBlock:(void(^)(NSError *error))errorBlock {
    if([self hasAccessToTwitter] == NO) {
        NSString *message = @"Twitter is not available.";
        NSError *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedDescriptionKey : message}];
        errorBlock(error);
        return;
    }
    
    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    [self.accountStore requestAccessToAccountsWithType:accountType
                                          options:NULL
                                       completion:^(BOOL granted, NSError *error) {
                                           
                                           [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                               
                                               if(granted) {
                                                   
                                                   NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];
                                                   ACAccount *twitterAccount = [accounts lastObject];
                                                   
                                                   successBlock(twitterAccount.username);
                                               } else {
                                                   errorBlock(error);
                                               }
                                               
                                           }];
                                       }];
}

- (void)requestAccessWithCompletionBlock:(void(^)(ACAccount *twitterAccount))completionBlock errorBlock:(void(^)(NSError *))errorBlock {
    
    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    [self.accountStore requestAccessToAccountsWithType:accountType options:nil completion:^(BOOL granted, NSError *error) {
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if(granted) {
                
                NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];
                
                // TODO: let the user choose the account he wants
                ACAccount *twitterAccount = [accounts lastObject];
                
                //                id cred = [twitterAccount credential];
                
                completionBlock(twitterAccount);
            } else {
                NSError *e = error;
                if(e == nil) {
                    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"Cannot access OS X or iOS Twitter account." };
                    e = [NSError errorWithDomain:@"STTwitterOS" code:0 userInfo:userInfo];
                }
                errorBlock(e);
            }
        }];
    }];
}

- (void)fetchAPIResource:(NSString *)resource
           baseURLString:(NSString *)baseURLString
              httpMethod:(NSInteger)httpMethod
              parameters:(NSDictionary *)params
         completionBlock:(void (^)(id response))completionBlock
              errorBlock:(void (^)(NSError *error))errorBlock {
    
    NSData *mediaData = [params valueForKey:@"media[]"];
    
    NSMutableDictionary *paramsWithoutMedia = [[params mutableCopy] autorelease];
    [paramsWithoutMedia removeObjectForKey:@"media[]"];
    
    [self requestAccessWithCompletionBlock:^(ACAccount *twitterAccount) {
        NSString *urlString = [baseURLString stringByAppendingString:resource];
        NSURL *url = [NSURL URLWithString:urlString];
        SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:httpMethod URL:url parameters:paramsWithoutMedia];
        request.account = twitterAccount;
        
        if(mediaData) {
            [request addMultipartData:mediaData withName:@"media[]" type:@"application/octet-stream" filename:@"media.jpg"];
        }
        
        [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
            if(responseData == nil) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    errorBlock(nil);
                }];
                return;
            }
            
            NSError *jsonError = nil;
            NSJSONSerialization *json = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableLeaves error:&jsonError];
            
            if(json == nil) {

                NSString *s = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];

                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionBlock(s);
                }];
                return;
            }
            
            /**/
            
            if([json isKindOfClass:[NSArray class]] == NO && [json valueForKey:@"error"]) {
                
                NSString *message = [json valueForKey:@"error"];
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
                NSError *jsonErrorFromResponse = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:userInfo];
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    errorBlock(jsonErrorFromResponse);
                }];
                
                return;
            }
            
            /**/
            
            id jsonErrors = [json valueForKey:@"errors"];
            
            if(jsonErrors != nil && [jsonErrors isKindOfClass:[NSArray class]] == NO) {
                if(jsonErrors == nil) jsonErrors = @"";
                jsonErrors = [NSArray arrayWithObject:@{@"message":jsonErrors, @"code" : @(0)}];
            }
            
            if([jsonErrors count] > 0 && [jsonErrors lastObject] != [NSNull null]) {
                
                NSDictionary *jsonErrorDictionary = [jsonErrors lastObject];
                NSString *message = jsonErrorDictionary[@"message"];
                NSInteger code = [jsonErrorDictionary[@"code"] intValue];
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
                NSError *jsonErrorFromResponse = [NSError errorWithDomain:NSStringFromClass([self class]) code:code userInfo:userInfo];
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    errorBlock(jsonErrorFromResponse);
                }];
                
                return;
            }
            
            /**/
            
            if(json) {
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionBlock((NSArray *)json);
                }];
                
            } else {
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    errorBlock(jsonError);
                }];
            }
        }];
        
    } errorBlock:^(NSError *error) {
        errorBlock(error);
    }];
}

- (void)fetchResource:(NSString *)resource
           HTTPMethod:(NSString *)HTTPMethod
        baseURLString:(NSString *)baseURLString
           parameters:(NSDictionary *)params
        progressBlock:(void (^)(id))progressBlock // TODO: handle progressBlock?
         successBlock:(void (^)(id))successBlock
           errorBlock:(void(^)(NSError *error))errorBlock {
    
    NSAssert(([ @[@"GET", @"POST"] containsObject:HTTPMethod]), @"unsupported HTTP method");
    
    NSInteger slRequestMethod = SLRequestMethodGET;
    
    NSDictionary *d = params;
    
    if([HTTPMethod isEqualToString:@"POST"]) {
        if (d == nil) d = @{};
        slRequestMethod = SLRequestMethodPOST;
    }
    
    NSString *baseURLStringWithTrailingSlash = baseURLString;
    if([baseURLString hasSuffix:@"/"] == NO) {
        baseURLStringWithTrailingSlash = [baseURLString stringByAppendingString:@"/"];
    }
    
    [self fetchAPIResource:resource
             baseURLString:baseURLStringWithTrailingSlash
                httpMethod:slRequestMethod
                parameters:d
           completionBlock:successBlock
                errorBlock:errorBlock];
}

+ (NSDictionary *)parametersDictionaryFromCommaSeparatedParametersString:(NSString *)s {
    
    NSArray *parameters = [s componentsSeparatedByString:@", "];
    
    NSMutableDictionary *md = [NSMutableDictionary dictionary];
    
    for(NSString *parameter in parameters) {
        // transform k="v" into {'k':'v'}

        NSArray *keyValue = [parameter componentsSeparatedByString:@"="];
        if([keyValue count] != 2) {
            continue;
        }
        
        NSString *value = [keyValue[1] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        
        [md setObject:value forKey:keyValue[0]];
    }
    
    return md;
}

// TODO: this code is duplicated from STTwitterOAuth
+ (NSDictionary *)parametersDictionaryFromAmpersandSeparatedParameterString:(NSString *)s {
    
    NSArray *parameters = [s componentsSeparatedByString:@"&"];
    
    NSMutableDictionary *md = [NSMutableDictionary dictionary];
    
    for(NSString *parameter in parameters) {
        NSArray *keyValue = [parameter componentsSeparatedByString:@"="];
        if([keyValue count] != 2) {
            continue;
        }
        
        [md setObject:keyValue[1] forKey:keyValue[0]];
    }
    
    return md;
}

// reverse auth phase 2
- (void)postReverseAuthAccessTokenWithAuthenticationHeader:(NSString *)authenticationHeader
                                              successBlock:(void(^)(NSString *oAuthToken, NSString *oAuthTokenSecret, NSString *userID, NSString *screenName))successBlock
                                                errorBlock:(void(^)(NSError *error))errorBlock {
    
    NSParameterAssert(authenticationHeader);
    
    NSDictionary *authenticationHeaderDictionary = [[self class] parametersDictionaryFromCommaSeparatedParametersString:authenticationHeader];
    
    NSString *consumerKey = [authenticationHeaderDictionary valueForKey:@"oauth_consumer_key"];
    
    NSAssert((consumerKey != nil), @"cannot find out consumerKey");
    
    NSDictionary *d = @{@"x_reverse_auth_target" : consumerKey,
                        @"x_reverse_auth_parameters" : authenticationHeader};
    
    [self fetchResource:@"oauth/access_token" HTTPMethod:@"GET" baseURLString:@"https://api.twitter.com" parameters:d progressBlock:nil successBlock:^(id response) {
        
        NSDictionary *d = [[self class] parametersDictionaryFromAmpersandSeparatedParameterString:response];
        
        NSString *oAuthToken = [d valueForKey:@"oauth_token"];
        NSString *oAuthTokenSecret = [d valueForKey:@"oauth_token_secret"];
        NSString *userID = [d valueForKey:@"user_id"];
        NSString *screenName = [d valueForKey:@"screen_name"];
        
        self.oauthAccessToken = oAuthToken;
        self.oauthAccessTokenSecret = oAuthTokenSecret;
        
        successBlock(oAuthToken, oAuthTokenSecret, userID, screenName);
    } errorBlock:^(NSError *error) {
        errorBlock(error);
    }];
}
@end
