
#import <UIKit/UIKit.h>

@interface CommonWebViewController : UIViewController

@property (nonatomic, copy) NSString *URLString;

@property (nonatomic, assign) BOOL canPullDownToRefresh;

@end
