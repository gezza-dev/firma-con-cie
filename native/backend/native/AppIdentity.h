// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#import <Foundation/Foundation.h>
#ifndef CIE_BUILD_APP_GROUP_ID
#define CIE_BUILD_APP_GROUP_ID ""
#endif

// Both bundles receive the same identity through Xcode build settings.
static inline NSString* CIEAppGroupIdentifier(void)
{
    id value = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CIEAppGroupIdentifier"];
    if ([value isKindOfClass:NSString.class] && [value length]) return value;
    // A PKCS#11 host does not carry the app's Info.plist.
    NSString* compiled = @CIE_BUILD_APP_GROUP_ID;
    return compiled.length ? compiled : nil;
}

static inline NSURL* CIESharedCacheURL(void)
{
    NSString* identifier = CIEAppGroupIdentifier();
    if (!identifier) return nil;
    NSFileManager* manager = NSFileManager.defaultManager;
    NSURL* group = [manager containerURLForSecurityApplicationGroupIdentifier:identifier];
    if (!group) return nil;
    NSURL* cache = [group URLByAppendingPathComponent:@"Library/Caches/CIEPKI" isDirectory:YES];
    return [manager createDirectoryAtURL:cache withIntermediateDirectories:YES
        attributes:nil error:nil] ? cache : nil;
}
