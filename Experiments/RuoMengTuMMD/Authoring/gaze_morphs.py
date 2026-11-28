"""Author bounded gaze morphs on the stable layered anime eye surface."""
from pathlib import Path
import bpy,json,os,sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(os.environ['RMT_MODEL_WORKSPACE']).resolve();folder=R/'output/route-a';path=folder/'RuoMengTu-RouteA.blend';bpy.ops.wm.open_mainfile(filepath=str(path));face=bpy.data.objects['RuoMengTu_Face'];me=face.data
assert 'Ruo_EyeLook_Left' not in me.shape_keys.key_blocks,'Rebuild the base before authoring gaze morphs.'
white=BVHTree.FromPolygons([v.co.copy() for v in me.vertices],[tuple(p.vertices) for p in me.polygons if p.material_index==4],all_triangles=False);ids={i for p in me.polygons if p.material_index in [1,2] for i in p.vertices};report={}
for name,dx,dz in [('Left',.004,0),('Right',-.004,0),('Up',0,.003),('Down',0,-.003)]:
 key=face.shape_key_add(name='Ruo_EyeLook_'+name,from_mix=False);failed=0;translations={}
 for sign in [-1,1]:
  members=[i for i in ids if me.vertices[i].co.x*sign>0]
  center=sum((me.vertices[i].co for i in members),Vector())/len(members)
  before=white.ray_cast(Vector((center.x,-1,center.z)),Vector((0,1,0)))[0]
  after=white.ray_cast(Vector((center.x+dx,-1,center.z+dz)),Vector((0,1,0)))[0]
  for i in members:
   p=me.vertices[i].co;q=p+Vector((dx,0,dz));hit=white.ray_cast(Vector((q.x,-1,q.z)),Vector((0,1,0)))[0]
   if hit is None:failed+=1
  # Follow the central tangent, with bounded clearance. Border texture can
  # occlude the iris naturally; do not pull the whole eye out of the face.
  dy=max(-.003,min(0,after.y-before.y-.0008)) if before is not None and after is not None else 0
  delta=Vector((dx,dy,dz));translations[str(sign)]=list(delta)
  for i in members:key.data[i].co=me.vertices[i].co+delta
 report[name]={'vertices':len(ids),'unprojected':failed,'rigidEyeTranslations':translations}
face['gaze']='Four surface-conforming morphs; no spherical eyeball rotation.'
bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True);(folder/'gaze-morphs.json').write_text(json.dumps(report,indent=2));print(report,flush=True);sys.stdout.flush();os._exit(0)
