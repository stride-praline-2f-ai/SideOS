#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSDictionary * _Nullable SideOSSigningSnapshot(void);
int32_t SideOSRawKeychainStatus(NSDictionary *query);
BOOL SideOSRawKeychainControl(NSString *account);
NS_ASSUME_NONNULL_END
