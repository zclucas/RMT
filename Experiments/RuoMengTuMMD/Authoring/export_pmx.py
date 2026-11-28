"""Export the bound neutral model to PMX 2.0; no motion is included."""
from pathlib import Path
import bpy,sys,os,json,math
from mathutils import Vector
R=Path(os.environ['RMT_MODEL_WORKSPACE']).resolve();
if os.environ.get('RMT_MODEL_PYMESHIO'):sys.path.insert(0,os.environ['RMT_MODEL_PYMESHIO'])
from pymeshio import pmx,common
from pymeshio.pmx import writer,reader
route=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'route-a';folder=R/'output'/route/'rigged';out=folder/'pmx';out.mkdir(exist_ok=True);(out/'textures').mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(folder/'RuoMengTu-Rigged.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
model=pmx.Model(name='若梦兔 · '+route,english_name='RuoMengTu '+route,comment='隔离建模与骨骼绑定实验。非最终角色；无舞蹈、无物理。基体来源与条款见模型目录说明。',english_comment='Isolated model/rig experiment. Modified pixiv AvatarSample_B base; see THIRD_PARTY_NOTICES. No dance or physics.');model.vertices=[];model.indices=[];model.materials=[];model.bones=[];model.morphs=[];model.display_slots=[];model.rigidbodies=[];model.joints=[]
def v3(p,scale=10):return common.Vector3(p[0]*scale,p[2]*scale,p[1]*scale)
def rgb(p):return common.RGB(*p[:3])
def srgb(p):return tuple(12.92*v if v<=.0031308 else 1.055*v**(1/2.4)-.055 for v in p[:3])
def jp(name):
 if name=='Root':return '全ての親'
 central={'Hips':'下半身','Spine':'上半身','Chest':'上半身2','UpperChest':'上半身3','Neck':'首','Head':'頭'}
 if name.startswith('J_Bip_C_'):return central[name[8:]]
 if name.startswith('J_Adj_'):return ('左' if '_L_' in name else '右')+'目'
 if name.startswith('J_Bip_'):
  side='左' if '_L_' in name else '右';part=name[8:];parts={'Shoulder':'肩','UpperArm':'腕','LowerArm':'ひじ','Hand':'手首','UpperLeg':'足','LowerLeg':'ひざ','Foot':'足首','ToeBase':'つま先'}
  if part in parts:return side+parts[part]
  for finger,label in [('Thumb','親指'),('Index','人指'),('Middle','中指'),('Ring','薬指'),('Little','小指')]:
   if part.startswith(finger):return side+label+'０１２３'[int(part[-1])-(1 if finger=='Thumb' else 0)]
 return name
bones=list(rig.data.bones);indices={b.name:(0 if i==0 else i+1) for i,b in enumerate(bones)}
for b in bones:
 flags=pmx.BONEFLAG_CAN_ROTATE|pmx.BONEFLAG_IS_VISIBLE|pmx.BONEFLAG_CAN_MANIPULATE
 if b.name=='Root':flags|=pmx.BONEFLAG_CAN_TRANSLATE
 bone=pmx.Bone(jp(b.name),b.name,v3(rig.matrix_world@b.head_local),indices[b.parent.name] if b.parent else -1,0,flags,tail_position=v3(b.tail_local-b.head_local));model.bones.append(bone)
center=1;model.bones.insert(1,pmx.Bone('センター','Center',v3(rig.data.bones['J_Bip_C_Hips'].head_local),indices['Root'],0,pmx.BONEFLAG_CAN_ROTATE|pmx.BONEFLAG_CAN_TRANSLATE|pmx.BONEFLAG_IS_VISIBLE|pmx.BONEFLAG_CAN_MANIPULATE,tail_position=common.Vector3(0,1,0)));model.bones[indices['J_Bip_C_Hips']].parent_index=center
for side,japanese in [('L','左'),('R','右')]:
 foot=indices['J_Bip_'+side+'_Foot'];knee=indices['J_Bip_'+side+'_LowerLeg'];thigh=indices['J_Bip_'+side+'_UpperLeg'];toe=indices['J_Bip_'+side+'_ToeBase'];controller=len(model.bones)
 flags=pmx.BONEFLAG_CAN_ROTATE|pmx.BONEFLAG_CAN_TRANSLATE|pmx.BONEFLAG_IS_VISIBLE|pmx.BONEFLAG_CAN_MANIPULATE|pmx.BONEFLAG_IS_IK
 ik=pmx.Ik(foot,40,.5,[pmx.IkLink(knee,1,common.Vector3(-math.radians(165),0,0),common.Vector3(-.00001,0,0)),pmx.IkLink(thigh,0)])
 model.bones.append(pmx.Bone(japanese+'足ＩＫ',side+' foot IK',model.bones[foot].position,indices['Root'],1,flags,tail_position=common.Vector3(0,.5,0),ik=ik))
 toeik=pmx.Ik(toe,8,.35,[pmx.IkLink(foot,0)])
 model.bones.append(pmx.Bone(japanese+'つま先ＩＫ',side+' toe IK',model.bones[toe].position,controller,2,flags,tail_position=common.Vector3(0,0,-.5),ik=toeik))
texture_index={};material_indices={};triangles={};mapping={}
flat_toon=bpy.data.images.new('Ruo_FlatToon',width=4,height=32,alpha=False);flat_toon.pixels[:]=[1.0]*(4*32*4);flat_toon.filepath_raw=str(out/'textures/toon-flat.png');flat_toon.file_format='PNG';flat_toon.save();flat_toon_index=len(model.textures);model.textures.append('textures/toon-flat.png')
def material_index(mat):
 if mat.name in material_indices:return material_indices[mat.name]
 shader=mat.node_tree.nodes.get('Principled BSDF');color=(.8,.8,.8,1);alpha=1;tex=-1
 if shader:color=shader.inputs['Base Color'].default_value;alpha=shader.inputs['Alpha'].default_value
 image=next((n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
 if image:
  key=image.name
  if key not in texture_index:
   name='textures/texture-%02d.png'%len(texture_index);image.filepath_raw=str(out/name);image.file_format='PNG';image.save();texture_index[key]=len(model.textures);model.textures.append(name)
  tex=texture_index[key]
  if shader.inputs['Base Color'].is_linked:color=(1,1,1,1)
 if mat.name=='Ruo_BrownIris':color=(1,1,1,1)
 if mat.name.startswith('Ruo_Eyeline_'):color=(*srgb((.30,.22,.20)),1)
 if mat.name=='Ruo_FaceSkinTint':color=(1,1,1,1) if image else (1,.845,.80,1)
 elif tex<0:color=(*srgb(color),1)
 index=len(model.materials);material_indices[mat.name]=index;triangles[index]=[]
 flat=any(s in mat.name for s in ['Skin','Iris','EyeWhite','Eyeline','Brows','IvoryHair','IvoryFur','InnerEars'])
 # Soft outlines on clothing/hair; facial planes are double sided without edges.
 face=any(s in mat.name for s in ['Iris','Eyeline','EyeWhite','Face','Brows','InnerEars','IvoryHair','HairContour']);flag=1|(0 if face else 16)
 model.materials.append(pmx.Material(mat.name,mat.name,rgb(color),alpha,1,rgb((0,0,0)),rgb(tuple(c*.18 for c in color[:3])),flag,common.RGBA(.18,.17,.20,1),.25 if not face else 0,tex,-1,0,0 if flat else 1,flat_toon_index if flat else 0,'Experimental toon material',0));return index
for ob in meshes:
 me=ob.data;me.calc_loop_triangles();uv=me.uv_layers[0] if me.uv_layers else None;lookup={};vertex_map={}
 for tri in me.loop_triangles:
  mat=me.materials[tri.material_index];mi=material_index(mat);face_indices=[]
  for vi,li in zip(tri.vertices,tri.loops):
   coord=tuple(uv.data[li].uv) if uv else (0,0);normal=me.corner_normals[li].vector;key=(vi,tuple(round(x,6) for x in coord),tuple(round(x,5) for x in normal))
   if key not in lookup:
    v=me.vertices[vi];weights=sorted([(indices[ob.vertex_groups[g.group].name],g.weight) for g in v.groups if ob.vertex_groups[g.group].name in indices and g.weight>1e-7],key=lambda p:-p[1])[:4]
    if not weights:weights=[(indices['Root'],1)]
    total=sum(w for _,w in weights);weights=[(i,w/total) for i,w in weights]
    if len(weights)==1:deform=pmx.Bdef1(weights[0][0])
    elif len(weights)==2:deform=pmx.Bdef2(weights[0][0],weights[1][0],weights[0][1])
    else:
     weights+= [(0,0)]*(4-len(weights));deform=pmx.Bdef4(*(i for i,w in weights),*(w for i,w in weights))
    index=len(model.vertices);lookup[key]=index;vertex_map.setdefault(vi,[]).append(index);model.vertices.append(pmx.Vertex(v3(ob.matrix_world@v.co),v3(ob.matrix_world.to_3x3()@normal,1),common.Vector2(coord[0],1-coord[1]),deform,1))
   face_indices.append(lookup[key])
  triangles[mi].extend(face_indices[::-1])
 mapping[ob.name]=vertex_map
 if me.shape_keys:
  base=me.shape_keys.key_blocks[0]
  for shape in list(me.shape_keys.key_blocks)[1:]:
   offsets=[]
   for vi,targets in vertex_map.items():
    delta=shape.data[vi].co-base.data[vi].co
    if delta.length>.000001:
     for index in targets:offsets.append(pmx.VertexMorphOffset(index,v3(ob.matrix_world.to_3x3()@delta)))
   if offsets:model.morphs.append(pmx.Morph(shape.name,shape.name,2 if 'EYE' in shape.name else 3 if 'MTH' in shape.name else 4,1,offsets))
for i,mat in enumerate(model.materials):
 ids=triangles[i]
 if mat.texture_index>=0 and mat.name!='Ruo_EyeWhite':
  faces=[ids[j:j+3] for j in range(0,len(ids),3)];faces.sort(key=lambda tri:sum(model.vertices[v].position.z for v in tri)/3,reverse=True);ids=[v for tri in faces for v in tri]
 model.indices.extend(ids);mat.vertex_count=len(ids)
model.display_slots=[pmx.DisplaySlot('Root','Root',1,[(0,indices['Root']),(0,center)]),pmx.DisplaySlot('表情','Expressions',1,[(1,i) for i in range(len(model.morphs))])]
for jp_label,en_label,predicate in [
 ('体','Body',lambda b:b.english_name.startswith('J_Bip_') and not any(f in b.english_name for f in ['Thumb','Index','Middle','Ring','Little'])),
 ('指','Fingers',lambda b:any(f in b.english_name for f in ['Thumb','Index','Middle','Ring','Little'])),
 ('髪','Hair',lambda b:b.english_name.startswith('Ruo_Hair_')),
 ('耳としっぽ','Ears and tail',lambda b:b.english_name.startswith(('Ruo_Ear_','Ruo_Tail_'))),
 ('足IK','Foot IK',lambda b:b.ik is not None)]:
 model.display_slots.append(pmx.DisplaySlot(jp_label,en_label,0,[(0,i) for i,b in enumerate(model.bones) if predicate(b)]))
path=out/'RuoMengTu.pmx';writer.write_to_file(model,str(path));check=reader.read_from_file(str(path))
assert len(check.vertices)==len(model.vertices) and len(check.indices)==len(model.indices) and len(check.bones)==len(model.bones)
assert sum(m.vertex_count for m in check.materials)==len(check.indices)
report={'vertices':len(check.vertices),'triangles':len(check.indices)//3,'bones':len(check.bones),'morphs':len(check.morphs),'materials':len(check.materials),'textures':len(check.textures),'roundtrip':True,'physicsBodies':0,'danceClips':0}
(out/'pmx-export-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True);sys.stdout.flush();os._exit(0)
