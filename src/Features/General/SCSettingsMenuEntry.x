#import "../../InstagramHeaders.h"
#import "../../Settings/SCISettingsViewController.h"
#import <objc/runtime.h>

// Instagram 433+ ("Liquid Glass") moved the profile navigation into a Swift
// module, so the plain `%hook IGBadgedNavigationButton` resolved to a nil class
// and every hook below it silently no-op'd (upstream issue #281).
// The class is now registered with the ObjC runtime under its mangled name.
%hook _TtC19IGProfileNavigation24IGBadgedNavigationButton
- (void)didMoveToWindow {
    %orig;

    NSString *identifier = self.accessibilityIdentifier ?: @"";
    if ([identifier isEqualToString:@"profile-more-button"] || [identifier isEqualToString:@"profile-more-bar-button"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}

%new - (void)addLongPressGestureRecognizer {
    // Instagram attaches its own recognizers to this button now, so the old
    // `[self.gestureRecognizers count] == 0` guard never passed. Attach
    // unconditionally instead, once per view, and make Instagram's own
    // recognizers yield to ours.
    static char kSCISettingsGestureKey;
    if (objc_getAssociatedObject(self, &kSCISettingsGestureKey)) return;

    NSLog(@"[SCInsta] Adding tweak settings long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];

    for (UIGestureRecognizer *existing in self.gestureRecognizers) {
        [existing requireGestureRecognizerToFail:longPress];
    }

    [self addGestureRecognizer:longPress];
    objc_setAssociatedObject(self, &kSCISettingsGestureKey, longPress, OBJC_ASSOCIATION_ASSIGN);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSLog(@"[SCInsta] Tweak settings gesture activated");

    [SCIUtils showSettingsVC:[self window]];
}
%end

// Quick access to tweak settings by holding on home tab button
%hook IGTabBarButton
- (void)didMoveToSuperview {
    %orig;

    // Only work on home/feed tab
    if (![self.accessibilityIdentifier isEqualToString:@"mainfeed-tab"]) return;

    if ([SCIUtils getBoolPref:@"settings_shortcut"]) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.3;

        // Take precidence over existing gesture recognizers
        for (UIGestureRecognizer *existing in self.gestureRecognizers) {
            [existing requireGestureRecognizerToFail:longPress];
        }

        [self addGestureRecognizer:longPress];
    }
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    [SCIUtils showSettingsVC:[self window]];
}
%end

// Tapping the side tray (hamburger) button on the profile lets the user choose
// between the normal Instagram settings and the SCInsta tweak settings.
// Ported from upstream PR #282 — this is the only entry point that does not
// depend on a gesture recognizer, so it survives Instagram's own long-press.
@protocol SCSideTrayController
- (void)onSideTrayButton;
@end

static BOOL sciBypassSideTray = NO;

%hook _TtC19IGProfileNavigation34IGProfileNavigationItemsController
- (void)onSideTrayButton {
    // Re-entrant call from the "Instagram Settings" option: run the original
    if (sciBypassSideTray) {
        sciBypassSideTray = NO;
        %orig;
        return;
    }

    NSLog(@"[SCInsta] Side tray button intercepted");

    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    UIViewController *presenter = [window rootViewController];
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Settings"
                                                                  message:@"Which settings would you like to open?"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Instagram Settings"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        sciBypassSideTray = YES;
        [(id<SCSideTrayController>)self onSideTrayButton];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"SCInsta Settings"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [SCIUtils showSettingsVC:window];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // Required for iPad to avoid a crash when presenting an action sheet
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = presenter.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(presenter.view.bounds.size.width / 2.0, presenter.view.bounds.size.height / 2.0, 1.0, 1.0);
    }

    [presenter presentViewController:alert animated:YES completion:nil];
}
%end
