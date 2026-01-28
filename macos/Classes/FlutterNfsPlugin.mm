#import "FlutterNfsPlugin.h"
#include "nfs_bridge.h"

@implementation FlutterNfsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  // Dummy reference to force linking of bridge_nfs_init_context
  // The volatile pointer prevents the compiler from optimizing away the reference
  volatile auto force_link = &bridge_nfs_init_context;
  (void)force_link;
}
@end
