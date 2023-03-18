//
//  PriceMonitorView.m
//  iGlobalTrader
//
//  Created by 黃宇綸 on 2021/3/17.
//  Copyright © 2021 Capital. All rights reserved.
//

#import "PriceMonitorView.h"
#import "UISegmentedControl+OSMode.h"
#import "UITextField+OSMode.h"

#import "PriceMonitorRequest.h"
#import "SKProgress.h"
#import "SKUtility.h"
#import "SKUserConfig.h"
#import "SKTextFieldStepperView.h"

#import <SolaceLib/quote_message.h>
#import <SolaceLib/quote_warehouse.h>
#import <SolaceLib/requestCenter.h>
#import <Firebase/Firebase.h>

#import "SKRequestNotification.h"

@implementation PriceMonitorView
{
    Product *_product;
    NSMutableArray *_showListArray;
    NSMutableArray *_selectedArray;
    UIRefreshControl *_refreshControl;
    NSString *_pageNo;
    NSInteger _indexForDelete;
}

#pragma mark - API
- (id)initWithFrame:(CGRect)frame viewController:(UIViewController *)vCtrl navigationViewController:(UINavigationController *)navCtrl delegate:(id)delegate
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        _assignViewController = vCtrl;
        _monitorDelegate = delegate;
        requestCenter *request = [requestCenter getInstance];
        _pageNo = [request getPageNo];
    }
    return self;
}

#pragma mark - OverWrite
- (void)setFrame:(CGRect)Frame
{
    [super setFrame:Frame];
    
    if (CGRectIsEmpty(Frame))
    {
        UIView *xibView = [[[NSBundle mainBundle] loadNibNamed:@"PriceMonitorView"
        owner:self
        options:nil]
        objectAtIndex:0];
        //設定該xibView的Frame
        xibView.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
        xibView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        //將xibView加入
        
        [self addSubview: xibView];
        _showListArray = [[NSMutableArray alloc] init];
        _selectedArray = [[NSMutableArray alloc] init];
        [self customUI];
    }
}

- (void)setOrderObj:(Product *)obj
{
    if (_product)
    {
        requestCenter *request = [requestCenter getInstance];
        [request requestInitialQuote:@[_product] pageNo:_pageNo clear:YES];
        [request requestRealTimeQuote:@[_product] pageNo:_pageNo clear:YES];
        [self setQfCloseLabelColor:_product toLabel:_qfCloseLabel];
        [_stepperView setProduct:_product];
    }
}

// 全名, 供頁籤編輯時顯示
- (NSString *)getFullName
{
    return [SKUtility getViewNameWithProjectName:@"PriceMonitorView" isGetShortName:NO];
}

// 簡稱, 供頁籤顯示
- (NSString *)getSimpleName
{
    return [SKUtility getViewNameWithProjectName:@"PriceMonitorView" isGetShortName:YES];
}

// 專案名, 儲存設定用
- (NSString *)getProjectName
{
    return @"PriceMonitorView";
}

// 支援的市場(TS/TF/OF), 可複選
- (NSInteger)getMarket
{
    return [SKUtility getViewMarketWithProjectName:@"PriceMonitorView"];
}

// 商品選單顯示類型
- (FastSwitch_ProductSelectStyle)getProductSelectType
{
    return FastSwitch_ProductSelectStyle_Single;
}

//是否只顯示可下單商品
- (BOOL)showOnlyOrderProduct
{
    return NO;
}

// 是否顯示商品選單
- (BOOL)needSelect
{
    return NO;
}

// 是否顯示帳號選單
- (BOOL)needAccount
{
    return NO;
}

// 是否顯示未平倉(或庫存)
- (BOOL)needUnCover
{
    return NO;
}

- (void)active:(BOOL)active
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cleanOrder];
    requestCenter *center = [requestCenter getInstance];
    if (_pageNo == nil)
        _pageNo = [center getPageNo];
    [center releaseAllRequestData:_pageNo];
    
    if (active)
    {
        SKUserConfig *config = [SKUserConfig getInstance];
        BOOL haveSearch = [config isPriceMonitorCheck];
        if (!haveSearch)
        {
            NSLog(@"gotoSearch");
            SKRequestNotification *request = [[SKRequestNotification alloc] init];
            SKUserConfig *userConfig = [SKUserConfig getInstance];
            // 到價提示:AL
            [request checkSubScribe:[userConfig getLoginID] withMessageKind:@"AL" complete:^(NSString * _Nonnull status) {
                    if (status != nil && ([status isEqualToString:@"None"] || [status isEqualToString:@"001"]))
                    {
                        SKRequestNotification *change = [[SKRequestNotification alloc] init];
                        [change changeNotificationSetting:@"AL" complete:^{
                            if (change.success)
                            {
                                [config setPriceMonitorCheck];
                            }
                        }];
                    }
                    else if (status != nil && [status isEqualToString:@"000"])
                    {
                        [config setPriceMonitorCheck];
                    }
            }];
        }
        [FIRAnalytics logEventWithName:kFIREventScreenView parameters:@{kFIRParameterScreenName: @"到價提示", kFIRParameterScreenClass: @"PriceMonitorView"}];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNotifyQuoteConnected:) name:MSG_CONNECT object:nil];// 斷線處理
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNotifyQuote:) name:MSG_INITIALQUOTE object:NULL];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNotifyQuote:) name:MSG_REALTIMEQUOTE object:NULL];
        [self sendResearchRequest:0]; // 查詢全市場
    }
}

- (void)accountChange
{

}

#pragma  mark - settingViewAction
- (IBAction)addSetting:(id)sender // 按下新增按鈕
{
    _settingAlertView.hidden = NO;
}

- (IBAction)onSaveBtnClick:(id)sender // 按下新增視窗的確定按鈕
{
    BOOL checkOK = [self checkInput];
    
    
    if (checkOK)
    {
        [self sendAddingRequest];
        [self cleanOrder];
        _settingAlertView.hidden = YES;
    }
}

- (IBAction)onCancelSettingClick:(id)sender // 按下新增視窗的取消按鈕
{
    [self cleanOrder];
    _settingAlertView.hidden = YES;
}

- (IBAction)onDirectionChange:(id)sender
{
    
}

- (void)openCommodityProductList // 點選商品TextField
{
    [self onTitleClick:NO];
}

- (void)onTitleClick:(BOOL)isOpenSearchDirectly
{

    if (isOpenSearchDirectly) {
        SKProductSearchViewController *vc = [[SKProductSearchViewController alloc] initWithNibName:@"SKProductSearchViewController" bundle:nil];
        vc.delegate = self;
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [_assignViewController presentViewController:vc animated:true completion:nil];
    }else
    {
        SKProductSelectViewController * vc = [[SKProductSelectViewController alloc] initWithNibName:@"SKProductSelectViewController" bundle:nil];
        vc.delegate = self;
        [vc setType:productSelectType_PriceMonitor group:false];
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [_assignViewController presentViewController:vc animated:true completion:nil];
    }
}

- (void)onSelectedcallback:(NSObject*)product
{
    NSLog(@"%@", product);
    if ([product isKindOfClass:[Product class]])
    {
        if (_product != product)
        {
            [_stepperView setPriceString:@""];
            [_stepperView setPrice1String:@""];
        }
            
        _product = (Product *)product;
        
        if (_product)
        {
            [self setOrderObj:_product];
            
            _stockTextField.text = [NSString stringWithFormat:@"%@", _product.name];
        }
    }
}

- (void)onQfClosePriceClick // 點擊參考市價label(市價跟漲跌幅共用一個label 中間以空白隔開 市價在前漲跌幅在後)
{
    NSArray *labelText = [_qfCloseLabel.text componentsSeparatedByString:@" "];
    NSString *price = @"";
    if (labelText.count > 0)
    {
        price = labelText[0]; // 市價
    }
    
    if (price.length != 0 && ![price isEqualToString:@"--"]) //市價不為空白且不為"--"才可以點擊
    {
        NSArray *priceArr = [_qfCloseLabel.text componentsSeparatedByString:@" "];
        if (priceArr.count > 0)
        {
            if ([[priceArr objectAtIndex:0] containsString:@"'"])
            {
                NSString *tempPriceStr = [priceArr objectAtIndex:0];
                NSString *numerator = @"0";

                [SKUtility stringPriceHandle:&tempPriceStr numerator:&numerator denominator:_product.denominator];
                
                [_stepperView setPriceString:tempPriceStr];
                [_stepperView setProduct:_product];
                if (_product.denominator > 1)
                {
                    quote_warehouse *warehouse = [quote_warehouse getInstance];
                    NSNumberFormatter *format = [warehouse returnFormatter:_product.formatString];
                    NSString *showStr = [format stringFromNumber:[NSNumber numberWithDouble:[numerator doubleValue]]];
                    [_stepperView setPrice1String:showStr];
                }
            }
            else
                [_stepperView setPriceString:[priceArr objectAtIndex:0]];
        }
    }
}

#pragma  mark - listViewAction
- (IBAction)onMarketSegChange:(id)sender
{
    [SKProgress showProgress:self];
    if (_selectedArray == nil)
        _selectedArray = [[NSMutableArray alloc] init];
    else
        [_selectedArray removeAllObjects];
    
    switch (_marketSeg.selectedSegmentIndex)
    {
        case 0:
        {
            _selectedArray = [self getData:@"TS"];
        }
            break;
        case 1:
        {
            _selectedArray = [self getData:@"TF"];
        }
            break;
        case 2:
        {
            _selectedArray = [self getData:@"OF"];
        }
            break;
        default:
            break;
    }
    [_listTable reloadData];
    [SKProgress hideProgress];
}

- (NSMutableArray *)getData:(NSString *)type
{
    NSMutableArray *tsArray = [[NSMutableArray alloc]init];
    NSMutableArray *tfArray = [[NSMutableArray alloc]init];
    NSMutableArray *ofArray = [[NSMutableArray alloc]init];
    for (int i=0;i<_showListArray.count;i++)
    {
        NSString *market = [[_showListArray objectAtIndex:i] objectForKey:@"Market"];
        if ([market isEqualToString:@"TS"])
        {
            [tsArray addObject:[_showListArray objectAtIndex:i]];
        }
        else if ([market isEqualToString:@"TF"])
        {
            [tfArray addObject:[_showListArray objectAtIndex:i]];
        }
        else if ([market isEqualToString:@"OF"])
        {
            [ofArray addObject:[_showListArray objectAtIndex:i]];
        }
    }
    
    if ([type isEqualToString:@"TS"])
    {
        return tsArray;
    }
    else if ([type isEqualToString:@"TF"])
    {
        return tfArray;
    }
    else
        return ofArray;
}
#pragma  mark - maskViewAction
- (IBAction)onComfirmClick:(id)sender // 按下刪除視窗的確認按鈕
{
    [self sendDeleteRequest:_indexForDelete];
    [self hideMaskView:YES];
}

- (IBAction)onCancelClick:(id)sender // 按下刪除視窗的取消按鈕
{
    [self hideMaskView:YES];
}

#pragma mark - interFace
- (void)customUI
{
    [_directionSeg checkDarkMode3];
    [_marketSeg checkDarkMode3];
    UITapGestureRecognizer *qfClosePriceTap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(onQfClosePriceClick)];
    [_qfCloseLabel addGestureRecognizer:qfClosePriceTap];
    _qfCloseLabel.userInteractionEnabled = YES;
    
    UITapGestureRecognizer *openCommodityTap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(openCommodityProductList)];
    [_stockTextField addGestureRecognizer:openCommodityTap];
    _stockTextField.font = [UIFont fontWithName:@"HelveticaNeue" size:16];
    _stockTextField.backgroundColor = [UIColor whiteColor];
    _stockTextField.textColor = [UIColor blackColor];
    _stockTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"請選擇商品" attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:192.0/255.0 green:192.0/255.0 blue:192.0/255.0 alpha:1.0], NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue-Bold" size:17]}];
        
    _qfCloseLabel.text = @"--";
    _qfCloseLabel.textColor = [UIColor whiteColor];
    // 新增按鈕
    _addSettingButton.layer.shadowOffset = CGSizeMake(2, 2);
    _addSettingButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    _addSettingButton.layer.shadowRadius = 5;
    _addSettingButton.layer.shadowOpacity = 1.0;
    _addSettingButton.layer.cornerRadius = 5;
    _addSettingButton.layer.borderWidth = 1.5;
    _addSettingButton.layer.borderColor = [[UIColor yellowColor] CGColor];
    _addSettingButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16];
    [_addSettingButton setTitleColor:[UIColor yellowColor] forState:UIControlStateNormal];
    
    _settingAlertView.frame = CGRectMake(0.0, 0.0, [[UIScreen mainScreen] bounds].size.width, [[UIScreen mainScreen] bounds].size.height - 130);
    _settingView.layer.borderColor = [[UIColor whiteColor] CGColor];
    _settingView.layer.borderWidth = 1.5;
    _settingView.layer.cornerRadius = 5.0;
    _settingAlertView.hidden = YES;
    [_listView addSubview:_settingAlertView];
    _stepperView.frame = CGRectMake(0, 0, _settingAlertView.frame.size.width - 60, 35);
    _stepperView.delegate = self;

    _directionSeg.selectedSegmentIndex = -1;
    
    _listTable.dataSource = self;
    _listTable.delegate = self;
    //註冊GroupsTableViewcell
    [_listTable registerNib:[UINib nibWithNibName:@"listCellTableViewCell" bundle:nil] forCellReuseIdentifier:@"Infomation"];
    _listTable.rowHeight = UITableViewAutomaticDimension;
    _listTable.estimatedRowHeight = 120;

    // 刷新UI
    _refreshControl = [[UIRefreshControl alloc] init];
    
    //設置refreshControl的屬性
    _refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"刷新中..." attributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:20], NSForegroundColorAttributeName:[UIColor whiteColor]}];
    _refreshControl.tintColor = [UIColor whiteColor];
    [_refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    _listTable.refreshControl = _refreshControl;
    
    
    _comfirmView.layer.borderWidth = 1.5;
    _comfirmView.layer.borderColor = [[UIColor whiteColor] CGColor];
    _comfirmView.layer.cornerRadius = 5.0;
    
    [_cancelBtn setBackgroundImage:[UIImage imageNamed:@"button-function.png"] forState:UIControlStateNormal];
    _cancelBtn.clipsToBounds = YES;
    _cancelBtn.layer.cornerRadius = 2.0;
    
    _comfirmBtn.clipsToBounds = YES;
    _comfirmBtn.layer.cornerRadius = 2.0;
    
    [[[UIApplication sharedApplication]keyWindow]addSubview:_maskView];
    _maskView.frame = CGRectMake(0.0, 0.0, [[UIScreen mainScreen] bounds].size.width, [[UIScreen mainScreen] bounds].size.height);
    _maskView.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.8];
    _maskView.hidden = YES;
}

#pragma  mark - function

- (BOOL)checkInput
{
    BOOL checkOK = NO;
    NSString *msg = @"";
    NSInteger productMarket = [self getMarket:_product];
        
    if (_stockTextField.text.length == 0)
    {
        msg = @"尚未選擇商品";
    }
    else if ([_stepperView getPriceString].length == 0)
    {
        msg = @"觸發價不可為空白";
    }
    else if (_directionSeg.selectedSegmentIndex == -1)
    {
        msg = @"請選擇觸發方向";
    }
    else if (productMarket == marketNone)
    {
        msg = @"查無此商品";
    }
    else
    {
        checkOK = YES;
    }
    if (msg.length > 0)
        [self showAlertWithTitle:msg cancelBtn:NO complete:nil];
    
    return checkOK;
}

- (void)showAlertWithTitle:(NSString *)title cancelBtn:(BOOL)cancelBtn complete:(void(^)())complete
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"訊息" message:title preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"確定"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action)
                                    {
                                        if (complete)
                                            complete();
                                    }];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction * action)
                                    {

                                    }];
    [alertController addAction:defaultAction];
    if (cancelBtn)
        [alertController addAction:cancelAction];

    [_assignViewController presentViewController:alertController animated:YES completion:nil];
}

- (void)sendAddingRequest // 新增request
{
    quote_warehouse *quote = [quote_warehouse getInstance];
    SKExchange *exchange = [quote getExchange:_product.exchangeIndex market:semNone];
    // 市場別
    int marketType = 0;
    if (exchange.type == semStock)
    {
        marketType = 1; // TS
    }
    else
    {
        if (exchange.isOversea)
        {
            marketType = 4; // OF
        }
        else
        {
            marketType = 3; // TF
        }
    }
    
    //觸發方向
    NSMutableDictionary *settingInfo = [[NSMutableDictionary alloc]init];
    int direction = 1;
    if (_directionSeg.selectedSegmentIndex == 1)
        direction = 2;
    
    [settingInfo setObject:[NSNumber numberWithInt:direction] forKey:@"PriceDirection"];
    [settingInfo setObject:exchange.no forKey:@"ExchangeID"]; // 交易所代碼 ex:ES、TSE
    [settingInfo setObject:_product.fullNo forKey:@"Commodity"]; // 商品代碼
    
    if (_product.denominator > 1)
    {
        NSString *triggerPrice = [_stepperView getTextFieldString];
        NSString *triggerPriceM = [_stepperView getTextField1String];
        double triggerPriceD = _product.denominator;
    
        [settingInfo setObject:[NSNumber numberWithDouble:[triggerPrice doubleValue]] forKey:@"TriggerPrice"];
        [settingInfo setObject:[NSNumber numberWithDouble:[triggerPriceM doubleValue]] forKey:@"TriggerPriceM"];
        [settingInfo setObject:[NSNumber numberWithDouble:triggerPriceD] forKey:@"TriggerPriceD"];
        
        if ([triggerPrice containsString:@"-"] && [triggerPrice intValue] == 0)
        {
            // -0要將負號放到分子，才能正確下單
            triggerPrice = [triggerPrice stringByReplacingOccurrencesOfString:@"-" withString:@""];
            [settingInfo setObject:[NSNumber numberWithDouble:[triggerPrice doubleValue]] forKey:@"TriggerPrice"]; // 觸發價
            triggerPriceM = [NSString stringWithFormat:@"-%@", triggerPriceM];
            [settingInfo setObject:[NSNumber numberWithDouble:[triggerPriceM doubleValue]] forKey:@"TriggerPriceM"]; // 觸發價分子
        }
    }
    else
    {
        double triggerPrice = [[_stepperView getTextFieldString] doubleValue];
        [settingInfo setObject:[NSNumber numberWithDouble:triggerPrice] forKey:@"TriggerPrice"];
        [settingInfo setObject:[NSNumber numberWithDouble:0] forKey:@"TriggerPriceM"];
        [settingInfo setObject:[NSNumber numberWithDouble:0] forKey:@"TriggerPriceD"];
    }
    
    
    
    [SKProgress showProgress:self message:@"儲存設定中..."];
    PriceMonitorRequest *request = [[PriceMonitorRequest alloc] init];
    [request requestWithFunc:1 withMarketType:marketType withSettingDic:settingInfo complete:^
    {
        if (request.success == NO)
        {
            if (request.msg.length > 0)
            {
                [self showAlertWithTitle:request.msg cancelBtn:NO complete:nil];
            }
        }
        else
        {
            if (request.msg.length > 0)
            {
                [self showAlertWithTitle:request.msg cancelBtn:NO complete:^{
                    [self sendResearchRequest:0];
                }];
            }
        }
        [SKProgress hideProgress];
    }];
}

- (void)sendResearchRequest:(int)marketType // 查詢request
{
    [SKProgress showProgress:self message:@"載入中..."];
    PriceMonitorRequest *request = [[PriceMonitorRequest alloc] init];
    [request requestSettingListWithMarketType:marketType complete:^{
        NSLog(@"research done");
        
        if (request.listResult != nil || request.listResult.count > 0)
        {
            _showListArray = [[NSMutableArray alloc] initWithArray:request.listResult];
            [self requestShowListQuote];
            [self onMarketSegChange:_marketSeg];
            [self sortList];
            [_listTable reloadData];
        }
        [SKProgress hideProgress];
    }];
}

- (void)sendDeleteRequest:(NSInteger)index // 刪除request
{
    if (_selectedArray.count <= index)
        return;
    [SKProgress showProgress:self message:@"刪除中..."];
    
    NSMutableDictionary *deleteItem = [_selectedArray objectAtIndex:index];
    NSString *market = [deleteItem objectForKey:@"Market"];
    
    int marketType = 0;
    
    if ([market isEqualToString:@"TS"])
        marketType = 1;
    else if ([market isEqualToString:@"TF"])
        marketType = 3;
    else if ([market isEqualToString:@"OF"])
        marketType = 4;
    
    PriceMonitorRequest *request = [[PriceMonitorRequest alloc] init];
    [request requestWithFunc:2 withMarketType:marketType withSettingDic:deleteItem complete:^{
        if (request.success == NO)
        {
            if (request.msg.length > 0)
            {
                [self showAlertWithTitle:request.msg cancelBtn:NO complete:nil];
            }
        }
        else
        {
            if (request.msg.length > 0)
            {
                [self showAlertWithTitle:request.msg cancelBtn:NO complete:^{
                    [self sendResearchRequest:0];
                }];
            }
        }
        [SKProgress hideProgress];
    }];
}

- (void)sortList // 排列(已觸發的設定排在最前面)
{
    NSMutableArray *triggerArr = [[NSMutableArray alloc] init];
    NSMutableArray *otherArr = [[NSMutableArray alloc] init];
    for (int i=0; i<_selectedArray.count; i++)
    {
        NSString *status = [self getStatusStr:i];
        
        if ([status isEqualToString:@"觸發"])
        {
            [triggerArr addObject:[_selectedArray objectAtIndex:i]];
        }
        else
        {
            [otherArr addObject:[_selectedArray objectAtIndex:i]];
        }
    }
    
    [_selectedArray removeAllObjects];
    [_selectedArray addObjectsFromArray:triggerArr];
    [_selectedArray addObjectsFromArray:otherArr];
}

- (void)hideMaskView:(BOOL)show
{
    if (!show)
        _maskView.hidden = NO;
    else
        _maskView.hidden = YES;
}

- (void)cleanOrder
{
    _product = nil;
    _stockTextField.text = @"";
    [_stepperView setPriceString:@""];
    [_stepperView setPrice1String:@""];
    _directionSeg.selectedSegmentIndex = -1;
    _qfCloseLabel.text = @"--";
    _qfCloseLabel.textColor = [UIColor whiteColor];
}

- (void)setQfCloseLabelColor:(Product *)product toLabel:(UILabel *)label
{
    quote_warehouse *quoteInfo = [quote_warehouse getInstance];
    SKQuoteInfo *getQuoteInfo = [quoteInfo getQuoteInfo:product];
    if (getQuoteInfo)
    {
        label.text = [NSString stringWithFormat:@"%@ %@", [getQuoteInfo getFieldToString:qfClosePrice], [getQuoteInfo getFieldToString:qfRaiseOrFallInPrice]];
        NSMutableAttributedString * attriStr = [[NSMutableAttributedString alloc]initWithString:label.text];
        NSArray *infoArr = [label.text componentsSeparatedByString:@" "];
        if (infoArr.count > 1)
        {
            NSRange range1 = [label.text rangeOfString:infoArr[0]];
            NSRange range2 = [label.text rangeOfString:infoArr[1]];
            
            [attriStr addAttributes:@{NSForegroundColorAttributeName:[getQuoteInfo getFieldTextColor:qfClosePrice], NSBackgroundColorAttributeName:[getQuoteInfo getFieldBackgroundColor:qfClosePrice]} range:range1];
            [attriStr addAttributes:@{NSForegroundColorAttributeName:[getQuoteInfo getFieldTextColor:qfRaiseOrFallInPrice]} range:range2];

            label.attributedText = attriStr;
        }
        else
            label.textColor = [UIColor whiteColor];
    }
    else
    {
        label.text = @"--";
        label.textColor = [UIColor whiteColor];
    }
}

// 取得所有有設定到價提示的商品
- (void)requestShowListQuote
{
    NSMutableArray *requestQuoteArray = [[NSMutableArray alloc] init];
    for (int i = 0; i < _showListArray.count; i++)
    {
        Product *quoteProduct = [self getProduct:i withArr:_showListArray];
        if (quoteProduct != nil)
        {
            [requestQuoteArray addObject:quoteProduct];
        }
        
    }
    requestCenter *request = [requestCenter getInstance];
    [request requestInitialQuote:requestQuoteArray pageNo:_pageNo clear:YES];
    [request requestRealTimeQuote:requestQuoteArray pageNo:_pageNo clear:YES];
}

#pragma mark - notify
- (void)onNotifyQuote:(NSNotification *)notification
{
    if ([notification.name isEqualToString:MSG_REALTIMEQUOTE] || [notification.name isEqualToString:MSG_INITIALQUOTE])
    {
        if (_settingAlertView.isHidden == YES)
        {
            if (![_listTable isEditing])
                [_listTable reloadData];
        }
        else
        {
            NSDictionary *userInfo = notification.userInfo;
            Product *product = (Product*)userInfo[@"quoteCommodity"];
            Product *checkProduct = _product;
            
            if ([[product fullNo] isEqualToString:[checkProduct fullNo]])
            {
                [self setQfCloseLabelColor:_product toLabel:_qfCloseLabel];

                NSLog(@"%@", _qfCloseLabel.text);
                NSLog(@"get quote");
            }
        }
    }
}

- (void)onNotifyQuoteConnected:(NSNotification *)notification
{
    if (_product)
    {
        [self setOrderObj:_product];
    }
}


#pragma mark -  stepperTextField delegate
- (void)textFieldIsSelect:(SKTextFieldStepperView *)textFieldStepperView
{
    [_stepperView showBorder:YES];
}

- (UIViewController *)getViewController
{
    return  _assignViewController;
}

#pragma mark - cell delegate

- (void)tradeBtnPressed:(NSInteger)index
{
    Product *tradeStock = [self getProduct:index withArr:_selectedArray];
    if (!tradeStock)
    {
        [KGStatusBar showErrorWithStatus:@"查無此商品" showType:ShowType_Android];
    }
    else
        [_monitorDelegate PriceMonitorjumpToLuminalSpeedWithData:tradeStock];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    if (_selectedArray.count == 0)
        return 0;
    else
        return _selectedArray.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    listCellTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Infomation" forIndexPath:indexPath];
    [cell setIndex:indexPath.row];
    cell.delegate = self;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    //stockName
    cell.stockName.textColor = [UIColor whiteColor];
    Product *showProduct = [self getProduct:indexPath.row withArr:_selectedArray];

    if (showProduct != nil)
    {
        if ([showProduct isKindOfClass:[Stock class]])
        {
            cell.stockName.text = [NSString stringWithFormat:@"%@(%@)", showProduct.name, showProduct.fullNo];
        }
        else
            cell.stockName.text = [NSString stringWithFormat:@"%@", showProduct.name];
    }
    else
        cell.stockName.text = [[_selectedArray objectAtIndex:indexPath.row] objectForKey:@"Commondity"];
    
    //triggerPrice
    cell.direction.textColor = [UIColor whiteColor];
    cell.direction.text = [NSString stringWithFormat:@"( %@ )", [self getTriggerPrice:indexPath.row]];
    
    //status
    cell.status.text = [self getStatusStr:indexPath.row];
    if ([cell.status.text isEqualToString:@"觸發"])
        cell.status.textColor = [UIColor yellowColor];
    else
        cell.status.textColor = [UIColor whiteColor];
    
    //time
    if ([cell.status.text isEqualToString:@"洗價中"])
    {
        quote_warehouse *quote = [quote_warehouse getInstance];
        SKQuoteInfo *getQuoteInfo = [quote getQuoteInfo:showProduct];
        if (getQuoteInfo)
        {
            cell.time.text = [NSString stringWithFormat:@"%@ %@", [getQuoteInfo getFieldToString:qfClosePrice], [getQuoteInfo getFieldToString:qfRaiseOrFallInPrice]];
        }
        else
        {
            cell.time.text = @"-- --";
        }
        
        [self setQfCloseLabelColor:showProduct toLabel:cell.time];
    }
    else
    {
        cell.time.textColor = [UIColor whiteColor];
        cell.time.text = [self getTime:indexPath.row];
    }
    
    
    return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    EdgeLabel *caution = [[EdgeLabel alloc] init];
    caution.frame = CGRectMake(0.0, 0.0, [UIScreen mainScreen].bounds.size.width - 55, 30);
    caution.font = [UIFont fontWithName:@"HelveticaNeue" size:18];
    caution.text = @"左滑可取消到價通知設定";
    caution.textColor = [UIColor whiteColor];
    caution.textInsets = UIEdgeInsetsMake(0.f, 20.0f, 0.f, 0.f);
    
    UIButton *addBtn = [[UIButton alloc] init];
    addBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 55, 1.5, 50, 27);
    [addBtn setTitle:@"新增" forState:UIControlStateNormal];
    [addBtn setTitleColor:[UIColor yellowColor] forState:UIControlStateNormal];
//    [addBtn addTarget:self action:@selector(addNewSetting) forControlEvents:UIControlEventTouchUpInside];
    addBtn.layer.shadowOffset = CGSizeMake(2, 2);
    addBtn.layer.shadowColor = [[UIColor blackColor] CGColor];
    addBtn.layer.shadowRadius = 5;
    addBtn.layer.shadowOpacity = 1.0;
    addBtn.layer.cornerRadius = 5;
    addBtn.layer.borderWidth = 1.5;
    addBtn.layer.borderColor = [[UIColor yellowColor] CGColor];
    addBtn.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16];
    addBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    
    EdgeLabel *itemLabel = [[EdgeLabel alloc] init];
    itemLabel.frame = CGRectMake(0.0, 30.0, [UIScreen mainScreen].bounds.size.width/2, 30);
    itemLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:18];
    itemLabel.text = @"商品名稱";
    itemLabel.textColor = [UIColor whiteColor];
    itemLabel.textInsets = UIEdgeInsetsMake(0.f, 20.0f, 0.f, 0.f);
    
    EdgeLabel *statusLabel = [[EdgeLabel alloc] init];
    statusLabel.frame = CGRectMake([UIScreen mainScreen].bounds.size.width/2, 30.0, [UIScreen mainScreen].bounds.size.width/2, 30);
    statusLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:18];
    statusLabel.text = @"觸發狀態";
    statusLabel.textColor = [UIColor whiteColor];
    statusLabel.textAlignment = NSTextAlignmentRight;
    statusLabel.textInsets = UIEdgeInsetsMake(0.f, 0.f, 0.f, [UIScreen mainScreen].bounds.size.width/2 - 105);
    
    EdgeLabel *triggerPriceLabel = [[EdgeLabel alloc] init];
    triggerPriceLabel.frame = CGRectMake(0.0, 60.0, [UIScreen mainScreen].bounds.size.width/2, 30);
    triggerPriceLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:18];
    triggerPriceLabel.text = @"觸價條件";
    triggerPriceLabel.textColor = [UIColor whiteColor];
    triggerPriceLabel.textInsets = UIEdgeInsetsMake(0.f, 20.0f, 0.f, 0.f);

    EdgeLabel *triggerTimeLabel = [[EdgeLabel alloc] init];
    triggerTimeLabel.frame = CGRectMake([UIScreen mainScreen].bounds.size.width/2, 60.0, [UIScreen mainScreen].bounds.size.width/2, 30);
    triggerTimeLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:18];
    triggerTimeLabel.text = @"觸發時間";
    triggerTimeLabel.textColor = [UIColor whiteColor];
    triggerTimeLabel.textAlignment = NSTextAlignmentRight;
    triggerTimeLabel.textInsets = UIEdgeInsetsMake(0.f, 0.f, 0.f, [UIScreen mainScreen].bounds.size.width/2 - 105);
    
    UIView *headerView = [[UIView alloc] init];
    headerView.backgroundColor = [UIColor colorWithRed:51.0/255.0 green:51.0/255.0 blue:51.0/255.0 alpha:1.0];
    [headerView addSubview:caution];
    [headerView addSubview:addBtn];
    [headerView addSubview:itemLabel];
    [headerView addSubview:statusLabel];
    [headerView addSubview:triggerPriceLabel];
    [headerView addSubview:triggerTimeLabel];
    return headerView;
}

#pragma mark-返回編輯模式
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

-(BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= 0)
    {
        NSString *status = [self getStatusStr:indexPath.row];
        if ([status isEqualToString:@"洗價中"])
            return YES;
        else
            return NO;
    }
    else
        return NO;
}

#pragma mark-左滑刪除
-(void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
        if (editingStyle == UITableViewCellEditingStyleDelete)
        {
            Product *showProduct = [self getProduct:indexPath.row withArr:_selectedArray];

            _cancelMarketTypeLabel.text = [_marketSeg titleForSegmentAtIndex:_marketSeg.selectedSegmentIndex];
            if (showProduct != nil)
            {
                if ([showProduct isKindOfClass:[Stock class]])
                {
                    _cancelStockNameLabel.text = [NSString stringWithFormat:@"%@(%@)", showProduct.name, showProduct.fullNo];
                }
                else
                    _cancelStockNameLabel.text = [NSString stringWithFormat:@"%@", showProduct.name];
                
            }
            else
                _cancelStockNameLabel.text = [[_selectedArray objectAtIndex:indexPath.row] objectForKey:@"Commondity"];
            _cancelConditionLabel.text = [self getTriggerPrice:indexPath.row];
            _indexForDelete = indexPath.row;
            
            _comfirmViewTitle.text = @"請問是否取消到價通知";
            _cancelComfirmView.hidden = NO;
            [self hideMaskView:NO];
        }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
}

#pragma  mark - get info
- (Product *)getProduct:(NSInteger)indexPathRow withArr:(NSMutableArray *)array
{
    NSString *stockNo = [[array objectAtIndex:indexPathRow] objectForKey:@"Commondity"];
    NSString *exchangeNo = [[array objectAtIndex:indexPathRow] objectForKey:@"ExchangeID"];
    
    quote_warehouse *quote = [quote_warehouse getInstance];
    SKExchange *exchange = [quote getExchangeByNo:exchangeNo market:semNone];
    Product *showProduct = [quote getProduct:exchange.index stockNo:stockNo];
    
    return  showProduct;
}

- (NSString *)getTriggerPrice:(NSInteger)indexPathRow
{
    NSString *msg;
    if (indexPathRow < _selectedArray.count)
    {
        int direction = [[[_selectedArray objectAtIndex:indexPathRow]objectForKey:@"PriceDirection"] intValue];
        NSString *price = [NSString stringWithFormat:@"%@", [[_selectedArray objectAtIndex:indexPathRow]objectForKey:@"TriggerPrice"]];
        NSString *triggerM = [NSString stringWithFormat:@"%@", [[_selectedArray objectAtIndex:indexPathRow]objectForKey:@"TriggerPriceM"]];
        NSString *triggerD = [NSString stringWithFormat:@"%@", [[_selectedArray objectAtIndex:indexPathRow]objectForKey:@"TriggerPriceD"]];
    
        NSString *directionStr = @"";
        if (direction == 1)
        {
            directionStr = @">=";
        }
        else
        {
            directionStr = @"<=";
        }
        Product *product = [self getProduct:indexPathRow withArr:_selectedArray];
        NSString *priceStr = [SKUtility getPrice:[price doubleValue] withPriceD:[triggerD doubleValue] withPriceM:[triggerM intValue] withProduct:product];
        msg = [NSString stringWithFormat:@"%@ %@", directionStr, priceStr];
    }
    else
        msg = @"--";
    
    return msg;
}

- (NSString *)getStatusStr:(NSInteger)indexPathRow
{
    NSString *statusStr;
    if (indexPathRow < _selectedArray.count)
    {
        int status = [[[_selectedArray objectAtIndex:indexPathRow]objectForKey:@"Status"] intValue];
        
        switch(status)
        {
            case 1:
                statusStr = @"收單";
                break;
            case 2:
                statusStr = @"洗價中";
                break;
            case 3:
                statusStr = @"觸發";
                break;
            case 4:
                statusStr = @"刪單";
                break;
            default:
                break;
        }
    }
    else
        statusStr = @"--";
    return statusStr;
}

- (NSString *)getTime:(NSInteger)indexPathRow
{
    NSString *timeStr;
    if (indexPathRow < _selectedArray.count)
    {
        timeStr = [[_selectedArray objectAtIndex:indexPathRow]objectForKey:@"TriggerTime"];
        NSString *status = [self getStatusStr:indexPathRow];
        NSArray *timeArr = [timeStr componentsSeparatedByString:@" "];
        if (timeArr.count > 2 && [status isEqualToString:@"觸發"])
        {
            timeStr = [NSString stringWithFormat:@"%@ %@\n%@", [timeArr objectAtIndex:0], [timeArr objectAtIndex:1], [timeArr objectAtIndex:2]];
        }
        else
            timeStr = @"--:--:--";
    }
    else
        timeStr = @"--:--:--";

    return timeStr;
}

- (NSInteger)getMarket:(Product *)product
{
    NSInteger productMarket = marketNone;
    switch ([[quote_warehouse getInstance] getProductMarket:product])
    {
        case semStock:
            productMarket = marketTS;
            break;
        case semFuture:
            {
                SKExchange *exchangeInfo = [[quote_warehouse getInstance] getExchange:product.exchangeIndex market:semFuture];
                if (exchangeInfo.isOversea)
                {
                    productMarket = marketOF;
                }
                else
                    productMarket = marketTF;
            }
            break;
        case semOption:
            {
                SKExchange *exchangeInfo = [[quote_warehouse getInstance] getExchange:product.exchangeIndex market:semOption];
                if (exchangeInfo.isOversea)
                {
                    productMarket = marketOO;
                }
                else
                    productMarket = marketTO;
            }
            break;
        default:
            break;
    }
    return productMarket;
}

/*- (NSString*)getFormatStringPrice:(NSString*)price numerator:(NSString*)numerator denominator:(NSString*)denominator withIndex:(NSInteger)index
{
    
    Product *product = [self getProduct:index withArr:_selectedArray];
    
    int df = [denominator intValue];
    if (df == 0)
        df = 1;
    
    if (product)
    {
        if ([product isKindOfClass:[SKCommodity class]])
        {
            SKCommodity* cmdy = (SKCommodity*)product;
            double pf = [price floatValue];
            double nf = [numerator floatValue];
            if ([price containsString:@"-"])
                return [cmdy priceToString:pf - (nf / df) format:NULL];
            else
                return [cmdy priceToString:pf + (nf / df) format:NULL];
        }
        else
        {
            double pf = [price floatValue];
            double nf = [numerator floatValue];
            
            return [product priceToString:pf + (nf / df) format:NULL];
        }
    }
    else
    {
        return [self setStringPrice:price numerator:numerator denominator:denominator];
    }
}

//如果沒有commodity的處理方式
- (NSString*) setStringPrice:(NSString*)price numerator:(NSString*)numerator denominator:(NSString*)denominator
{
    int dDenom = [denominator intValue];
    if (dDenom == 0 || dDenom == 1)
    {
        return price;
    }
    else
    {
        int pf = [price floatValue];
        double nf = [numerator floatValue];
        
        return [NSString stringWithFormat:@"%d %f/%@", pf, nf, denominator];
    }
}*/

#pragma mark - 表格下拉刷新
- (void)handleRefresh:(id)paramSender
{
    // 模擬兩秒後刷新數據
    int64_t delayInSeconds = 1.0f;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        //停止刷新
        [_refreshControl endRefreshing];
        [self sendResearchRequest:0];
    });
}

#pragma  mark - SKProductSelectDelegate
- (void)getSelectObj:(SelectObj*)obj
{
    _qfCloseLabel.text = @"--";
    _qfCloseLabel.textColor = [UIColor whiteColor];
    if ([obj.data[obj.index] isKindOfClass:[Product class]])
    {
        [self onSelectedcallback:obj.data[obj.index]];
    }
}

- (void)showMask
{
    
}

- (void)hideMask
{
    
}

- (void)changeToSearchVC
{
    SKProductSearchViewController *vc = [[SKProductSearchViewController alloc] initWithNibName:@"SKProductSearchViewController" bundle:nil];
    vc.delegate = self;
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [_assignViewController presentViewController:vc animated:false completion:nil];
}

#pragma  mark - SKProductSearchViewControllerDelegate
- (void)getSearchObj:(Product*)searchObj
{
    _qfCloseLabel.text = @"--";
    _qfCloseLabel.textColor = [UIColor whiteColor];
    [self onSelectedcallback:searchObj];
}

@end
