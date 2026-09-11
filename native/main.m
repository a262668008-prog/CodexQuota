#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

static NSColor *CQColor(NSUInteger hex, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0
                               green:((hex >> 8) & 0xff) / 255.0
                                blue:(hex & 0xff) / 255.0
                               alpha:alpha];
}

@interface CQTheme : NSObject
@property NSString *key;
@property NSString *title;
@property NSString *image;
@property NSUInteger accent;
@property BOOL light;
+ (instancetype)theme:(NSString *)key title:(NSString *)title image:(NSString *)image accent:(NSUInteger)accent light:(BOOL)light;
@end

@implementation CQTheme
+ (instancetype)theme:(NSString *)key title:(NSString *)title image:(NSString *)image accent:(NSUInteger)accent light:(BOOL)light {
    CQTheme *theme = [CQTheme new];
    theme.key = key; theme.title = title; theme.image = image; theme.accent = accent; theme.light = light;
    return theme;
}
@end

@interface CQInteractiveView : NSView
@property (copy) void (^singleClick)(void);
@property (copy) void (^doubleClick)(void);
@property (copy) void (^mouseExit)(void);
@property BOOL dragLocked;
@property BOOL didDrag;
@property NSTrackingArea *trackingArea;
@end

@implementation CQInteractiveView
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if ([hit isKindOfClass:NSButton.class]) return hit;
    return self;
}
- (void)mouseDown:(NSEvent *)event {
    self.didDrag = NO;
    if (event.clickCount == 2 && self.doubleClick) self.doubleClick();
}
- (void)mouseDragged:(NSEvent *)event {
    if (self.dragLocked) return;
    self.didDrag = YES;
    [self.window performWindowDragWithEvent:event];
}
- (void)mouseUp:(NSEvent *)event {
    if (event.clickCount == 1 && !self.didDrag && self.singleClick) self.singleClick();
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) [self removeTrackingArea:self.trackingArea];
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                      owner:self userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}
- (void)mouseExited:(NSEvent *)event {
    if (self.mouseExit) self.mouseExit();
}
@end

@interface QuotaAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property NSStatusItem *statusItem;
@property NSPanel *panel;
@property CQInteractiveView *rootView;
@property NSImageView *backgroundView;
@property NSView *shadeView;
@property CAGradientLayer *shadeLayer;
@property NSTextField *codexLabel;
@property NSTextField *planLabel;
@property NSTextField *themeLabel;
@property NSTextField *sessionValue;
@property NSTextField *sessionReset;
@property NSTextField *weeklyValue;
@property NSTextField *weeklyReset;
@property NSTextField *footerLabel;
@property NSView *sessionCard;
@property NSView *weeklyCard;
@property NSView *operationBar;
@property NSButton *lockButton;
@property NSView *collapsedContainer;
@property NSTextField *collapsedWeeklyLabel;
@property NSView *collapsedWeeklyTrack;
@property NSView *collapsedWeeklyFill;
@property NSView *collapsedSessionRow;
@property NSTextField *collapsedSessionLabel;
@property NSView *collapsedSessionTrack;
@property NSView *collapsedSessionFill;
@property NSView *projectPanel;
@property NSArray<NSTextField *> *projectNameLabels;
@property NSArray<NSTextField *> *projectPercentLabels;
@property NSArray<NSView *> *projectFills;
@property NSArray<NSDictionary *> *projectStats;
@property NSMenuItem *toggleItem;
@property NSMenuItem *sessionMenuItem;
@property NSMenuItem *weeklyMenuItem;
@property NSMenuItem *accountMenuItem;
@property NSArray<CQTheme *> *themes;
@property CQTheme *theme;
@property NSTask *quotaTask;
@property NSPipe *quotaInputPipe;
@property NSPipe *quotaOutputPipe;
@property NSPipe *quotaErrorPipe;
@property NSMutableData *quotaBuffer;
@property NSMutableData *errorBuffer;
@property NSTimer *refreshTimer;
@property NSDate *lastRefresh;
@property NSMutableDictionary<NSString *, NSMutableDictionary *> *accountHistory;
@property NSArray<NSMutableDictionary *> *accountRows;
@property NSString *currentAccountEmail;
@property NSDictionary *pendingAccount;
@property NSDictionary *pendingSnapshot;
@property NSWindow *accountWindow;
@property NSTableView *accountTable;
@property NSTextField *accountSummaryLabel;
@property dispatch_queue_t projectStatsQueue;
@property NSMutableDictionary<NSString *, NSDictionary *> *projectFileCache;
@property BOOL projectStatsScanRunning;
@property BOOL accountResponseReceived;
@property BOOL rateResponseReceived;
@property BOOL positionLocked;
@property BOOL compactMode;
@end

@implementation QuotaAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.themes = @[
        [CQTheme theme:@"ocean" title:@"深海蓝" image:@"" accent:0x62E1FF light:NO],
        [CQTheme theme:@"amber" title:@"暖琥珀" image:@"" accent:0xFFC45C light:NO],
        [CQTheme theme:@"mint" title:@"薄荷绿" image:@"" accent:0x65E8AD light:NO]
    ];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"selectedTheme"];
    self.theme = [self themeForKey:saved] ?: self.themes.firstObject;
    [self loadAccountHistory];
    self.projectStatsQueue = dispatch_queue_create("com.jason.codexquota.project-stats", DISPATCH_QUEUE_SERIAL);
    self.projectFileCache = [NSMutableDictionary dictionary];
    [self buildPanel];
    [self buildStatusItem];
    [self applyTheme];
    [self.panel orderFrontRegardless];
    NSString *selfTest = NSProcessInfo.processInfo.environment[@"CODEXQUOTA_SELF_TEST"];
    if (selfTest.length) {
        [self runSelfTest:selfTest];
    } else {
        [self refresh:nil];
        self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [self cleanupQuotaTask:self.quotaTask terminate:YES];
}

- (CQTheme *)themeForKey:(NSString *)key {
    for (CQTheme *theme in self.themes) if ([theme.key isEqualToString:key]) return theme;
    return nil;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = NSColor.whiteColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSView *)cardWithFrame:(NSRect)frame title:(NSString *)title valueLabel:(NSTextField **)value resetLabel:(NSTextField **)reset {
    NSView *card = [[NSView alloc] initWithFrame:frame];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 11;
    card.layer.borderWidth = 0.7;
    NSTextField *titleLabel = [self label:title size:9 weight:NSFontWeightBold frame:NSMakeRect(10, 45, frame.size.width - 20, 13)];
    titleLabel.alphaValue = 0.72;
    [card addSubview:titleLabel];
    *value = [self label:@"—" size:19 weight:NSFontWeightHeavy frame:NSMakeRect(10, 23, frame.size.width - 20, 24)];
    [card addSubview:*value];
    *reset = [self label:@"等待数据" size:8 weight:NSFontWeightSemibold frame:NSMakeRect(10, 8, frame.size.width - 20, 13)];
    (*reset).alphaValue = 0.82;
    [card addSubview:*reset];
    return card;
}

- (void)buildPanel {
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 340, 360)
                                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                              backing:NSBackingStoreBuffered defer:NO];
    self.panel.level = NSFloatingWindowLevel;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.movableByWindowBackground = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    [self.panel setFrameAutosaveName:@"CodexQuotaFloatingPanel"];

    CQInteractiveView *root = [[CQInteractiveView alloc] initWithFrame:NSMakeRect(0, 0, 340, 360)];
    self.rootView = root;
    root.wantsLayer = YES;
    root.layer.cornerRadius = 18;
    root.layer.masksToBounds = YES;
    self.panel.contentView = root;

    self.backgroundView = [[NSImageView alloc] initWithFrame:root.bounds];
    self.backgroundView.imageScaling = NSImageScaleAxesIndependently;
    self.backgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:self.backgroundView];

    NSView *shade = [[NSView alloc] initWithFrame:root.bounds];
    self.shadeView = shade;
    shade.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    shade.wantsLayer = YES;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    self.shadeLayer = gradient;
    gradient.frame = shade.bounds;
    gradient.colors = @[(id)[NSColor colorWithWhite:0 alpha:0.04].CGColor,
                        (id)[NSColor colorWithWhite:0 alpha:0.18].CGColor,
                        (id)[NSColor colorWithWhite:0 alpha:0.86].CGColor];
    gradient.locations = @[@0, @0.46, @1];
    [shade.layer addSublayer:gradient];
    [root addSubview:shade];

    self.codexLabel = [self label:@"CODEX" size:16 weight:NSFontWeightHeavy frame:NSMakeRect(14, 328, 66, 21)];
    [root addSubview:self.codexLabel];
    self.planLabel = [self label:@"连接中" size:8 weight:NSFontWeightBold frame:NSMakeRect(80, 330, 60, 18)];
    [root addSubview:self.planLabel];
    self.themeLabel = [self label:self.theme.title size:8 weight:NSFontWeightBold frame:NSMakeRect(190, 331, 134, 16)];
    self.themeLabel.alignment = NSTextAlignmentRight;
    [root addSubview:self.themeLabel];

    NSTextField *sessionValue = nil, *sessionReset = nil, *weeklyValue = nil, *weeklyReset = nil;
    self.sessionCard = [self cardWithFrame:NSMakeRect(13, 230, 153, 72) title:@"5小时窗口" valueLabel:&sessionValue resetLabel:&sessionReset];
    self.weeklyCard = [self cardWithFrame:NSMakeRect(174, 230, 153, 72) title:@"每周额度" valueLabel:&weeklyValue resetLabel:&weeklyReset];
    self.sessionValue = sessionValue; self.sessionReset = sessionReset;
    self.weeklyValue = weeklyValue; self.weeklyReset = weeklyReset;
    [root addSubview:self.sessionCard]; [root addSubview:self.weeklyCard];

    self.footerLabel = [self label:@"正在连接 Codex · 60秒刷新" size:8 weight:NSFontWeightBold frame:NSMakeRect(14, 17, 312, 15)];
    [root addSubview:self.footerLabel];
    [self buildProjectPanelInView:root];
    [self buildCollapsedProgressInView:root];
    [self buildOperationBarInView:root];
    __weak typeof(self) weakSelf = self;
    root.singleClick = ^{
        if (weakSelf.compactMode) [weakSelf setCompactMode:NO animated:YES];
    };
    root.doubleClick = ^{ [weakSelf toggleCompactMode]; };
    root.mouseExit = ^{
        if (!weakSelf.compactMode) [weakSelf setCompactMode:YES animated:YES];
    };
    if (![self.panel setFrameUsingName:@"CodexQuotaFloatingPanel"]) [self.panel center];
    [self setCompactMode:YES animated:NO];
}

- (NSButton *)toolbarButton:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleRecessed;
    button.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    button.contentTintColor = NSColor.whiteColor;
    return button;
}

- (NSView *)progressTrackWithFill:(NSView **)fill {
    NSView *track = [[NSView alloc] initWithFrame:NSZeroRect];
    track.wantsLayer = YES;
    track.layer.cornerRadius = 4;
    track.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.22].CGColor;
    *fill = [[NSView alloc] initWithFrame:NSZeroRect];
    (*fill).wantsLayer = YES;
    (*fill).layer.cornerRadius = 4;
    [track addSubview:*fill];
    return track;
}

- (void)buildCollapsedProgressInView:(NSView *)root {
    NSView *container = [[NSView alloc] initWithFrame:root.bounds];
    container.wantsLayer = YES;
    container.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:0.54].CGColor;
    self.collapsedContainer = container;
    self.collapsedWeeklyLabel = [self label:@"周额度 · 等待数据" size:12 weight:NSFontWeightBold frame:NSZeroRect];
    [container addSubview:self.collapsedWeeklyLabel];
    NSView *weeklyFill = nil;
    self.collapsedWeeklyTrack = [self progressTrackWithFill:&weeklyFill];
    self.collapsedWeeklyFill = weeklyFill;
    [container addSubview:self.collapsedWeeklyTrack];
    self.collapsedSessionRow = [[NSView alloc] initWithFrame:NSZeroRect];
    self.collapsedSessionLabel = [self label:@"5小时额度 · 等待数据" size:11 weight:NSFontWeightSemibold frame:NSZeroRect];
    [self.collapsedSessionRow addSubview:self.collapsedSessionLabel];
    NSView *sessionFill = nil;
    self.collapsedSessionTrack = [self progressTrackWithFill:&sessionFill];
    self.collapsedSessionFill = sessionFill;
    [self.collapsedSessionRow addSubview:self.collapsedSessionTrack];
    [container addSubview:self.collapsedSessionRow];
    self.collapsedSessionRow.hidden = YES;
    container.hidden = YES;
    [root addSubview:container];
}

- (void)buildProjectPanelInView:(NSView *)root {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(13, 82, 314, 132)];
    panel.wantsLayer = YES;
    panel.layer.cornerRadius = 12;
    panel.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:0.58].CGColor;
    panel.layer.borderWidth = 0.7;
    self.projectPanel = panel;
    NSTextField *title = [self label:@"本周最近项目" size:10 weight:NSFontWeightBold frame:NSMakeRect(10, 108, 180, 16)];
    [panel addSubview:title];
    NSMutableArray *names = [NSMutableArray array], *percents = [NSMutableArray array], *fills = [NSMutableArray array];
    for (NSInteger index = 0; index < 3; index++) {
        CGFloat y = 77 - index * 34;
        NSTextField *name = [self label:@"暂无项目记录" size:10 weight:NSFontWeightSemibold frame:NSMakeRect(10, y + 9, 220, 15)];
        NSTextField *percent = [self label:@"—" size:10 weight:NSFontWeightBold frame:NSMakeRect(245, y + 9, 58, 15)];
        percent.alignment = NSTextAlignmentRight;
        NSView *fill = nil;
        NSView *track = [self progressTrackWithFill:&fill];
        track.frame = NSMakeRect(10, y, 293, 5);
        [panel addSubview:name]; [panel addSubview:percent]; [panel addSubview:track];
        [names addObject:name]; [percents addObject:percent]; [fills addObject:fill];
    }
    self.projectNameLabels = names; self.projectPercentLabels = percents; self.projectFills = fills;
    [root addSubview:panel];
}

- (void)buildOperationBarInView:(NSView *)root {
    NSVisualEffectView *bar = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(13, 42, 314, 34)];
    bar.material = NSVisualEffectMaterialHUDWindow;
    bar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    bar.state = NSVisualEffectStateActive;
    bar.wantsLayer = YES;
    bar.layer.cornerRadius = 10;
    self.operationBar = bar;
    [bar addSubview:[self toolbarButton:@"刷新" action:@selector(refresh:) frame:NSMakeRect(6, 4, 56, 26)]];
    [bar addSubview:[self toolbarButton:@"账号" action:@selector(showAccountManager:) frame:NSMakeRect(68, 4, 56, 26)]];
    [bar addSubview:[self toolbarButton:@"换肤" action:@selector(cycleTheme:) frame:NSMakeRect(130, 4, 56, 26)]];
    self.lockButton = [self toolbarButton:@"锁定" action:@selector(togglePositionLock:) frame:NSMakeRect(192, 4, 56, 26)];
    [bar addSubview:self.lockButton];
    [bar addSubview:[self toolbarButton:@"隐藏" action:@selector(togglePanel:) frame:NSMakeRect(254, 4, 54, 26)]];
    bar.hidden = NO;
    [root addSubview:bar];
}

- (void)toggleOperationBar {
    if (self.compactMode) [self setCompactMode:NO animated:YES];
}

- (void)cycleTheme:(id)sender {
    NSUInteger index = [self.themes indexOfObject:self.theme];
    self.theme = self.themes[(index + 1) % self.themes.count];
    [[NSUserDefaults standardUserDefaults] setObject:self.theme.key forKey:@"selectedTheme"];
    [self applyTheme];
}

- (void)togglePositionLock:(id)sender {
    self.positionLocked = !self.positionLocked;
    self.rootView.dragLocked = self.positionLocked;
    self.lockButton.title = self.positionLocked ? @"已锁定" : @"锁定";
}

- (void)toggleCompactMode {
    [self setCompactMode:!self.compactMode animated:YES];
}

- (void)setCompactMode:(BOOL)compact animated:(BOOL)animated {
    if (self.compactMode == compact) return;
    self.compactMode = compact;
    self.collapsedContainer.hidden = !compact;
    self.codexLabel.hidden = compact; self.planLabel.hidden = compact; self.themeLabel.hidden = compact;
    self.sessionCard.hidden = compact; self.weeklyCard.hidden = compact;
    self.projectPanel.hidden = compact; self.operationBar.hidden = compact; self.footerLabel.hidden = compact;
    NSRect frame = self.panel.frame;
    CGFloat oldHeight = frame.size.height;
    CGFloat collapsedHeight = self.collapsedSessionRow.hidden ? 62 : 92;
    frame.size = compact ? NSMakeSize(280, collapsedHeight) : NSMakeSize(340, 360);
    frame.origin.y += oldHeight - frame.size.height;
    [self.panel setFrame:frame display:YES animate:animated];
    if (compact) {
        [self layoutCollapsedProgress];
    }
    self.shadeLayer.frame = self.shadeView.bounds;
}

- (void)layoutCollapsedProgress {
    CGFloat height = self.collapsedSessionRow.hidden ? 62 : 92;
    self.collapsedContainer.frame = NSMakeRect(0, 0, 280, height);
    if (self.collapsedSessionRow.hidden) {
        self.collapsedWeeklyLabel.frame = NSMakeRect(12, 32, 256, 18);
        self.collapsedWeeklyTrack.frame = NSMakeRect(12, 17, 256, 8);
    } else {
        self.collapsedWeeklyLabel.frame = NSMakeRect(12, 61, 256, 18);
        self.collapsedWeeklyTrack.frame = NSMakeRect(12, 48, 256, 8);
        self.collapsedSessionRow.frame = NSMakeRect(0, 0, 280, 43);
        self.collapsedSessionLabel.frame = NSMakeRect(12, 19, 256, 17);
        self.collapsedSessionTrack.frame = NSMakeRect(12, 7, 256, 7);
    }
    [self updateCollapsedFillFrames];
}

- (void)updateCollapsedFillFrames {
    CGFloat weeklyPercent = [[self.collapsedWeeklyLabel.stringValue componentsSeparatedByString:@"%"].firstObject componentsSeparatedByString:@" "].lastObject.doubleValue;
    CGFloat sessionPercent = [[self.collapsedSessionLabel.stringValue componentsSeparatedByString:@"%"].firstObject componentsSeparatedByString:@" "].lastObject.doubleValue;
    self.collapsedWeeklyFill.frame = NSMakeRect(0, 0, self.collapsedWeeklyTrack.bounds.size.width * weeklyPercent / 100.0, self.collapsedWeeklyTrack.bounds.size.height);
    self.collapsedSessionFill.frame = NSMakeRect(0, 0, self.collapsedSessionTrack.bounds.size.width * sessionPercent / 100.0, self.collapsedSessionTrack.bounds.size.height);
}

- (void)buildStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"gauge.with.dots.needle.50percent" accessibilityDescription:@"Codex 额度"];
    self.statusItem.button.title = @" —";
    NSMenu *menu = [NSMenu new];
    self.accountMenuItem = [[NSMenuItem alloc] initWithTitle:@"账号：等待识别" action:nil keyEquivalent:@""];
    self.sessionMenuItem = [[NSMenuItem alloc] initWithTitle:@"5小时：等待数据" action:nil keyEquivalent:@""];
    self.weeklyMenuItem = [[NSMenuItem alloc] initWithTitle:@"每周：等待数据" action:nil keyEquivalent:@""];
    [menu addItem:self.accountMenuItem]; [menu addItem:self.sessionMenuItem]; [menu addItem:self.weeklyMenuItem]; [menu addItem:NSMenuItem.separatorItem];
    self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"隐藏桌面组件" action:@selector(togglePanel:) keyEquivalent:@""];
    self.toggleItem.target = self; [menu addItem:self.toggleItem];
    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"立即刷新" action:@selector(refresh:) keyEquivalent:@"r"];
    refresh.target = self; [menu addItem:refresh];
    NSMenuItem *accounts = [[NSMenuItem alloc] initWithTitle:@"账号管理…" action:@selector(showAccountManager:) keyEquivalent:@"a"];
    accounts.target = self; [menu addItem:accounts];
    NSMenuItem *skin = [[NSMenuItem alloc] initWithTitle:@"选择皮肤" action:nil keyEquivalent:@""];
    NSMenu *skinMenu = [NSMenu new];
    for (CQTheme *theme in self.themes) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:theme.title action:@selector(selectTheme:) keyEquivalent:@""];
        item.target = self; item.representedObject = theme.key; [skinMenu addItem:item];
    }
    skin.submenu = skinMenu; [menu addItem:skin];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 Codex Quota" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp; [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)togglePanel:(id)sender {
    if (self.panel.visible) { [self.panel orderOut:nil]; self.toggleItem.title = @"显示桌面组件"; }
    else { [self.panel orderFrontRegardless]; self.toggleItem.title = @"隐藏桌面组件"; }
}

- (void)selectTheme:(NSMenuItem *)sender {
    CQTheme *theme = [self themeForKey:sender.representedObject];
    if (!theme) return;
    self.theme = theme;
    [[NSUserDefaults standardUserDefaults] setObject:theme.key forKey:@"selectedTheme"];
    [self applyTheme];
}

- (void)applyTheme {
    self.backgroundView.image = nil;
    self.rootView.layer.backgroundColor = CQColor(0x10202D, 1).CGColor;
    self.themeLabel.stringValue = self.theme.title;
    NSColor *foreground = self.theme.light ? CQColor(0x123D58, 1) : NSColor.whiteColor;
    NSColor *card = self.theme.light ? [NSColor colorWithWhite:1 alpha:0.76] : [NSColor colorWithWhite:0 alpha:0.61];
    for (NSTextField *label in @[self.codexLabel, self.planLabel, self.themeLabel, self.sessionValue, self.sessionReset, self.weeklyValue, self.weeklyReset, self.footerLabel]) label.textColor = foreground;
    for (NSView *view in @[self.sessionCard, self.weeklyCard]) {
        view.layer.backgroundColor = card.CGColor;
        view.layer.borderColor = [foreground colorWithAlphaComponent:0.18].CGColor;
        for (NSView *subview in view.subviews) if ([subview isKindOfClass:NSTextField.class]) ((NSTextField *)subview).textColor = foreground;
    }
    for (NSView *subview in self.projectPanel.subviews) if ([subview isKindOfClass:NSTextField.class]) ((NSTextField *)subview).textColor = foreground;
    self.projectPanel.layer.backgroundColor = card.CGColor;
    self.projectPanel.layer.borderColor = [foreground colorWithAlphaComponent:0.18].CGColor;
    self.collapsedWeeklyLabel.textColor = NSColor.whiteColor;
    self.collapsedSessionLabel.textColor = NSColor.whiteColor;
    NSColor *accent = CQColor(self.theme.accent, 1);
    self.collapsedWeeklyFill.layer.backgroundColor = accent.CGColor;
    self.collapsedSessionFill.layer.backgroundColor = accent.CGColor;
    for (NSView *fill in self.projectFills) fill.layer.backgroundColor = accent.CGColor;
    self.panel.contentView.layer.borderWidth = 1;
    self.panel.contentView.layer.borderColor = CQColor(self.theme.accent, 0.55).CGColor;
}

- (NSString *)codexExecutable {
    NSArray *paths = @[@"/Applications/ChatGPT.app/Contents/Resources/codex", @"/Applications/Codex.app/Contents/Resources/codex", @"/opt/homebrew/bin/codex", @"/usr/local/bin/codex"];
    for (NSString *path in paths) if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    return nil;
}

- (void)refresh:(id)sender {
    if (self.quotaTask.running) return;
    NSString *executable = [self codexExecutable];
    if (!executable) { [self showError:@"未找到 Codex"]; return; }
    self.footerLabel.stringValue = @"正在读取登录额度…";
    self.pendingAccount = nil;
    self.pendingSnapshot = nil;
    self.accountResponseReceived = NO;
    self.rateResponseReceived = NO;
    self.quotaBuffer = [NSMutableData data];
    self.errorBuffer = [NSMutableData data];
    NSTask *task = [NSTask new]; self.quotaTask = task;
    NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe], *errors = [NSPipe pipe];
    self.quotaInputPipe = input;
    self.quotaOutputPipe = output;
    self.quotaErrorPipe = errors;
    task.executableURL = [NSURL fileURLWithPath:executable]; task.arguments = @[@"app-server", @"--stdio"];
    task.standardInput = input; task.standardOutput = output; task.standardError = errors;
    __weak typeof(self) weakSelf = self;
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) {
            handle.readabilityHandler = nil;
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.quotaTask == task) [weakSelf consumeData:data];
        });
    };
    errors.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) {
            handle.readabilityHandler = nil;
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.quotaTask == task) [weakSelf.errorBuffer appendData:data];
        });
    };
    task.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.quotaTask == finishedTask) [weakSelf cleanupQuotaTask:finishedTask terminate:NO];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self cleanupQuotaTask:task terminate:NO];
        [self showError:error.localizedDescription];
        return;
    }
    NSString *payload = @"{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"codex-quota-widget\",\"title\":\"Codex Quota Widget\",\"version\":\"0.3.2\"},\"capabilities\":{\"experimentalApi\":true,\"requestAttestation\":false}}}\n{\"method\":\"initialized\"}\n{\"method\":\"account/read\",\"id\":2,\"params\":{\"refreshToken\":false}}\n{\"method\":\"account/rateLimits/read\",\"id\":3}\n";
    [input.fileHandleForWriting writeData:[payload dataUsingEncoding:NSUTF8StringEncoding]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (weakSelf.quotaTask != task || !task.running) return;
        NSString *details = [[NSString alloc] initWithData:weakSelf.errorBuffer encoding:NSUTF8StringEncoding];
        [weakSelf cleanupQuotaTask:task terminate:YES];
        [weakSelf showError:details.length ? @"Codex 数据服务超时" : @"额度读取超时，请确认 Codex 已登录"];
    });
}

- (void)cleanupQuotaTask:(NSTask *)task terminate:(BOOL)terminate {
    if (!task) return;
    NSPipe *output = [task.standardOutput isKindOfClass:NSPipe.class] ? task.standardOutput : nil;
    NSPipe *errors = [task.standardError isKindOfClass:NSPipe.class] ? task.standardError : nil;
    NSPipe *input = [task.standardInput isKindOfClass:NSPipe.class] ? task.standardInput : nil;
    output.fileHandleForReading.readabilityHandler = nil;
    errors.fileHandleForReading.readabilityHandler = nil;
    [input.fileHandleForWriting closeFile];
    if (terminate && task.running) [task terminate];
    task.terminationHandler = nil;
    if (self.quotaTask == task) {
        self.quotaTask = nil;
        self.quotaInputPipe = nil;
        self.quotaOutputPipe = nil;
        self.quotaErrorPipe = nil;
    }
}

- (void)consumeData:(NSData *)data {
    [self.quotaBuffer appendData:data];
    while (true) {
        NSRange range = [self.quotaBuffer rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, self.quotaBuffer.length)];
        if (range.location == NSNotFound) break;
        NSData *line = [self.quotaBuffer subdataWithRange:NSMakeRange(0, range.location)];
        [self.quotaBuffer replaceBytesInRange:NSMakeRange(0, range.location + 1) withBytes:NULL length:0];
        NSDictionary *json = line.length ? [NSJSONSerialization JSONObjectWithData:line options:0 error:nil] : nil;
        NSInteger responseID = [json[@"id"] integerValue];
        if (responseID == 2) {
            self.accountResponseReceived = YES;
            if (!json[@"error"]) {
                NSDictionary *result = [json[@"result"] isKindOfClass:NSDictionary.class] ? json[@"result"] : nil;
                NSDictionary *account = [result[@"account"] isKindOfClass:NSDictionary.class] ? result[@"account"] : nil;
                if ([account[@"type"] isEqual:@"chatgpt"]) {
                    self.pendingAccount = account;
                } else {
                    self.currentAccountEmail = nil;
                    self.accountMenuItem.title = @"账号：未登录或非 ChatGPT 登录";
                    [self rebuildAccountRows];
                }
            }
            [self finishRefreshIfReady];
            continue;
        }
        if (responseID == 3) {
            self.rateResponseReceived = YES;
            if (json[@"error"]) {
                NSDictionary *error = [json[@"error"] isKindOfClass:NSDictionary.class] ? json[@"error"] : nil;
                [self showError:[error[@"message"] isKindOfClass:NSString.class] ? error[@"message"] : @"额度读取失败"];
                [self cleanupQuotaTask:self.quotaTask terminate:YES];
                return;
            }
            NSDictionary *result = [json[@"result"] isKindOfClass:NSDictionary.class] ? json[@"result"] : nil;
            NSDictionary *byLimit = [result[@"rateLimitsByLimitId"] isKindOfClass:NSDictionary.class] ? result[@"rateLimitsByLimitId"] : nil;
            NSDictionary *codexSnapshot = [byLimit[@"codex"] isKindOfClass:NSDictionary.class] ? byLimit[@"codex"] : nil;
            NSDictionary *legacySnapshot = [result[@"rateLimits"] isKindOfClass:NSDictionary.class] ? result[@"rateLimits"] : nil;
            self.pendingSnapshot = codexSnapshot ?: legacySnapshot;
            [self finishRefreshIfReady];
            continue;
        }
    }
}

- (void)finishRefreshIfReady {
    if (!self.accountResponseReceived || !self.rateResponseReceived) return;
    if (!self.pendingSnapshot) {
        [self showError:@"额度数据格式异常"];
    } else {
        [self updateWithSnapshot:self.pendingSnapshot];
        [self recordAccount:self.pendingAccount snapshot:self.pendingSnapshot];
    }
    [self cleanupQuotaTask:self.quotaTask terminate:YES];
}

- (void)updateWithSnapshot:(NSDictionary *)snapshot {
    if (!snapshot) { [self showError:@"额度数据格式异常"]; return; }
    NSDictionary *session = nil, *weekly = nil;
    NSMutableArray<NSDictionary *> *windows = [NSMutableArray array];
    if ([snapshot[@"primary"] isKindOfClass:NSDictionary.class]) [windows addObject:snapshot[@"primary"]];
    if ([snapshot[@"secondary"] isKindOfClass:NSDictionary.class]) [windows addObject:snapshot[@"secondary"]];
    for (NSDictionary *window in windows) {
        NSInteger duration = [window[@"windowDurationMins"] integerValue];
        if (!window[@"usedPercent"]) continue;
        if (duration > 0 && duration < 10080) session = window;
        if (duration >= 10080) weekly = window;
    }
    NSString *plan = [snapshot[@"planType"] isKindOfClass:NSString.class] ? [snapshot[@"planType"] uppercaseString] : @"CODEX";
    self.planLabel.stringValue = plan;
    [self setWindow:session value:self.sessionValue reset:self.sessionReset menu:self.sessionMenuItem missing:@"等待本次会话产生数据"];
    [self setWindow:weekly value:self.weeklyValue reset:self.weeklyReset menu:self.weeklyMenuItem missing:@"暂未返回周额度"];
    NSDictionary *credits = [snapshot[@"credits"] isKindOfClass:NSDictionary.class] ? snapshot[@"credits"] : @{};
    NSString *creditText = [credits[@"hasCredits"] boolValue] ? [NSString stringWithFormat:@"积分 %@", credits[@"balance"] ?: @"—"] : @"订阅额度";
    self.footerLabel.stringValue = [NSString stringWithFormat:@"%@ · 实时 · 60秒刷新", creditText];
    self.lastRefresh = NSDate.date;
    NSDictionary *preferred = session ?: weekly;
    self.statusItem.button.title = preferred ? [NSString stringWithFormat:@" %ld%%", (long)[self remaining:preferred]] : @" —";
    if (weekly) self.collapsedWeeklyLabel.stringValue = [NSString stringWithFormat:@"周额度 · %ld%% 剩余", (long)[self remaining:weekly]];
    else self.collapsedWeeklyLabel.stringValue = @"周额度 · 等待数据";
    self.collapsedSessionRow.hidden = session == nil;
    if (session) self.collapsedSessionLabel.stringValue = [NSString stringWithFormat:@"5小时额度 · %ld%% 剩余", (long)[self remaining:session]];
    [self resizeCollapsedIfNeeded];
    [self refreshProjectStats];
}

- (void)resizeCollapsedIfNeeded {
    if (!self.compactMode) { [self updateCollapsedFillFrames]; return; }
    CGFloat desiredHeight = self.collapsedSessionRow.hidden ? 62 : 92;
    NSRect frame = self.panel.frame;
    if (fabs(frame.size.height - desiredHeight) > 0.5 || fabs(frame.size.width - 280) > 0.5) {
        CGFloat oldHeight = frame.size.height;
        frame.size = NSMakeSize(280, desiredHeight);
        frame.origin.y += oldHeight - desiredHeight;
        [self.panel setFrame:frame display:YES animate:YES];
    }
    [self layoutCollapsedProgress];
}

- (void)refreshProjectStats {
    if (self.projectStatsScanRunning) return;
    self.projectStatsScanRunning = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.projectStatsQueue, ^{
        NSArray<NSDictionary *> *stats = [weakSelf collectProjectStats];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.projectStatsScanRunning = NO;
            [weakSelf displayProjectStats:stats];
        });
    });
}

- (NSDictionary *)scanProjectFile:(NSString *)path
                       fromOffset:(unsigned long long)startOffset
                               cwd:(NSString *)initialCwd
                            tokens:(long long)initialTokens {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    @try {
        [handle seekToFileOffset:startOffset];
    } @catch (__unused NSException *exception) {
        [handle closeFile];
        return nil;
    }

    __block NSString *cwd = [initialCwd copy];
    __block long long maxTokens = initialTokens;
    unsigned long long bytesRead = startOffset;
    unsigned long long completeOffset = startOffset;
    NSMutableData *pending = [NSMutableData data];
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];

    while (true) {
        @autoreleasepool {
            NSData *chunk = [handle readDataOfLength:64 * 1024];
            if (!chunk.length) break;
            bytesRead += chunk.length;
            [pending appendData:chunk];
            NSUInteger consumed = 0;
            while (consumed < pending.length) {
                NSRange searchRange = NSMakeRange(consumed, pending.length - consumed);
                NSRange newlineRange = [pending rangeOfData:newline options:0 range:searchRange];
                if (newlineRange.location == NSNotFound) break;
                NSRange lineRange = NSMakeRange(consumed, newlineRange.location - consumed);
                NSData *line = lineRange.length ? [pending subdataWithRange:lineRange] : nil;
                if (line.length) {
                    NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                    if ([entry isKindOfClass:NSDictionary.class]) {
                        NSDictionary *payload = [entry[@"payload"] isKindOfClass:NSDictionary.class] ? entry[@"payload"] : nil;
                        if ([entry[@"type"] isEqual:@"session_meta"] && [payload[@"cwd"] isKindOfClass:NSString.class]) {
                            cwd = [payload[@"cwd"] copy];
                        } else if ([entry[@"type"] isEqual:@"event_msg"] && [payload[@"type"] isEqual:@"token_count"]) {
                            NSDictionary *info = [payload[@"info"] isKindOfClass:NSDictionary.class] ? payload[@"info"] : nil;
                            NSDictionary *usage = [info[@"total_token_usage"] isKindOfClass:NSDictionary.class] ? info[@"total_token_usage"] : nil;
                            NSNumber *tokens = [usage[@"total_tokens"] isKindOfClass:NSNumber.class] ? usage[@"total_tokens"] : nil;
                            if (tokens) maxTokens = MAX(maxTokens, tokens.longLongValue);
                        }
                    }
                }
                consumed = NSMaxRange(newlineRange);
            }
            if (consumed) {
                [pending replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
                completeOffset = bytesRead - pending.length;
            }
        }
    }
    [handle closeFile];
    return @{ @"cwd": cwd ?: @"", @"tokens": @(maxTokens), @"offset": @(completeOffset) };
}

- (NSArray<NSDictionary *> *)collectProjectStats {
    NSString *base = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/sessions"];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDate *weekStart = nil;
    [NSCalendar.currentCalendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&weekStart interval:NULL forDate:NSDate.date];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *projects = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *nextCache = [NSMutableDictionary dictionary];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:base];
    NSString *relative = nil;
    while ((relative = enumerator.nextObject)) {
        if (![relative.pathExtension.lowercaseString isEqualToString:@"jsonl"]) continue;
        NSString *path = [base stringByAppendingPathComponent:relative];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
        NSDate *modified = attributes[NSFileModificationDate];
        if (!modified || [modified compare:weekStart] == NSOrderedAscending) continue;
        NSNumber *size = attributes[NSFileSize];
        NSNumber *fileID = attributes[NSFileSystemFileNumber] ?: @0;
        NSDictionary *cached = self.projectFileCache[path];
        BOOL sameFile = cached && [cached[@"fileID"] isEqual:fileID];
        BOOL unchanged = sameFile && [cached[@"size"] isEqual:size] && [cached[@"modified"] isEqual:modified];
        NSDictionary *scan = cached;
        if (!unchanged) {
            BOOL appendOnly = sameFile && size.unsignedLongLongValue >= [cached[@"size"] unsignedLongLongValue];
            unsigned long long offset = appendOnly ? [cached[@"offset"] unsignedLongLongValue] : 0;
            NSString *initialCwd = appendOnly ? cached[@"cwd"] : nil;
            long long initialTokens = appendOnly ? [cached[@"tokens"] longLongValue] : 0;
            scan = [self scanProjectFile:path fromOffset:offset cwd:initialCwd tokens:initialTokens];
        }
        if (!scan) continue;
        NSString *cwd = [scan[@"cwd"] isKindOfClass:NSString.class] ? scan[@"cwd"] : nil;
        long long maxTokens = [scan[@"tokens"] longLongValue];
        nextCache[path] = @{ @"fileID": fileID,
                             @"size": size ?: @0,
                             @"modified": modified,
                             @"cwd": cwd ?: @"",
                             @"tokens": @(maxTokens),
                             @"offset": scan[@"offset"] ?: @0 };
        if (!cwd.length || maxTokens <= 0) continue;
        NSMutableDictionary *project = projects[cwd];
        if (!project) {
            NSString *name = cwd.lastPathComponent.length ? cwd.lastPathComponent : cwd;
            project = [@{@"name": name, @"tokens": @0, @"last": modified} mutableCopy];
            projects[cwd] = project;
        }
        project[@"tokens"] = @([project[@"tokens"] longLongValue] + maxTokens);
        if ([modified compare:project[@"last"]] == NSOrderedDescending) project[@"last"] = modified;
    }
    self.projectFileCache = nextCache;
    long long total = 0;
    for (NSDictionary *project in projects.allValues) total += [project[@"tokens"] longLongValue];
    NSArray *recent = [projects.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [right[@"last"] compare:left[@"last"]];
    }];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *project in [recent subarrayWithRange:NSMakeRange(0, MIN(3, recent.count))]) {
        double percent = total > 0 ? [project[@"tokens"] doubleValue] * 100.0 / total : 0;
        [result addObject:@{@"name": project[@"name"], @"percent": @(percent)}];
    }
    return result;
}

- (void)displayProjectStats:(NSArray<NSDictionary *> *)stats {
    self.projectStats = stats;
    for (NSInteger index = 0; index < 3; index++) {
        NSTextField *name = self.projectNameLabels[index];
        NSTextField *percentLabel = self.projectPercentLabels[index];
        NSView *fill = self.projectFills[index];
        if ((NSUInteger)index < stats.count) {
            NSDictionary *project = stats[index];
            double percent = [project[@"percent"] doubleValue];
            name.stringValue = project[@"name"];
            percentLabel.stringValue = [NSString stringWithFormat:@"%.1f%%", percent];
            fill.frame = NSMakeRect(0, 0, 293 * MIN(100, percent) / 100.0, 5);
        } else {
            name.stringValue = @"暂无项目记录";
            percentLabel.stringValue = @"—";
            fill.frame = NSMakeRect(0, 0, 0, 5);
        }
    }
}

- (NSInteger)remaining:(NSDictionary *)window {
    return MAX(0, MIN(100, lround(100.0 - [window[@"usedPercent"] doubleValue])));
}

- (void)setWindow:(NSDictionary *)window value:(NSTextField *)value reset:(NSTextField *)reset menu:(NSMenuItem *)menu missing:(NSString *)missing {
    if (!window) { value.stringValue = @"—"; reset.stringValue = missing; menu.title = missing; return; }
    NSInteger remaining = [self remaining:window];
    value.stringValue = [NSString stringWithFormat:@"%ld%% 剩余", (long)remaining];
    NSNumber *timestamp = [window[@"resetsAt"] isKindOfClass:NSNumber.class] ? window[@"resetsAt"] : nil;
    NSString *countdown = timestamp ? [self countdown:[NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue]] : @"重置时间未知";
    reset.stringValue = countdown; menu.title = [NSString stringWithFormat:@"%@ · %@", value.stringValue, countdown];
}

- (NSString *)countdown:(NSDate *)date {
    NSInteger total = MAX(0, lround(date.timeIntervalSinceNow));
    NSInteger hours = total / 3600, minutes = (total % 3600) / 60;
    if (hours >= 24) return [NSString stringWithFormat:@"%ld天 %ld小时后重置", (long)(hours / 24), (long)(hours % 24)];
    if (hours > 0) return [NSString stringWithFormat:@"%ld小时 %ld分后重置", (long)hours, (long)minutes];
    return [NSString stringWithFormat:@"%ld分钟后重置", (long)minutes];
}

- (void)loadAccountHistory {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"accountHistoryV1"];
    self.accountHistory = [NSMutableDictionary dictionary];
    [saved enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *value, __unused BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSDictionary.class]) {
            self.accountHistory[key] = [value mutableCopy];
        }
    }];
    [self rebuildAccountRows];
}

- (void)saveAccountHistory {
    [[NSUserDefaults standardUserDefaults] setObject:self.accountHistory forKey:@"accountHistoryV1"];
}

- (NSString *)normalizedEmail:(NSString *)email {
    if (![email isKindOfClass:NSString.class]) return nil;
    NSString *normalized = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    return normalized.length ? normalized : nil;
}

- (NSString *)maskedEmail:(NSString *)email {
    NSString *normalized = [self normalizedEmail:email];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByString:@"@"]; 
    if (parts.count != 2) return normalized ?: @"未知账号";
    NSString *name = parts.firstObject;
    NSUInteger maskLength = name.length > 2 ? MIN((NSUInteger)6, name.length - 2) : 0;
    NSUInteger visibleLength = name.length - maskLength;
    NSUInteger prefixLength = (visibleLength + 1) / 2;
    NSUInteger suffixLength = visibleLength - prefixLength;
    NSString *prefix = prefixLength ? [name substringToIndex:prefixLength] : @"";
    NSString *suffix = suffixLength ? [name substringFromIndex:name.length - suffixLength] : @"";
    NSString *middle = maskLength ? [@"" stringByPaddingToLength:maskLength withString:@"*" startingAtIndex:0] : @"";
    return [NSString stringWithFormat:@"%@%@%@%@%@", prefix, middle, suffix, @"@", parts.lastObject];
}

- (NSDictionary *)quotaWindowsFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *session = nil, *weekly = nil;
    NSArray *windows = @[snapshot[@"primary"] ?: NSNull.null, snapshot[@"secondary"] ?: NSNull.null];
    for (id candidate in windows) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *window = candidate;
        if (![window[@"usedPercent"] isKindOfClass:NSNumber.class]) continue;
        NSInteger duration = [window[@"windowDurationMins"] integerValue];
        if (duration > 0 && duration < 10080) session = window;
        if (duration >= 10080) weekly = window;
    }
    return @{ @"session": session ?: NSNull.null, @"weekly": weekly ?: NSNull.null };
}

- (void)recordAccount:(NSDictionary *)account snapshot:(NSDictionary *)snapshot {
    NSString *email = [self normalizedEmail:account[@"email"]];
    if (!email.length) {
        self.currentAccountEmail = nil;
        self.accountMenuItem.title = @"账号：未登录或无法识别";
        [self rebuildAccountRows];
        return;
    }

    NSDate *now = NSDate.date;
    NSMutableDictionary *record = self.accountHistory[email];
    BOOL accountChanged = ![self.currentAccountEmail isEqual:email];
    if (!record) {
        record = [NSMutableDictionary dictionaryWithDictionary:@{ @"email": email, @"firstSeen": now }];
        self.accountHistory[email] = record;
    }
    NSNumber *previousSessionRemaining = [record[@"sessionRemaining"] isKindOfClass:NSNumber.class] ? record[@"sessionRemaining"] : nil;
    NSNumber *previousWeeklyRemaining = [record[@"weeklyRemaining"] isKindOfClass:NSNumber.class] ? record[@"weeklyRemaining"] : nil;
    if (!record[@"firstSeen"]) record[@"firstSeen"] = now;
    record[@"lastSeen"] = now;
    record[@"lastSnapshotAt"] = now;
    if (accountChanged) record[@"lastLoginAt"] = now;
    NSString *plan = [account[@"planType"] isKindOfClass:NSString.class] ? account[@"planType"] : ([snapshot[@"planType"] isKindOfClass:NSString.class] ? snapshot[@"planType"] : nil);
    if (plan.length) record[@"plan"] = plan.uppercaseString;

    NSDictionary *windows = [self quotaWindowsFromSnapshot:snapshot];
    NSDictionary *session = [windows[@"session"] isKindOfClass:NSDictionary.class] ? windows[@"session"] : nil;
    NSDictionary *weekly = [windows[@"weekly"] isKindOfClass:NSDictionary.class] ? windows[@"weekly"] : nil;
    if (session) {
        NSNumber *remaining = @([self remaining:session]);
        record[@"sessionRemaining"] = remaining;
        if (!record[@"lastUsed"] || (previousSessionRemaining && remaining.integerValue < previousSessionRemaining.integerValue)) record[@"lastUsed"] = now;
        if ([session[@"resetsAt"] isKindOfClass:NSNumber.class]) record[@"sessionResetsAt"] = [NSDate dateWithTimeIntervalSince1970:[session[@"resetsAt"] doubleValue]];
    } else {
        [record removeObjectForKey:@"sessionRemaining"];
        [record removeObjectForKey:@"sessionResetsAt"];
    }
    if (weekly) {
        NSNumber *remaining = @([self remaining:weekly]);
        record[@"weeklyRemaining"] = remaining;
        if (!record[@"lastUsed"] || (previousWeeklyRemaining && remaining.integerValue < previousWeeklyRemaining.integerValue)) record[@"lastUsed"] = now;
        if ([weekly[@"resetsAt"] isKindOfClass:NSNumber.class]) record[@"weeklyResetsAt"] = [NSDate dateWithTimeIntervalSince1970:[weekly[@"resetsAt"] doubleValue]];
    } else {
        [record removeObjectForKey:@"weeklyRemaining"];
        [record removeObjectForKey:@"weeklyResetsAt"];
    }
    NSDictionary *credits = [snapshot[@"credits"] isKindOfClass:NSDictionary.class] ? snapshot[@"credits"] : nil;
    if ([credits[@"balance"] isKindOfClass:NSString.class]) record[@"creditsBalance"] = credits[@"balance"];
    record[@"hasCredits"] = @([credits[@"hasCredits"] boolValue]);

    self.currentAccountEmail = email;
    self.accountMenuItem.title = [NSString stringWithFormat:@"当前账号：%@", [self maskedEmail:email]];
    self.footerLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", [self maskedEmail:email], self.footerLabel.stringValue];
    [self saveAccountHistory];
    [self rebuildAccountRows];
}

- (void)rebuildAccountRows {
    NSArray *values = self.accountHistory.allValues ?: @[];
    NSString *current = self.currentAccountEmail;
    self.accountRows = [values sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        BOOL leftCurrent = [left[@"email"] isEqual:current];
        BOOL rightCurrent = [right[@"email"] isEqual:current];
        if (leftCurrent != rightCurrent) return leftCurrent ? NSOrderedAscending : NSOrderedDescending;
        NSDate *leftDate = left[@"lastSeen"] ?: left[@"manualAddedAt"] ?: NSDate.distantPast;
        NSDate *rightDate = right[@"lastSeen"] ?: right[@"manualAddedAt"] ?: NSDate.distantPast;
        NSComparisonResult dateOrder = [rightDate compare:leftDate];
        if (dateOrder != NSOrderedSame) return dateOrder;
        return [left[@"email"] compare:right[@"email"]];
    }];
    [self.accountTable reloadData];
    if (self.accountSummaryLabel) {
        NSString *currentText = current.length ? [self maskedEmail:current] : @"尚未识别";
        self.accountSummaryLabel.stringValue = [NSString stringWithFormat:@"已管理 %ld 个账号 · 当前 %@", (long)self.accountRows.count, currentText];
    }
}

- (void)showAccountManager:(id)sender {
    NSAssert(NSThread.isMainThread, @"Account window must be used on the main thread");
    if (!self.accountWindow) [self buildAccountManagerWindow];
    [self rebuildAccountRows];
    [NSApp activateIgnoringOtherApps:YES];
    [self.accountWindow makeKeyAndOrderFront:nil];
}

- (void)buildAccountManagerWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 500)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Codex 账号管理";
    window.minSize = NSMakeSize(720, 420);
    window.releasedWhenClosed = NO;
    [window center];
    self.accountWindow = window;

    NSView *content = window.contentView;
    NSTextField *title = [self label:@"账号使用台账" size:20 weight:NSFontWeightBold frame:NSMakeRect(20, 452, 300, 28)];
    title.textColor = NSColor.labelColor;
    [content addSubview:title];
    self.accountSummaryLabel = [self label:@"" size:12 weight:NSFontWeightSemibold frame:NSMakeRect(20, 427, 760, 20)];
    self.accountSummaryLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.accountSummaryLabel];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 92, 780, 322)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    table.delegate = self; table.dataSource = self;
    table.usesAlternatingRowBackgroundColors = YES;
    table.rowHeight = 34;
    NSArray *columns = @[
        @{ @"id": @"account", @"title": @"账号", @"width": @170 },
        @{ @"id": @"status", @"title": @"登录状态", @"width": @100 },
        @{ @"id": @"session", @"title": @"5小时额度", @"width": @92 },
        @{ @"id": @"weekly", @"title": @"每周额度", @"width": @92 },
        @{ @"id": @"reset", @"title": @"刷新情况", @"width": @150 },
        @{ @"id": @"last", @"title": @"最后活动", @"width": @105 }
    ];
    for (NSDictionary *definition in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:definition[@"id"]];
        column.title = definition[@"title"];
        column.width = [definition[@"width"] doubleValue];
        column.minWidth = 80;
        [table addTableColumn:column];
    }
    scroll.documentView = table;
    self.accountTable = table;
    [content addSubview:scroll];

    NSTextField *note = [self label:@"只实时读取当前登录账号；其他账号显示最后一次登录快照。达到预计重置时间后会标记“待登录确认”。" size:11 weight:NSFontWeightRegular frame:NSMakeRect(20, 62, 780, 18)];
    note.textColor = NSColor.secondaryLabelColor;
    [content addSubview:note];

    NSButton *add = [NSButton buttonWithTitle:@"添加已知账号…" target:self action:@selector(addAccount:)];
    add.frame = NSMakeRect(20, 20, 124, 30); [content addSubview:add];
    NSButton *copy = [NSButton buttonWithTitle:@"复制所选邮箱" target:self action:@selector(copySelectedAccount:)];
    copy.frame = NSMakeRect(154, 20, 116, 30); [content addSubview:copy];
    NSButton *remove = [NSButton buttonWithTitle:@"删除所选记录" target:self action:@selector(removeSelectedAccount:)];
    remove.frame = NSMakeRect(280, 20, 116, 30); [content addSubview:remove];
    NSButton *refresh = [NSButton buttonWithTitle:@"刷新当前账号" target:self action:@selector(refresh:)];
    refresh.frame = NSMakeRect(664, 20, 136, 30); [content addSubview:refresh];
    [self rebuildAccountRows];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.accountRows.count; }

- (NSString *)dateText:(NSDate *)date {
    if (![date isKindOfClass:NSDate.class]) return @"从未";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

- (NSString *)remainingTextForRecord:(NSDictionary *)record key:(NSString *)key {
    NSNumber *remaining = [record[key] isKindOfClass:NSNumber.class] ? record[key] : nil;
    if (!remaining) return @"—";
    BOOL current = [record[@"email"] isEqual:self.currentAccountEmail];
    return [NSString stringWithFormat:current ? @"%@%%" : @"上次 %@%%", remaining];
}

- (NSString *)resetTextForRecord:(NSDictionary *)record {
    BOOL current = [record[@"email"] isEqual:self.currentAccountEmail];
    NSDate *sessionReset = [record[@"sessionResetsAt"] isKindOfClass:NSDate.class] ? record[@"sessionResetsAt"] : nil;
    NSDate *weeklyReset = [record[@"weeklyResetsAt"] isKindOfClass:NSDate.class] ? record[@"weeklyResetsAt"] : nil;
    if (!current && ((sessionReset && sessionReset.timeIntervalSinceNow <= 0) || (weeklyReset && weeklyReset.timeIntervalSinceNow <= 0))) {
        return @"预计已刷新 · 待确认";
    }
    NSMutableArray *parts = [NSMutableArray array];
    if (sessionReset) [parts addObject:[NSString stringWithFormat:@"5h %@", [self countdown:sessionReset]]];
    if (weeklyReset) [parts addObject:[NSString stringWithFormat:@"周 %@", [self countdown:weeklyReset]]];
    return parts.count ? [parts componentsJoinedByString:@" · "] : @"待登录获取";
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSDictionary *record = self.accountRows[row];
    NSString *identifier = tableColumn.identifier;
    NSString *value = @"—";
    if ([identifier isEqual:@"account"]) {
        NSString *plan = [record[@"plan"] isKindOfClass:NSString.class] ? record[@"plan"] : @"未识别";
        value = [NSString stringWithFormat:@"%@  ·  %@", [self maskedEmail:record[@"email"]], plan];
    } else if ([identifier isEqual:@"status"]) {
        if ([record[@"email"] isEqual:self.currentAccountEmail]) value = @"● 当前登录";
        else if ([record[@"lastSnapshotAt"] isKindOfClass:NSDate.class] && [record[@"lastSnapshotAt"] timeIntervalSinceNow] < -600) value = @"已登录 · 快照旧";
        else if (record[@"lastSeen"]) value = @"以前登录过";
        else value = @"尚未登录验证";
    } else if ([identifier isEqual:@"session"]) {
        value = [self remainingTextForRecord:record key:@"sessionRemaining"];
    } else if ([identifier isEqual:@"weekly"]) {
        value = [self remainingTextForRecord:record key:@"weeklyRemaining"];
    } else if ([identifier isEqual:@"reset"]) {
        value = [self resetTextForRecord:record];
    } else if ([identifier isEqual:@"last"]) {
        value = [self dateText:record[@"lastUsed"] ?: record[@"firstSeen"]];
    }
    NSTextField *field = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = identifier;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        field.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    }
    field.stringValue = value;
    field.textColor = ([identifier isEqual:@"status"] && [record[@"email"] isEqual:self.currentAccountEmail]) ? NSColor.systemGreenColor : NSColor.labelColor;
    return field;
}

- (void)addAccount:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"添加已知账号";
    alert.informativeText = @"只记录邮箱，不保存密码。首次在 Codex 登录后会自动补全套餐和额度。";
    [alert addButtonWithTitle:@"添加"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    input.placeholderString = @"name@example.com";
    alert.accessoryView = input;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *email = [self normalizedEmail:input.stringValue];
    if (![email containsString:@"@"] || [email hasPrefix:@"@"] || [email hasSuffix:@"@"]) {
        NSBeep(); return;
    }
    if (!self.accountHistory[email]) {
        self.accountHistory[email] = [@{ @"email": email, @"manualAddedAt": NSDate.date } mutableCopy];
        [self saveAccountHistory];
    }
    [self rebuildAccountRows];
}

- (void)copySelectedAccount:(id)sender {
    NSInteger row = self.accountTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.accountRows.count) { NSBeep(); return; }
    NSString *email = self.accountRows[row][@"email"];
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:email forType:NSPasteboardTypeString];
}

- (void)removeSelectedAccount:(id)sender {
    NSInteger row = self.accountTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.accountRows.count) { NSBeep(); return; }
    NSDictionary *record = self.accountRows[row];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"删除这条账号记录？";
    alert.informativeText = [NSString stringWithFormat:@"只会删除 %@ 的本地台账，不会删除 OpenAI 账号。", [self maskedEmail:record[@"email"]]];
    [alert addButtonWithTitle:@"删除记录"];
    [alert addButtonWithTitle:@"取消"];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self.accountHistory removeObjectForKey:record[@"email"]];
    [self saveAccountHistory];
    [self rebuildAccountRows];
}

- (void)showError:(NSString *)message {
    self.footerLabel.stringValue = [NSString stringWithFormat:@"连接异常 · %@", message ?: @"未知错误"];
    self.statusItem.button.title = @" !";
}

- (void)runSelfTest:(NSString *)mode {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([mode isEqual:@"account-window"]) {
            const NSInteger iterations = 100;
            for (NSInteger index = 0; index < iterations; index++) {
                [self showAccountManager:nil];
                [self.accountWindow close];
                NSCAssert(self.accountWindow != nil, @"Account window reference was lost");
            }
            fprintf(stdout, "CODEXQUOTA_SELF_TEST_PASS account-window iterations=%ld\n", (long)iterations);
            fflush(stdout);
            [NSApp terminate:nil];
            return;
        }
        if ([mode isEqual:@"project-stats"]) {
            dispatch_async(self.projectStatsQueue, ^{
                CFAbsoluteTime firstStart = CFAbsoluteTimeGetCurrent();
                NSArray *first = [self collectProjectStats];
                CFAbsoluteTime firstDuration = CFAbsoluteTimeGetCurrent() - firstStart;
                CFAbsoluteTime cachedStart = CFAbsoluteTimeGetCurrent();
                NSArray *cached = [self collectProjectStats];
                CFAbsoluteTime cachedDuration = CFAbsoluteTimeGetCurrent() - cachedStart;
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:cached options:0 error:nil];
                NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"[]";
                fprintf(stdout, "CODEXQUOTA_SELF_TEST_PASS project-stats first=%.3f cached=%.3f rows=%lu/%lu data=%s\n",
                        firstDuration, cachedDuration, (unsigned long)first.count, (unsigned long)cached.count, json.UTF8String);
                fflush(stdout);
                dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
            });
            return;
        }
        if ([mode isEqual:@"incremental-parser"]) {
            NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            NSString *path = [directory stringByAppendingPathComponent:@"fixture.jsonl"];
            NSError *error = nil;
            [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
            NSString *initial = @"{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/tmp/project-a\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":10}}}}\n";
            [initial writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
            NSDictionary *first = error ? nil : [self scanProjectFile:path fromOffset:0 cwd:nil tokens:0];
            NSFileHandle *writer = [NSFileHandle fileHandleForWritingAtPath:path];
            [writer seekToEndOfFile];
            NSData *partial = [@"{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":30}}}}" dataUsingEncoding:NSUTF8StringEncoding];
            [writer writeData:partial];
            [writer closeFile];
            NSDictionary *beforeNewline = [self scanProjectFile:path
                                                     fromOffset:[first[@"offset"] unsignedLongLongValue]
                                                             cwd:first[@"cwd"]
                                                          tokens:[first[@"tokens"] longLongValue]];
            writer = [NSFileHandle fileHandleForWritingAtPath:path];
            [writer seekToEndOfFile];
            [writer writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
            [writer closeFile];
            NSDictionary *afterNewline = [self scanProjectFile:path
                                                    fromOffset:[beforeNewline[@"offset"] unsignedLongLongValue]
                                                            cwd:beforeNewline[@"cwd"]
                                                         tokens:[beforeNewline[@"tokens"] longLongValue]];
            BOOL passed = [first[@"cwd"] isEqual:@"/tmp/project-a"] && [first[@"tokens"] longLongValue] == 10 &&
                          [beforeNewline[@"tokens"] longLongValue] == 10 && [afterNewline[@"tokens"] longLongValue] == 30;
            [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
            fprintf(passed ? stdout : stderr, "CODEXQUOTA_SELF_TEST_%s incremental-parser first=%lld partial=%lld appended=%lld\n",
                    passed ? "PASS" : "FAIL", [first[@"tokens"] longLongValue],
                    [beforeNewline[@"tokens"] longLongValue], [afterNewline[@"tokens"] longLongValue]);
            fflush(passed ? stdout : stderr);
            [NSApp terminate:nil];
            return;
        }
        fprintf(stderr, "CODEXQUOTA_SELF_TEST_FAIL unknown-mode=%s\n", mode.UTF8String);
        fflush(stderr);
        [NSApp terminate:nil];
    });
}

@end

static QuotaAppDelegate *gQuotaDelegate;

int main(__unused int argc, __unused const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        // NSApplication does not strongly retain its delegate. Keep it alive for
        // the entire process so toolbar/menu targets remain valid after launch.
        gQuotaDelegate = [QuotaAppDelegate new];
        app.delegate = gQuotaDelegate;
        [app run];
    }
    return 0;
}
