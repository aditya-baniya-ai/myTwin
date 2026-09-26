"""Mobile optimization, UV atlas, facial morphs, deformation rig and exports."""
import bpy, os, math, json, bmesh, sys, numpy as np
from mathutils import Vector, Quaternion
from math import sin, cos, pi, exp
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'Dash_Working.blend'))
scene=bpy.context.scene
names=['Body','Eyes','Hair','Cap','Jacket','Shirt','Pants','Shoes']
objects=[bpy.data.objects[n] for n in names]
def activate(o):
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
def tri(o):return sum(len(p.vertices)-2 for p in o.data.polygons)
budgets={'Body':11500,'Eyes':2000,'Hair':3500,'Cap':4000,'Jacket':7600,'Shirt':1500,'Pants':7000,'Shoes':6700}
stats={}
for o in objects:
    before=tri(o);activate(o)
    # Keep the complete smooth source in Dash_Working; evaluated mobile meshes here.
    if before>budgets[o.name]:
        mod=o.modifiers.new('Mobile surface optimization','DECIMATE');mod.ratio=budgets[o.name]/before
        mod.use_collapse_triangulate=False;bpy.ops.object.modifier_apply(modifier=mod.name)
    bm=bmesh.new();bm.from_mesh(o.data)
    if o.name!='Body':bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.0000001)
    boundary=[e for e in bm.edges if e.is_boundary]
    if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=12)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()
    stats[o.name]={'source_triangles':before,'triangles':tri(o),'vertices':len(o.data.vertices)}
    print(o.name,stats[o.name],flush=True)

# A single shared 2K color atlas and 2K roughness atlas; repeatable fine textile grain.
palette=['Skin','Lip','Hair','Sunflower','Cream','Cobalt','Ink','Chalk','Sole','Sclera','Iris','Pupil','Mouth']
size=2048;tile=512
base=np.ones((size,size,4),dtype=np.float32);rough=np.ones((size,size,4),dtype=np.float32)
rng=np.random.default_rng(2409)
def srgb(a):return np.where(a<=.0031308,a*12.92,1.055*np.power(a,1/2.4)-.055)
for k,name in enumerate(palette):
    mat=bpy.data.materials['Dash_'+name];p=mat.node_tree.nodes.get('Principled BSDF')
    c=np.array(p.inputs['Base Color'].default_value[:3]);r=p.inputs['Roughness'].default_value
    yy,xx=np.mgrid[0:tile,0:tile];grain=rng.normal(0,.0025,(tile,tile))
    if name in ['Sunflower','Cream','Cobalt','Chalk']:
        grain+=.0018*np.sin(xx*pi/2)*np.sin(yy*pi/2)
    if name=='Hair':grain+=.005*np.sin(xx*.13+np.sin(yy*.015))
    if name=='Skin':grain*=.28
    col=np.clip(srgb(c)[None,None,:]+grain[:,:,None],0,1)
    x=(k%4)*tile;y=(k//4)*tile
    base[y:y+tile,x:x+tile,:3]=col
    rough[y:y+tile,x:x+tile,:3]=np.clip(r+grain[:,:,None]*3,0,1)
for name,pixels,space in [('Dash_BaseColor_2K',base,'sRGB'),('Dash_Roughness_2K',rough,'Non-Color')]:
    im=bpy.data.images.new(name,width=size,height=size,alpha=False)
    im.colorspace_settings.name=space;im.pixels.foreach_set(pixels.ravel());im.filepath_raw=os.path.join(ROOT,'textures',name+'.png');im.file_format='PNG';im.save();im.pack()
    # Provide exact downscaled variants for runtime experiments.
    small=im.copy();small.name=name.replace('2K','1K');small.scale(1024,1024)
    small.filepath_raw=os.path.join(ROOT,'textures',small.name+'.png');small.save();bpy.data.images.remove(small)
for name in palette:
    mat=bpy.data.materials['Dash_'+name];nt=mat.node_tree;p=nt.nodes.get('Principled BSDF')
    for suffix,socket in [('BaseColor_2K','Base Color'),('Roughness_2K','Roughness')]:
        node=nt.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images['Dash_'+suffix];node.label='Shared mobile atlas';nt.links.new(node.outputs['Color'],p.inputs[socket])
    if name in ['Iris','Pupil']:
        p.inputs['Coat Weight'].default_value=.25;p.inputs['Coat Roughness'].default_value=.16
activate(objects[0])
for o in objects:o.select_set(True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.012,area_weight=.2)
bpy.ops.object.mode_set(mode='OBJECT')
for o in objects:
    uv=o.data.uv_layers.active;uv.name='UV_Atlas'
    for poly in o.data.polygons:
        name=o.data.materials[poly.material_index].name.replace('Dash_','');k=palette.index(name)
        for li in poly.loop_indices:
            u,v=uv.data[li].uv;uv.data[li].uv=((k%4+.035+.93*u)/4,(k//4+.035+.93*v)/4)

# Atlas-driven surface families minimize real-time material batches.
families={}
for label,source in [('Skin','Skin'),('TextileRubber','Sunflower'),('Hair','Hair'),('EyeGloss','Iris')]:
    m=bpy.data.materials['Dash_'+source].copy();m.name='Dash_PBR_'+label;families[label]=m
for o in objects:
    indices=[];used=[]
    for p in o.data.polygons:
        old=o.data.materials[p.material_index].name.replace('Dash_','')
        family='Skin' if old in ['Skin','Lip'] else 'Hair' if old=='Hair' else 'EyeGloss' if old in ['Sclera','Iris','Pupil'] else 'TextileRubber'
        if family not in used:used.append(family)
        indices.append(used.index(family))
    o.data.materials.clear()
    for family in used:o.data.materials.append(families[family])
    for p,i in zip(o.data.polygons,indices):p.material_index=i

# Humanoid deformation skeleton. No leaf bones or platform-specific control rig.
ad=bpy.data.armatures.new('Dash_Skeleton');rig=bpy.data.objects.new('Dash_Armature',ad)
bpy.data.collections['Rig'].objects.link(rig);rig.show_in_front=True;ad.display_type='OCTAHEDRAL'
activate(rig);bpy.ops.object.mode_set(mode='EDIT')
bone_specs=[]
def bone(name,head,tail,parent=None,connect=False):
    b=ad.edit_bones.new(name);b.head=head;b.tail=tail
    if parent:b.parent=ad.edit_bones[parent];b.use_connect=connect
    bone_specs.append((name,Vector(head),Vector(tail),parent));return b
bone('Root',(0,0,.03),(0,0,.15))
bone('Hips',(0,.015,.91),(0,.015,1.075),'Root')
bone('Spine',(0,.015,1.075),(0,.015,1.24),'Hips',True)
bone('Chest',(0,.015,1.24),(0,.015,1.385),'Spine',True)
bone('Neck',(0,.015,1.385),(0,.015,1.495),'Chest',True)
bone('Head',(0,.015,1.495),(0,.02,1.81),'Neck',True)
for s,side in [(1,'L'),(-1,'R')]:
    bone('Clavicle.'+side,(0,.015,1.35),(s*.17,.015,1.34),'Chest')
    bone('UpperArm.'+side,(s*.17,.015,1.34),(s*.306,-.005,1.203),'Clavicle.'+side,True)
    bone('LowerArm.'+side,(s*.306,-.005,1.203),(s*.425,-.025,1.043),'UpperArm.'+side,True)
    bone('Hand.'+side,(s*.425,-.025,1.043),(s*.464,-.025,.980),'LowerArm.'+side,True)
    wrist=Vector((s*.425,-.025,1.043));down=Vector((s*.53,0,-.848));across=Vector((s*.848,0,.53))
    for k,(fn,length) in enumerate([('Index',.065),('Middle',.074),('Ring',.066),('Little',.052)]):
        base=wrist+down*.066+across*((k-1.5)*.018);direction=(down+across*((k-1.5)*.075)).normalized()
        joints=[base,base+direction*length*.42+Vector((0,-.004,0)),base+direction*length*.74+Vector((0,-.010,0)),base+direction*length+Vector((0,-.017,0))]
        for j in range(3):bone(f'{fn}{j+1}.{side}',joints[j],joints[j+1],'Hand.'+side if j==0 else f'{fn}{j}.{side}',j>0)
    base=wrist+down*.024-across*.023
    joints=[base,base+down*.013-across*.028+Vector((0,-.004,0)),base+down*.035-across*.036+Vector((0,-.012,0)),base+down*.047-across*.033+Vector((0,-.018,0))]
    for j in range(3):bone(f'Thumb{j+1}.{side}',joints[j],joints[j+1],'Hand.'+side if j==0 else f'Thumb{j}.{side}',j>0)
    bone('UpperLeg.'+side,(s*.09,.015,.954),(s*.127,-.008,.50),'Hips')
    bone('LowerLeg.'+side,(s*.127,-.008,.50),(s*.123,.025,.174),'UpperLeg.'+side,True)
    bone('Foot.'+side,(s*.123,.025,.174),(s*.123,-.105,.078),'LowerLeg.'+side,True)
    bone('Toe.'+side,(s*.123,-.105,.078),(s*.123,-.20,.068),'Foot.'+side,True)
bpy.ops.object.mode_set(mode='OBJECT')
rig['forward_axis']='-Y';rig['units']='metres';rig['retargeting']='Humanoid rest pose. Source-specific retarget mapping required.'
rig['expression_controls']='Named morph targets on Body and Eyes. Set both objects for eye expressions.'
def smoothstep(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def segment_distance(p,a,b):
    t=max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared));return (p-(a+(b-a)*t)).length
def body_weights(p):
    if p.z<1.1:return {'Hips':1}
    if p.z<1.25:
        t=smoothstep(1.1,1.25,p.z);return {'Hips':1-t,'Spine':t}
    t=smoothstep(1.25,1.37,p.z);return {'Spine':1-t,'Chest':t}
def arm_weights(p,side):
    t=smoothstep(.26,.362,abs(p.x));return {'UpperArm.'+side:1-t,'LowerArm.'+side:t}
for o in objects:
    # Preserve face tags until morph authoring; recalculate all deform weights after booleans.
    for g in list(o.vertex_groups):
        if not g.name.startswith('FACE_'):o.vertex_groups.remove(g)
    for v in o.data.vertices:
        p=v.co;side='L' if p.x>=0 else 'R'
        if o.name in ['Eyes','Hair','Cap']:w={'Head':1}
        elif o.name=='Body':
            if p.z>1.47:w={'Head':1}
            elif p.z>1.34:
                t=smoothstep(1.42,1.49,p.z);w={'Neck':1-t,'Head':t}
            else:
                wrist=Vector(((1 if side=='L' else -1)*.425,-.025,1.043))
                if p.z>1.012:
                    t=smoothstep(1.015,1.065,p.z);w={'Hand.'+side:1-t,'LowerArm.'+side:t}
                else:
                    candidates=[(segment_distance(p,a,b),n) for n,a,b,_ in bone_specs if n.endswith('.'+side) and (n.startswith(('Index','Middle','Ring','Little','Thumb','Hand')))]
                    candidates.sort();best=candidates[:2]
                    ww=[1/(d+.004)**4 for d,n in best];total=sum(ww);w={n:q/total for (d,n),q in zip(best,ww)}
        elif o.name in ['Jacket','Shirt']:
            if abs(p.x)>.21:w=arm_weights(p,side)
            elif abs(p.x)>.135 and p.z>1.26:
                t=smoothstep(.145,.22,abs(p.x));w={'Chest':1-t,'UpperArm.'+side:t}
            else:w=body_weights(p)
        elif o.name=='Pants':
            upper=smoothstep(.44,.57,p.z);hip=smoothstep(.85,1.02,p.z)
            ankle=1-smoothstep(.16,.195,p.z)
            w={'LowerLeg.'+side:(1-upper)*(1-ankle),'UpperLeg.'+side:upper*(1-hip),'Hips':upper*hip,'Foot.'+side:ankle}
        elif o.name=='Shoes':
            t=(1-smoothstep(-.16,-.09,p.y))*.6;w={'Foot.'+side:1-t,'Toe.'+side:t}
        total=sum(w.values())
        for n,val in w.items():
            if val>1e-5:
                g=o.vertex_groups.get(n) or o.vertex_groups.new(name=n);g.add([v.index],val/total,'REPLACE')
    o.parent=rig;mod=o.modifiers.new('Dash skin deformation','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
rig.location.z=-.016

# Morph targets use separately authored lid, eyebrow and lip regions.
expressions=['Smile','Frown','BlinkLeft','BlinkRight','EyesWide','EyesTired','BrowsUp','BrowsDown','MouthOpen','Yawn']
def gauss(x,c,w):return exp(-((x-c)/w)**2)
for o in [bpy.data.objects['Body'],bpy.data.objects['Eyes']]:
    tags={v.index:[] for v in o.data.vertices}
    for v in o.data.vertices:
        for g in v.groups:
            n=o.vertex_groups[g.group].name
            if n.startswith('FACE_') and g.weight>.15:tags[v.index].append(n[5:])
    o.shape_key_add(name='Basis')
    for expression in expressions:
        # Eyes only need eyelid/sclera opening controls, avoiding empty morphs.
        if o.name=='Eyes' and expression not in ['BlinkLeft','BlinkRight','EyesWide','EyesTired']:continue
        key=o.shape_key_add(name=expression);key.slider_min=0;key.slider_max=1
        for v in o.data.vertices:
            p=v.co.copy();x,y,z=p;vt=tags[v.index];side='L' if x>0 else 'R';cx=.059 if x>0 else -.059
            eye=('eye'+side in vt);lid=('lid'+side in vt);brow=('brow'+side in vt)
            mouth=any(t in vt for t in ['lipUpper','lipLower','mouthInner']);head='head' in vt
            if expression in ['BlinkLeft','BlinkRight','EyesTired','EyesWide'] and (eye or lid):
                active=expression not in ['BlinkLeft','BlinkRight'] or (expression=='BlinkLeft' and side=='L') or (expression=='BlinkRight' and side=='R')
                if active:
                    factor={'EyesWide':1.21,'EyesTired':.53}.get(expression,.035)
                    if eye:p.z=1.681+(z-1.681)*factor;p.y+=.003*(1-factor)
                    else:
                        edge=1-smoothstep(.019,.035,abs(z-1.681))
                        p.z+=(1.681-z)*(1-factor)*edge
            if brow:
                if expression=='BrowsUp':p.z+=.013
                if expression=='BrowsDown':p.z-=.009;p.z+=.004*(abs(x)-.02)/.08
                if expression=='EyesTired':p.z-=.003
                if expression=='Yawn':p.z+=.009
            if mouth or (head and z<1.61 and abs(x)<.095):
                influence=1 if mouth else gauss(z,1.554,.044)*gauss(x,0,.07)
                if expression=='Smile':p.z+=.014*(abs(x)/.06)**1.5*influence;p.x+=.005*(1 if x>0 else -1)*gauss(x,0,.05)*influence
                if expression=='Frown':p.z-=.012*(abs(x)/.06)**1.4*influence
                if expression in ['MouthOpen','Yawn']:
                    amount=.013 if expression=='MouthOpen' else .033
                    width=max(0,1-(x/.044)**2)
                    if 'lipLower' in vt:p.z-=amount*width;p.y-=.002*width
                    if head and z<1.552:p.z-=amount*influence;p.y-=.002*influence
                    if 'lipUpper' in vt:p.z+=amount*.18*(1-min(1,abs(x)/.044))
                    if 'mouthInner' in vt:
                        w=max(.00001,1-(x/.043)**2);line=1.553+.010*abs(x/.043)**1.8
                        t=max(-1,min(1,(z-line)/(.0025*w)))
                        p.z=line+w*(.0025*t+amount*(-.41+.59*t))
            key.data[v.index].co=p
    for g in list(o.vertex_groups):
        if g.name.startswith('FACE_'):o.vertex_groups.remove(g)
for o in objects:
    for g in list(o.vertex_groups):
        if g.name.startswith('FACE_'):o.vertex_groups.remove(g)

# Animation: two seamless, in-place loops. Rest pose remains the saved state.
scene.render.fps=30;scene.frame_start=1;scene.frame_end=121
def reset_pose():
    for p in rig.pose.bones:p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
def create_idle(name,energetic=False):
    reset_pose();rig.animation_data_create();action=bpy.data.actions.new(name);rig.animation_data.action=action
    frames=range(1,122,5)
    for frame in frames:
        phase=(frame-1)/120*2*pi;energy=1.8 if energetic else 1
        reset_pose()
        rig.pose.bones['Hips'].location.x=.006*sin(phase)*energy
        rig.pose.bones['Hips'].location.y=.0035*(1-cos(2*phase))*energy
        rig.pose.bones['Spine'].rotation_euler[1]=.009*sin(phase)*energy
        rig.pose.bones['Chest'].rotation_euler[0]=.009*sin(phase+.2)*energy
        rig.pose.bones['Chest'].scale=(1+.008*sin(phase),1+.004*sin(phase),1+.013*sin(phase))
        rig.pose.bones['Head'].rotation_euler[1]=.025*sin(phase)*energy
        rig.pose.bones['Head'].rotation_euler[2]=.018*sin(phase)*energy
        for side,sgn in [('L',1),('R',-1)]:
            rig.pose.bones['UpperArm.'+side].rotation_euler[1]=sgn*.013*sin(phase+.4)
            rig.pose.bones['LowerArm.'+side].rotation_euler[0]=.018*sin(phase-.2)*energy
            rig.pose.bones['Hand.'+side].rotation_euler[1]=.018*sin(phase+sgn*.7)
            for fn in ['Index','Middle','Ring','Little']:
                for j in range(1,4):rig.pose.bones[f'{fn}{j}.{side}'].rotation_euler[0]=.045+.016*sin(phase+j*.3)
        for p in rig.pose.bones:
            p.keyframe_insert(data_path='location',frame=frame,group=p.name)
            p.keyframe_insert(data_path='rotation_euler',frame=frame,group=p.name)
            p.keyframe_insert(data_path='scale',frame=frame,group=p.name)
    action.use_fake_user=True
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,action);track.mute=True
    return action
normal=create_idle('idle_normal');energetic=create_idle('idle_energetic',True)
reset_pose();rig.animation_data.action=None;scene.frame_set(1)
rig['animation_notes']='Unmute exactly one NLA track to preview. Both loops are 4 seconds at 30fps. A-pose saved with tracks muted.'

# Export only the character and armature, never studio fixtures.
activate(rig)
for o in objects:o.select_set(True)
for track in rig.animation_data.nla_tracks:track.mute=False
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'Dash_Final.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_skins=True,export_morph=True,export_yup=True,export_apply=False)
bpy.ops.export_scene.fbx(filepath=os.path.join(ROOT,'Dash_Final.fbx'),use_selection=True,object_types={'ARMATURE','MESH'},apply_unit_scale=True,axis_forward='-Z',axis_up='Y',add_leaf_bones=False,bake_anim=True,bake_anim_use_all_bones=True,bake_anim_use_nla_strips=True,bake_anim_use_all_actions=False,path_mode='COPY',embed_textures=True,use_mesh_modifiers=True)
for track in rig.animation_data.nla_tracks:track.mute=True
reset_pose();scene.frame_set(1)
scene.camera=bpy.data.objects['Camera_Hero'];scene.cycles.samples=64
scene.render.resolution_x=1200;scene.render.resolution_y=1500
try:scene.view_settings.look='AgX - Medium High Contrast'
except:pass
# Open in a clean material-lit inspection view.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=2.8
            area.spaces.active.region_3d.view_location=(0,0,1)
            area.spaces.active.region_3d.view_rotation=scene.camera.rotation_euler.to_quaternion()
            area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_overlays=False
activate(bpy.data.objects['Body'])
for mat in list(bpy.data.materials):
    if mat.users==0:bpy.data.materials.remove(mat)
report={'triangles':sum(tri(o) for o in objects),'materials':len(set(m.name for o in objects for m in o.data.materials)),'textures':{'BaseColor':[2048,2048],'Roughness':[2048,2048],'optional_downscales':[1024,1024]},'bones':len(ad.bones),'shape_keys':{o.name:[k.name for k in o.data.shape_keys.key_blocks if k.name!='Basis'] for o in objects if o.data.shape_keys},'actions':['idle_normal','idle_energetic'],'meshes':stats,'validation':{}}
for o in objects:
    bm=bmesh.new();bm.from_mesh(o.data)
    report['validation'][o.name]={'non_manifold_edges':sum(not e.is_manifold for e in bm.edges),'loose_vertices':sum(not v.link_faces for v in bm.verts),'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces)}
    bm.free()
with open(os.path.join(ROOT,'validation','Dash_Asset_Report.json'),'w') as f:json.dump(report,f,indent=2)
text=bpy.data.texts.new('READ_ME_Dash');text.write('DASH / myTwin\nOriginal stylized character.\n\nA-pose is saved with NLA tracks muted. Select Dash_Armature and unmute exactly one idle track.\nMorph controls live on Body and Eyes. Apply matching blink/wide/tired values to both.\nShared atlas textures are packed in this file.\nRuntime verification and known limitations are described in the delivery README.\n')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'Dash_Final.blend'))
print('FINAL_ASSET_SAVED',json.dumps(report),flush=True)
if '--skip-renders' in sys.argv:sys.exit(0)
for name in ['Hero','ThreeQuarter','Front','Side','Back','Face']:
    scene.camera=bpy.data.objects['Camera_'+name]
    scene.render.resolution_x=1400 if name=='Hero' else 1000;scene.render.resolution_y=1700 if name=='Hero' else (1000 if name=='Face' else 1300)
    scene.render.filepath=os.path.join(ROOT,'renders','Dash_'+name+'.png');bpy.ops.render.render(write_still=True)
print('FINAL_RENDERS_COMPLETE',flush=True)
