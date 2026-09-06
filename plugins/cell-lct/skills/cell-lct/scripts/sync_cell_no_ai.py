"""Synchronize the official cell_no_ai skill without touching credentials."""
import argparse, hashlib, json, shutil, subprocess, tempfile, time
from pathlib import Path

def sync(destination):
    destination=Path(destination).resolve()
    with tempfile.TemporaryDirectory(prefix='cell-no-ai-update-') as temp:
        checkout=Path(temp)/'source'
        subprocess.run(['git','clone','--depth','1','--branch','main','https://github.com/yrui-cmd/cell_no_ai.git',str(checkout)],check=True,capture_output=True)
        revision=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
        names=subprocess.check_output(['git','-C',str(checkout),'ls-files'],text=True).splitlines()
        files=[Path(n) for n in names if n=='SKILL.md' or Path(n).parts[0] in ('agents','references','scripts')]
        if not (checkout/'SKILL.md').is_file():raise RuntimeError('Missing upstream SKILL.md')
        for rel in files:
            src=checkout/rel;target=destination/rel
            if rel.is_absolute() or '..' in rel.parts or src.is_symlink() or not target.resolve().is_relative_to(destination):raise RuntimeError('Unsafe skill path')
        destination.mkdir(parents=True,exist_ok=True)
        backup=destination.parent/'.cell_no_ai-backups'/str(time.time_ns())
        changed=0
        for rel in files:
            src=checkout/rel;target=destination/rel
            if target.is_file() and target.read_bytes()==src.read_bytes():continue
            if target.exists():
                saved=backup/rel;saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,saved)
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target);changed+=1
        (destination/'.upstream.json').write_text(json.dumps({'repository':'https://github.com/yrui-cmd/cell_no_ai','revision':revision}),encoding='utf-8')
        print(f'SYNC_OK|revision={revision}|changed={changed}')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--destination',default=str(Path(__file__).absolute().parents[2]/'cell_no_ai'));args=parser.parse_args()
    try:sync(args.destination)
    except Exception as exc:raise SystemExit('SYNC_FAILED|'+type(exc).__name__+'|existing_installation_preserved; retry before watermark submission')
