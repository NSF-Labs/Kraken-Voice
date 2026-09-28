Vendored from file_picker 8.3.7 (pub.dev), preserving LICENSE and runtime sources.
Example and upstream test projects are omitted.

On iOS, FileType.audio opens UIDocumentPickerViewController filtered to
public.audio, instead of MPMediaPickerController. Kraken imports recording files
from Files/providers, and does not request Apple Music library access. This fixes
the confirmed TCC/NSAppleMusicUsageDescription abort on both physical iPhones.

The private Objective-C FileUtils class is renamed KrakenFilePickerUtils to avoid
the class collision with Apple's OSAnalytics.framework observed on these devices.
All internal references and header filenames are updated. Dart APIs are unchanged.
