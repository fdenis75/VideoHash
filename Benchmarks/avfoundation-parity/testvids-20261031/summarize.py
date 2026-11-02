from pathlib import Path
import csv,json,re
base=Path(__file__).resolve().parent
log=(base/'batch.log').read_text()
match=re.search(r'Saving temporary AVFoundation frames to: (.*?) for /Users/francois/Dev/testvids/',log)
run=(Path(match[1])/'run.txt').read_text()
root=Path('/Users/francois/Dev/VideoHash/temp')
folders=[p for p in root.iterdir() if p.is_dir() and (p/'run.txt').exists() and (p/'run.txt').read_text()==run]
rows=[]
for folder in folders:
 if not folder.name.endswith('-ffmpg'):continue
 name=Path((folder/'source.txt').read_text()).name
 block=re.search(r'  '+re.escape(name)+r'\n    PHash:    ([0-9a-f]+)\n    OSHash:   ([0-9a-f]+)\n    Duration: ([^\n]+)\n    PHash distance \(AVFoundation vs ffmpeg\): (\d+)',log)
 times=list(csv.DictReader((folder/'comparison.csv').open()))
 valid=[r for r in times if r['actual_difference_ms']]
 diffs=[abs(float(r['actual_difference_ms'])) for r in valid]
 rows.append(dict(file=name,distance=int(block[4]) if block else None,valid_timestamps=len(valid),max_time_difference_ms=max(diffs,default=None),different_timestamps=sum(d>0.001 for d in diffs),ffmpeg_directory=str(folder),comparison=str(folder/'comparison.csv')))
rows.sort(key=lambda r:(-(r['distance'] or 0),r['file']))
summary={'run_id':run,'file_count':len(rows),'exact_hashes':sum(r['distance']==0 for r in rows),'valid_timestamps':sum(r['valid_timestamps'] for r in rows),'different_timestamps':sum(r['different_timestamps'] for r in rows),'rows':rows}
(base/'summary.json').write_text(json.dumps(summary,indent=2))
lines=['# testvids batch — 2026-10-31','',f"Run: `{run}`",'',f"{summary['exact_hashes']}/{len(rows)} exact PHashes; {summary['valid_timestamps']} timestamp pairs; {summary['different_timestamps']} pairs differ by more than 0.001 ms.",'','| File | PHash distance / 64 | Timestamp differences / 25 | Max timing difference (ms) |','|---|---:|---:|---:|']
for r in rows:lines.append(f"| {r['file']} | {r['distance']} | {r['different_timestamps']} | {r['max_time_difference_ms']:.6f} |")
lines+=['','Command: `.build/debug/test-hash /Users/francois/Dev/testvids 8`','', 'Source files were not modified. Detailed output: `batch.log`. Per-video CSV paths are in `summary.json`.']
(base/'README.md').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
