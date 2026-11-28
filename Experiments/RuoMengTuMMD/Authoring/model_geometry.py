"""Route A: fitted clean avatar topology + reference-authored clothing.
The character is authored in its neutral A pose. No dance is loaded.
"""
from pathlib import Path
import bpy,bmesh,math,json,sys,os
sys.dont_write_bytecode=True
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
R=Path(os.environ['RMT_MODEL_WORKSPACE']).resolve();OUT=R/'output/route-a';OUT.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(R/'source/Template.blend'))
sourceFace=bpy.data.objects['Face'];sourceBody=bpy.data.objects['Body']
textureFiles=json.loads((R/'source/material-textures.json').read_text(encoding='utf-8'))
originals=[sourceFace,sourceBody]
for ob in originals:
 ob.data.transform(ob.matrix_world,shape_keys=True);ob.parent=None;ob.matrix_world=Matrix.Identity(4);ob.modifiers.clear()
for ob in list(bpy.data.objects):
 if ob not in originals:bpy.data.objects.remove(ob,do_unlink=True)

sys.path.insert(0,str(Path(__file__).resolve().parent))
from fit_coordinates import interp,headwarp,bodywarp,targets

def armweight(ob,v):
 return sum(g.weight for g in v.groups if any(key in ob.vertex_groups[g.group].name for key in ['UpperArm','LowerArm','Hand','Thumb','Index','Middle','Ring','Little']))

def filter_mesh(ob,keep):
 wanted={p.index for p in ob.data.polygons if keep(p)};bm=bmesh.new();bm.from_mesh(ob.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in wanted],context='FACES');bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(ob.data);bm.free();ob.data.update()

def clone(ob,name):
 n=ob.copy();n.data=ob.data.copy();n.name=name;bpy.context.collection.objects.link(n);return n

skin=clone(sourceBody,'RuoMengTu_BodySkin')
if skin.data.shape_keys:skin.shape_key_clear()
filter_mesh(skin,lambda p:p.material_index in [0,1] and all(skin.data.vertices[i].co.z<.90 or abs(skin.data.vertices[i].co.x)>.510 for i in p.vertices))
for v in skin.data.vertices:
 v.co=bodywarp(v.co,armweight(skin,v))
 if .82<v.co.z<1.09 and abs(v.co.x)<.22:
  q=math.sqrt((v.co.x/.166)**2+((v.co.y-.014)/.083)**2)
  if q>1:v.co.x/=q;v.co.y=.014+(v.co.y-.014)/q
skin.data.update()
face=clone(sourceFace,'RuoMengTu_Face')
if face.data.shape_keys:
 for key in face.data.shape_keys.key_blocks:
  for p in key.data:p.co=headwarp(p.co)
 for v,p in zip(face.data.vertices,face.data.shape_keys.key_blocks[0].data):v.co=p.co
else:
 for v in face.data.vertices:v.co=headwarp(v.co)
for material_index,offset in [(1,-.0018),(2,-.0024)]:
 ids={i for poly in face.data.polygons if poly.material_index==material_index for i in poly.vertices}
 if face.data.shape_keys:
  for key in face.data.shape_keys.key_blocks:
   for i in ids:key.data[i].co.y+=offset
  for i in ids:face.data.vertices[i].co=face.data.shape_keys.key_blocks[0].data[i].co
 else:
  for i in ids:face.data.vertices[i].co.y+=offset
white_polys=[tuple(p.vertices) for p in face.data.polygons if p.material_index==4]
white_bvh=BVHTree.FromPolygons([v.co.copy() for v in face.data.vertices],white_polys,all_triangles=False)
for material_index,depth in [(1,.0006),(2,.0010)]:
 ids={i for p in face.data.polygons if p.material_index==material_index for i in p.vertices}
 for i in ids:
  p=face.data.vertices[i].co;hit=white_bvh.ray_cast(Vector((p.x,-1,p.z)),Vector((0,1,0)))
  if hit[0] is None:continue
  delta=hit[0].y-depth-p.y
  if face.data.shape_keys:
   for key in face.data.shape_keys.key_blocks:key.data[i].co.y+=delta
   face.data.vertices[i].co=face.data.shape_keys.key_blocks[0].data[i].co
  else:face.data.vertices[i].co.y+=delta

# Softer neutral brows, retaining the relative deltas of all expression shapes.
brow_ids={i for p in face.data.polygons if p.material_index==5 for i in p.vertices}
for i in brow_ids:
 delta=.006*max(-1,min(1,(.070-abs(face.data.vertices[i].co.x))/.060))
 for key in face.data.shape_keys.key_blocks:key.data[i].co.z+=delta
 face.data.vertices[i].co=face.data.shape_keys.key_blocks[0].data[i].co

for ob in originals:bpy.data.objects.remove(ob,do_unlink=True)

def linear(rgb):return tuple(x/12.92 if x<.04045 else ((x+.055)/1.055)**2.4 for x in rgb)
def material(name,rgb):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*linear(rgb),1);p.inputs['Roughness'].default_value=.85;return m
SKIN=material('Ruo_Skin',(1,.845,.80));NAVY=material('Ruo_NavyHoodie',(.145,.16,.23));IVORY=material('Ruo_IvoryHair',(.96,.935,.91));FUR=material('Ruo_IvoryFur',(.98,.97,.95));PINK=material('Ruo_InnerEars',(.96,.68,.73));SHOE=material('Ruo_WhiteSneakers',(.95,.95,.96));ZIP=material('Ruo_Zipper',(.84,.84,.84));HAIRLINE=material('Ruo_HairContour',(.79,.75,.73));SEAM=material('Ruo_FabricSeams',(.22,.24,.32));CUFF=material('Ruo_CuffFabric',(.115,.13,.19));UNDER=material('Ruo_UnderlayerShorts',(.12,.13,.19))

def recolor_material(src,name,rgb=None,factor=None):
 m=src.copy();m.name=name;image=bpy.data.images.load(str(R/'source/custom/iris-brown-v1.png' if 'BrownIris' in name else R/'source/textures'/textureFiles[src.name]),check_existing=True) if src.name in textureFiles else None
 nodes=m.node_tree.nodes;nodes.clear();p=nodes.new('ShaderNodeBsdfPrincipled');p.inputs['Roughness'].default_value=.9;out=nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs[0],out.inputs[0])
 if image:
  t=nodes.new('ShaderNodeTexImage');t.image=image;image.pack();uv=nodes.new('ShaderNodeUVMap');uv.uv_map=face.data.uv_layers[0].name;m.node_tree.links.new(uv.outputs['UV'],t.inputs['Vector'])
  if 'EyeWhite' not in name:m.node_tree.links.new(t.outputs['Alpha'],p.inputs['Alpha'])
  if factor:
   mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*factor,1);m.node_tree.links.new(t.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(mix.outputs[0],p.inputs['Base Color'])
  elif rgb is None:m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
 if rgb is not None:p.inputs['Base Color'].default_value=(*linear(rgb),1)
 m.surface_render_method='DITHERED';m.use_backface_culling=False;return m

for i,m in enumerate(face.data.materials):
 if 'Face_00_SKIN' in m.name:face.data.materials[i]=SKIN
 elif 'EyeIris' in m.name:face.data.materials[i]=recolor_material(m,'Ruo_BrownIris')
 elif 'FaceBrow' in m.name:face.data.materials[i]=recolor_material(m,'Ruo_WhiteBrownBrows',rgb=(.47,.38,.35))
 elif 'Eyelash' in m.name or 'Eyeline' in m.name:face.data.materials[i]=recolor_material(m,'Ruo_Eyeline_'+str(i),factor=(.30,.22,.20))
 elif 'EyeWhite' in m.name:face.data.materials[i]=recolor_material(m,'Ruo_EyeWhite')
 elif 'EyeHighlight' in m.name:
  face.data.materials[i]=recolor_material(m,'Ruo_FaceDetail_'+str(i));mat=face.data.materials[i];shader=mat.node_tree.nodes.get('Principled BSDF');mat.node_tree.links.remove(shader.inputs['Alpha'].links[0]);shader.inputs['Alpha'].default_value=0
 else:face.data.materials[i]=recolor_material(m,'Ruo_FaceDetail_'+str(i))
# A subtle cheek tint is authored as vertex color, preserving all facial morphs.
face_skin=SKIN.copy();face_skin.name='Ruo_FaceSkinTint';nodes=face_skin.node_tree.nodes;shader=nodes.get('Principled BSDF');vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='RuoTint';face_skin.node_tree.links.new(vc.outputs['Color'],shader.inputs['Base Color'])
face.data.materials[3]=face_skin
colors=face.data.color_attributes.new(name='RuoTint',type='FLOAT_COLOR',domain='POINT')
for c in colors.data:c.color=(1,1,1,1)
skin_ids={i for poly in face.data.polygons if poly.material_index==3 for i in poly.vertices}
base=linear((1,.845,.80));blush=linear((1,.67,.66))
for i in skin_ids:
 p=face.data.vertices[i].co;mask=math.exp(-((abs(p.x)-.075)/.033)**2-((p.z-1.570)/.022)**2)*max(0,min(1,(-p.y-.025)/.045))*.42
 color=tuple(a*(1-mask)+b*mask for a,b in zip(base,blush));lip=math.exp(-(p.x/.019)**6-((p.z-1.548)/.0013)**2)*max(0,min(1,(-p.y-.09)/.025))*.25;lipcolor=linear((.67,.36,.34));colors.data[i].color=tuple(a*(1-lip)+b*lip for a,b in zip(color,lipcolor))+(1,)
face.data.color_attributes.active_color=colors
for i in range(len(skin.data.materials)):skin.data.materials[i]=SHOE if i==1 else SKIN
under_index=len(skin.data.materials);skin.data.materials.append(UNDER)
for poly in skin.data.polygons:
 if poly.material_index==0 and poly.center.z>.83 and abs(poly.center.x)<.22:poly.material_index=under_index

def mesh_object(name,verts,faces,mat):
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update();o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
 for p in data.polygons:p.use_smooth=True
 return o
def grid(name,rows,cols,fn,mat,closed=False):
 verts=[fn(j/rows,i/cols) for j in range(rows+1) for i in range(cols+1)];faces=[]
 for j in range(rows):
  for i in range(cols):a=j*(cols+1)+i;faces.append((a,a+1,a+cols+2,a+cols+1))
 if closed:faces.extend([tuple(range(cols,-1,-1)),tuple(rows*(cols+1)+i for i in range(cols+1))])
 return mesh_object(name,verts,faces,mat)

controls=[(.845,.191,.112),(.88,.209,.125),(.95,.216,.130),(1.06,.208,.128),(1.18,.195,.125),(1.30,.186,.125),(1.39,.194,.120),(1.44,.154,.092),(1.485,.055,.052)]
def coat(t,u):
 z=controls[0][0]+t*(controls[-1][0]-controls[0][0]);rx=interp(z,[(a,b) for a,b,c in controls]);ry=interp(z,[(a,c) for a,b,c in controls]);th=u*math.pi*2
 # Small fabric folds in geometry; no silhouette stretching or painted limbs.
 fold=.002*math.sin(th*9+z*18)*math.sin(t*math.pi);return ((rx+fold)*math.cos(th),.018+(ry+fold)*math.sin(th),z)
coatob=grid('RuoMengTu_QuadHoodie',40,64,coat,NAVY,True)
for sign in [-1,1]:
 sh,el,wr=targets[sign];upper=(el-sh).length;lower=(wr-el).length;length=upper+lower-.006
 def sleeve(t,u,sign=sign,sh=sh.copy(),el=el.copy(),wr=wr.copy(),upper=upper,lower=lower,length=length):
  d=t*length
  if d<upper:center=sh+(el-sh)*(d/upper);direction=(el-sh).normalized()
  else:center=el+(wr-el)*((d-upper)/lower);direction=(wr-el).normalized()
  across=Vector((-direction.z*sign,0,direction.x*sign));th=u*2*math.pi
  radius=interp(t,[(0,.040),(.06,.062),(.14,.080),(.45,.084),(.60,.094),(.80,.081),(.95,.043),(1,.036)])
  radius+=.0017*math.sin(t*46+math.cos(th)*2)*math.sin(t*math.pi)
  if t<.18:center-=Vector((sign*.035,0,.006))*(1-t/.18)
  return center+across*(radius*math.cos(th))+Vector((0,radius*.9*math.sin(th),0))
 grid('RuoMengTu_Sleeve_'+str(sign),48,40,sleeve,NAVY,True)
def neck(t,u):
 th=u*2*math.pi;z=1.390+t*.160;rx=interp(z,[(1.39,.084),(1.43,.080),(1.46,.052),(1.485,.035),(1.55,.034)]);ry=interp(z,[(1.39,.05),(1.46,.042),(1.485,.034),(1.55,.034)]);return (rx*math.cos(th),.016+ry*math.sin(th),z)
grid('RuoMengTu_Neck',8,40,neck,SKIN,True)
def trim(t,u):
 th=u*2*math.pi;cross=t*2*math.pi;bump=.0033*math.sin(th*47)*math.sin(cross*9)+.0015*math.sin(th*23)*math.cos(cross*5);r=.029+bump
 return ((.197+r*math.cos(cross))*math.cos(th),.018+(.117+r*math.cos(cross))*math.sin(th),.833+r*math.sin(cross))
grid('RuoMengTu_FleeceHem',16,128,trim,FUR)
def cowl(t,u):
 th=u*2*math.pi;cross=t*2*math.pi;rx=.110+.023*math.cos(cross);ry=.073+.023*math.cos(cross);front=math.sin(th)
 return (rx*math.cos(th),.027+ry*math.sin(th),1.477+.022*math.sin(cross)+.033*front)
grid('RuoMengTu_HoodRim',12,80,cowl,NAVY)
def hood(t,u):
 lat=.01+(math.pi-.02)*t;th=2*math.pi*u;return (.138*math.sin(lat)*math.cos(th),.131+.048*math.sin(lat)*math.sin(th),1.378+.125*math.cos(lat))
grid('RuoMengTu_FoldedHood',24,48,hood,NAVY)

def curve(name,points,radius,mat):
 data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D';data.resolution_u=4;data.bevel_depth=radius;data.bevel_resolution=0 if radius<.0017 or mat==HAIRLINE else 2;sp=data.splines.new('POLY');sp.points.add(len(points)-1)
 for a,b in zip(sp.points,points):a.co=(*b,1)
 o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.data.materials.append(mat);return o
zippts=[]
for j in range(60):
 z=.86+(1.42-.86)*j/59;y=.018-interp(z,[(a,c) for a,b,c in controls])-.0018;zippts.append((0,y,z))
curve('RuoMengTu_Zipper',zippts,.0014,ZIP)
for sign in [-1,1]:
 curve('RuoMengTu_Drawstring_'+str(sign),[(sign*.047,-.060,1.463),(sign*.046,-.105,1.405),(sign*.047,-.116,1.28)],.0023,FUR)
 curve('RuoMengTu_Pocket_'+str(sign),[(sign*.045,-.113,1.04),(sign*.080,-.116,1.13),(sign*.143,-.091,1.13)],.0008,NAVY)

def loft_ear(label,ctrl):
 def center(t):
  f=t*(len(ctrl)-1);i=min(len(ctrl)-2,int(f));a=f-i;p0=Vector(ctrl[max(0,i-1)][:3]);p1=Vector(ctrl[i][:3]);p2=Vector(ctrl[i+1][:3]);p3=Vector(ctrl[min(len(ctrl)-1,i+2)][:3]);p=.5*((2*p1)+(-p0+p2)*a+(2*p0-5*p1+4*p2-p3)*a*a+(-p0+3*p1-3*p2+p3)*a*a*a);width=.029*max(.015,math.sin(t*math.pi))**.65+.008*(1-t)**5;return p,width
 def fn(t,u):
  p,w=center(t);angle=2*math.pi*u;return p+Vector((w*math.cos(angle),.009*math.sin(angle)*min(1,w/.012),0))
 o=grid('RuoMengTu_Ear_'+label,48,28,fn,IVORY,True)
 def pink(t,u):
  v=.08+t*.80;p,w=center(v);s=(u*2-1)*.65*math.sin(t*math.pi)**.35
  return p+Vector((w*s,-.009*math.sqrt(max(0,1-s*s))-.0003,0))
 grid('RuoMengTu_EarInner_'+label,40,16,pink,PINK);return o
loft_ear('upright',[(-.083,.015,1.806,.015),(-.105,.015,1.900,.029),(-.130,.020,2.030,.001)])
loft_ear('bent',[(.078,.018,1.810,.014),(.102,.016,1.922,.026),(.130,.010,1.948,.028),(.197,.004,1.879,.001)])

def tail(t,u):
 lat=.008+(math.pi-.016)*t;th=u*math.pi*2;noise=.0022*math.sin(th*17)*math.sin(lat*23);rad=.057+noise
 return (rad*math.sin(lat)*math.cos(th),.175+rad*math.sin(lat)*math.sin(th),.915+rad*math.cos(lat))
grid('RuoMengTu_BackTail',28,56,tail,FUR)

# A tailored bob: continuous crown and independent volumetric tapered locks.
# These are closed surfaces, with roots buried under the crown, not flat cards.
def haircap(t,u):
 th=2*math.pi*u;back=(math.sin(th)+1)/2;lat=.002+t*(1.42+back*.68)
 return (.162*math.sin(lat)*math.cos(th),.018+.136*math.sin(lat)*math.sin(th),1.666+.169*math.cos(lat))
hair=grid('RuoMengTu_BobHair',28,80,haircap,IVORY,True)
def lock(name,control,width,thickness=.006):
 def fn(t,u):
  a,b,c,d=[Vector(p) for p in control];p=(1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d
  tangent=(3*(1-t)**2*(b-a)+6*(1-t)*t*(c-b)+3*t*t*(d-c)).normalized()
  if 'BobLock' in name and p.z>1.58:
   current=math.sqrt((p.x/.162)**2+((p.y-.018)/.136)**2);required=math.sqrt(max(0,1-((p.z-1.666)/.169)**2))+.030
   if current>0 and current<required:p.x*=required/current;p.y=.018+(p.y-.018)*required/current
  normal=Vector((p.x,p.y-.018,0)).normalized();side=tangent.cross(normal).normalized();normal=side.cross(tangent).normalized()
  w=width*max(.001,math.sin(math.pi*t))**.55+.008*(1-t)**5;w=max(.0004,w);angle=u*2*math.pi
  return p+side*(w*math.cos(angle))+normal*(thickness*math.sin(angle)*min(1,w/.008))
 o=grid(name,30,16,fn,IVORY,True)
 if 'Fringe' in name or 'Temple' in name or 'BobLock' in name:curve(name+'_Contour',[fn(.12+.86*j/35,0) for j in range(36)],.00024 if 'BobLock' in name else .00030,HAIRLINE)
 return o
for i in range(23):
 th=-.46+i*(math.pi+.92)/22;x=math.cos(th);y=math.sin(th)
 end=1.492+.012*math.sin(i*2.4)
 lock('RuoMengTu_BobLock_%02d'%i,[(x*.020,.018+y*.016,1.817),(x*.159,.018+y*.122,1.769),(x*.178,.018+y*.134,1.543),(x*.149,.018+y*.106,end)],.024,.006)
for sign in [-1,1]:
 lock('RuoMengTu_Temple_'+str(sign),[(sign*.05,-.035,1.824),(sign*.135,-.104,1.78),(sign*.158,-.104,1.59),(sign*.125,-.065,1.49)],.029,.007)
# Swept fringe exposes both eyes; the central lock has a distinct tapered end.
for i,(endx,endz,rootx) in enumerate([(-.118,1.594,-.020),(-.087,1.652,-.018),(-.049,1.661,-.017),(-.006,1.653,-.016),(.038,1.630,-.014),(.078,1.658,-.009),(.115,1.592,.008)]):
 lock('RuoMengTu_Fringe_%02d'%i,[(rootx,-.025,1.818),(rootx*.65+endx*.45,-.119,1.794),(endx*.82,-.146,1.705),(endx,-.133,endz)],.026 if i not in [0,6] else .022,.0045)

# Fitted ribbed cuffs, stitched pockets, zipper teeth and pull are separate meshes.
for sign in [-1,1]:
 sh,el,wr=targets[sign];axis=(wr-el).normalized();across=Vector((-axis.z*sign,0,axis.x*sign))
 def cuff(t,u,wr=wr.copy(),axis=axis.copy(),across=across.copy()):
  th=u*math.pi*2;r=.039;return wr+axis*(-.040+t*.044)+across*(r*math.cos(th))+Vector((0,r*.9*math.sin(th),0))
 grid('RuoMengTu_Sleeve_Cuff_'+str(sign),8,64,cuff,CUFF,True)
 def pocketpoint(x,z):
  rx=interp(z,[(a,b) for a,b,c in controls]);ry=interp(z,[(a,c) for a,b,c in controls]);return (x,.018-ry*math.sqrt(max(.01,1-(x/rx)**2))-.002,z)
 curve('RuoMengTu_PocketStitch_'+str(sign),[pocketpoint(sign*x,z) for x,z in [(.048,1.000),(.095,1.100),(.146,1.100)]],.0009,SEAM)
for j in range(100):
 z=.872+j*.00515;y=.018-interp(z,[(a,c) for a,b,c in controls])-.0025
 curve('RuoMengTu_ZipperTooth_%03d'%j,[(-.0028,y,z),(.0028,y,z)],.00065,ZIP)
curve('RuoMengTu_ZipperPull',[(0,-.102,1.424),(-.0034,-.105,1.418),(-.0034,-.106,1.405),(.0034,-.106,1.405),(.0034,-.105,1.418),(0,-.102,1.424)],.0011,ZIP)

# Sneaker lace mesh follows the retained five-finger template's shoe surface.
shoe_polys=[tuple(p.vertices) for p in skin.data.polygons if p.material_index==1]
shoe_bvh=BVHTree.FromPolygons([v.co.copy() for v in skin.data.vertices],shoe_polys,all_triangles=False)
for sign in [-1,1]:
 pts=[]
 for j in range(5):
  y=-.094+j*.021
  for q in [-1,1]:
   x=sign*.082+q*.018;hit=shoe_bvh.ray_cast(Vector((x,y,.4)),Vector((0,0,-1)))[0]
   if hit is not None:pts.append((x,y,hit.z+.0018))
 if len(pts)>2:curve('RuoMengTu_SneakerLaces_'+str(sign),pts,.0016,FUR)
 curve('RuoMengTu_SneakerSole_'+str(sign),[(sign*.082+.051*math.cos(j*2*math.pi/80),-.031+.108*math.sin(j*2*math.pi/80),.017) for j in range(81)],.0014,ZIP)

# Clothing print is real mesh geometry, with the same location as the reference.
bpy.ops.object.text_add(location=(.099,-.118,1.345));o=bpy.context.object;o.name='RuoMengTu_RMT_Print';o.data.body='RMT';o.data.size=.027;o.data.align_x='CENTER';o.data.extrude=.00005;o.rotation_euler=(math.pi/2,0,0);o.data.materials.append(FUR)
for ob in list(bpy.context.scene.objects):
 if ob.type in ['FONT','CURVE']:
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH')
# Printed letters and zipper hardware follow the actual cloth surface. The
# source remains fully volumetric when inspected from a side or rear view.
cloth_surface=BVHTree.FromPolygons([v.co.copy() for v in coatob.data.vertices],[tuple(p.vertices) for p in coatob.data.polygons],all_triangles=False)
for ob in bpy.context.scene.objects:
 if 'RMT_Print' not in ob.name and 'Zipper' not in ob.name:continue
 if 'RMT_Print' in ob.name:
  bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=2,use_grid_fill=True);bm.to_mesh(ob.data);bm.free()
 inverse=ob.matrix_world.inverted()
 for v in ob.data.vertices:
  point=ob.matrix_world@v.co;hit=cloth_surface.ray_cast(Vector((point.x,-1,point.z)),Vector((0,1,0)))[0]
  if hit is None:continue
  if 'RMT_Print' in ob.name:reference_y=-.118
  elif 'ZipperPull' in ob.name:reference_y=-.102
  else:reference_y=.018-interp(point.z,[(a,c) for a,b,c in controls])-(.0025 if 'Tooth' in ob.name else .0018)
  relief=reference_y-point.y
  point.y=hit.y-(.0013 if 'Print' in ob.name else .0015)-relief;v.co=inverse@point
for ob in bpy.context.scene.objects:
 if ob.type=='MESH' and ob!=face:
  bm=bmesh.new();bm.from_mesh(ob.data)
  if ob!=skin:bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0000001)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
  for p in ob.data.polygons:p.use_smooth=True

# Bake only skin polygons; other facial UV islands may overlap this sheet.
bakeob=face.copy();bakeob.data=face.data.copy();bakeob.name='temporary_face_bake';bpy.context.collection.objects.link(bakeob);bakeob.shape_key_clear();filter_mesh(bakeob,lambda p:p.material_index==3)
bakemat=face_skin.copy();bakemat.name='temporary_bake_material';bakeob.data.materials.clear();bakeob.data.materials.append(bakemat)
for poly in bakeob.data.polygons:poly.material_index=0
nodes=bakemat.node_tree.nodes;nodes.clear();emit=nodes.new('ShaderNodeEmission');vcolor=nodes.new('ShaderNodeVertexColor');vcolor.layer_name='RuoTint';outnode=nodes.new('ShaderNodeOutputMaterial');bakemat.node_tree.links.new(vcolor.outputs['Color'],emit.inputs['Color']);bakemat.node_tree.links.new(emit.outputs[0],outnode.inputs[0]);image=bpy.data.images.new('Ruo_FaceSkin_Painted',width=1024,height=1024,alpha=False);image.colorspace_settings.name='sRGB';target=nodes.new('ShaderNodeTexImage');target.image=image;nodes.active=target
bpy.ops.object.select_all(action='DESELECT');bakeob.select_set(True);bpy.context.view_layer.objects.active=bakeob;scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.margin=8;bpy.ops.object.bake(type='EMIT');image.filepath_raw=str(R/'source/custom/face-skin-baked.png');image.file_format='PNG';image.save();image.pack();bpy.data.objects.remove(bakeob,do_unlink=True)
nodes=face_skin.node_tree.nodes;nodes.clear();shader=nodes.new('ShaderNodeBsdfPrincipled');shader.inputs['Roughness'].default_value=.9;outnode=nodes.new('ShaderNodeOutputMaterial');tex=nodes.new('ShaderNodeTexImage');tex.image=image;uv=nodes.new('ShaderNodeUVMap');uv.uv_map=face.data.uv_layers[0].name;face_skin.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);face_skin.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color']);face_skin.node_tree.links.new(shader.outputs[0],outnode.inputs[0])
# Hand-painted skin color is baked from anatomy-aware vertex color. No source
# body clothing/tattoo pixels are reused on the legs or hands.
body_colors=skin.data.color_attributes.new(name='RuoBodyTint',type='FLOAT_COLOR',domain='POINT');skin.data.color_attributes.active_color=body_colors
for v in skin.data.vertices:
 p=v.co;n=v.normal;edge=min(1,abs(n.x))*.055+max(0,n.y)*.035;col=tuple(c*(1-edge) for c in linear((1,.845,.80)))
 if p.z<.95:
  blushmask=math.exp(-((p.z-.49)/.043)**2)*max(0,-n.y)*.16;flush=linear((1,.73,.71));col=tuple(a*(1-blushmask)+b*blushmask for a,b in zip(col,flush))
 else:
  distal=sum(g.weight for g in v.groups if any(x in skin.vertex_groups[g.group].name for x in ['Thumb3','Index3','Middle3','Ring3','Little3']))
  nail=distal*max(0,n.y)*.24;nailcolor=linear((1,.91,.90));col=tuple(a*(1-nail)+b*nail for a,b in zip(col,nailcolor))
 body_colors.data[v.index].color=col+(1,)
body_skin=SKIN.copy();body_skin.name='Ruo_BodySkinPainted';nodes=body_skin.node_tree.nodes;nodes.clear();emit=nodes.new('ShaderNodeEmission');vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='RuoBodyTint';output=nodes.new('ShaderNodeOutputMaterial');body_skin.node_tree.links.new(vc.outputs['Color'],emit.inputs['Color']);body_skin.node_tree.links.new(emit.outputs[0],output.inputs[0])
bakeob=skin.copy();bakeob.data=skin.data.copy();bpy.context.collection.objects.link(bakeob);filter_mesh(bakeob,lambda p:p.material_index==0);bakeob.data.materials.clear();bakeob.data.materials.append(body_skin)
for p in bakeob.data.polygons:p.material_index=0
body_image=bpy.data.images.new('Ruo_BodySkin_Painted',width=2048,height=2048,alpha=False);body_image.colorspace_settings.name='sRGB';target=nodes.new('ShaderNodeTexImage');target.image=body_image;nodes.active=target
bpy.ops.object.select_all(action='DESELECT');bakeob.select_set(True);bpy.context.view_layer.objects.active=bakeob;bpy.ops.object.bake(type='EMIT');body_image.filepath_raw=str(R/'source/custom/body-skin-baked.png');body_image.file_format='PNG';body_image.save();body_image.pack();bpy.data.objects.remove(bakeob,do_unlink=True)
nodes.clear();shader=nodes.new('ShaderNodeBsdfPrincipled');shader.inputs['Roughness'].default_value=.9;output=nodes.new('ShaderNodeOutputMaterial');tex=nodes.new('ShaderNodeTexImage');tex.image=body_image;uv=nodes.new('ShaderNodeUVMap');uv.uv_map=skin.data.uv_layers[0].name;body_skin.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);body_skin.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color']);body_skin.node_tree.links.new(shader.outputs[0],output.inputs[0]);skin.data.materials[0]=body_skin
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=face
for image in bpy.data.images:
 if image.source=='FILE':
  try:image.pack()
  except:pass
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'RuoMengTu-RouteA.blend'),compress=True)
report={'route':'A clean template + reference-authored quad clothing','tailCenter':[0,.175,.915],'tailRadius':.057,'template':'pixiv ChatVRM AvatarSample_B','faceShapes':len(face.data.shape_keys.key_blocks) if face.data.shape_keys else 0,'vertices':sum(len(o.data.vertices) for o in bpy.context.scene.objects if o.type=='MESH'),'experimental':True,'rigged':False}
(OUT/'model-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True);sys.stdout.flush();os._exit(0)
