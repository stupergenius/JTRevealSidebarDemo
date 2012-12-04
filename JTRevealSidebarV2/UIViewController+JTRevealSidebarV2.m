/*
 * This file is part of the JTRevealSidebar package.
 * (c) James Tang <mystcolor@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIViewController+JTRevealSidebarV2.h"
#import "UINavigationItem+JTRevealSidebarV2.h"
#import "JTRevealSidebarV2Delegate.h"
#import <objc/runtime.h>

@interface UIViewController (JTRevealSidebarV2Private)

- (UIViewController *)selectedViewController;
- (void)revealLeftSidebar:(BOOL)showLeftSidebar;
- (void)revealRightSidebar:(BOOL)showRightSidebar;

@end

@implementation UIViewController (JTRevealSidebarV2)

static char *revealedStateKey;

- (void)setRevealedState:(JTRevealedState)revealedState {
    JTRevealedState currentState = self.revealedState;

    if (revealedState == currentState) {
        return;
    }

    id <JTRevealSidebarV2Delegate> delegate = [self selectedViewController].navigationItem.revealSidebarDelegate;
    // notify delegate for controller will change state
    if ([delegate respondsToSelector:@selector(willChangeRevealedStateForViewController:)]) {
        [delegate willChangeRevealedStateForViewController:self];
    }

    objc_setAssociatedObject(self, &revealedStateKey, [NSNumber numberWithInt:revealedState], OBJC_ASSOCIATION_RETAIN);

    switch (currentState) {
        case JTRevealedStateNo:
            if (revealedState == JTRevealedStateLeft) {
                [self revealLeftSidebar:YES];
            } else if (revealedState == JTRevealedStateRight) {
                [self revealRightSidebar:YES];
            } else {
                // Do Nothing
            }
            break;
        case JTRevealedStateLeft:
            if (revealedState == JTRevealedStateNo) {
                [self revealLeftSidebar:NO];
            } else if (revealedState == JTRevealedStateRight) {
                [self revealLeftSidebar:NO];
                [self revealRightSidebar:YES];
            } else {
                [self revealLeftSidebar:YES];
            }
            break;
        case JTRevealedStateRight:
            if (revealedState == JTRevealedStateNo) {
                [self revealRightSidebar:NO];
            } else if (revealedState == JTRevealedStateLeft) {
                [self revealRightSidebar:NO];
                [self revealLeftSidebar:YES];
            } else {
                [self revealRightSidebar:YES];
            }
        default:
            break;
    }
}

- (JTRevealedState)revealedState {
    return (JTRevealedState)[objc_getAssociatedObject(self, &revealedStateKey) intValue];
}

- (CGAffineTransform)baseTransform {
    CGAffineTransform baseTransform;
    
    return self.view.transform;
    switch (self.interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
            baseTransform = CGAffineTransformIdentity;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            baseTransform = CGAffineTransformMakeRotation(-M_PI/2);
            break;
        case UIInterfaceOrientationLandscapeRight:
            baseTransform = CGAffineTransformMakeRotation(M_PI/2);
            break;
        default:
            baseTransform = CGAffineTransformMakeRotation(M_PI);
            break;
    }
    return baseTransform;
}

// Converting the applicationFrame from UIWindow is founded to be always correct
- (CGRect)applicationViewFrame {
    CGRect appFrame = [[UIScreen mainScreen] applicationFrame];
    CGRect expectedFrame = [self.view convertRect:appFrame fromView:nil];
    return expectedFrame;
}

- (void)toggleRevealState:(JTRevealedState)openingState {
    JTRevealedState state = openingState;
    if (self.revealedState == openingState) {
        state = JTRevealedStateNo;
    }
    [self setRevealedState:state];
}

@end

#define SIDEBAR_VIEW_TAG 10000
#define VIEW_OVERLAY_TAG 10001

@implementation UIViewController (JTRevealSidebarV2Private)

- (UIViewController *)selectedViewController {
    return self;
}

// Looks like we collasped with the official animationDidStop:finished:context: 
// implementation in the default UITabBarController here, that makes us never
// getting the callback we wanted. So we renamed the callback method here.
- (void)animationDidStop2:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
    if ([animationID isEqualToString:@"hideSidebarView"]) {
        // Remove the sidebar view after the sidebar closes.
        UIView *view = [self.view.superview viewWithTag:(int)context];
        [view removeFromSuperview];
        
        UIView *overlayView = [self.view viewWithTag:VIEW_OVERLAY_TAG];
        if (overlayView != nil) {
            [overlayView removeFromSuperview];
        }
    }
    
    // notify delegate for controller changed state
    id <JTRevealSidebarV2Delegate> delegate = 
        [self selectedViewController].navigationItem.revealSidebarDelegate;
    if ([delegate respondsToSelector:@selector(didChangeRevealedStateForViewController:)]) {
        [delegate didChangeRevealedStateForViewController:self];
    }
}

- (void)revealLeftSidebar:(BOOL)showLeftSidebar {

    id <JTRevealSidebarV2Delegate> delegate = [self selectedViewController].navigationItem.revealSidebarDelegate;

    if ( ! [delegate respondsToSelector:@selector(viewForLeftSidebar)]) {
        return;
    }

    UIView *revealedView = [delegate viewForLeftSidebar];
    revealedView.tag = SIDEBAR_VIEW_TAG;
    CGFloat width = CGRectGetWidth(revealedView.frame);
    
    // Maintain some frames that represent the "original" frame, i.e. the frame
    // that the view will display to the user, and the translated, or hidden
    // frame that the view will reveal from.
    CGRect originalRevealFrame = CGRectMake(0, 0, width, CGRectGetHeight(revealedView.frame));
    CGRect translatedRevealFrame = CGRectOffset(originalRevealFrame, -width, 0);
    translatedRevealFrame.origin.x = -width;
    
    // A partially transparent view that gets overlaid over this navigation
    // controller's view that when tapped, will dismiss the sidebar.
    UIView *overlayView;

    if (showLeftSidebar) {
        // Setup the overlay and add a simple tap gesture recognizer.
        UITapGestureRecognizer *overlayTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewOverlayTapped:)];
        overlayView = [[UIView alloc] initWithFrame:self.view.frame];
        overlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
        overlayView.tag = VIEW_OVERLAY_TAG;
        [overlayView addGestureRecognizer:overlayTapRecognizer];
        [self.view addSubview:overlayView];
        
        [self.view.superview addSubview:revealedView];
        revealedView.frame = translatedRevealFrame;
        
        [UIView beginAnimations:@"" context:nil];
        revealedView.frame = originalRevealFrame;
        overlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
    } else {
        overlayView = [self.view viewWithTag:VIEW_OVERLAY_TAG];
        revealedView.frame = originalRevealFrame;
        
        [UIView beginAnimations:@"hideSidebarView" context:(void *)SIDEBAR_VIEW_TAG];
        revealedView.frame = translatedRevealFrame;
        if (overlayView != nil) {
            overlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
        }
    }
    
    [UIView setAnimationDuration: 1];
    [UIView setAnimationDidStopSelector:@selector(animationDidStop2:finished:context:)];
    [UIView setAnimationDelegate:self];
    [UIView commitAnimations];
}

- (void)viewOverlayTapped:(UIGestureRecognizer *)recog {
    [self toggleRevealState:JTRevealedStateNo];
}

- (void)revealRightSidebar:(BOOL)showRightSidebar {

    id <JTRevealSidebarV2Delegate> delegate = [self selectedViewController].navigationItem.revealSidebarDelegate;
    
    if ( ! [delegate respondsToSelector:@selector(viewForRightSidebar)]) {
        return;
    }

    UIView *revealedView = [delegate viewForRightSidebar];
    revealedView.tag = SIDEBAR_VIEW_TAG;
    CGFloat width = CGRectGetWidth(revealedView.frame);
    revealedView.frame = (CGRect){self.view.frame.size.width - width, revealedView.frame.origin.y, revealedView.frame.size};

    if (showRightSidebar) {
        [self.view.superview insertSubview:revealedView belowSubview:self.view];

        [UIView beginAnimations:@"" context:nil];
//        self.view.transform = CGAffineTransformTranslate([self baseTransform], -width, 0);
        
        self.view.frame = CGRectOffset(self.view.frame, -width, 0);
    } else {
        [UIView beginAnimations:@"hideSidebarView" context:(void *)SIDEBAR_VIEW_TAG];
//        self.view.transform = CGAffineTransformTranslate([self baseTransform], width, 0);
        self.view.frame = CGRectOffset(self.view.frame, width, 0);
    }
    
    [UIView setAnimationDidStopSelector:@selector(animationDidStop2:finished:context:)];
    [UIView setAnimationDelegate:self];

    NSLog(@"%@", NSStringFromCGAffineTransform(self.view.transform));
    
    [UIView commitAnimations];
}

@end


@implementation UINavigationController (JTRevealSidebarV2)

- (UIViewController *)selectedViewController {
    return self.topViewController;
}

@end