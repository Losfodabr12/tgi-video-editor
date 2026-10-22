from pathlib import Path
import ctypes
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import argparse
import xml.etree.ElementTree as ET
import urllib.request
import zipfile

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser()
parser.add_argument('--work-dir',type=Path,default=root/'source/tools/.downloads/vulkan-b5454')
parser.add_argument('--tools-root',type=Path,default=root/'source/tools')
options=parser.parse_args()
work=options.work_dir.resolve()
work.mkdir(parents=True,exist_ok=True)
manifest={}
INPUTS={'whisper-b5454-source.zip': {'url': 'https://codeload.github.com/ggml-org/whisper.cpp/zip/d1be6fde11ac6e0407606b4e42fe72d34add8037', 'bytes': 10802365, 'sha256': '6be93b881acb415c5a25d0ef85bb6a488099de0296e072e22a66d50f20ec40b9'}, 'vulkan-headers-1.4.357.zip': {'url': 'https://codeload.github.com/KhronosGroup/Vulkan-Headers/zip/refs/tags/vulkan-sdk-1.4.357.0', 'bytes': 3412609, 'sha256': 'bc7925a17854a9bac9433309e8df88a701ef1d49d2020fff6db9407b637ea840'}, 'spirv-headers-1.4.357.zip': {'url': 'https://codeload.github.com/KhronosGroup/SPIRV-Headers/zip/refs/tags/vulkan-sdk-1.4.357.0', 'bytes': 667873, 'sha256': '7d40c8c1983c1aba6f6f2fcbcf7be345d33a5693aeee0cc5b8c579fb8e3f2fea'}, 'shaderc-windows-release.zip': {'url': 'https://storage.googleapis.com/shaderc/artifacts/prod/graphics_shader_compiler/shaderc/windows-vs2022-amd64-release/continuous/49/20261021-084415/install.zip', 'bytes': 231571498, 'sha256': '54ad65fb8beea082554553d09d4104192b711cbfc4c5e1f16a72f39beb7c0f3b'}}
COMMIT='d1be6fde11ac6e0407606b4e42fe72d34add8037'
def fetch(url,filename):
    path=work/filename
    if not path.is_file():
        request=urllib.request.Request(url,headers={'User-Agent':'tgi-video-editor-validation'})
        with urllib.request.urlopen(request,timeout=120) as response,path.open('wb') as out:
            shutil.copyfileobj(response,out,4*1024*1024)
    with path.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    if digest != INPUTS[filename]['sha256']:raise RuntimeError('SHA-256 mismatch: '+filename)
    manifest[filename]={'url':url,'bytes':path.stat().st_size,'sha256':digest}
    print(f'Fetched {filename}: {path.stat().st_size} bytes',flush=True)
    return path

def unpack_zip(archive,destination):
    destination.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as zipped:
        for item in zipped.infolist():
            parts=Path(item.filename).parts[1:]
            if not parts:continue
            target=destination.joinpath(*parts)
            assert target.resolve().is_relative_to(destination.resolve())
            if item.is_dir():target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                with zipped.open(item) as source,target.open('wb') as out:shutil.copyfileobj(source,out)

commit=COMMIT
manifest['whisper_ref']={'tag':'b5454','commit':commit}
source_zip=fetch(INPUTS['whisper-b5454-source.zip']['url'],'whisper-b5454-source.zip')
headers_zip=fetch(INPUTS['vulkan-headers-1.4.357.zip']['url'],'vulkan-headers-1.4.357.zip')
spirv_zip=fetch(INPUTS['spirv-headers-1.4.357.zip']['url'],'spirv-headers-1.4.357.zip')
shader_archive=fetch(INPUTS['shaderc-windows-release.zip']['url'],'shaderc-windows-release.zip')
source=work/'whisper-src'
headers=work/'vulkan-headers'
spirv=work/'spirv-headers'
if not (source/'CMakeLists.txt').is_file():unpack_zip(source_zip,source)
if not (headers/'include/vulkan/vulkan.hpp').is_file():unpack_zip(headers_zip,headers)
if not (spirv/'CMakeLists.txt').is_file():unpack_zip(spirv_zip,spirv)
toolchain=work/'toolchain'
(toolchain/'bin').mkdir(parents=True,exist_ok=True)
(toolchain/'lib').mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(shader_archive) as archive:
    for member in archive.infolist():
        if not member.is_dir() and (Path(member.filename).name == 'glslc.exe' or member.filename.lower().endswith('.dll')):
            with archive.open(member) as stream,(toolchain/'bin'/Path(member.filename).name).open('wb') as out:shutil.copyfileobj(stream,out)
assert (toolchain/'bin/glslc.exe').is_file()

# Link-time import library only. The installed GPU driver supplies the loader.
# Registry declarations avoid requiring a GPU or Vulkan SDK on CI builders.
registry=ET.parse(headers/'registry/vk.xml')
names=sorted({node.text for node in registry.findall('./commands/command/proto/name')})
(toolchain/'lib/vulkan-1.def').write_text('LIBRARY vulkan-1.dll\nEXPORTS\n'+'\n'.join(names)+'\n',encoding='ascii')

vswhere=Path(r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe')
vs=Path(subprocess.check_output([str(vswhere),'-latest','-products','*','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip())
vsdev=vs/'Common7/Tools/VsDevCmd.bat'
command=f'"{vsdev}" -arch=x64 -host_arch=x64 -no_logo >nul && set'
env_result=subprocess.run(command,shell=True,capture_output=True,text=True,check=True)
build_env={key.upper():value for key,value in os.environ.items()}
for line in env_result.stdout.splitlines():
    if '=' in line and not line.startswith('='):
        key,value=line.split('=',1);build_env[key.upper()]=value
cmake=vs/'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
ninja=vs/'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe'
build_env['PATH']=str(ninja.parent)+';'+str(toolchain/'bin')+';'+build_env['PATH']
assert not Path('R:/').exists(),'Build drive R: already occupied'
subprocess.run(['subst.exe','R:',str(work)],check=True)
try:
    def run(label,argv):
        with (work/(label+'.log')).open('wb') as log:
            result=subprocess.run([str(arg) for arg in argv],env=build_env,stdout=log,stderr=log)
        if result.returncode:raise RuntimeError(f'{label} failed ({result.returncode}); inspect private log')
        print(label+' completed',flush=True)
    run('vulkan-import-library',[shutil.which('lib.exe',path=build_env['PATH']),'/nologo','/machine:x64','/def:R:/toolchain/lib/vulkan-1.def','/out:R:/toolchain/lib/vulkan-1.lib'])
    run('spirv-configure',[cmake,'-S','R:/spirv-headers','-B','R:/spirv-build','-G','Ninja','-DCMAKE_INSTALL_PREFIX=R:/toolchain','-DSPIRV_HEADERS_SKIP_EXAMPLES=ON'])
    run('spirv-install',[cmake,'--install','R:/spirv-build'])
    shutil.copytree(headers/'include',toolchain/'include',dirs_exist_ok=True)
    args=[cmake,'-S','R:/whisper-src','-B','R:/whisper-build','-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DGGML_VULKAN=ON','-DGGML_CUDA=OFF','-DGGML_NATIVE=OFF','-DGGML_CPU_ALL_VARIANTS=OFF','-DGGML_BACKEND_DL=ON','-DWHISPER_BUILD_IS_DEV=OFF','-DWHISPER_BUILD_TESTS=OFF','-DWHISPER_BUILD_EXAMPLES=ON','-DWHISPER_BUILD_SERVER=OFF','-DWHISPER_SDL2=OFF','-DVulkan_INCLUDE_DIR=R:/toolchain/include','-DVulkan_LIBRARY=R:/toolchain/lib/vulkan-1.lib','-DVulkan_GLSLC_EXECUTABLE=R:/toolchain/bin/glslc.exe','-DSPIRV-Headers_DIR=R:/toolchain/share/cmake/SPIRV-Headers']
    manifest['cmake_arguments']=[str(arg) for arg in args]
    (work/'vulkan-build-provenance.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    run('whisper-vulkan-configure',args)
    run('whisper-vulkan-build',[cmake,'--build','R:/whisper-build','--target','whisper-cli','ggml-vulkan','ggml-cpu','--parallel','4'])
    if not (work/'vulkan-probe.exe').is_file() or (work/'vulkan-probe.exe').stat().st_mtime < (root/'tool/vulkan_probe.cpp').stat().st_mtime:
        run('vulkan-probe-build',[shutil.which('cl.exe',path=build_env['PATH']),'/nologo','/std:c++17','/EHsc','/O2','/MD',str(root/'tool/vulkan_probe.cpp'),'/I'+str(source/'ggml/include'),'/Fo'+str(work/'vulkan-probe.obj'),'/Fe'+str(work/'vulkan-probe.exe'),'/link','/LIBPATH:R:/whisper-build/src','/LIBPATH:R:/whisper-build/ggml/src','ggml.lib','ggml-base.lib'])
finally:
    subprocess.run(['subst.exe','R:','/D'],check=True)

runtime=work/'vulkan-runtime'
runtime.mkdir(exist_ok=True)
shutil.copy2(work/'vulkan-probe.exe',runtime/'vulkan-probe.exe')
for name in ['whisper-cli.exe','whisper.dll','ggml.dll','ggml-base.dll','ggml-cpu.dll','ggml-vulkan.dll']:
    candidate=work/'whisper-build/bin'/name
    assert candidate.is_file(),str(candidate)
    shutil.copy2(candidate,runtime/name)
files=[{'name':path.name,'bytes':path.stat().st_size} for path in runtime.iterdir() if path.is_file()]
archive=work/'whisper-b5454-vulkan-runtime.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as zipped:
    for path in runtime.iterdir():zipped.write(path,arcname=path.name)
manifest['runtime_files']=files
manifest['runtime_bytes']=sum(item['bytes'] for item in files)
manifest['runtime_zip_bytes']=archive.stat().st_size
(work/'vulkan-build-provenance.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('VULKAN_BUILD_COMPLETE: runtime '+str(manifest['runtime_bytes'])+' bytes; ZIP '+str(archive.stat().st_size)+' bytes.',flush=True)

# The compiled app receives this exact manifest via --dart-define, not an
# editable runtime manifest. Each distributed DLL and executable is checked.
digests={path.name:hashlib.file_digest(path.open('rb'),'sha256').hexdigest() for path in runtime.iterdir() if path.is_file()}
assert sum(path.stat().st_size for path in runtime.iterdir() if path.is_file()) <= 50_000_000, 'Runtime exceeds the bundled GPU budget'
destination=options.tools_root.resolve()/'whisper/vulkan/bin'
destination.mkdir(parents=True,exist_ok=True)
for path in runtime.iterdir():shutil.copy2(path,destination/path.name)
(destination.parent/'manifest.json').write_text(json.dumps(digests,sort_keys=True),encoding='utf8')
(destination.parent/'provenance.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('Vulkan runtime installed (SHA-256 verified build inputs and measured output manifest).',flush=True)

license_root=destination.parent/'licenses'
license_root.mkdir(exist_ok=True)
for name,path in {
    'whisper.cpp-MIT.txt': source/'LICENSE',
    'Vulkan-Headers-LICENSE.md': headers/'LICENSE.md',
    'Vulkan-Headers-Apache-2.0.txt': headers/'LICENSES/Apache-2.0.txt',
    'Vulkan-Headers-MIT.txt': headers/'LICENSES/MIT.txt',
    'SPIRV-Headers-MIT.txt': spirv/'LICENSE',
}.items():
    shutil.copy2(path,license_root/name)
print('Pinned upstream notices included in the runtime package.',flush=True)
