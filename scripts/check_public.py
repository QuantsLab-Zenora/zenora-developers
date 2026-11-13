from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
spec=json.loads((root/'v1/openapi.json').read_text(encoding='utf-8'))
assert spec['openapi'].startswith('3.1')
for p in [root/'README.md',*list((root/'v1').glob('*')),*list((root/'examples').rglob('*'))]:
 if not p.is_file():continue
 text=p.read_text(encoding='utf-8')
 for forbidden in ('C:/workspace/','C:\\workspace\\','.env.local','mudabbirulsaad@gmail.com','/run/secrets/','x-zenora-controller'):
  assert forbidden.lower() not in text.lower(),str(p)+': private operational material'
 assert not re.search(r'gh[pousr]_[A-Za-z0-9]{20,}',text),str(p)+': credential pattern'
print('PASS public-only documentation and OpenAPI export')
