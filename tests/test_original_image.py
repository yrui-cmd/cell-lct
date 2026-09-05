"""Original-image forwarding and separate backend state without a paid API call."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'plugins' / 'cell_gd' / 'skills' / 'cell_gd' / 'scripts'


def main():
    spec = importlib.util.spec_from_file_location('image_entry', SCRIPTS / 'run_from_image.py')
    entry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(entry)
    actual_run = entry.run
    svg = (ROOT / 'tests/fixtures/visibility.svg').read_bytes()
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        image = work / 'original.png'
        original = b'\x89PNG\r\n\x1a\noriginal image bytes including all lettering'
        image.write_bytes(original)
        uploads = []

        def fake_service(*args):
            if Path(args[0]).name == 'vectorize_xiaomiao.py':
                uploaded = Path(args[args.index('--input-image') + 1])
                uploads.append(uploaded)
                assert uploaded == image.resolve()
                assert uploaded.read_bytes() == original
                Path(args[args.index('--output-svg') + 1]).write_bytes(svg)
            else:
                actual_run(*args)

        argv = ['run_from_image.py', '--input-image', str(image), '--output-root', str(work / 'output')]
        with patch.object(sys, 'argv', argv), patch.object(entry, 'run', fake_service):
            assert entry.main() == 0
        assert uploads == [image.resolve()]
        assert image.read_bytes() == original
        master = next((work / 'output').glob('*/*[0-9].svg'))
        assert master.read_bytes() == svg
        assert len(list((work / 'output').rglob('*.pptx'))) == 1
        assert not list(work.rglob('*text-manifest*'))
        # AI keeps its own resumable playback schema rather than accidentally
        # receiving PowerPoint's drawing-state.json after the package merge.
        cache = work / 'ai-cache'
        command = [sys.executable, str(SCRIPTS / 'prepare_illustrator_cache.py'), '--input', str(master), '--output-dir', str(cache), '--job-id', 'shibielujing1']
        subprocess.run(command, check=True, capture_output=True)
        before = (cache / 'geometry-cache.json').read_bytes()
        subprocess.run(command, check=True, capture_output=True)
        assert (cache / 'geometry-cache.json').read_bytes() == before
        state = json.loads((cache / 'playback.json').read_text())
        assert state['root_group_name'].startswith('CELL_LCT_CACHE_JOB_')
        assert not (cache / 'drawing-state.json').exists()
    print('ORIGINAL_IMAGE_OK|input=unchanged|text_merge=absent|pptx=created|ai_cache=preserved')


if __name__ == '__main__':
    main()
