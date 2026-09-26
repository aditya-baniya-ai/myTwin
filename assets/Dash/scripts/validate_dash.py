import bpy, os, json, math, struct
from mathutils import Vector, Quaternion
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path=os.path.join(ROOT,'Dash_Final.blend');bpy.ops.wm.open_mainfile(filepath=path)
scene=bpy.context.scene;rig=bpy.data.objects['Dash_Armature'];scene.cycles.samples=24
scene.render.resolution_x=800;scene.render.resolution_y=1000
def clear():
    rig.animation_data.action=None
    for t in rig.animation_data.nla_tracks:t.mute=True
    for p in rig.pose.bones:p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
    for name in ['Body','Eyes']:
        keys=bpy.data.objects[name].data.shape_keys
        keys.animation_data.action=None
        for t in keys.animation_data.nla_tracks:t.mute=True
        for k in keys.key_blocks:k.value=0
    scene.frame_set(1)
def render(name,camera):
    scene.camera=bpy.data.objects['Camera_'+camera];scene.render.filepath=os.path.join(ROOT,'validation',name+'.png');bpy.ops.render.render(write_still=True)
clear()
# A combined diagnostic pose deliberately exceeds the idle's motion ranges.
rig.pose.bones['UpperArm.L'].rotation_euler[0]=math.radians(35)
rig.pose.bones['UpperArm.R'].rotation_euler[2]=math.radians(-25)
rig.pose.bones['LowerArm.L'].rotation_euler[0]=math.radians(80)
rig.pose.bones['LowerArm.R'].rotation_euler[0]=math.radians(60)
rig.pose.bones['UpperLeg.L'].rotation_euler[0]=math.radians(-32)
rig.pose.bones['LowerLeg.L'].rotation_euler[0]=math.radians(66)
rig.pose.bones['Neck'].rotation_euler[2]=math.radians(12)
rig.pose.bones['Head'].rotation_euler[0]=math.radians(8)
render('JointStress_ThreeQuarter','Hero');render('JointStress_Side','Side')
for name,frame in [('idle_normal',31),('idle_energetic',46),('idle_tired',91),('idle_exhausted',121),('yawn',76),('celebrate',46),('stretch',76)]:
    clear();rig.animation_data.action=bpy.data.actions[name]
    for ob in ['Body','Eyes']:bpy.data.objects[ob].data.shape_keys.animation_data.action=bpy.data.actions[name+'__'+ob+'_face']
    scene.frame_set(frame);render('Animation_'+name,'Hero')
scene.render.resolution_x=800;scene.render.resolution_y=800
for name,values in [('Smile',{'Smile':1,'BrowsUp':.3}),('Tired',{'EyesTired':1,'BrowsDown':.25,'Frown':.5}),('Blink',{'BlinkLeft':1,'BlinkRight':1}),('Yawn',{'Yawn':1,'EyesTired':.7})]:
    clear()
    for obj in ['Body','Eyes']:
        for key,val in values.items():
            if key in bpy.data.objects[obj].data.shape_keys.key_blocks:bpy.data.objects[obj].data.shape_keys.key_blocks[key].value=val
    render('Expression_'+name,'Face')
clear()
results={}
# Verify every vertex has a normalized set of deform influences.
bn=set(rig.data.bones.keys());bad=[];max_influences=0
for o in [x for x in bpy.data.collections['Character'].objects if x.type=='MESH']:
    for v in o.data.vertices:
        ws=[g.weight for g in v.groups if o.vertex_groups[g.group].name in bn]
        max_influences=max(max_influences,len(ws))
        if abs(sum(ws)-1)>.0001:bad.append([o.name,v.index,sum(ws)])
results['weights']={'bad_normalization':len(bad),'maximum_influences':max_influences}
# Inspect the GLB payload directly, not only the exporter success message.
with open(os.path.join(ROOT,'Dash_Final.glb'),'rb') as f:
    data=f.read();length,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+length])
results['glb']={'triangles':sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives']), 'materials':len(doc['materials']),'skins':len(doc.get('skins',[])),'joints':[len(s['joints']) for s in doc.get('skins',[])],'animations':[a.get('name') for a in doc.get('animations',[])],'morph_animation_channels':{a['name']:sum(c['target']['path']=='weights' for c in a['channels']) for a in doc.get('animations',[])},'morphs':{m['name']:m.get('extras',{}).get('targetNames',[]) for m in doc['meshes']},'textures':len(doc.get('textures',[])),'embedded_images':len(doc.get('images',[]))}
for ext in ['glb','fbx']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext=='glb':bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'Dash_Final.glb'))
    else:bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT,'Dash_Final.fbx'))
    results[ext+'_reimport']={'armatures':{o.name:len(o.data.bones) for o in bpy.data.objects if o.type=='ARMATURE'},'mesh_count':sum(o.type=='MESH' for o in bpy.data.objects),'actions':[a.name for a in bpy.data.actions],'morph_objects':{o.name:[k.name for k in o.data.shape_keys.key_blocks] for o in bpy.data.objects if o.type=='MESH' and o.data.shape_keys}}
with open(os.path.join(ROOT,'validation','Dash_Export_Validation.json'),'w') as f:json.dump(results,f,indent=2)
print('VALIDATION_COMPLETE',json.dumps(results),flush=True)
