"""Bind the neutral models. This creates no motion/dance clips."""
from pathlib import Path
import bpy,json,struct,math,sys,os
sys.dont_write_bytecode=True
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fit_coordinates import headwarp,bodywarp,armwarp,targets
R=Path(os.environ['RMT_MODEL_WORKSPACE']).resolve()
route=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'route-a'
folder=R/'output'/route
src=next(folder.glob('*Route*.blend'))
bpy.ops.wm.open_mainfile(filepath=str(src))
source_bones=json.loads((R/'output/template-analysis.json').read_text())['bones']
byname={b['name']:b for b in source_bones}
raw=(R/'source/AvatarSample_B.vrm').read_bytes();n=struct.unpack_from('<I',raw,12)[0];vrm=json.loads(raw[20:20+n])
human={k:vrm['nodes'][v['node']]['name'] for k,v in vrm['extensions']['VRMC_vrm']['humanoid']['humanBones'].items()}
human.pop('leftEye',None);human.pop('rightEye',None);names=set(human.values())
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
data=bpy.data.armatures.new('RuoMengTu_Humanoid');rig=bpy.data.objects.new('RuoMengTu_ExperimentalRig',data);bpy.context.collection.objects.link(rig);rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
root=data.edit_bones.new('Root');root.head=(0,0,0);root.tail=(0,0,.15)
def fit(p,name):
 if any(k in name for k in ['UpperArm','LowerArm','Hand','Thumb','Index','Middle','Ring','Little']):return armwarp(Vector(p),1 if '_L_' in name else -1)
 if 'Shoulder' in name:
  v=bodywarp(Vector(p));v.x*=.85;return v
 if any(k in name for k in ['Head','FaceEye']):return headwarp(Vector(p))
 return bodywarp(Vector(p))
for source in source_bones:
 name=source['name']
 if name not in names:continue
 bone=data.edit_bones.new(name);bone.head=fit(source['head'],name);bone.tail=fit(source['tail'],name)
 if (bone.tail-bone.head).length<.001:bone.tail=bone.head+Vector((0,0,.015))
for name in names:
 source=byname[name];parent=source['parent']
 while parent and parent not in names:parent=byname[parent]['parent']
 data.edit_bones[name].parent=data.edit_bones.get(parent) if parent else root
 # Use the next joint as the endpoint to eliminate discontinuous joint axes.
 children=[b for b in source_bones if b['parent']==name and b['name'] in names]
 if children:
  preferred=children[0]
  if 'Hand' in name:preferred=next((b for b in children if 'Middle1' in b['name']),preferred)
  if name.endswith('Head'):preferred=None
  if preferred:
   endpoint=fit(preferred['head'],preferred['name'])
   if (endpoint-data.edit_bones[name].head).length>.002:data.edit_bones[name].tail=endpoint
 # Finger curls use a common palm normal, stable for both hands.
 if any(k in name for k in ['Thumb','Index','Middle','Ring','Little']):data.edit_bones[name].align_roll(Vector((0,-1,0)))
ear_paths={
 'upright':[(-.083,.015,1.806),(-.101,.015,1.879),(-.119,.019,1.963),(-.130,.020,2.030)],
 'bent':[(.078,.018,1.810),(.102,.016,1.922),(.146,.009,1.939),(.197,.004,1.879)]}
for side,points in ear_paths.items():
 parent=data.edit_bones[human['head']]
 for i in range(3):
  b=data.edit_bones.new('Ruo_Ear_'+side+'_'+str(i+1));b.head=points[i];b.tail=points[i+1];b.parent=parent;parent=b
for i,(a,b) in enumerate([((0,.135,.915),(0,.175,.915)),((0,.175,.915),(0,.232,.915))]):
 bone=data.edit_bones.new('Ruo_Tail_'+str(i+1));bone.head=a;bone.tail=b;bone.parent=data.edit_bones[human['hips']] if i==0 else data.edit_bones['Ruo_Tail_1']
hair_chains={}
for ob in objects:
 if not any(ob.name.startswith('RuoMengTu_'+part) for part in ['BobLock_','Fringe_','Temple_']) or 'Contour' in ob.name:continue
 points=[ob.matrix_world@v.co for v in ob.data.vertices];low=min(p.z for p in points);high=max(p.z for p in points)
 def center_at(z):
  closest=sorted(points,key=lambda p:abs(p.z-z))[:16];return sum(closest,Vector())/len(closest)
 path=[center_at(high-.045),center_at((high+low)/2),center_at(low+.003)];label=ob.name.removeprefix('RuoMengTu_');bone_names=[];parent=data.edit_bones[human['head']]
 for i in range(2):
  name='Ruo_Hair_'+label+'_'+str(i+1);b=data.edit_bones.new(name);b.head=path[i];b.tail=path[i+1];b.parent=parent;parent=b;bone_names.append(name)
 hair_chains[ob.name]={'bones':bone_names,'points':[list(p) for p in path]}
bpy.ops.object.mode_set(mode='OBJECT')
rig.show_in_front=True;data.display_type='OCTAHEDRAL'
def blend(a,b,t):
 t=max(0,min(1,t));t=t*t*(3-2*t)
 return {a:1-t,b:t}
def torso(p):
 z=p.z
 keys=[(.96,human['hips']),(1.095,human['spine']),(1.235,human['chest']),(1.385,human['upperChest'])]
 if z<=keys[0][0]:return {keys[0][1]:1}
 for (za,a),(zb,b) in zip(keys,keys[1:]):
  if z<=zb:return blend(a,b,(z-za)/(zb-za))
 return {human['upperChest']:1}
def garment(p):
 # The front hem follows a lifted thigh; the rear stays attached at the tail.
 weights=torso(p);front=max(0,min(1,(.12-p.y)/.20));amount=max(0,min(.85,(1.05-p.z)/.18*.85))*front
 if amount<=0:return weights
 lr=max(0,min(1,(p.x+.040)/.080));weights={n:w*(1-amount) for n,w in weights.items()}
 weights[human['leftUpperLeg']]=amount*lr;weights[human['rightUpperLeg']]=amount*(1-lr)
 return weights
def arm(p):
 sign=1 if p.x>=0 else -1;side='left' if sign>0 else 'right';sh,el,wr=targets[sign]
 axis=(wr-sh).normalized();d=(p-sh).dot(axis);joint=(el-sh).dot(axis)
 return blend(human[side+'UpperArm'],human[side+'LowerArm'],(d-joint+.065)/.13)
def leg(p):
 side='left' if p.x>=0 else 'right'
 if p.z<.17:return blend(human[side+'Foot'],human[side+'LowerLeg'],(p.z-.115)/.08)
 return blend(human[side+'LowerLeg'],human[side+'UpperLeg'],(p.z-.42)/.14)
def ear(p,side):
 points=[Vector(v) for v in ear_paths[side]];best=(1e9,0,0)
 for i,(a,b) in enumerate(zip(points,points[1:])):
  axis=b-a;t=max(0,min(1,(p-a).dot(axis)/axis.length_squared));distance=(p-(a+axis*t)).length
  if distance<best[0]:best=(distance,i,t)
 _,i,t=best
 if i==0:return blend('Ruo_Ear_'+side+'_1','Ruo_Ear_'+side+'_2',max(0,(t-.65)/.7))
 if i==1:return blend('Ruo_Ear_'+side+'_2','Ruo_Ear_'+side+'_3',max(0,(t-.65)/.7))
 return {'Ruo_Ear_'+side+'_3':1}
stats=[]
for ob in objects:
 # Preserve expert-authored hand/leg weighting wherever topology is retained.
 old={v.index:{ob.vertex_groups[g.group].name:g.weight for g in v.groups if ob.vertex_groups[g.group].name in names} for v in ob.data.vertices}
 ob.vertex_groups.clear();groups={name:ob.vertex_groups.new(name=name) for name in data.bones.keys()};maxerr=0;unbound=0;fingerverts=0
 eye_ids={i for p in ob.data.polygons if p.material_index in [1,2] for i in p.vertices} if ob.name=='RuoMengTu_Face' else set()
 for v in ob.data.vertices:
  p=ob.matrix_world@v.co;name=ob.name
  if name=='RuoMengTu_Face':weights={human['head']:1}
  elif 'EarInner_' in name or 'Ear_' in name:weights=ear(p,'upright' if 'upright' in name else 'bent')
  elif 'BackTail' in name:weights={'Ruo_Tail_2':1}
  elif any(k in name for k in ['BobLock','Fringe','Temple']):
   key=next(k for k in hair_chains if name==k or name.startswith(k+'_'));chain=hair_chains[key];a,b=chain['bones'];za,zm,zb=[p[2] for p in chain['points']]
   weights=blend(human['head'],a,(za+.025-p.z)/(za+.025-zm)) if p.z>=zm else blend(a,b,(zm-p.z)/max(.001,zm-zb))
  elif 'BobHair' in name:weights={human['head']:1}
  elif 'Neck' in name:weights=blend(human['neck'],human['head'],(p.z-1.46)/.065)
  elif 'BodySkin' in name or 'FiveFingerHands' in name:
   weights=old[v.index] or (arm(p) if abs(p.x)>.25 else leg(p))
   if any(any(f in g for f in ['Thumb','Index','Middle','Ring','Little']) for g in weights):fingerverts+=1
  elif 'Sneaker' in name:weights={human['leftFoot' if p.x>0 else 'rightFoot']:1}
  elif 'Sleeve_' in name:weights=arm(p)
  elif 'ReconstructedClothing' in name:
   if p.z<.78:weights=leg(p)
   elif abs(p.x)>.21 and p.z>1.00:weights=arm(p)
   else:weights=garment(p)
  else:weights=garment(p)
  weights=dict(sorted(((n,w) for n,w in weights.items() if w>1e-6),key=lambda a:-a[1])[:4]);total=sum(weights.values())
  if total<=0:unbound+=1;weights={human['hips']:1};total=1
  for n,w in weights.items():groups[n].add([v.index],w/total,'REPLACE')
  maxerr=max(maxerr,abs(sum(w/total for w in weights.values())-1))
 mod=ob.modifiers.new('Experimental skeletal binding','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False;ob.parent=rig
 stats.append({'mesh':ob.name,'vertices':len(ob.data.vertices),'unbound':unbound,'weightError':maxerr,'fingerWeightedVertices':fingerverts})
rig['experiment']='Model and binding only; no dance or runtime integration';rig['humanoidMap']=json.dumps(human)
rig['hairChains']=json.dumps(hair_chains)
for name in ['hips','spine','chest','upperChest','neck','head']:
 data.bones[human[name]]['humanoid']=name
for name,points in ear_paths.items():rig['ear_'+name+'_joints']=3
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=rig
target=folder/'rigged';target.mkdir(exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(target/'RuoMengTu-Rigged.blend'),compress=True)
# Keep editable pieces in the saved scene, but join solid export copies. Face
# morphs remain separate so their data is not repeated for the entire body.
bpy.ops.object.select_all(action='DESELECT');copies=[]
for original in objects:
 if original.name=='RuoMengTu_Face':continue
 duplicate=original.copy();duplicate.data=original.data.copy();bpy.context.collection.objects.link(duplicate);duplicate.select_set(True);copies.append(duplicate)
active=next(o for o in copies if o.name.startswith('RuoMengTu_BodySkin'))
bpy.context.view_layer.objects.active=active;bpy.ops.object.join();body_export=bpy.context.object;body_export.name='RuoMengTu_Body'
bpy.ops.object.select_all(action='DESELECT');body_export.select_set(True);bpy.data.objects['RuoMengTu_Face'].select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
path=target/'RuoMengTu-Rigged.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_yup=True)
raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n])
for m in doc['materials']:
 factor=None
 if m['name']=='Ruo_BrownIris':factor=[1,1,1,1]
 if m['name'].startswith('Ruo_Eyeline_'):factor=[.30,.22,.20,1]
 if factor:m['pbrMetallicRoughness']['baseColorFactor']=factor
payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4);rest=raw[20+n:];path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(payload)+len(rest))+struct.pack('<I4s',len(payload),b'JSON')+payload+rest)
report={'bones':len(data.bones),'humanoidBones':len(human),'fingerChains':10,'fingerJointsPerChain':3,'earJointsPerEar':3,'tailJoints':2,'hairChains':len(hair_chains),'hairJointsPerChain':2,'exportMeshes':2,'meshes':stats,'danceClips':0,'humanoid':human}
(target/'binding-report.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['meshes','humanoid']}),flush=True);sys.stdout.flush();os._exit(0)
