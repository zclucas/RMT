"""Author standard glTF unlit materials for the flat anime face and hair."""
from pathlib import Path
import json,struct,sys,os
R=Path(os.environ['RMT_MODEL_WORKSPACE']).resolve();route=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'route-a';folder=R/'output'/route/'rigged';path=folder/'RuoMengTu-Rigged.glb'
raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);flat=[]
for mat in doc['materials']:
 name=mat['name']
 if any(s in name for s in ['Skin','Iris','EyeWhite','Eyeline','Brows','IvoryHair','IvoryFur','InnerEars','HairContour','WhiteSneakers']):
  mat.setdefault('extensions',{})['KHR_materials_unlit']={};flat.append(name)
  mat.setdefault('extras',{})['rmtShading']='flat-anime'
 if mat.get('alphaMode')=='BLEND':mat.setdefault('extras',{})['rmtDepthWrite']=False
used=doc.setdefault('extensionsUsed',[])
if 'KHR_materials_unlit' not in used:used.append('KHR_materials_unlit')
# Blender's armature container is identity. Put its skinned mesh nodes at the
# scene root, as recommended by glTF, without changing joint transforms.
flattened=[]
for index,node in enumerate(doc['nodes']):
 if 'skin' not in node:continue
 parents=[p for p in doc['nodes'] if index in p.get('children',[])]
 if not parents:continue
 assert len(parents)==1
 parent=parents[0]
 assert not any(k in parent for k in ['matrix','translation','rotation','scale'])
 parent_index=next(i for i,p in enumerate(doc['nodes']) if p is parent)
 scenes=[s for s in doc['scenes'] if parent_index in s['nodes']]
 assert scenes,'Expected the identity armature container to be a scene root.'
 for scene in scenes:scene['nodes'].append(index)
 parent['children'].remove(index);flattened.append(node['name'])
# Strip UV streams from untextured primitives, then compact unused accessors
# and buffer views. Image bytes and all position/weight/morph data stay intact.
assert not doc.get('animations'),'This authoring pipeline exports static models.'
def texture_coordinates(value):
 result=set()
 if isinstance(value,dict):
  for key,item in value.items():
   if key.endswith('Texture') and isinstance(item,dict) and 'index' in item:
    result.add(item.get('extensions',{}).get('KHR_texture_transform',{}).get('texCoord',item.get('texCoord',0)))
   result.update(texture_coordinates(item))
 elif isinstance(value,list):
  for item in value:result.update(texture_coordinates(item))
 return result
used_accessors=set()
for mesh in doc['meshes']:
 for primitive in mesh['primitives']:
  coordinates=texture_coordinates(doc['materials'][primitive['material']])
  for key in list(primitive['attributes']):
   if key.startswith('TEXCOORD_') and int(key[9:]) not in coordinates:del primitive['attributes'][key]
  used_accessors.update(primitive['attributes'].values())
  if 'indices' in primitive:used_accessors.add(primitive['indices'])
  for target in primitive.get('targets',[]):used_accessors.update(target.values())
for skin in doc.get('skins',[]):
 if 'inverseBindMatrices' in skin:used_accessors.add(skin['inverseBindMatrices'])
accessor_map={old:new for new,old in enumerate(sorted(used_accessors))}
doc['accessors']=[a for i,a in enumerate(doc['accessors']) if i in used_accessors]
for mesh in doc['meshes']:
 for primitive in mesh['primitives']:
  primitive['attributes']={key:accessor_map[index] for key,index in primitive['attributes'].items()}
  if 'indices' in primitive:primitive['indices']=accessor_map[primitive['indices']]
  for target in primitive.get('targets',[]):
   for key in target:target[key]=accessor_map[target[key]]
for skin in doc.get('skins',[]):
 if 'inverseBindMatrices' in skin:skin['inverseBindMatrices']=accessor_map[skin['inverseBindMatrices']]
view_references=[]
for accessor in doc['accessors']:
 if 'bufferView' in accessor:view_references.append(accessor)
 if 'sparse' in accessor:view_references.extend([accessor['sparse']['indices'],accessor['sparse']['values']])
view_references.extend(image for image in doc.get('images',[]) if 'bufferView' in image)
used_views={item['bufferView'] for item in view_references};view_map={old:new for new,old in enumerate(sorted(used_views))}
binary_header=20+n;binary_size,binary_type=struct.unpack_from('<I4s',raw,binary_header);assert binary_type==b'BIN\0'
binary=raw[binary_header+8:binary_header+8+binary_size];new_binary=bytearray();views=[]
for index,view in enumerate(doc['bufferViews']):
 if index not in used_views:continue
 new_binary.extend(b'\0'*((-len(new_binary))%4));start=view.get('byteOffset',0);offset=len(new_binary);new_binary.extend(binary[start:start+view['byteLength']]);view['byteOffset']=offset;views.append(view)
for item in view_references:item['bufferView']=view_map[item['bufferView']]
doc['bufferViews']=views;new_binary.extend(b'\0'*((-len(new_binary))%4));doc['buffers'][0]['byteLength']=len(new_binary)
payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4);total=12+8+len(payload)+8+len(new_binary)
path.write_bytes(struct.pack('<4sII',b'glTF',2,total)+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(new_binary),b'BIN\0')+new_binary)
(folder/'material-profile.json').write_text(json.dumps({'flatMaterials':flat,'transparentDepthWrite':False,'clothing':'toon or rough diffuse; no metallic/specular highlights','standardExtension':'KHR_materials_unlit','rootSkinMeshes':flattened,'animations':0},indent=2));print('Applied flat materials:',len(flat))
