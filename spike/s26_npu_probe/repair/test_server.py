"""Factual regression checks against an isolated local-only Hexagon server."""
import json
import re
import time
import urllib.request

BASE = 'http://127.0.0.1:18099'
context = '\n'.join(f'Agenda item {i}: The team reviewed progress, discussed testing, and agreed to keep the existing schedule.' for i in range(60))
cases = [
 ('capital', 'Answer in one sentence: What is the capital of France?', ['Paris']),
 ('original_meeting', 'Meeting decision: Approve a budget of 42750 dollars. Maya must deliver the audit by October 16. Summarize the amount, owner and deadline in one sentence.', ['42750', 'Maya', 'October 16']),
 ('arithmetic', 'Answer in one sentence: What is 17 plus 25?', ['42']),
 ('different_facts', 'Meeting decision: Approve 18600 dollars. Jordan must deliver the inventory report by November 9. Summarize the amount, owner and deadline in one sentence.', ['18600', 'Jordan', 'November 9']),
 ('correction', 'At first the team proposed 31000 dollars, Elena, and March 8. They rejected that proposal. The FINAL decision is 28500 dollars, Omar, and March 22. Summarize only the final amount, owner, and deadline in one sentence.', ['28500', 'Omar', 'March 22']),
 ('long_meeting', context+'\nFinal decision: Approve a budget of 42750 dollars. Maya must deliver the audit by October 16. Summarize ONLY the final decision, amount, owner and deadline in one sentence.', ['42750', 'Maya', 'October 16']),
]
failures = 0
for name, prompt, expected in cases:
 payload = {'messages':[{'role':'user','content':prompt}], 'temperature':0, 'seed':42, 'max_tokens':128, 'repeat_penalty':1.0, 'stream':False}
 req = urllib.request.Request(BASE+'/v1/chat/completions', data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})
 start = time.monotonic()
 try:
  with urllib.request.urlopen(req, timeout=180) as response: data=json.load(response)
  output = data['choices'][0]['message'].get('content') or ''
  normalized = re.sub(r'(?<=\d),(?=\d)', '', output).lower()
  missing = [x for x in expected if x.lower() not in normalized]
  truncated = data['choices'][0].get('finish_reason') == 'length'
  passed = not missing and not truncated
  failures += not passed
  print(json.dumps({'case':name,'pass':passed,'missing':missing,'truncated':truncated,'wall_s':round(time.monotonic()-start,3),'output':output,'usage':data.get('usage'),'timings':data.get('timings') }),flush=True)
 except Exception as exc:
  failures += 1
  print(json.dumps({'case':name,'pass':False,'error':str(exc)}),flush=True)
print(json.dumps({'failures':failures,'cases':len(cases)}),flush=True)
raise SystemExit(1 if failures else 0)
