#import <UIKit/UIKit.h>
#import <Security/Security.h>

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
static void eriUnlock(void) {
    eriUnlocked = YES;
    eriWindow.hidden = YES;
    eriWindow = nil;
}

@interface ERIGate : UIViewController <UITextFieldDelegate>
@property(nonatomic,strong) UISegmentedControl *selector;
@property(nonatomic,strong) UITextField *keyField;
@property(nonatomic,strong) UITextField *userField;
@property(nonatomic,strong) UITextField *passwordField;
@property(nonatomic,strong) UIButton *submitButton;
@property(nonatomic,strong) UILabel *status;
-(void)verifySaved;
@end

@implementation ERIGate
-(UITextField *)input:(NSString *)hint secure:(BOOL)secure {
    UITextField *field = [UITextField new];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.backgroundColor = UIColor.whiteColor;
    field.textColor = UIColor.blackColor;
    field.placeholder = hint;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.secureTextEntry = secure;
    field.adjustsFontSizeToFitWidth = YES;
    field.minimumFontSize = 10;
    field.delegate = self;
    [field.heightAnchor constraintEqualToConstant:52].active = YES;
    return field;
}
-(void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.025 green:0.054 blue:0.12 alpha:1];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 17;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [stack.widthAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor multiplier:0.86],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:380]
    ]];

    UILabel *title = [UILabel new];
    title.text = @"ERI LOGIN";
    title.font = [UIFont boldSystemFontOfSize:32];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:title];

    self.selector = [[UISegmentedControl alloc] initWithItems:@[@"TÀI KHOẢN", @"KEY"]];
    self.selector.selectedSegmentTintColor = UIColor.systemBlueColor;
    [self.selector addTarget:self action:@selector(changeMode:) forControlEvents:UIControlEventValueChanged];
    [self.selector.heightAnchor constraintEqualToConstant:42].active = YES;
    [stack addArrangedSubview:self.selector];

    self.keyField = [self input:@"ERI-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX" secure:NO];
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.keyField.text = eriRead(@"key");
    self.userField = [self input:@"Tên tài khoản ERI" secure:NO];
    self.userField.text = eriRead(@"username");
    self.passwordField = [self input:@"Mật khẩu do Admin cấp" secure:YES];
    self.passwordField.textContentType = UITextContentTypePassword;

    [stack addArrangedSubview:self.keyField];
    [stack addArrangedSubview:self.userField];
    [stack addArrangedSubview:self.passwordField];

    self.submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.submitButton.backgroundColor = [UIColor colorWithRed:0.13 green:0.40 blue:1 alpha:1];
    self.submitButton.layer.cornerRadius = 12;
    self.submitButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.submitButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.submitButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [self.submitButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.submitButton];

    self.status = [UILabel new];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.textColor = [UIColor colorWithWhite:0.87 alpha:1];
    self.status.numberOfLines = 0;
    [stack addArrangedSubview:self.status];

    self.selector.selectedSegmentIndex = [eriRead(@"last-mode") isEqualToString:@"key"] ? 1 : 0;
    [self changeMode:nil];
    [self verifySaved];
}
-(void)changeMode:(id)sender {
    BOOL keyMode = self.selector.selectedSegmentIndex == 1;
    self.keyField.hidden = !keyMode;
    self.userField.hidden = keyMode;
    self.passwordField.hidden = keyMode;
    [self.submitButton setTitle:(keyMode ? @"KÍCH HOẠT KEY" : @"ĐĂNG NHẬP TK + MK")
                       forState:UIControlStateNormal];
    self.status.text = keyMode
        ? @"Key 1 thiết bị do ERI ADMIN cấp."
        : @"Nhập đúng TÀI KHOẢN và MẬT KHẨU do ERI ADMIN cấp.";
    eriWrite(@"last-mode", keyMode ? @"key" : @"account");
}
-(BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    [self tap:nil];
    return YES;
}
-(void)verifySaved {
    // Revalidate every launch. Store a session token, not the user's password.
    NSString *token = eriRead(@"session-token");
    if (token.length >= 32) {
        self.selector.selectedSegmentIndex = 0;
        [self changeMode:nil];
        [self sendAccount:YES];
    } else if (self.keyField.text.length > 0) {
        self.selector.selectedSegmentIndex = 1;
        [self changeMode:nil];
        [self sendKey:NO];
    }
}
-(void)tap:(id)sender {
    [self.view endEditing:YES];
    if (self.selector.selectedSegmentIndex == 1) {
        [self sendKey:YES];
    } else {
        [self sendAccount:NO];
    }
}
-(void)send:(NSString *)endpoint
       data:(NSDictionary *)payload
    success:(void(^)(NSDictionary *response))onSuccess
    failure:(void(^)(NSString *message))onFailure {
    if (eriWorking) return;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    if (!bundle.length) { self.status.text = @"Không xác định được Bundle ID."; return; }
    NSMutableDictionary *body = [payload mutableCopy];
    body[@"app_id"] = bundle;
    NSError *jsonError = nil;
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!encoded || jsonError) { self.status.text = @"Dữ liệu đăng nhập không hợp lệ."; return; }
    eriWorking = YES;
    self.submitButton.enabled = NO;
    self.status.text = @"Đang xác minh với máy chủ...";
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
        self.status.text = @"Đây là ô KEY. Nếu được cấp TK/MK, hãy chọn TÀI KHOẢN.";
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
           eriWrite(@"session-token", @"");
           eriUnlock();
       }
       failure:^(NSString *errorText) {
           self.status.text = errorText;
       }];
}
-(void)sendAccount:(BOOL)verify {
    NSString *username = eriText(self.userField.text);
    NSString *password = self.passwordField.text ?: @"";
    NSString *token = eriRead(@"session-token");
    if (verify) {
        if (token.length < 32) { self.status.text = @"Không có phiên đăng nhập."; return; }
    } else if (username.length < 3 || username.length > 64 || password.length < 8) {
        self.status.text = @"Nhập tên tài khoản và mật khẩu (tối thiểu 8 ký tự).";
        return;
    }
    NSDictionary *payload = verify ? @{@"token":token} : @{@"username":username, @"password":password};
    [self send:(verify ? @"/api/verify" : @"/api/login") data:payload
       success:^(NSDictionary *response) {
           if (verify && ![response[@"valid"] boolValue]) {
               eriWrite(@"session-token", @"");
               self.status.text = @"Phiên đã hết hạn. Vui lòng đăng nhập lại.";
               return;
           }
           if (!verify) {
               NSString *newToken = [response[@"token"] isKindOfClass:NSString.class] ? response[@"token"] : @"";
               if (newToken.length < 32) {
                   self.status.text = @"Máy chủ chưa trả về phiên đăng nhập hợp lệ.";
                   return;
               }
               eriWrite(@"session-token", newToken);
               eriWrite(@"username", username);
           }
           self.passwordField.text = @"";
           eriWrite(@"key", @"");
           eriUnlock();
       }
       failure:^(NSString *errorText) {
           if (verify) eriWrite(@"session-token", @"");
           self.status.text = verify
             ? [NSString stringWithFormat:@"%@ Nhập TK/MK để đăng nhập lại.", errorText]
             : errorText;
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
