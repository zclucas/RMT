"""Fetch the pinned licensed base and prepare the editable authoring scene."""
from pathlib import Path
import hashlib,json,os,shutil,struct,sys,urllib.request
import bpy

experiment=Path(__file__).resolve().parents[1]
root=Path(os.environ['RMT_MODEL_WORKSPACE']).resolve()
source=root/'source';output=root/'output'
(source/'textures').mkdir(parents=True,exist_ok=True)
(source/'custom').mkdir(exist_ok=True)
(output/'route-a').mkdir(parents=True,exist_ok=True)
manifest=json.loads((experiment/'source-manifest.json').read_text(encoding='utf-8'))
path=source/'AvatarSample_B.vrm'
if not path.exists():
 request=urllib.request.Request(manifest['base']['url'],headers={'User-Agent':'RMT-model-authoring'})
 with urllib.request.urlopen(request,timeout=120) as response:
  path.write_bytes(response.read())
raw=path.read_bytes()
if hashlib.sha256(raw).hexdigest()!=manifest['base']['sha256']:
 raise RuntimeError('The base-model SHA-256 does not match the pinned source.')
size=struct.unpack_from('<I',raw,12)[0]
doc=json.loads(raw[20:20+size]);binary_start=28+size;images=[]
for i,image in enumerate(doc['images']):
 view=doc['bufferViews'][image['bufferView']]
 start=binary_start+view.get('byteOffset',0);name='image-%02d.png'%i
 (source/'textures'/name).write_bytes(raw[start:start+view['byteLength']]);images.append(name)
mapping={}
for material in doc['materials']:
 texture=material.get('pbrMetallicRoughness',{}).get('baseColorTexture')
 if texture:mapping[material['name']]=images[doc['textures'][texture['index']]['source']]
(source/'material-textures.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copy2(experiment/'Art/iris-brown.png',source/'custom/iris-brown-v1.png')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(path))
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
bones=[{'name':b.name,'head':list(arm.matrix_world@b.head_local),'tail':list(arm.matrix_world@b.tail_local),'parent':b.parent.name if b.parent else None} for b in arm.data.bones]
(output/'template-analysis.json').write_text(json.dumps({'bones':bones},indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(source/'Template.blend'),compress=True)
print('Prepared verified source model and original embedded textures.',flush=True)
sys.stdout.flush();os._exit(0)
