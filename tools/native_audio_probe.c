#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>
#include <CoreAudio/CoreAudio.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#define DYLD_INTERPOSE(_replacement, _replacee)                                      \
  __attribute__((used)) static struct {                                             \
    const void* replacement;                                                        \
    const void* replacee;                                                           \
  } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {       \
      (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee}

#ifndef SPOTIFY_NATIVE_AUDIO_PROBE_MODE
#define SPOTIFY_NATIVE_AUDIO_PROBE_MODE "unknown"
#endif

static FILE* g_log_file = NULL;
static pthread_mutex_t g_log_lock = PTHREAD_MUTEX_INITIALIZER;

static OSStatus probe_AudioComponentInstanceNew(AudioComponent component,
                                                AudioComponentInstance* instance);
static OSStatus probe_AudioComponentInstanceDispose(AudioComponentInstance instance);
static OSStatus probe_AudioUnitSetProperty(AudioUnit unit,
                                           AudioUnitPropertyID property_id,
                                           AudioUnitScope scope,
                                           AudioUnitElement element,
                                           const void* data,
                                           UInt32 data_size);
static OSStatus probe_AudioUnitInitialize(AudioUnit unit);
static OSStatus probe_AudioUnitUninitialize(AudioUnit unit);
static OSStatus probe_AudioOutputUnitStart(AudioUnit unit);
static OSStatus probe_AudioOutputUnitStop(AudioUnit unit);
static OSStatus probe_AudioObjectSetPropertyData(
    AudioObjectID object_id,
    const AudioObjectPropertyAddress* address,
    UInt32 qualifier_data_size,
    const void* qualifier_data,
    UInt32 data_size,
    const void* data);

static OSStatus (*const linked_AudioComponentInstanceNew)(
    AudioComponent, AudioComponentInstance*) = AudioComponentInstanceNew;
static OSStatus (*const linked_AudioComponentInstanceDispose)(
    AudioComponentInstance) = AudioComponentInstanceDispose;
static OSStatus (*const linked_AudioUnitSetProperty)(
    AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void*,
    UInt32) = AudioUnitSetProperty;
static OSStatus (*const linked_AudioUnitInitialize)(AudioUnit) = AudioUnitInitialize;
static OSStatus (*const linked_AudioUnitUninitialize)(AudioUnit) =
    AudioUnitUninitialize;
static OSStatus (*const linked_AudioOutputUnitStart)(AudioUnit) =
    AudioOutputUnitStart;
static OSStatus (*const linked_AudioOutputUnitStop)(AudioUnit) =
    AudioOutputUnitStop;
static OSStatus (*const linked_AudioObjectSetPropertyData)(
    AudioObjectID, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32,
    const void*) = AudioObjectSetPropertyData;

static void probe_log(const char* format, ...) {
  pthread_mutex_lock(&g_log_lock);

  if (!g_log_file) {
    const char* path = getenv("SPOTIFY_NATIVE_AUDIO_PROBE_LOG");
    if (!path || !path[0]) {
      path = "/tmp/spotify-native-audio-probe.log";
    }
    g_log_file = fopen(path, "a");
  }

  if (g_log_file) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);

    char thread_name[128] = {0};
    pthread_getname_np(pthread_self(), thread_name, sizeof(thread_name));

    fprintf(g_log_file, "[%lld.%03ld pid=%d thread=%s] ",
            (long long)ts.tv_sec, ts.tv_nsec / 1000000, getpid(),
            thread_name[0] ? thread_name : "(unnamed)");

    va_list args;
    va_start(args, format);
    vfprintf(g_log_file, format, args);
    va_end(args);

    fputc('\n', g_log_file);
    fflush(g_log_file);
  }

  pthread_mutex_unlock(&g_log_lock);
}

static const char* audio_unit_property_name(AudioUnitPropertyID property_id) {
  switch (property_id) {
    case kAudioUnitProperty_StreamFormat:
      return "kAudioUnitProperty_StreamFormat";
    case kAudioUnitProperty_SetRenderCallback:
      return "kAudioUnitProperty_SetRenderCallback";
    case kAudioUnitProperty_AudioChannelLayout:
      return "kAudioUnitProperty_AudioChannelLayout";
    case kAudioUnitProperty_MaximumFramesPerSlice:
      return "kAudioUnitProperty_MaximumFramesPerSlice";
    case kAudioOutputUnitProperty_CurrentDevice:
      return "kAudioOutputUnitProperty_CurrentDevice";
    case kAudioOutputUnitProperty_EnableIO:
      return "kAudioOutputUnitProperty_EnableIO";
    default:
      return "unknown";
  }
}

static const char* audio_object_selector_name(AudioObjectPropertySelector selector) {
  switch (selector) {
    case kAudioDevicePropertyBufferFrameSize:
      return "kAudioDevicePropertyBufferFrameSize";
    case kAudioDevicePropertyBufferFrameSizeRange:
      return "kAudioDevicePropertyBufferFrameSizeRange";
    case kAudioDevicePropertyStreamFormat:
      return "kAudioDevicePropertyStreamFormat";
    case kAudioDevicePropertyDeviceUID:
      return "kAudioDevicePropertyDeviceUID";
    case kAudioHardwarePropertyDefaultOutputDevice:
      return "kAudioHardwarePropertyDefaultOutputDevice";
    default:
      return "unknown";
  }
}

static void fourcc_to_string(UInt32 value, char out[5]) {
  out[0] = (char)((value >> 24) & 0xff);
  out[1] = (char)((value >> 16) & 0xff);
  out[2] = (char)((value >> 8) & 0xff);
  out[3] = (char)(value & 0xff);
  out[4] = '\0';
  for (int i = 0; i < 4; ++i) {
    if (out[i] < 32 || out[i] > 126) {
      out[i] = '.';
    }
  }
}

static const char* audio_format_flag_summary(AudioFormatID format_id,
                                             AudioFormatFlags flags) {
  if (format_id == kAudioFormatLinearPCM) {
    if ((flags & kAudioFormatFlagIsFloat) != 0) {
      return "float";
    }
    if ((flags & kAudioFormatFlagIsSignedInteger) != 0) {
      return "signed-int";
    }
    return "integer";
  }
  return "unknown";
}

static const char* channel_layout_tag_name(AudioChannelLayoutTag tag) {
  switch (tag) {
    case kAudioChannelLayoutTag_UseChannelDescriptions:
      return "kAudioChannelLayoutTag_UseChannelDescriptions";
    case kAudioChannelLayoutTag_UseChannelBitmap:
      return "kAudioChannelLayoutTag_UseChannelBitmap";
    case kAudioChannelLayoutTag_Mono:
      return "kAudioChannelLayoutTag_Mono";
    case kAudioChannelLayoutTag_Stereo:
      return "kAudioChannelLayoutTag_Stereo";
    case kAudioChannelLayoutTag_StereoHeadphones:
      return "kAudioChannelLayoutTag_StereoHeadphones";
    case kAudioChannelLayoutTag_Binaural:
      return "kAudioChannelLayoutTag_Binaural";
    default:
      return "unknown";
  }
}

static const char* channel_label_name(AudioChannelLabel label) {
  switch (label) {
    case kAudioChannelLabel_Left:
      return "left";
    case kAudioChannelLabel_Right:
      return "right";
    case kAudioChannelLabel_Center:
      return "center";
    case kAudioChannelLabel_LeftSurround:
      return "left-surround";
    case kAudioChannelLabel_RightSurround:
      return "right-surround";
    case kAudioChannelLabel_HeadphonesLeft:
      return "headphones-left";
    case kAudioChannelLabel_HeadphonesRight:
      return "headphones-right";
    case kAudioChannelLabel_Discrete:
      return "discrete";
    case kAudioChannelLabel_Unknown:
      return "unknown";
    default:
      return "other";
  }
}

static void log_audio_stream_basic_description(
    const AudioStreamBasicDescription* asbd) {
  char format_id[5];
  fourcc_to_string(asbd->mFormatID, format_id);
  probe_log("  ASBD sampleRate=%.1f format=%s flags=0x%08x/%s bytesPerPacket=%u framesPerPacket=%u bytesPerFrame=%u channels=%u bitsPerChannel=%u",
            asbd->mSampleRate, format_id, asbd->mFormatFlags,
            audio_format_flag_summary(asbd->mFormatID, asbd->mFormatFlags),
            asbd->mBytesPerPacket, asbd->mFramesPerPacket,
            asbd->mBytesPerFrame, asbd->mChannelsPerFrame,
            asbd->mBitsPerChannel);
}

static void log_audio_channel_layout(const AudioChannelLayout* layout,
                                     UInt32 data_size) {
  probe_log("  ChannelLayout tag=%u/%s bitmap=0x%08x descriptions=%u size=%u",
            layout->mChannelLayoutTag,
            channel_layout_tag_name(layout->mChannelLayoutTag),
            layout->mChannelBitmap, layout->mNumberChannelDescriptions,
            data_size);

  UInt32 max_descriptions = 0;
  if (data_size >= offsetof(AudioChannelLayout, mChannelDescriptions)) {
    max_descriptions =
        (data_size - (UInt32)offsetof(AudioChannelLayout, mChannelDescriptions)) /
        (UInt32)sizeof(AudioChannelDescription);
  }

  UInt32 descriptions_to_log = layout->mNumberChannelDescriptions;
  if (descriptions_to_log > max_descriptions) {
    descriptions_to_log = max_descriptions;
  }
  if (descriptions_to_log > 8) {
    descriptions_to_log = 8;
  }

  for (UInt32 i = 0; i < descriptions_to_log; ++i) {
    const AudioChannelDescription* description = &layout->mChannelDescriptions[i];
    probe_log("  ChannelDescription[%u] label=%u/%s flags=0x%08x coords=(%.3f, %.3f, %.3f)",
              i, description->mChannelLabel,
              channel_label_name(description->mChannelLabel),
              description->mChannelFlags, description->mCoordinates[0],
              description->mCoordinates[1], description->mCoordinates[2]);
  }
}

static void log_audio_unit_property_payload(AudioUnitPropertyID property_id,
                                            const void* data,
                                            UInt32 data_size) {
  if (!data) {
    return;
  }

  if (property_id == kAudioUnitProperty_StreamFormat &&
      data_size >= sizeof(AudioStreamBasicDescription)) {
    log_audio_stream_basic_description((const AudioStreamBasicDescription*)data);
  } else if (property_id == kAudioUnitProperty_SetRenderCallback &&
             data_size >= sizeof(AURenderCallbackStruct)) {
    const AURenderCallbackStruct* callback =
        (const AURenderCallbackStruct*)data;
    probe_log("  RenderCallback inputProc=%p refCon=%p",
              (void*)callback->inputProc, callback->inputProcRefCon);
  } else if (property_id == kAudioUnitProperty_AudioChannelLayout &&
             data_size >= offsetof(AudioChannelLayout, mChannelDescriptions)) {
    log_audio_channel_layout((const AudioChannelLayout*)data, data_size);
  } else if (property_id == kAudioOutputUnitProperty_CurrentDevice &&
             data_size >= sizeof(AudioDeviceID)) {
    probe_log("  CurrentDevice id=%u", *(const AudioDeviceID*)data);
  } else if (property_id == kAudioOutputUnitProperty_EnableIO &&
             data_size >= sizeof(UInt32)) {
    probe_log("  EnableIO value=%u", *(const UInt32*)data);
  }
}

static void* resolve_original_symbol(const char* symbol,
                                     const void* replacement,
                                     const void* linked_candidate,
                                     const char* const* framework_paths,
                                     size_t framework_count) {
  if (linked_candidate && linked_candidate != replacement) {
    return (void*)linked_candidate;
  }

  for (size_t i = 0; i < framework_count; ++i) {
    void* handle = dlopen(framework_paths[i], RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
      continue;
    }

    void* candidate = dlsym(handle, symbol);
    if (candidate && candidate != replacement) {
      return candidate;
    }
  }

  void* candidate = dlsym(RTLD_NEXT, symbol);
  if (candidate && candidate != replacement) {
    return candidate;
  }

  probe_log("original lookup for %s failed or resolved to replacement", symbol);
  return NULL;
}

static const char* const kAudioToolboxFrameworks[] = {
    "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",
    "/System/Library/Frameworks/AudioUnit.framework/AudioUnit",
};

static const char* const kCoreAudioFrameworks[] = {
    "/System/Library/Frameworks/CoreAudio.framework/CoreAudio",
};

__attribute__((constructor)) static void probe_loaded(void) {
  probe_log("native audio probe loaded mode=%s", SPOTIFY_NATIVE_AUDIO_PROBE_MODE);
}

static OSStatus probe_AudioComponentInstanceNew(AudioComponent component,
                                                AudioComponentInstance* instance) {
  static OSStatus (*original)(AudioComponent, AudioComponentInstance*) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioComponent, AudioComponentInstance*))
        resolve_original_symbol("AudioComponentInstanceNew",
                                (const void*)probe_AudioComponentInstanceNew,
                                (const void*)linked_AudioComponentInstanceNew,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  AudioComponentDescription description = {0};
  if (component) {
    AudioComponentGetDescription(component, &description);
  }

  char type[5], subtype[5], manufacturer[5];
  fourcc_to_string(description.componentType, type);
  fourcc_to_string(description.componentSubType, subtype);
  fourcc_to_string(description.componentManufacturer, manufacturer);
  probe_log("AudioComponentInstanceNew begin type=%s subtype=%s manufacturer=%s",
            type, subtype, manufacturer);

  if (!original) {
    probe_log("AudioComponentInstanceNew missing original");
    return kAudio_ParamError;
  }

  OSStatus result = original(component, instance);

  probe_log("AudioComponentInstanceNew type=%s subtype=%s manufacturer=%s result=%d instance=%p",
            type, subtype, manufacturer, (int)result,
            instance ? (void*)*instance : NULL);
  return result;
}

static OSStatus probe_AudioComponentInstanceDispose(AudioComponentInstance instance) {
  static OSStatus (*original)(AudioComponentInstance) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioComponentInstance))
        resolve_original_symbol("AudioComponentInstanceDispose",
                                (const void*)probe_AudioComponentInstanceDispose,
                                (const void*)linked_AudioComponentInstanceDispose,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  if (!original) {
    probe_log("AudioComponentInstanceDispose missing original instance=%p", (void*)instance);
    return kAudio_ParamError;
  }

  probe_log("AudioComponentInstanceDispose instance=%p", (void*)instance);
  return original(instance);
}

static OSStatus probe_AudioUnitSetProperty(AudioUnit unit,
                                           AudioUnitPropertyID property_id,
                                           AudioUnitScope scope,
                                           AudioUnitElement element,
                                           const void* data,
                                           UInt32 data_size) {
  static OSStatus (*original)(AudioUnit, AudioUnitPropertyID, AudioUnitScope,
                              AudioUnitElement, const void*, UInt32) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioUnit, AudioUnitPropertyID, AudioUnitScope,
                            AudioUnitElement, const void*, UInt32))
        resolve_original_symbol("AudioUnitSetProperty",
                                (const void*)probe_AudioUnitSetProperty,
                                (const void*)linked_AudioUnitSetProperty,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  probe_log("AudioUnitSetProperty begin property=%u/%s scope=%u element=%u size=%u",
            property_id, audio_unit_property_name(property_id), scope, element,
            data_size);
  log_audio_unit_property_payload(property_id, data, data_size);
  if (!original) {
    probe_log("AudioUnitSetProperty missing original");
    return kAudio_ParamError;
  }

  OSStatus result = original(unit, property_id, scope, element, data, data_size);
  probe_log("AudioUnitSetProperty property=%u/%s scope=%u element=%u size=%u result=%d",
            property_id, audio_unit_property_name(property_id), scope, element,
            data_size, (int)result);
  return result;
}

static OSStatus probe_AudioUnitInitialize(AudioUnit unit) {
  static OSStatus (*original)(AudioUnit) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioUnit))
        resolve_original_symbol("AudioUnitInitialize",
                                (const void*)probe_AudioUnitInitialize,
                                (const void*)linked_AudioUnitInitialize,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  probe_log("AudioUnitInitialize begin unit=%p", (void*)unit);
  if (!original) {
    probe_log("AudioUnitInitialize missing original");
    return kAudio_ParamError;
  }

  OSStatus result = original(unit);
  probe_log("AudioUnitInitialize unit=%p result=%d", (void*)unit, (int)result);
  return result;
}

static OSStatus probe_AudioUnitUninitialize(AudioUnit unit) {
  static OSStatus (*original)(AudioUnit) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioUnit))
        resolve_original_symbol("AudioUnitUninitialize",
                                (const void*)probe_AudioUnitUninitialize,
                                (const void*)linked_AudioUnitUninitialize,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  if (!original) {
    probe_log("AudioUnitUninitialize missing original unit=%p", (void*)unit);
    return kAudio_ParamError;
  }

  probe_log("AudioUnitUninitialize unit=%p", (void*)unit);
  return original(unit);
}

static OSStatus probe_AudioOutputUnitStart(AudioUnit unit) {
  static OSStatus (*original)(AudioUnit) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioUnit))
        resolve_original_symbol("AudioOutputUnitStart",
                                (const void*)probe_AudioOutputUnitStart,
                                (const void*)linked_AudioOutputUnitStart,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  probe_log("AudioOutputUnitStart begin unit=%p", (void*)unit);
  if (!original) {
    probe_log("AudioOutputUnitStart missing original");
    return kAudio_ParamError;
  }

  OSStatus result = original(unit);
  probe_log("AudioOutputUnitStart unit=%p result=%d", (void*)unit, (int)result);
  return result;
}

static OSStatus probe_AudioOutputUnitStop(AudioUnit unit) {
  static OSStatus (*original)(AudioUnit) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioUnit))
        resolve_original_symbol("AudioOutputUnitStop",
                                (const void*)probe_AudioOutputUnitStop,
                                (const void*)linked_AudioOutputUnitStop,
                                kAudioToolboxFrameworks,
                                sizeof(kAudioToolboxFrameworks) /
                                    sizeof(kAudioToolboxFrameworks[0]));
  }

  if (!original) {
    probe_log("AudioOutputUnitStop missing original unit=%p", (void*)unit);
    return kAudio_ParamError;
  }

  probe_log("AudioOutputUnitStop unit=%p", (void*)unit);
  return original(unit);
}

static OSStatus probe_AudioObjectSetPropertyData(
    AudioObjectID object_id,
    const AudioObjectPropertyAddress* address,
    UInt32 qualifier_data_size,
    const void* qualifier_data,
    UInt32 data_size,
    const void* data) {
  static OSStatus (*original)(AudioObjectID, const AudioObjectPropertyAddress*,
                              UInt32, const void*, UInt32, const void*) = NULL;
  if (!original) {
    original = (OSStatus(*)(AudioObjectID, const AudioObjectPropertyAddress*,
                            UInt32, const void*, UInt32, const void*))
        resolve_original_symbol("AudioObjectSetPropertyData",
                                (const void*)probe_AudioObjectSetPropertyData,
                                (const void*)linked_AudioObjectSetPropertyData,
                                kCoreAudioFrameworks,
                                sizeof(kCoreAudioFrameworks) /
                                    sizeof(kCoreAudioFrameworks[0]));
  }

  if (address) {
    char selector[5];
    fourcc_to_string(address->mSelector, selector);
    probe_log("AudioObjectSetPropertyData begin object=%u selector=%s/%s scope=%u element=%u size=%u",
              object_id, selector, audio_object_selector_name(address->mSelector),
              address->mScope, address->mElement, data_size);
  }

  if (!original) {
    probe_log("AudioObjectSetPropertyData missing original");
    return kAudio_ParamError;
  }

  OSStatus result = original(object_id, address, qualifier_data_size,
                             qualifier_data, data_size, data);

  if (address) {
    char selector[5];
    fourcc_to_string(address->mSelector, selector);
    probe_log("AudioObjectSetPropertyData object=%u selector=%s/%s scope=%u element=%u size=%u result=%d",
              object_id, selector, audio_object_selector_name(address->mSelector),
              address->mScope, address->mElement, data_size, (int)result);
  }

  return result;
}

#ifdef PROBE_AUDIO_COMPONENT
DYLD_INTERPOSE(probe_AudioComponentInstanceNew, AudioComponentInstanceNew);
DYLD_INTERPOSE(probe_AudioComponentInstanceDispose, AudioComponentInstanceDispose);
#endif

#ifdef PROBE_AUDIO_UNIT
DYLD_INTERPOSE(probe_AudioUnitSetProperty, AudioUnitSetProperty);
DYLD_INTERPOSE(probe_AudioUnitInitialize, AudioUnitInitialize);
DYLD_INTERPOSE(probe_AudioUnitUninitialize, AudioUnitUninitialize);
DYLD_INTERPOSE(probe_AudioOutputUnitStart, AudioOutputUnitStart);
DYLD_INTERPOSE(probe_AudioOutputUnitStop, AudioOutputUnitStop);
#endif

#ifdef PROBE_AUDIO_OBJECT
DYLD_INTERPOSE(probe_AudioObjectSetPropertyData, AudioObjectSetPropertyData);
#endif
