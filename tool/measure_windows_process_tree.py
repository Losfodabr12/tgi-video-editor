import ctypes
from ctypes import wintypes as W
import threading,time,sys,os,json,argparse
from pathlib import Path
import psutil

class CounterValue(ctypes.Structure):
    _fields_=[('status',W.DWORD),('value',ctypes.c_longlong)]
class CounterItem(ctypes.Structure):
    _fields_=[('name',W.LPWSTR),('value',CounterValue)]
class GpuMemory:
    def __init__(self):
        self.dll=ctypes.WinDLL('pdh.dll');self.query=W.HANDLE();self.counter=W.HANDLE()
        self.dll.PdhOpenQueryW.argtypes=[W.LPCWSTR,ctypes.c_size_t,ctypes.POINTER(W.HANDLE)]
        self.dll.PdhAddEnglishCounterW.argtypes=[W.HANDLE,W.LPCWSTR,ctypes.c_size_t,ctypes.POINTER(W.HANDLE)]
        self.dll.PdhCollectQueryData.argtypes=[W.HANDLE]
        self.dll.PdhGetFormattedCounterArrayW.argtypes=[W.HANDLE,W.DWORD,ctypes.POINTER(W.DWORD),ctypes.POINTER(W.DWORD),ctypes.c_void_p]
        self.dll.PdhCloseQuery.argtypes=[W.HANDLE]
        assert self.dll.PdhOpenQueryW(None,0,ctypes.byref(self.query))==0
        assert self.dll.PdhAddEnglishCounterW(self.query,r'\GPU Process Memory(*)\Dedicated Usage',0,ctypes.byref(self.counter))==0
    def sample(self):
        self.dll.PdhCollectQueryData(self.query)
        size=W.DWORD();count=W.DWORD()
        self.dll.PdhGetFormattedCounterArrayW(self.counter,0x400,ctypes.byref(size),ctypes.byref(count),None)
        if not size.value:return {}
        buffer=ctypes.create_string_buffer(size.value)
        code=self.dll.PdhGetFormattedCounterArrayW(self.counter,0x400,ctypes.byref(size),ctypes.byref(count),buffer)
        if code!=0:return {}
        items=ctypes.cast(buffer,ctypes.POINTER(CounterItem));result={}
        for i in range(count.value):
            item=items[i]
            if item.value.status not in (0,1):continue
            name=item.name
            if not name.startswith('pid_'):continue
            pid=int(name.split('_')[1]);result[pid]=result.get(pid,0)+max(0,item.value.value)
        return result
    def close(self):self.dll.PdhCloseQuery(self.query)
class Monitor:
    def __init__(self,pid):
        self.root=psutil.Process(pid);self.stop=threading.Event();self.peak_ram=0;self.peak_private=0;self.peak_engine_ram=0;self.peak_vram=0;self.peak_engine_vram=0;self.samples=0;self.engine_pids=set();self.gpu=GpuMemory()
    def loop(self):
        while not self.stop.is_set():
            processes=[self.root]+self.root.children(recursive=True)
            owned=set();rss=private=0
            for process in processes:
                if process.pid == os.getpid():continue
                try:
                    owned.add(process.pid);memory=process.memory_info();rss+=memory.rss;private+=memory.private
                    if process.name().lower()=='whisper-cli.exe':
                        self.engine_pids.add(process.pid);self.peak_engine_ram=max(self.peak_engine_ram,memory.rss)
                except (psutil.NoSuchProcess,psutil.AccessDenied):pass
            gpu=self.gpu.sample();self.peak_vram=max(self.peak_vram,sum(gpu.get(pid,0) for pid in owned));self.peak_engine_vram=max(self.peak_engine_vram,sum(gpu.get(pid,0) for pid in self.engine_pids))
            self.peak_ram=max(self.peak_ram,rss);self.peak_private=max(self.peak_private,private);self.samples+=1
            self.stop.wait(0.1)
    def __enter__(self):
        self.started=time.perf_counter();self.thread=threading.Thread(target=self.loop,daemon=True);self.thread.start();return self
    def __exit__(self,*args):
        self.seconds=time.perf_counter()-self.started;self.stop.set();self.thread.join(3);self.gpu.close()
    def metrics(self):return dict(seconds=self.seconds,tree_peak_rss_bytes=self.peak_ram,tree_peak_private_bytes=self.peak_private,engine_peak_rss_bytes=self.peak_engine_ram,tree_peak_dedicated_gpu_bytes=self.peak_vram,engine_peak_dedicated_gpu_bytes=self.peak_engine_vram,sample_interval_ms=100,samples=self.samples,engine_pids=sorted(self.engine_pids))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description='Sample Windows app/child RAM and dedicated GPU process memory; requires psutil.')
    parser.add_argument('--pid',type=int,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--stop-file',type=Path,required=True)
    parser.add_argument('--timeout',type=float,default=600)
    args=parser.parse_args()
    with Monitor(args.pid) as measure:
        args.output.with_suffix('.ready').write_text('ready')
        deadline=time.monotonic()+args.timeout
        while not args.stop_file.exists() and time.monotonic()<deadline:time.sleep(.05)
    args.output.write_text(json.dumps(measure.metrics(),indent=2),encoding='utf8')
