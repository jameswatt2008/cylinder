#import "substrate/substrate.h"
#import <UIKit/UIKit.h>
#import "luashit.h"
#import "macros.h"

static IMP original_SB_scrollViewDidScroll;
static UIScrollView *_scrollView = nil;

static BOOL _setHierarchy = false;

static BOOL _enabled;

void reset_everything(UIView *view)
{
    view.layer.transform = DEFAULT_TRANSFORM;
    view.alpha = 1;
    for(UIView *v in view.subviews)
    {
        v.layer.transform = DEFAULT_TRANSFORM;
        v.alpha = 1;
    }
}

void genscrol(UIScrollView *scrollView, int i, UIView *view)
{
    float offset = scrollView.contentOffset.x;
    if(IOS_VERSION < 7) i++; //on iOS 6-, the spotlight is a page to the left, so we gotta bump the pageno. up a notch
    offset -= i*SCREEN_SIZE.width;

    if(fabs(offset) > SCREEN_SIZE.width)
    {
        reset_everything(view);
        return;
    }

    _enabled = manipulate(view, SCREEN_SIZE.width, offset);
}

void SB_scrollViewDidScroll(id self, SEL _cmd, UIScrollView *scrollView)
{
    original_SB_scrollViewDidScroll(self, _cmd, scrollView);
    if(!_scrollView) _scrollView = scrollView;

    if(!_enabled) return;

    if(!_setHierarchy)
    {
        if(IOS_VERSION < 7)
        {
            [scrollView.superview sendSubviewToBack:scrollView];
        }
        _setHierarchy = true;
    }

    NSMutableArray *views = [NSMutableArray arrayWithCapacity:scrollView.subviews.count];
    for(UIView *view in scrollView.subviews)
    {
        if([view isKindOfClass:NSClassFromString(@"SBIconListView")])
        {
            NSUInteger sortedIndex = [views indexOfObject:view
                    inSortedRange:(NSRange){0, views.count}
                    options:NSBinarySearchingInsertionIndex
                    usingComparator:^NSComparisonResult(UIView *obj1, UIView *obj2)
                    {
                        NSNumber *n1 = [NSNumber numberWithFloat:obj1.frame.origin.x];
                        NSNumber *n2 = [NSNumber numberWithFloat:obj2.frame.origin.x];
                        return [n1 compare:n2];
                    }];

            [views insertObject:view atIndex:sortedIndex];

        }
    }

    for(int i = 0; i < views.count; i++)
    {
        genscrol(scrollView, i, views[i]);
        if(!_enabled) break;
    }

}

void load_that_shit()
{
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];

    for(UIView *view in _scrollView.subviews)
    {
        if([view isKindOfClass:NSClassFromString(@"SBIconListView")])
        {
            reset_everything(view);
        }
    }

    if(settings[@"enabled"] != nil && ![settings[@"enabled"] boolValue])
    {
        close_lua();
        _enabled = false;
    }
    else
    {
        NSString *key = settings[PrefsEffectKey];
        _enabled = init_lua(key.UTF8String);
    }
}

static inline void setSettingsNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    load_that_shit();
}

// The attribute forces this function to be called on load.
__attribute__((constructor))
static void initialize() {
    load_that_shit();

    //hook scroll
    Class cls = NSClassFromString(@"SBRootFolderView"); //iOS 7
    if(cls == nil) cls = NSClassFromString(@"SBIconController"); //iOS 5
    MSHookMessageEx(cls, @selector(scrollViewDidScroll:), (IMP)SB_scrollViewDidScroll, (IMP *)&original_SB_scrollViewDidScroll);

    //listen to notification center (for settings change)
    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, &setSettingsNotification, (CFStringRef)kCylinderSettingsChanged, NULL, 0);
}