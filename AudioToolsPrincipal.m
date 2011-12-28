#import "AudioToolsPrincipal.h"

#import "AudioDeviceInfoPatch.h"
#import "AudioFileInfoPatch.h"
#import "AudioFilePlayerPatch.h"
#import "AudioInputPatch.h"
#import "AudioFileInputPatch.h"
#import "AudioSystemBeepPatch.h"
#import "AudioEmbeddedFilePlayerPatch.h"
#import "AudioEmbeddedFileInputPatch.h"

@implementation AudioToolsPlugin
+ (void)registerNodesWithManager:(GFNodeManager*)manager
{
	KIRegisterPatch(AudioDeviceInfoPatch);
	KIRegisterPatch(AudioFileInfoPatch);
	KIRegisterPatch(AudioFilePlayerPatch);
	KIRegisterPatch(AudioInputPatch);
	KIRegisterPatch(AudioFileInputPatch);
	KIRegisterPatch(AudioSystemBeepPatch);
	KIRegisterPatch(AudioEmbeddedFilePlayerPatch);
	KIRegisterPatch(AudioEmbeddedFileInputPatch);
}
@end
