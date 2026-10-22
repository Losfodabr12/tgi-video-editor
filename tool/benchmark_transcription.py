"""Windows Whisper benchmark. No downloads. Inputs/outputs must stay private."""
import argparse, ctypes, ctypes.wintypes as wt, datetime, hashlib, json, pathlib, subprocess, time, threading
class PMC(ctypes.Structure):
 _fields_=[("cb",wt.DWORD),("PageFaultCount",wt.DWORD)]+[(name,ctypes.c_size_t) for name in ("PeakWorkingSetSize","WorkingSetSize","QuotaPeakPagedPoolUsage","QuotaPagedPoolUsage","QuotaPeakNonPagedPoolUsage","QuotaNonPagedPoolUsage","PagefileUsage","PeakPagefileUsage","PrivateUsage")]
psapi=ctypes.WinDLL("psapi",use_last_error=True)
psapi.GetProcessMemoryInfo.argtypes=[wt.HANDLE,ctypes.POINTER(PMC),wt.DWORD]
psapi.GetProcessMemoryInfo.restype=wt.BOOL
kernel=ctypes.WinDLL("kernel32",use_last_error=True)
kernel.GetProcessTimes.argtypes=[wt.HANDLE]+[ctypes.POINTER(wt.FILETIME)]*4
kernel.GetProcessTimes.restype=wt.BOOL
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
 return h.hexdigest()
def run_measure(label,args):
 start=time.perf_counter(); peak_ws=peak_commit=peak_private=0; cpu=0; samples=0
 with (OUT/(label+".stdout.log")).open("wb") as so, (OUT/(label+".stderr.log")).open("wb") as se:
  proc=subprocess.Popen([str(x) for x in args],stdout=so,stderr=se,creationflags=subprocess.CREATE_NO_WINDOW)
  handle=wt.HANDLE(int(proc._handle))
  while True:
   c=PMC();c.cb=ctypes.sizeof(c)
   if psapi.GetProcessMemoryInfo(handle,ctypes.byref(c),c.cb):
    samples+=1;peak_ws=max(peak_ws,c.PeakWorkingSetSize);peak_commit=max(peak_commit,c.PeakPagefileUsage);peak_private=max(peak_private,c.PrivateUsage)
   f=[wt.FILETIME() for _ in range(4)]
   if kernel.GetProcessTimes(handle,*[ctypes.byref(x) for x in f]):
    val=lambda v:(v.dwHighDateTime<<32)|v.dwLowDateTime
    cpu=(val(f[2])+val(f[3]))/1e7
   if proc.poll() is not None:break
   if time.perf_counter()-start>1800:
    proc.kill();proc.wait();raise RuntimeError("timeout "+label)
   time.sleep(.02)
  code=proc.wait()
 elapsed=time.perf_counter()-start
 result={"label":label,"argv":[str(x) for x in args],"exit_code":code,"elapsed_seconds":elapsed,"cpu_seconds":cpu,"peak_working_set_bytes":peak_ws,"peak_pagefile_bytes":peak_commit,"max_sampled_private_bytes":peak_private,"memory_samples":samples,"sampling_interval_seconds":.02}
 (OUT/(label+".metrics.json")).write_text(json.dumps(result,indent=2),encoding="utf-8")
 if code:raise RuntimeError("failed "+label+"; see stderr")
 print(json.dumps({k:v for k,v in result.items() if k != "argv"}),flush=True)
 return result

def main():
 global OUT
 ap=argparse.ArgumentParser()
 for flag in ['cpu','cuda','base','small','audio','vad-model','output']:
  ap.add_argument('--'+flag,required=True,type=pathlib.Path)
 ap.add_argument('--runs',type=int,default=3)
 args=ap.parse_args()
 OUT=args.output; OUT.mkdir(parents=True,exist_ok=True)
 report={'created':datetime.datetime.now().astimezone().isoformat(),
         'audio_sha256':sha(args.audio), 'audio_bytes':args.audio.stat().st_size,
         'vad_sha256':sha(args.vad_model), 'runs':[], 'gpu_memory_scope':'whole device, MiB, nvidia-smi ~100ms; includes other apps'}
 gpu_values=[]; stop=threading.Event()
 monitor=subprocess.Popen(['nvidia-smi','--query-gpu=memory.used','--format=csv,noheader,nounits','--loop-ms=100'],
                          stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW)
 def read_gpu():
  for line in monitor.stdout:
   try: gpu_values.append(int(line.strip()))
   except ValueError: pass
 thread=threading.Thread(target=read_gpu,daemon=True);thread.start()
 try:
  for backend in ['cpu','cuda']:
   cli=getattr(args,backend)
   report[backend+'_cli_sha256']=sha(cli)
   for model in ['base','small']:
    modelpath=getattr(args,model)
    report[model+'_sha256']=sha(modelpath)
    for n in range(1,args.runs+1):
     label=f'{model}-{backend}-{n}'
     before=len(gpu_values)
     result=run_measure(label,[cli,'-m',modelpath,'-f',args.audio,'-l','pt','-t','4','-ojf','-of',OUT/label,'--vad','-vm',args.vad_model]+(['-ng'] if backend=='cpu' else []))
     result.pop('argv',None)
     result.update(model=model,backend=backend,run=n,gpu_device_peak_mib=max(gpu_values[before:] or [0]))
     log=(OUT/(label+'.stderr.log')).read_text(encoding='utf8',errors='replace')
     result['requested_backend'] = backend
     result['actual_backend'] = 'cuda' if 'using CUDA' in log else 'cpu'
     result['backend_evidence']=[line for line in log.splitlines() if any(x in line.lower() for x in ['using device','using cuda','no gpu','loaded cuda','found 1 cuda'])]
     report['runs'].append(result)
     (OUT/'report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf8')
 finally:
  monitor.terminate(); monitor.wait(timeout=5); stop.set()
 print('DONE',flush=True)
if __name__=='__main__': main()
