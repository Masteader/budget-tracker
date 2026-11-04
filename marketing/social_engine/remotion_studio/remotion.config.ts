import {Config} from '@remotion/cli/config';

// The Batch G wrapper passes the per-reel bitrate. These are the fixed parts of spec Section 8.6.
Config.setCodec('h264');
Config.setAudioCodec('aac');
Config.setPixelFormat('yuv420p');
Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
