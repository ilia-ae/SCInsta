#import <Security/Security.h>

// Instagram asks the keychain for access groups that belong to Meta —
// `group.com.facebook.family` above all, shared across the Facebook app family.
// A re-signed copy can never hold another team's group: the provisioning profile
// only authorises ours, so every such call fails with
//   -34018 "Client explicitly specifies access group … but is only entitled for …"
// and the login session is never stored. The app then asks for credentials on
// every launch.
//
// Drop the access group from those queries instead. Without kSecAttrAccessGroup
// the keychain uses the app's default group (its application-identifier), which a
// re-signed app always has, so the item is stored and found again.
//
// Why not rewrite the strings in the binary: the very same constants name the
// shared app-group CONTAINER. Renaming them satisfies the keychain and breaks the
// container — Meta's shared code then builds a nil path and the app aborts.
// Hooking the keychain touches exactly one of the two roles.

static NSMutableSet<NSString *> *SCISeenGroups(void) {
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
    return seen;
}

/// Returns a +1 copy of `query` without a foreign access group, or NULL to keep the original.
static CFDictionaryRef SCICopyQueryWithoutForeignGroup(CFDictionaryRef query) {
    if (!query) return NULL;

    CFTypeRef group = CFDictionaryGetValue(query, kSecAttrAccessGroup);
    if (!group || CFGetTypeID(group) != CFStringGetTypeID()) return NULL;

    NSString *name = (__bridge NSString *)group;
    // App-group ids are the ones we can never be entitled to. Team-prefixed groups
    // are already rewritten into our namespace before signing.
    if (![name hasPrefix:@"group."]) return NULL;

    @synchronized (SCISeenGroups()) {
        if (![SCISeenGroups() containsObject:name]) {
            [SCISeenGroups() addObject:name];
            NSLog(@"[SCInsta] Keychain group %@ is not ours — using the app's default group", name);
        }
    }

    NSMutableDictionary *fixed = [(__bridge NSDictionary *)query mutableCopy];
    [fixed removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    return (__bridge_retained CFDictionaryRef)fixed;
}

%hookf(OSStatus, SecItemAdd, CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef fixed = SCICopyQueryWithoutForeignGroup(query);
    if (!fixed) return %orig;

    OSStatus status = %orig(fixed, result);
    CFRelease(fixed);
    return status;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef fixed = SCICopyQueryWithoutForeignGroup(query);
    if (!fixed) return %orig;

    OSStatus status = %orig(fixed, result);
    CFRelease(fixed);
    return status;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributes) {
    CFDictionaryRef fixed = SCICopyQueryWithoutForeignGroup(query);
    if (!fixed) return %orig;

    OSStatus status = %orig(fixed, attributes);
    CFRelease(fixed);
    return status;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    CFDictionaryRef fixed = SCICopyQueryWithoutForeignGroup(query);
    if (!fixed) return %orig;

    OSStatus status = %orig(fixed);
    CFRelease(fixed);
    return status;
}
