//
//  TNLResponseTest.m
//  TwitterNetworkLayer
//
//  Created on 11/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLResponse+TNLAdditions.h"
#import "TNLAttemptMetaData.h"
#import "TNLAttemptMetaData_Project.h"
#import "TNLAttemptMetrics_Project.h"
#import "TNLRequest.h"
#import "TNLResponse_Project.h"

@import XCTest;

// we need a leaway of at least 1 second since the timing is only to the 1 second granularity level
// that means rounding/truncation of the time could have the timing be up to a second off
#define ACCURACY_LEEWAY (1.15)

@interface TNLResponseTest : XCTestCase

@end

@implementation TNLResponseTest

- (void)testNSCoding
{
    NSURLRequest *finalRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://m.dummy.com"]];
    NSHTTPURLResponse *urlResponse = [[NSHTTPURLResponse alloc] initWithURL:finalRequest.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Header1" : @"Value1" }];
    id<TNLTemporaryFile> tempFile = nil;
    TNLResponseSource source = TNLResponseSourceNetworkRequest;
    NSData *data = [@"{ success: true }" dataUsingEncoding:NSUTF8StringEncoding];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.dummy.co"]];
    NSError *error = nil;

    uint64_t enqueueTime, firstAttemptStartTime, currentAttemptStartTime, currentAttemptEndTime, completeTime = 0;
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];
    metaData.HTTPVersion = @"1.1";

    NSData *archive = nil;

    enqueueTime = (UInt64)(NSEC_PER_SEC * CFAbsoluteTimeGetCurrent());
    firstAttemptStartTime = currentAttemptStartTime = enqueueTime + (NSEC_PER_SEC * 1ULL); // 1 sec later
    currentAttemptEndTime = currentAttemptStartTime + (NSEC_PER_SEC * 1ULL); // 1 sec later
    completeTime = currentAttemptEndTime + NSEC_PER_MSEC; // 1 millisec later

    TNLResponseInfo *info = [[TNLResponseInfo alloc] initWithFinalURLRequest:finalRequest URLResponse:urlResponse source:source data:data temporarySavedFile:tempFile];
    TNLResponseMetrics *metrics = [[TNLResponseMetrics alloc] initWithEnqueueTime:enqueueTime completeTime:completeTime attemptMetrics:nil];
    [metrics addInitialStartWithMachTime:firstAttemptStartTime request:finalRequest];
    [metrics addMetaData:metaData];
    [metrics addEnd:currentAttemptEndTime response:info.URLResponse operationError:error];
    TNLResponse *response = [TNLResponse responseWithRequest:request operationError:error info:info metrics:metrics];

    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 2.001, 0.0005);
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 1.0, 0.0005);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.0, 0.0005);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 1.0, 0.0005);

    archive = [NSKeyedArchiver archivedDataWithRootObject:response];
    XCTAssertNotEqual(0UL, archive.length);
    TNLResponse *decodedResponse = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
    XCTAssertTrue([decodedResponse isKindOfClass:[TNLResponse class]]);
    if (![decodedResponse isKindOfClass:[TNLResponse class]]) {
        return;
    }

    // metrics
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, decodedResponse.metrics.totalDuration, 0.0005);
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, decodedResponse.metrics.queuedDuration, 0.0005);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, decodedResponse.metrics.allAttemptsDuration, 0.0005);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, decodedResponse.metrics.currentAttemptDuration, 0.0005);
    XCTAssertEqualObjects([response.metrics.attemptMetrics.lastObject metaData], [decodedResponse.metrics.attemptMetrics.lastObject metaData]);
    XCTAssertEqual(response.metrics.attemptCount, decodedResponse.metrics.attemptCount);
    XCTAssertEqualObjects(response.metrics, decodedResponse.metrics);
    XCTAssertEqual([response.metrics.attemptMetrics.firstObject attemptType], [decodedResponse.metrics.attemptMetrics.firstObject attemptType]);

    // info
    XCTAssertEqualObjects(response.info.finalURLRequest, decodedResponse.info.finalURLRequest);
    XCTAssertTrue([response.info.URLResponse tnl_isEqualToResponse:decodedResponse.info.URLResponse]);
    XCTAssertEqualObjects(response.info.data, decodedResponse.info.data);
    XCTAssertTrue((response.info.temporarySavedFile == nil) == (decodedResponse.info.temporarySavedFile == nil));
    XCTAssertEqualObjects(response.info, decodedResponse.info);

    // base
    XCTAssertEqualObjects(response.operationError, decodedResponse.operationError);
    XCTAssertEqualObjects(response.originalRequest, decodedResponse.originalRequest);
    XCTAssertEqualObjects(response, decodedResponse);
}

- (void)testRetryAfterMethods
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.locale = enUSPOSIXLocale;
    dateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];

    TNLResponseInfo *info;
    NSString *value;
    NSDate *date;
    CFAbsoluteTime start, end;

    // Invalid

    start = CFAbsoluteTimeGetCurrent();
    value = nil;
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertFalse(info.hasRetryAfterHeader);
    XCTAssertNil(info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"Dummy";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"0.5";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"-1";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"2147483648";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"15000000000";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNil(info.retryAfterDate);
    XCTAssertEqual(NSTimeIntervalSince1970, info.retryAfterDelayFromNow);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    // Delay

    start = CFAbsoluteTimeGetCurrent();
    value = @"0";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 0.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"000";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 0.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"1";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 1.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"0000000000000000000001";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 1.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"64000";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 64000.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"2147483647";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 2147483647.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    start = CFAbsoluteTimeGetCurrent();
    value = @"0";
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, -1.0, ACCURACY_LEEWAY);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 1.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    //                           Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
    dateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";

    date = [NSDate dateWithTimeIntervalSinceNow:0.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 0.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:1.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 1.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:64000.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 64000.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:0.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, -1.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 1.2) {
        NSLog(@"Slow execution!  %fs!", end - start - 1.0);
    }

    //                         Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
    dateFormatter.dateFormat = @"EEEE, dd-MMM-yy HH:mm:ss zzz";

    date = [NSDate dateWithTimeIntervalSinceNow:0.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 0.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:1.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 1.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:64000.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 64000.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:0.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, -1.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 1.2) {
        NSLog(@"Slow execution!  %fs!", end - start - 1.0);
    }

    //                           Sun Nov 6 08:49:37 1994       ; ANSI C's asctime() format
    dateFormatter.dateFormat = @"EEE MMM d HH:mm:ss yyyy";

    date = [NSDate dateWithTimeIntervalSinceNow:0.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 0.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:1.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 1.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:64000.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, 64000.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 0.2) {
        NSLog(@"Slow execution!  %fs!", end - start);
    }

    date = [NSDate dateWithTimeIntervalSinceNow:0.0];
    start = CFAbsoluteTimeGetCurrent();
    value = [dateFormatter stringFromDate:date];
    info = [self fakeResponseInfoWithRetryAfterHeaderValue:value];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    XCTAssertTrue(info.hasRetryAfterHeader);
    XCTAssertEqualObjects(value, info.retryAfterRawValue);
    XCTAssertNotNil(info.retryAfterDate);
    XCTAssertEqualWithAccuracy(info.retryAfterDelayFromNow, -1.0, ACCURACY_LEEWAY, @"Value Date: %@, Parsed Date: %@", date, info.retryAfterDate);
    end = CFAbsoluteTimeGetCurrent();
    if (end - start > 1.2) {
        NSLog(@"Slow execution!  %fs!", end - start - 1.0);
    }
}

- (void)testValueForHeaderField
{
    NSString *const kExpectedValue = @"42";
    TNLResponseInfo *info = [self fakeResponseInfoWithRetryAfterHeaderValue:kExpectedValue];
    XCTAssertNotNil(info);
    XCTAssertEqualObjects([info valueForResponseHeaderField:@"Retry-After"], kExpectedValue);
    XCTAssertEqualObjects([info valueForResponseHeaderField:@"retry-after"], kExpectedValue);
    XCTAssertEqualObjects([info valueForResponseHeaderField:@"RETRY-AFTER"], kExpectedValue);
    XCTAssertNil([info valueForResponseHeaderField:@"retryafter"]);
    XCTAssertNil([info valueForResponseHeaderField:@""]);
    XCTAssertNil([info valueForResponseHeaderField:(NSString * __nonnull)nil]);
}

- (TNLResponseInfo *)fakeResponseInfoWithRetryAfterHeaderValue:(NSString *)retryAfterHeaderValue
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.dummy.com"]];
    NSDictionary *dictionary = (retryAfterHeaderValue) ? @{ @"Retry-After" : retryAfterHeaderValue } : @{};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:TNLHTTPStatusCodeServiceUnavailable HTTPVersion:@"HTTP/1.1" headerFields:dictionary];
    TNLResponseInfo *info = [[TNLResponseInfo alloc] initWithFinalURLRequest:request URLResponse:response source:TNLResponseSourceNetworkRequest data:nil temporarySavedFile:nil];
    return info;
}

@end
