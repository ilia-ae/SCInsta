#import "../../InstagramHeaders.h"

// Instagram builds that come from the TestFlight/dogfood channel (Info.plist
// carries FBBuildBranchName = "dev") compare their own build number against the
// latest beta the server advertises and put up a full-screen nudge:
//   "It's time to update Instagram Beta" → "Update Instagram Beta" → TestFlight.
//
// The controller keeps no "already shown" state — no userDefaults ivar, unlike
// IGTestFlightUpdateNagController — so it comes back on every single launch.
// A sideloaded copy can never be updated through TestFlight anyway, so the nudge
// is pure noise: dismiss it before it is drawn.
//
// %hook on a mangled Swift name only forward-declares the class, so declare it
// explicitly to reach the UIViewController API.
@interface _TtC29IGCoreRootTestFlightNagPlugin35TestFlightUpdateNudgeViewController : UIViewController
- (void)sciDismissTestFlightNudge; // new
@end

%hook _TtC29IGCoreRootTestFlightNagPlugin35TestFlightUpdateNudgeViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    [self sciDismissTestFlightNudge];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    // Presentation may only settle after viewWillAppear, so try once more.
    [self sciDismissTestFlightNudge];
}

%new - (void)sciDismissTestFlightNudge {
    NSLog(@"[SCInsta] Dismissing TestFlight beta update nudge");

    if (self.presentingViewController) {
        [self.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        return;
    }

    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:NO];
        return;
    }

    // Neither presented nor pushed: detach it from whatever hosts it. Never hide
    // the window here — it can be the app's own key window.
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

%end
