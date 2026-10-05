"""先核验引擎user隔离，再测HD2D独立资产与旧可达范围。"""
import os,re,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='ssa-hd2d-') as tmp:
 root=Path(tmp);env=os.environ.copy()
 for key,name in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache'),('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
  p=root/name;p.mkdir();env[key]=str(p)
 env.update(RPG_TEST_ROOT=str(root),RPG_TEST_ISOLATED='0')
 def run(script):
  result=subprocess.run([os.environ.get('GODOT_BIN','godot'),'--headless','--path',str(ROOT),'--script',script],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
  print(result.stdout,end='');return result
 r=run('res://tools/rpg/test_environment.gd');paths=re.findall(r'^RPG_ISOLATION_OK:(.*)$',r.stdout,re.M)
 if r.returncode or len(paths)!=1 or not Path(paths[0]).resolve().is_relative_to(root):raise SystemExit('隔离失败，不运行HD2D检查')
 env['RPG_TEST_ISOLATED']='1';r=run('res://tools/campaign/test_night02_hd2d_spatial.gd')
 raise SystemExit(1 if r.returncode or re.search(r'(^|\n)(SCRIPT ERROR|ERROR):',r.stdout) else 0)
