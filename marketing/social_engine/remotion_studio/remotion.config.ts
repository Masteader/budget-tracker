import {Config} from '@remotion/cli/config';

// The Batch G wrapper passes the per-reel bitrate. These are the fixed parts of spec Section 8.6.
Config.setCodec('h264');
Config.setAudioCodec('aac');
Config.setPixelFormat('yuv420p');
Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
// A phone recording is about 8 MB a frame once decoded. On a busy laptop the default cache, half of
// what memory is free, can run so short that the compositor fails with "No frame found".
Config.setOffthreadVideoCacheSizeInBytes(1_500_000_000);
