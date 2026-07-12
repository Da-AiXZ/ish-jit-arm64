//
//  SceneDelegate.m
//  iSH
//
//  Created by Theodore Dubois on 10/26/19.
//
//  Modified for CodingPad: root view is now SwiftUI MainLayout.
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "AboutViewController.h"

// Auto-generated Swift header. Name matches PRODUCT_MODULE_NAME:
// "iSH ARM64" → "iSH_ARM64-Swift.h"
#if __has_include("iSH_ARM64-Swift.h")
#import "iSH_ARM64-Swift.h"
#elif __has_include("CodingPad-Swift.h")
#import "CodingPad-Swift.h"
#endif

TerminalViewController *currentTerminalViewController = NULL;

@interface SceneDelegate ()

@property NSString *terminalUUID;

@end

static NSString *const TerminalUUID = @"TerminalUUID";

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"recovery"]) {
        UINavigationController *vc = [[UIStoryboard storyboardWithName:@"About" bundle:nil] instantiateInitialViewController];
        AboutViewController *avc = (AboutViewController *) vc.topViewController;
        avc.recoveryMode = YES;
        self.window.rootViewController = vc;
        return;
    }

    // CodingPad: use SwiftUI MainLayout as the root view controller.
    // This replaces iSH's TerminalViewController with our AI agent UI.
    UIViewController *codingPadVC = [CodingPadUI createRootViewController];
    self.window.rootViewController = codingPadVC;
}

- (NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene {
    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:@"app.ish.scene"];
    return activity;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [AppDelegate applyJITPreferences];
}

- (void)sceneWillResignActive:(UIScene *)scene {
}

@end
