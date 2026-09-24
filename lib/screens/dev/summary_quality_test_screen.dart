import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:krak_en_voice/kernel/kernel.dart';

/// Developer test screen for verifying summary quality across 5 transcript types.
/// Access via Settings > Test Summaries (debug only).
class SummaryQualityTestScreen extends StatefulWidget {
  const SummaryQualityTestScreen({super.key});

  @override
  State<SummaryQualityTestScreen> createState() => _SummaryQualityTestScreenState();
}

class _SummaryQualityTestScreenState extends State<SummaryQualityTestScreen> {
  int _selectedType = -1;
  bool _isGenerating = false;
  String _streamingOutput = "";
  String? _parsedResult;
  String? _parseError;

  static const _bg = Color(0xFF0A0A0C);
  static const _surface = Color(0xFF121216);
  static const _surfaceElevated = Color(0xFF17171D);
  static const _border = Color(0x0FFFFFFF);
  static const _accent = Color(0xFF8B7DFF);
  static const _textMuted = Color(0xFF6B6966);
  static const _textPrimary = Color(0xFFF2EFE8);

  static const _testTranscripts = <String, String>{
    '1. Sales Call': '''
Sarah: Thanks for taking the call, Mike. I wanted to walk you through our enterprise tier.
Mike: Sure, we've been evaluating three vendors. What makes yours different?
Sarah: Our platform does real-time transcription with on-device AI, so nothing leaves your network. That's a huge differentiator for regulated industries.
Mike: That's interesting. We're in healthcare, so HIPAA is non-negotiable.
Sarah: Exactly. We're HIPAA-compliant out of the box, and we just added BAA support. Pricing starts at forty-nine per seat per month for the enterprise plan.
Mike: How does that compare to your mid-tier?
Sarah: Mid-tier is twenty-nine but doesn't include the on-device processing. Everything goes through our cloud.
Mike: We'd definitely need on-device. What's the minimum commitment?
Sarah: Annual contracts with a ten-seat minimum. We can do a thirty-day pilot at no cost.
Mike: That works. Can you send over a pilot agreement? I'd also need a security questionnaire filled out.
Sarah: Absolutely, I'll have both over by Friday. One more thing — we're running a Q2 promotion, twenty percent off the first year if you sign by end of May.
Mike: Good to know. Let me loop in our IT director, Janet. She'll want to see a technical demo.
Sarah: Perfect. I'll set up a demo for next week. Does Tuesday or Wednesday work better?
Mike: Wednesday afternoon would be ideal.
Sarah: Done. I'll send the calendar invite today. Thanks Mike, excited to work with you.
''',

    '2. Daily Standup': '''
Rachel: Alright, let's do standup. Tom, you're up.
Tom: Yesterday I finished the database migration for the user preferences table. Today I'm starting on the API endpoints for the new settings screen. No blockers.
Rachel: Great. Lisa?
Lisa: I spent yesterday debugging the notification service. Turns out the FCM token was expiring and we weren't refreshing it. I pushed a fix, PR is up for review. Today I'm picking up the push notification preferences UI. One blocker — I need design specs for the notification settings page. Maria, can you prioritize that?
Maria: Yeah, I can have mockups to you by noon.
Lisa: Perfect, thanks.
Rachel: Okay, Dev?
Dev: Yesterday I paired with QA on the regression suite. We found two flaky tests related to the login flow timing. I'm fixing those today. Also, the staging deploy failed last night — looks like a Docker image issue. I'll investigate after standup.
Rachel: Is the staging issue blocking anyone?
Dev: Not yet, QA can still test on the current build.
Rachel: Good. I'll flag the staging issue in the ops channel just in case. Anything else? No? Great, let's ship it.
''',

    '3. One-on-One': '''
Jordan: Hey Alex, thanks for meeting. How's the week going?
Alex: Honestly, a bit stressful. The deadline for the analytics dashboard got moved up two weeks and I'm not sure we can hit it with the current scope.
Jordan: Yeah, I heard about that. What specifically feels tight?
Alex: The data pipeline refactor. We estimated three weeks for that alone, and it's a dependency for everything else. If I cut corners there, we'll pay for it in production bugs.
Jordan: I agree, don't cut corners on the pipeline. Let me talk to product about scoping down the initial release. Maybe we launch with three chart types instead of seven and add the rest in a fast follow.
Alex: That would help a lot. The three core charts — revenue, churn, and active users — are almost done.
Jordan: Perfect. On a different note, how are you feeling about the senior engineer promotion track? We talked about that last quarter.
Alex: I've been thinking about it. I think the analytics project is good visibility, but I feel like I need more experience leading cross-team initiatives.
Jordan: What if I put you as the tech lead for the Q3 platform migration? It spans three teams and would give you exactly that experience.
Alex: I'd be really interested in that. Can we talk scope next week?
Jordan: Absolutely. I'll send you the brief. One last thing — make sure you're taking PTO. You've been heads-down for six weeks straight.
Alex: Yeah, I was thinking about taking a long weekend in June.
Jordan: Do it. Block it off before it fills up.
''',

    '4. Job Interview': '''
Priya: Welcome, James. Thanks for coming in. I've reviewed your resume and I'm excited to dig in. Can you tell me about your most complex technical project?
James: Sure. At my last company I led the migration of our monolithic Django application to a microservices architecture on Kubernetes. We had about two million daily active users, so zero-downtime was critical.
Priya: How did you approach the migration without disrupting users?
James: We used the strangler fig pattern. We identified the highest-traffic endpoints first — authentication and the product catalog — and built standalone services for those. We ran them in parallel with the monolith using a feature flag system, gradually shifting traffic over about four months.
Priya: What was the biggest challenge?
James: Data consistency. The monolith used a single Postgres database, and splitting that across services meant we needed eventual consistency patterns. We implemented event sourcing with Kafka for the order pipeline, which was the trickiest part.
Priya: How did you handle team coordination?
James: We had three squads working on different services. I held weekly architecture reviews to make sure interfaces stayed compatible. We also invested heavily in contract testing with Pact, which caught integration issues before they hit staging.
Priya: Impressive. What's a technical decision you made that you'd do differently now?
James: We chose gRPC for inter-service communication, which was great for performance but made debugging harder. In hindsight, I'd use REST for most services and reserve gRPC only for the latency-sensitive paths.
Priya: Good reflection. Let's talk about the system design exercise next.
''',

    '5. Support Escalation': '''
Support Lead Kim: Okay team, we have a P1 from Meridian Corp. Their entire reporting module has been down for six hours. Let me bring in engineering.
Engineer Raj: I've been looking at this. The issue is in our aggregation pipeline — a schema change we deployed yesterday broke the ETL job that feeds their reports.
Kim: So this is our bug, not a customer configuration issue?
Raj: Correct. The migration added a NOT NULL constraint to the metrics table, but the ETL job inserts rows with nullable timestamps for in-progress calculations. Every insert is failing now.
Kim: What's the fix timeline?
Raj: Two options. Quick fix: roll back the migration, which restores their reports in about thirty minutes but we lose the data integrity improvement. Proper fix: update the ETL job to handle the constraint, which takes about four hours.
Kim: Meridian is our second-largest account. Six hours of downtime is already bad. Let's do the rollback now to restore service, then do the proper fix during their maintenance window Saturday night.
Raj: Agreed. I'll start the rollback. One concern — three other customers got the same migration. We should check if they're affected too.
Kim: Good call. Sarah, can you pull the deployment log and check Apex Industries, TechFlow, and NovaBridge?
Sarah: On it. I'll have status in fifteen minutes.
Kim: Perfect. Raj, start the rollback. I'll draft a customer communication for Meridian. We need to offer them an SLA credit for this.
Raj: Rolling back now. I'll ping you when reports are back online.
Kim: Thanks everyone. Let's debrief after this is resolved to make sure our migration checklist catches this pattern going forward.
''',
  };

  Future<void> _runTest(int index) async {
    final entry = _testTranscripts.entries.elementAt(index);
    setState(() {
      _selectedType = index;
      _isGenerating = true;
      _streamingOutput = "";
      _parsedResult = null;
      _parseError = null;
    });

    String transcript = entry.value;
    if (transcript.length > 3000) {
      transcript = '${transcript.substring(0, 3000)}\n\n[...truncated...]';
    }

    final prompt = '''Summarize this meeting transcript into a structured report.

Return ONLY valid JSON in this exact format, nothing else:
{"tldr": "A 1-2 sentence executive summary", "key_points": ["point 1", "point 2"], "decisions": ["decision 1", "decision 2"], "action_items": ["action 1", "action 2"], "open_questions": ["question 1", "question 2"]}

If a section has no items, use an empty array []. Keep each item concise (1 sentence max).

Transcript:
$transcript''';

    final inference = context.read<LocalInferenceService>();

    try {
      try { await inference.loadModel(); } catch (_) {}

      final stream = inference.generateStream(prompt, maxTokens: 512);
      stream.listen(
        (token) {
          if (mounted) setState(() => _streamingOutput += token.text);
        },
        onDone: () {
          if (mounted) {
            String cleaned = _streamingOutput.trim();
            if (cleaned.startsWith('```')) {
              final lines = cleaned.split('\n');
              if (lines.length > 2) {
                cleaned = lines.sublist(1, lines.length - (lines.last.trim() == '```' ? 1 : 0)).join('\n').trim();
              }
            }

            try {
              final parsed = jsonDecode(cleaned);
              final hasAllKeys = parsed is Map &&
                parsed.containsKey('tldr') &&
                parsed.containsKey('key_points') &&
                parsed.containsKey('action_items');

              setState(() {
                _isGenerating = false;
                _parsedResult = const JsonEncoder.withIndent('  ').convert(parsed);
                if (!hasAllKeys) {
                  _parseError = '⚠️ Missing expected keys. Got: ${parsed.keys.join(", ")}';
                }
              });
            } catch (e) {
              setState(() {
                _isGenerating = false;
                _parseError = '❌ JSON parse failed: $e\n\nRaw output:\n$cleaned';
              });
            }
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _isGenerating = false;
              _parseError = '❌ Inference error: $e';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _parseError = '❌ Failed to start: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Summary Quality Test',
          style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            'Tap a transcript type to generate a summary and verify quality.',
            style: TextStyle(color: _textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),

          // Test type buttons
          ...List.generate(_testTranscripts.length, (i) {
            final name = _testTranscripts.keys.elementAt(i);
            final isSelected = _selectedType == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isGenerating ? null : () => _runTest(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? _accent.withValues(alpha: 0.15) : _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? _accent : _border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle : Icons.play_circle_outline,
                          color: isSelected ? _accent : _textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(name, style: const TextStyle(color: _textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Results
          if (_isGenerating) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator(color: _accent)),
            const SizedBox(height: 12),
            Text(
              'Generating... (${_streamingOutput.length} chars)',
              style: const TextStyle(color: _textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],

          if (_parseError != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: SelectableText(
                _parseError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],

          if (_parsedResult != null) ...[
            const SizedBox(height: 20),
            const Text('✅ Valid JSON Output',
              style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: SelectableText(
                _parsedResult!,
                style: const TextStyle(
                  color: _textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

