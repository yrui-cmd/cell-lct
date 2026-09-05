"""Exercise real vectorizer entrypoints with a mocked, non-billable service."""
import contextlib
import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'plugins/cell_gd/skills/cell_gd/scripts'
spec = importlib.util.spec_from_file_location('vectorizer', SCRIPTS / 'vectorize_xiaomiao.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

for balance, expected in [(12, '12'), (0, '0'), (None, '暂不可用'), (-1, '暂不可用'), ('bad', '暂不可用')]:
    with tempfile.TemporaryDirectory(prefix='cell-gd-balance-') as directory:
        work = Path(directory)
        output = work / 'output.svg'
        job = {'status': 'completed', 'credits_left': balance}
        def fake_call(adapter, action, *args):
            if action == 'verify':
                return {'authenticated': True}
            if action == 'upload':
                return {'image_id': 'mock'}
            if action == 'status':
                return job
            return {'ok': True}
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(sys, 'argv', ['vectorizer', '--input-image', 'mock.png', '--output-svg', str(output)]), patch.object(module, 'call', fake_call), patch.object(module.subprocess, 'run'), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            assert module.main() == 0
        assert stderr.getvalue().strip() == f'剩余额度：{expected}'
        assert json.loads(stdout.getvalue())['credits_left'] == balance

        if sys.platform == 'win32':
            scripts = work / 'scripts'
            shutil.copytree(SCRIPTS, scripts)
            (scripts / 'xiaomiao.ps1').write_text('''param($Action, $BaseUrl, $ImagePath, $ImageId, $OutputPath)
switch ($Action) {
  verify { [pscustomobject]@{authenticated=$true} }
  upload { [pscustomobject]@{image_id='mock'} }
  status { Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'job.json') | ConvertFrom-Json }
  download { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixture.svg') -Destination $OutputPath }
}
''', encoding='utf-8-sig')
            (scripts / 'job.json').write_text(json.dumps(job), encoding='utf-8')
            shutil.copyfile(ROOT / 'tests/fixtures/visibility.svg', scripts / 'fixture.svg')
            image = work / 'original.png'
            image.write_bytes(b'mock input')
            # Match callers that discard the success stream; information must survive.
            harness = work / 'test.ps1'
            harness.write_text('''$ErrorActionPreference='Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $root 'scripts/vectorize-xiaomiao.ps1') -InputImage (Join-Path $root 'original.png') -OutputSvg (Join-Path $root 'output.svg') | Out-Null
''', encoding='utf-8-sig')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(harness)], capture_output=True, encoding='utf-8')
            assert result.returncode == 0, result.stderr
            assert f'剩余额度：{expected}' in result.stdout, result.stdout
            assert output.exists()
print('BALANCE_OK|python=5|powershell=5|zero=preserved|unknown=explicit|pipeline=visible|api=mocked')
