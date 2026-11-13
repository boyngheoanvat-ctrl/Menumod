#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <QuartzCore/QuartzCore.h>

static UIWindow *eriWindow = nil;
static BOOL eriUnlocked = NO;
static BOOL eriWorking = NO;
static NSString *const ERIService = @"vn.eri.license.runtime.v1";
static NSString *const ERIBase = @"https://eri-login-api.onrender.com";

static NSString *eriRead(NSString *account) {
    NSDictionary *q = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:ERIService, (__bridge id)kSecAttrAccount:account,
        (__bridge id)kSecReturnData:@YES, (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne};
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess) return @"";
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}
static void eriWrite(NSString *account, NSString *value) {
    NSDictionary *q = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:ERIService, (__bridge id)kSecAttrAccount:account};
    if (!value.length) {
        SecItemDelete((__bridge CFDictionaryRef)q);
        return;
    }
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)q,
        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (status == errSecItemNotFound) {
        NSMutableDictionary *newItem = [q mutableCopy];
        newItem[(__bridge id)kSecValueData] = data;
        newItem[(__bridge id)kSecAttrAccessible] =
            (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)newItem, NULL);
    }
}
static NSString *eriDeviceID(void) {
    NSString *old = eriRead(@"device-id");
    if ([[NSUUID alloc] initWithUUIDString:old]) return old.lowercaseString;
    NSString *newID = [NSUUID UUID].UUIDString.lowercaseString;
    eriWrite(@"device-id", newID);
    return newID;
}
static NSString *eriText(NSString *input) {
    return [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}
// A stable logical product identifier can be provided by the app owner in Info.plist.
 // This prevents a re-signing operation that changes CFBundleIdentifier from silently
 // changing which ERI license namespace is checked.
static NSString *eriLicenseAppID(void) {
    id configured=[NSBundle.mainBundle objectForInfoDictionaryKey:@"ERILicenseAppID"];
    if ([configured isKindOfClass:NSString.class]) {
        NSString *value=eriText((NSString *)configured);
        if(value.length) return value;
    }
    return NSBundle.mainBundle.bundleIdentifier ?: @"";
}
static void eriUnlock(void) {
    eriUnlocked = YES;
    eriWindow.hidden = YES;
    eriWindow = nil;
}

@interface ERIGate : UIViewController <UITextFieldDelegate>
@property(nonatomic,strong) UITextField *keyField;
@property(nonatomic,strong) UIButton *submitButton;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) CAGradientLayer *bgLayer;
@property(nonatomic,strong) CAGradientLayer *ctaLayer;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
-(void)verifySaved;
@end

@implementation ERIGate
static UIColor *eriBlue(unsigned rgb) {
 return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0
                         blue:(rgb&255)/255.0 alpha:1];
}
static UILabel *eriMakeLabel(NSString *s,CGFloat size,UIFontWeight w,UIColor *c) {
 UILabel *x=[UILabel new];x.text=s;x.textAlignment=NSTextAlignmentCenter;
 x.numberOfLines=0;x.textColor=c;x.font=[UIFont systemFontOfSize:size weight:w];return x;
}
-(void)viewDidLoad {
 [super viewDidLoad];
 self.view.backgroundColor=eriBlue(0x071025);
 self.bgLayer=[CAGradientLayer layer];
 self.bgLayer.colors=@[(__bridge id)eriBlue(0x070C20).CGColor,
                        (__bridge id)eriBlue(0x18335A).CGColor,
                        (__bridge id)eriBlue(0x070D1F).CGColor];
 self.bgLayer.startPoint=CGPointMake(0,0);self.bgLayer.endPoint=CGPointMake(1,1);
 [self.view.layer insertSublayer:self.bgLayer atIndex:0];
 UIScrollView *scroll=[UIScrollView new];
 scroll.translatesAutoresizingMaskIntoConstraints=NO;
 scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
 [self.view addSubview:scroll];
 [NSLayoutConstraint activateConstraints:@[
  [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
  [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
  [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
  [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
 ]];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;
 stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=NO;
 [scroll addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[
  [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
  [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
  [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:50],
  [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-30],
  [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48]
 ]];
 UIView *brand=[UIView new];brand.layer.cornerRadius=18;brand.layer.borderWidth=1;
 brand.layer.borderColor=[eriBlue(0x88DEFF) colorWithAlphaComponent:.35].CGColor;
 brand.backgroundColor=[eriBlue(0x183861) colorWithAlphaComponent:.85];
 UILabel *brandName=eriMakeLabel(@"✦ MOD BY ERI NGUYỄN ✦",12,UIFontWeightBold,eriBlue(0x8DDEFF));
 brandName.translatesAutoresizingMaskIntoConstraints=NO;[brand addSubview:brandName];
 [NSLayoutConstraint activateConstraints:@[
  [brand.heightAnchor constraintEqualToConstant:38],
  [brandName.centerYAnchor constraintEqualToAnchor:brand.centerYAnchor],
  [brandName.centerXAnchor constraintEqualToAnchor:brand.centerXAnchor]
 ]];[stack addArrangedSubview:brand];
 UIStackView *hero=[UIStackView new];hero.axis=UILayoutConstraintAxisVertical;
 hero.alignment=UIStackViewAlignmentCenter;hero.spacing=13;[stack addArrangedSubview:hero];
 UIView *emblem=[UIView new];emblem.backgroundColor=eriBlue(0x173962);
 emblem.layer.cornerRadius=34;emblem.layer.borderColor=eriBlue(0x73D8FF).CGColor;
 emblem.layer.borderWidth=1;[emblem.widthAnchor constraintEqualToConstant:68].active=YES;
 [emblem.heightAnchor constraintEqualToConstant:68].active=YES;
 UIImageView *shield=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"]];
 shield.translatesAutoresizingMaskIntoConstraints=NO;shield.tintColor=eriBlue(0x8BE4FF);
 shield.contentMode=UIViewContentModeScaleAspectFit;[emblem addSubview:shield];
 [NSLayoutConstraint activateConstraints:@[
  [shield.centerXAnchor constraintEqualToAnchor:emblem.centerXAnchor],
  [shield.centerYAnchor constraintEqualToAnchor:emblem.centerYAnchor],
  [shield.widthAnchor constraintEqualToConstant:35],
  [shield.heightAnchor constraintEqualToConstant:35]
 ]];
 [hero addArrangedSubview:emblem];
 [hero addArrangedSubview:eriMakeLabel(@"ERI LOGIN",38,UIFontWeightHeavy,UIColor.whiteColor)];
 [hero addArrangedSubview:eriMakeLabel(@"KÍCH HOẠT QUYỀN TRUY CẬP",12,UIFontWeightMedium,eriBlue(0xC1CFE7))];
 [hero addArrangedSubview:eriMakeLabel(@"01 KEY  •  01 THIẾT BỊ",13,UIFontWeightBold,eriBlue(0x75E0E8))];
 UIView *card=[UIView new];card.backgroundColor=eriBlue(0x14233D);
 card.layer.cornerRadius=22;card.layer.borderWidth=1;
 card.layer.borderColor=[eriBlue(0x648DC3) colorWithAlphaComponent:.4].CGColor;
 [stack addArrangedSubview:card];
 UIStackView *panel=[UIStackView new];panel.axis=UILayoutConstraintAxisVertical;
 panel.spacing=14;panel.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:panel];
 [NSLayoutConstraint activateConstraints:@[
  [panel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
  [panel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
  [panel.topAnchor constraintEqualToAnchor:card.topAnchor constant:21],
  [panel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-21]
 ]];
 UILabel *fieldLabel=eriMakeLabel(@"MÃ KÍCH HOẠT CỦA BẠN",12,UIFontWeightBold,eriBlue(0xD3E2FF));
 fieldLabel.textAlignment=NSTextAlignmentLeft;[panel addArrangedSubview:fieldLabel];
 self.keyField=[UITextField new];self.keyField.backgroundColor=eriBlue(0x0A162C);
 self.keyField.textColor=UIColor.whiteColor;self.keyField.layer.cornerRadius=12;
 self.keyField.layer.borderWidth=1;self.keyField.layer.borderColor=eriBlue(0x4F7CA7).CGColor;
 self.keyField.font=[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
 self.keyField.minimumFontSize=9;self.keyField.adjustsFontSizeToFitWidth=YES;
 self.keyField.clearButtonMode=UITextFieldViewModeWhileEditing;
 self.keyField.autocorrectionType=UITextAutocorrectionTypeNo;
 self.keyField.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;
 self.keyField.keyboardType=UIKeyboardTypeASCIICapable;
 self.keyField.returnKeyType=UIReturnKeyDone;self.keyField.delegate=self;
 self.keyField.attributedPlaceholder=[[NSAttributedString alloc]initWithString:
  @"ERI-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX" attributes:@{
  NSForegroundColorAttributeName:eriBlue(0x7B90B0),
  NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]}];
 self.keyField.leftView=[[UIView alloc]initWithFrame:CGRectMake(0,0,12,1)];
 self.keyField.leftViewMode=UITextFieldViewModeAlways;
 self.keyField.text=eriRead(@"key");
 [self.keyField.heightAnchor constraintEqualToConstant:54].active=YES;
 [panel addArrangedSubview:self.keyField];
 UIButton *paste=[UIButton buttonWithType:UIButtonTypeSystem];
 [paste setTitle:@"DÁN KEY TỪ BỘ NHỚ TẠM" forState:UIControlStateNormal];
 [paste setTitleColor:eriBlue(0x86D8FF) forState:UIControlStateNormal];
 paste.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];
 paste.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
 [paste.heightAnchor constraintEqualToConstant:25].active=YES;
 [paste addTarget:self action:@selector(pasteKey:) forControlEvents:UIControlEventTouchUpInside];
 [panel addArrangedSubview:paste];
 self.submitButton=[UIButton buttonWithType:UIButtonTypeSystem];
 [self.submitButton setTitle:@"KÍCH HOẠT KEY  ›" forState:UIControlStateNormal];
 self.submitButton.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightBold];
 [self.submitButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
 self.submitButton.layer.cornerRadius=14;self.submitButton.layer.masksToBounds=YES;
 [self.submitButton.heightAnchor constraintEqualToConstant:56].active=YES;
 [self.submitButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
 [panel addArrangedSubview:self.submitButton];
 self.ctaLayer=[CAGradientLayer layer];
 self.ctaLayer.colors=@[(__bridge id)eriBlue(0x268AFF).CGColor,
                         (__bridge id)eriBlue(0x645AEA).CGColor];
 self.ctaLayer.startPoint=CGPointMake(0,.5);self.ctaLayer.endPoint=CGPointMake(1,.5);
 [self.submitButton.layer insertSublayer:self.ctaLayer atIndex:0];
 self.spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
 self.spinner.hidesWhenStopped=YES;self.spinner.color=UIColor.whiteColor;self.spinner.translatesAutoresizingMaskIntoConstraints=NO;
 [self.submitButton addSubview:self.spinner];
 [NSLayoutConstraint activateConstraints:@[
  [self.spinner.trailingAnchor constraintEqualToAnchor:self.submitButton.trailingAnchor constant:-18],
  [self.spinner.centerYAnchor constraintEqualToAnchor:self.submitButton.centerYAnchor]
 ]];
 self.status=eriMakeLabel(@"Dán key do Admin cấp để kích hoạt.",12,UIFontWeightMedium,eriBlue(0xB2C6DF));
 [panel addArrangedSubview:self.status];
 UIButton *appIdButton=[UIButton buttonWithType:UIButtonTypeSystem];
 NSString *appLabel=[NSString stringWithFormat:@"APP ID: %@   •   SAO CHÉP",eriLicenseAppID()];
 [appIdButton setTitle:appLabel forState:UIControlStateNormal];
 [appIdButton setTitleColor:eriBlue(0x80C9EE) forState:UIControlStateNormal];
 appIdButton.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
 appIdButton.titleLabel.numberOfLines=2;
 appIdButton.titleLabel.textAlignment=NSTextAlignmentCenter;
 [appIdButton addTarget:self action:@selector(copyAppID:) forControlEvents:UIControlEventTouchUpInside];
 [panel addArrangedSubview:appIdButton];
 [stack addArrangedSubview:eriMakeLabel(@"XÁC MINH ONLINE • LIÊN KẾT THEO THIẾT BỊ\nMOD BY ERI NGUYỄN",
  10,UIFontWeightMedium,eriBlue(0x7791B4))];
 [self verifySaved];
}
-(void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];
 self.bgLayer.frame=self.view.bounds;
 self.ctaLayer.frame=self.submitButton.bounds;
 self.ctaLayer.cornerRadius=14;
}
-(void)copyAppID:(id)sender {
 UIPasteboard.generalPasteboard.string=eriLicenseAppID();
 self.status.text=@"Đã sao chép App ID. Kiểm tra ID này trong ERI ADMIN.";
 self.status.textColor=eriBlue(0x86E5EF);
}
-(void)pasteKey:(id)sender {
 NSString *p=UIPasteboard.generalPasteboard.string;
 if(!p.length){self.status.text=@"Bộ nhớ tạm chưa có key.";return;}
 self.keyField.text=p;
 [self.keyField resignFirstResponder];
 self.status.text=@"Đã dán key. Nhấn KÍCH HOẠT KEY.";
 self.status.textColor=eriBlue(0x86E5EF);
}
-(BOOL)textFieldShouldReturn:(UITextField *)field {
 [field resignFirstResponder];[self tap:nil];return YES;
}
-(void)verifySaved {
 NSString *key=eriText(self.keyField.text).uppercaseString;
 if([key rangeOfString:@"^ERI-[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){5}$"
                options:NSRegularExpressionSearch].location!=NSNotFound)[self sendKey:NO];
}
-(void)tap:(id)sender {[self.view endEditing:YES];[self sendKey:YES];}
-(void)send:(NSString *)endpoint
       data:(NSDictionary *)payload
    success:(void(^)(NSDictionary *response))onSuccess
    failure:(void(^)(NSString *message))onFailure {
    if (eriWorking) return;
    NSString *bundle = eriLicenseAppID();
    if (!bundle.length) { self.status.text = @"Không xác định được Bundle ID."; return; }
    NSMutableDictionary *body = [payload mutableCopy];
    body[@"app_id"] = bundle;
    NSError *jsonError = nil;
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!encoded || jsonError) { self.status.text = @"Dữ liệu đăng nhập không hợp lệ."; return; }
    eriWorking = YES;
    self.submitButton.enabled = NO;
    self.status.text = @"Đang xác minh key qua HTTPS...";
    self.status.textColor = eriBlue(0x86E5EF);
    [self.spinner startAnimating];
    NSURL *url = [NSURL URLWithString:[ERIBase stringByAppendingString:endpoint]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = encoded;
    req.timeoutInterval = 65;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    __weak ERIGate *weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *networkError) {
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *response = [json isKindOfClass:NSDictionary.class] ? json : @{};
        NSInteger code = [res isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)res statusCode] : 0;
        BOOL ok = code >= 200 && code < 300;
        NSString *errorText = networkError ? @"Không kết nối được máy chủ. Kiểm tra Internet." :
            ([response[@"error"] isKindOfClass:NSString.class] ? response[@"error"] :
             [NSString stringWithFormat:@"Máy chủ từ chối (HTTP %ld)", (long)code]);
        dispatch_async(dispatch_get_main_queue(), ^{
            eriWorking = NO;
            ERIGate *ctl = weakSelf;
            if (!ctl) return;
            ctl.submitButton.enabled = YES;
            [ctl.spinner stopAnimating];
            if (!ok) ctl.status.textColor=eriBlue(0xFFACA8);
            if (ok) onSuccess(response);
            else onFailure(errorText);
        });
    }] resume];
}
-(void)sendKey:(BOOL)activate {
    NSString *key = eriText(self.keyField.text).uppercaseString;
    // Key format generated by the ERI key backend, not a username.
    NSString *pattern = @"^ERI-[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){5}$";
    if ([key rangeOfString:pattern options:NSRegularExpressionSearch].location == NSNotFound) {
        self.status.text = @"Sai định dạng. Dán key ERI-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX, không nhập tên tài khoản.";
        self.status.textColor=eriBlue(0xFFACA8);
        return;
    }
    [self send:(activate ? @"/api/key/activate" : @"/api/key/verify")
          data:@{@"key":key, @"device_id":eriDeviceID()}
       success:^(NSDictionary *response) {
           if (![response[@"valid"] boolValue]) {
               self.status.text = @"Máy chủ không xác nhận key.";
               return;
           }
           eriWrite(@"key", key);
           eriUnlock();
       }
       failure:^(NSString *errorText) {
           self.status.text = errorText;
       }];
}
@end

static void eriShow(int retries) {
    if (eriUnlocked || eriWindow) return;
    UIWindowScene *scene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class] &&
                s.activationState != UISceneActivationStateUnattached) {
                scene = (UIWindowScene *)s; break;
            }
        }
    }
    if (!scene) {
        if (retries > 0)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ eriShow(retries-1); });
        return;
    }
    eriWindow = [[UIWindow alloc] initWithWindowScene:scene];
    eriWindow.windowLevel = UIWindowLevelAlert + 100;
    eriWindow.rootViewController = [ERIGate new];
    eriWindow.hidden = NO;
    [eriWindow makeKeyAndVisible];
}
__attribute__((constructor)) static void eriStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) { if (!eriUnlocked) eriShow(30); }];
        [NSNotificationCenter.defaultCenter
            addObserverForName:UISceneDidActivateNotification
                        object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) { if (!eriUnlocked) eriShow(30); }];
        eriShow(30);
    });
}
