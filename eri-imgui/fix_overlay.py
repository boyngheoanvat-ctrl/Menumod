from pathlib import Path

src = Path('eri-imgui/Sources/ERIOverlay.mm')
s = src.read_text()
menu = Path('eri-imgui/Sources/ERIMenu.cpp')
m = menu.read_text()

def replace_once(text, old, new):
    found = text.count(old)
    if found != 1:
        raise RuntimeError(f'Expected 1 match, got {found}: {old[:80]}')
    return text.replace(old,new,1)

s = replace_once(s, '@interface ERIOverlay : NSObject <MTKViewDelegate>', '''// An independent non-key window keeps ImGui above original UIKit overlays.
// Outside the icon/panel it passes all touches to the game.
@interface ERIOverlayWindow : UIWindow
@property(nonatomic,weak) ERIPassThroughMetalView* eriView;
@end
@implementation ERIOverlayWindow
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    ERIPassThroughMetalView* v=self.eriView;
    if(!v || v.hidden) return nil;
    CGPoint p=[v convertPoint:point fromView:self];
    if(!CGRectContainsPoint(v.panelRect,p) && !CGRectContainsPoint(v.toggleRect,p)) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface ERIOverlay : NSObject <MTKViewDelegate>''')
s = replace_once(s, '@property(nonatomic,strong) ERIPassThroughMetalView* view;', '''@property(nonatomic,strong) ERIPassThroughMetalView* view;
@property(nonatomic,strong) ERIOverlayWindow* overlayWindow;
@property(nonatomic,strong) UILabel* rainbowTitle;''')
s = replace_once(s, '- (void)loadOriginalRows {', '''// Hide just the old UIKit menu chrome, not any of its action handlers.
- (void)suppressOriginalUI {
    id menu=[self originalMenu];
    if(!menu) return;
    @try {
        id visible=[menu valueForKey:@"_menuVisible"];
        if([visible respondsToSelector:@selector(boolValue)] && [visible boolValue] &&
           [menu respondsToSelector:@selector(dismissMenu)]) {
            ((void(*)(id,SEL))objc_msgSend)(menu,@selector(dismissMenu));
        }
    } @catch(NSException* exception) { }
    for(NSString* key in @[@"_menuButton",@"_menuIconView",@"_modMenuView"]) {
        @try {
            id v=[menu valueForKey:key];
            if([v isKindOfClass:[UIView class]]) [(UIView*)v setHidden:YES];
        } @catch(NSException* exception) { }
    }
}

- (void)loadOriginalRows {''')
s = replace_once(s, 'if(self.names.count && self.cachedRows.count) return;', 'if(self.names.count && self.cachedRows.count) { [self suppressOriginalUI]; return; }')
s = replace_once(s, '''    // Keep callback handlers alive through their owning row objects.
    // The original UIKit chrome is dismissed; no game hooks are rewritten.
    if([menu respondsToSelector:@selector(dismissMenu)]) {
        ((void(*)(id,SEL))objc_msgSend)(menu,@selector(dismissMenu));
    }
    @try {
        UIView* icon=[menu valueForKey:@"_menuIconView"];
        if([icon isKindOfClass:[UIView class]]) icon.hidden=YES;
    } @catch(NSException* exc) { }''','''    [self suppressOriginalUI];''')
s = replace_once(s, '''- (void)startInWindow:(UIWindow*)window {
    if(self.view || !window) return;''','''- (void)startInWindow:(UIWindow*)window {
    if(!window) return;
    if(self.view) { [self suppressOriginalUI]; return; }''')
s = replace_once(s, '''    m.delegate=self;
    [window addSubview:m];
    self.view=m;
    self.open=YES;''','''    m.delegate=self;
    ERIOverlayWindow* cover=nil;
    if(@available(iOS 13.0,*)) {
        UIWindowScene* scene=window.windowScene;
        if(scene) cover=[[ERIOverlayWindow alloc] initWithWindowScene:scene];
    }
    if(!cover) cover=[[ERIOverlayWindow alloc] initWithFrame:window.bounds];
    cover.frame=window.bounds;
    cover.windowLevel=UIWindowLevelAlert+100;
    cover.backgroundColor=UIColor.clearColor;
    UIViewController* controller=[UIViewController new];
    controller.view.backgroundColor=UIColor.clearColor;
    cover.rootViewController=controller;
    [controller.view addSubview:m];
    m.frame=controller.view.bounds;
    cover.eriView=m;
    // UIKit font guarantees Vietnamese accents without redistributing fonts.
    UILabel* label=[[UILabel alloc] initWithFrame:CGRectZero];
    label.text=@"Mod By Eri Nguyễn";
    label.font=[UIFont boldSystemFontOfSize:19.0];
    label.backgroundColor=UIColor.clearColor;
    label.userInteractionEnabled=NO;
    [controller.view addSubview:label];
    self.rainbowTitle=label;
    self.view=m;
    self.overlayWindow=cover;
    cover.hidden=NO;
    self.open=YES;''')
s = replace_once(s, '''        [self loadOriginalRows];
        ImGuiIO& io=ImGui::GetIO();''','''        [self loadOriginalRows];
        [self suppressOriginalUI];
        ImGuiIO& io=ImGui::GetIO();''')
s = replace_once(s, '''        CGRect panelRect=(self.open && panel)?CGRectMake(panel->Pos.x,panel->Pos.y,panel->Size.x,panel->Size.y):CGRectZero;
        ((ERIPassThroughMetalView*)view).panelRect=panelRect;''','''        CGRect panelRect=(self.open && panel)?CGRectMake(panel->Pos.x,panel->Pos.y,panel->Size.x,panel->Size.y):CGRectZero;
        self.rainbowTitle.hidden=!self.open || !panel;
        if(self.open && panel) {
            self.rainbowTitle.frame=CGRectMake(panel->Pos.x+14, panel->Pos.y+12,
                                              MAX(40.f,panel->Size.x-28.f),27.f);
            static const CGFloat colors[7][3]={{1,.18,.27},{1,.53,.11},{1,.92,.16},
                                                {.17,.98,.40},{.13,.86,1},
                                                {.33,.47,1},{.88,.23,.98}};
            NSInteger i=((NSInteger)(ImGui::GetTime()*8.0))%7;
            self.rainbowTitle.textColor=[UIColor colorWithRed:colors[i][0]
                green:colors[i][1] blue:colors[i][2] alpha:1];
        }
        ((ERIPassThroughMetalView*)view).panelRect=panelRect;''')
s = replace_once(s, '''    for(UIWindow* w in app.windows) if(w.isKeyWindow) { window=w; break; }
    if(!window) window=app.windows.firstObject;''','''    for(UIWindow* w in app.windows) {
        if([w isKindOfClass:[ERIOverlayWindow class]]) continue;
        if(w.isKeyWindow) { window=w; break; }
        if(!window) window=w;
    }''')
m = replace_once(m, 'ERIRainbowTitle("Mod By Eri Nguyễn");',
                 'ImGui::Dummy(ImVec2(1.f, ImGui::GetFontSize()*1.15f+7.f));')
src.write_text(s)
menu.write_text(m)
print('Applied ERI UIKit suppression + high-level ImGui window + rainbow title')