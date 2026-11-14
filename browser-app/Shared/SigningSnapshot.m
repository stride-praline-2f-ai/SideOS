#import "SigningSnapshot.h"
#include <dlfcn.h>
#import <Security/Security.h>

// A hosted guest's SecItem imports may be rebound to a simulated guest group.
// Resolve the framework implementation directly for the adversarial canary probe.
int32_t SideOSRawKeychainStatus(NSDictionary *query) {
    void *library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL | RTLD_FIRST);
    if (!library) return errSecUnimplemented;
    typedef OSStatus (*CopyMatching)(CFDictionaryRef, CFTypeRef *);
    CopyMatching copy = (CopyMatching)dlsym(library, "SecItemCopyMatching");
    OSStatus status = copy ? copy((__bridge CFDictionaryRef)query, NULL) : errSecUnimplemented;
    dlclose(library);
    return status;
}

BOOL SideOSRawKeychainControl(NSString *account) {
    void *library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL | RTLD_FIRST);
    if (!library) return NO;
    typedef OSStatus (*Add)(CFDictionaryRef, CFTypeRef *);
    typedef OSStatus (*Delete)(CFDictionaryRef);
    Add add = (Add)dlsym(library, "SecItemAdd");
    Delete remove = (Delete)dlsym(library, "SecItemDelete");
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"SideOSIsolationProbeControl", (__bridge id)kSecAttrAccount: account};
    BOOL passed = NO;
    if (add && remove) {
        remove((__bridge CFDictionaryRef)query);
        NSMutableDictionary *item = query.mutableCopy;
        item[(__bridge id)kSecValueData] = [@"synthetic-control" dataUsingEncoding:NSUTF8StringEncoding];
        item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        passed = add((__bridge CFDictionaryRef)item, NULL) == errSecSuccess && SideOSRawKeychainStatus(query) == errSecSuccess;
        remove((__bridge CFDictionaryRef)query);
    }
    dlclose(library);
    return passed;
}

NSDictionary *SideOSSigningSnapshot(void) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    CreateTask create = (CreateTask)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create || !copy) return nil;
    CFTypeRef task = create(kCFAllocatorDefault);
    if (!task) return nil;
    NSArray *keys = @[@"application-identifier", @"com.apple.security.application-groups", @"keychain-access-groups",
        @"get-task-allow", @"com.apple.security.get-task-allow", @"task_for_pid-allow", @"platform-application",
        @"com.apple.system-task-ports", @"dynamic-codesigning", @"com.apple.security.cs.allow-jit",
        @"com.apple.security.cs.disable-library-validation", @"com.apple.private.security.no-sandbox", @"com.apple.private.security.no-container"];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        CFErrorRef error = NULL;
        CFTypeRef value = copy(task, (__bridge CFStringRef)key, &error);
        if (error) {
            if (value) CFRelease(value);
            CFRelease(error); CFRelease(task); return nil;
        }
        result[key] = value ? CFBridgingRelease(value) : NSNull.null;
    }
    CFRelease(task);
    return result;
}
