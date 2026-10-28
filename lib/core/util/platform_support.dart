import 'dart:io';

bool get isHarmony => Platform.operatingSystem == 'ohos';

bool get isMobileLike => Platform.isAndroid || Platform.isIOS || isHarmony;
