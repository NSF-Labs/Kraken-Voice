/// Maps a Whisper ISO 639-1 language code to a display name.
/// Available to all screens that need to render language labels.
String whisperLanguageLabel(String code) {
  const labels = {
    'auto': 'Auto-detect',
    'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
    'it': 'Italian', 'pt': 'Portuguese', 'nl': 'Dutch', 'pl': 'Polish',
    'ru': 'Russian', 'zh': 'Chinese', 'ja': 'Japanese', 'ko': 'Korean',
    'ar': 'Arabic', 'hi': 'Hindi', 'tr': 'Turkish', 'vi': 'Vietnamese',
    'th': 'Thai', 'uk': 'Ukrainian', 'sv': 'Swedish', 'da': 'Danish',
    'fi': 'Finnish', 'no': 'Norwegian', 'he': 'Hebrew', 'id': 'Indonesian',
    'ms': 'Malay', 'tl': 'Tagalog',
  };
  return labels[code] ?? code.toUpperCase();
}

/// Full language map with flag emojis for pickers.
const Map<String, String> whisperLanguageOptions = {
  'auto': '🌐  Auto-detect',
  'en': '🇺🇸  English',
  'es': '🇪🇸  Spanish',
  'fr': '🇫🇷  French',
  'de': '🇩🇪  German',
  'it': '🇮🇹  Italian',
  'pt': '🇧🇷  Portuguese',
  'nl': '🇳🇱  Dutch',
  'pl': '🇵🇱  Polish',
  'ru': '🇷🇺  Russian',
  'zh': '🇨🇳  Chinese',
  'ja': '🇯🇵  Japanese',
  'ko': '🇰🇷  Korean',
  'ar': '🇸🇦  Arabic',
  'hi': '🇮🇳  Hindi',
  'tr': '🇹🇷  Turkish',
  'vi': '🇻🇳  Vietnamese',
  'th': '🇹🇭  Thai',
  'uk': '🇺🇦  Ukrainian',
  'sv': '🇸🇪  Swedish',
  'da': '🇩🇰  Danish',
  'fi': '🇫🇮  Finnish',
  'no': '🇳🇴  Norwegian',
  'he': '🇮🇱  Hebrew',
  'id': '🇮🇩  Indonesian',
  'ms': '🇲🇾  Malay',
  'tl': '🇵🇭  Tagalog',
};
