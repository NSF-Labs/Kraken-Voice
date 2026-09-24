# PDF and Word imports — build 1.0.12-npu-sm8850+12

In **Files**, use **Import Files → Import PDF or Word document**, pick a file,
then choose a folder. The same import action is available inside a folder.
Open a document to view extracted text or generate an on-device AI summary.
Audio import remains available from the same menu.

Supported: text PDFs (Android 15+) and Word `.docx`. Older `.doc` files must be
saved as `.docx` first. No cloud upload, OCR, or macro execution is involved.

- Limits: 50 MB per file, 200 PDF pages, 500,000 extracted characters; Word XML
  is bounded to 8 MB decompressed. Over-limit documents fail without partial
  imports. Long text uses the existing tokenizer-measured section summaries.
- Scanned/image-only PDFs fail with an OCR explanation. Mixed PDFs warn about
  pages without readable text. Word body text and tables are included; omitted
  images, comments, headers/footers and footnotes are disclosed in the viewer.
- Imported copies use UUID names in private app documents storage. Extracted
  text, warnings and summaries are stored in encrypted SQLite schema version 20.
- Documents have their own table and view. They are never audio transcription
  jobs and are not deleted by audio retention rules.
- Folder moves/deletion include documents. Deleting a document asks for
  confirmation, removes its imported copy/text/summary, and preserves the
  original file. This deletion is permanent, unlike recording trash.
- Summary work survives navigation. Failed or capped generations do not replace
  a saved summary. Document-specific prompts avoid inventing meeting details.

Verification: `flutter test`, `flutter analyze`, synthetic native extraction and
NPU tests in `integration_test/document_import_test.dart`. Run device checks via
manual `adb install -r` and launch; do not use the automatic Flutter device test
runner against a populated app. Restore a clean normal profile build afterward
and run `scripts/verify_npu_apk.py` before installing.

## Verified on the S26 (2026-09-24)

- 54 Flutter regression tests pass; analyzer has no errors or warnings (12
  existing informational notices).
- Native device checks pass: PDF extraction; Word tables, Unicode/entity text,
  exclusion of deleted revisions; blank PDF and malformed Word rejection;
  correct NPU summaries from both formats.
- Normal build 12: top-level PDF picker → folder selection → imported viewer →
  AI summary verified. Reopening the app retained the document and saved summary.
- Folder-level Word picker opens the document directly in that folder.
- Existing appointment remains present; update uses `adb install -r`, never
  uninstall/data reset. Runtime profile and compiled APK identity verified.
- Normal-app Word summary also completed with the correct amount, owner and
  date; both folder cards showed Summary saved. The temporary test folder and
  original fixture downloads were removed afterward; the existing appointment
  folder still contains its original recording.

Installed profile APK SHA-256: `78b663a57c0a58a8c703a35d7765b33856621cc9168620cb9d8fa548759c894f`

## Build 13 summary continuation

Final summaries now reserve 2,048 output tokens. If that allowance is reached,
generation continues using the same native KV state while the 4,096-token total
context has room. The source text and response share that context; it is not
an unlimited output allowance. Long inputs are condensed before generation.

Final responses are checkpointed in the encrypted vault every 512 characters
and on completion, cancellation, or a handled error. A successfully saved summary
clears its draft. If generation fails, reopen the file and expand **Saved incomplete
summary** to read or copy the partial response. Existing completed summaries are
kept separately. Abrupt process termination may lose text since the last checkpoint.
Drafts survive app restarts, but the model cannot resume its KV state after a restart
or continue beyond the hard context limit. Regeneration starts a new response.

Intermediate sections retain their separate 3,072-token input budget. Later
condensation passes merge and prioritize notes into shorter overviews instead
of repeatedly extracting the same detail. The final pass is checked before
reporting a condensation failure. The 75,026-character S26 document completed
and its saved summary survived reopening with this correction.

## Build 14 progress display

Generate AI Summary shows an estimated overall bar, the current preparation pass
and section count, growing character counts during generation, and elapsed time.
A separate activity spinner remains animated while awaiting model output. Section
completion comes from completed inference calls; output length cannot establish an
exact percentage, so the bar is explicitly labeled estimated and stays below 100%
until saving. Leaving and reopening the document retains its active progress and
original elapsed start time. Manual recording summaries and refinement use the
same panel. No model, context-window, or acceleration backend change is included.
