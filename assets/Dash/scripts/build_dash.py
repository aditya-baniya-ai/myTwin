"""Dash: original authored mesh construction, Blender 4.5 LTS.
Coordinates: metres, +Z up, -Y forward. Rebuild reproducibly with Blender --python.
"""
import bpy, math, os, json, sys, random
import numpy as np
from mathutils import Vector
from math import sin, cos, pi, exp, sqrt
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
random.seed(24)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections): bpy.data.collections.remove(c)
scene=bpy.context.scene
dash=bpy.data.collections.new('Dash'); scene.collection.children.link(dash)
collections={}
for name in ['Character','Rig','Lighting','Camera','Studio']:
    c=bpy.data.collections.new(name); dash.children.link(c); collections[name]=c
parts=[]; meta={}
def material(name,color,rough=.5,subsurface=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough
    p.inputs['Subsurface Weight'].default_value=subsurface
    if subsurface: p.inputs['Subsurface Radius'].default_value=(.8,.38,.2)
    return m
palette=[('Skin',(.53,.25,.127),.54,.055),('Lip',(.40,.15,.088),.55,.025),('Hair',(.062,.022,.009),.53,0),('Sunflower',(.95,.43,.018),.72,0),('Cream',(.75,.68,.49),.76,0),('Cobalt',(.018,.115,.38),.77,0),('Ink',(.012,.032,.068),.62,0),('Chalk',(.85,.87,.81),.68,0),('Sole',(.53,.59,.61),.63,0),('Sclera',(.81,.84,.77),.25,0),('Iris',(.045,.17,.125),.25,0),('Pupil',(.003,.006,.007),.19,0)]
mats={n:material('Dash_'+n,c,r,s) for n,c,r,s in palette}
mats['Mouth']=material('Dash_Mouth',(.035,.004,.003),.82)
mats['Orange']=material('Dash_Orange',(.94,.25,.018),.7)
mats['HairLight']=material('Dash_HairLight',(.16,.065,.027),.46)
for name,color in [('Skin',(.66,.32,.19)),('Lip',(.54,.225,.15)),('Hair',(.075,.025,.01)),('Iris',(.14,.043,.006)),('Sunflower',(.90,.36,.006)),('Cobalt',(.037,.10,.25))]:
    mats[name].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1)
    mats[name].diffuse_color=(*color,1)
mats['Sleeve']=material('Dash_Sleeve',(.90,.36,.006),.72)
def activate(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
def mesh(name,verts,faces,mat,cat,sub=0,weights=None,tag=None):
    me=bpy.data.meshes.new(name+'_Mesh'); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); collections['Character'].objects.link(o); o.data.materials.append(mats[mat])
    for p in me.polygons: p.use_smooth=True
    if weights:
        for i,v in enumerate(me.vertices):
            for b,w in weights(v.co).items():
                if w>1e-6:
                    g=o.vertex_groups.get(b) or o.vertex_groups.new(name=b); g.add([i],w,'REPLACE')
    if tag:
        o.vertex_groups.new(name='FACE_'+tag).add(list(range(len(verts))),1,'REPLACE')
    if sub:
        activate(o); mod=o.modifiers.new('Authored surface refinement','SUBSURF'); mod.levels=sub
        bpy.ops.object.modifier_apply(modifier=mod.name)
    parts.append(o); meta[o.name]=cat
    return o
def rigid(b): return lambda p:{b:1}
def loft(name,rings,mat,cat,n=20,sub=1,weights=None,cap=True):
    # rings: centre, two cross section axes. Entire surfaces use quad loops.
    vs=[]; fs=[]
    for center,u,v in rings:
        for j in range(n):
            a=2*pi*j/n; vs.append(tuple(Vector(center)+Vector(u)*cos(a)+Vector(v)*sin(a)))
    for i in range(len(rings)-1):
        for j in range(n): fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    if cap: fs.extend([tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+j for j in range(n))])
    return mesh(name,vs,fs,mat,cat,sub,weights)
def zloft(name,rs,mat,cat,n=24,sub=1,weights=None):
    return loft(name,[((x,y,z),(rx,0,0),(0,ry,0)) for x,y,z,rx,ry in rs],mat,cat,n,sub,weights)
def tube(name,points,radii,mat,cat,n=8,sub=1,weights=None,tag=None):
    vs=[]; fs=[]
    for i,p in enumerate(points):
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        tangent.normalize(); ref=Vector((0,1,0))
        if abs(tangent.dot(ref))>.94: ref=Vector((1,0,0))
        u=tangent.cross(ref).normalized(); v=tangent.cross(u).normalized()
        r=radii[i] if isinstance(radii,list) else radii
        if not isinstance(r,(list,tuple)): r=(r,r)
        for j in range(n):
            a=2*pi*j/n; vs.append(tuple(Vector(p)+u*r[0]*cos(a)+v*r[1]*sin(a)))
    for i in range(len(points)-1):
        for j in range(n): fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    fs.extend([tuple(range(n-1,-1,-1)),tuple((len(points)-1)*n+j for j in range(n))])
    return mesh(name,vs,fs,mat,cat,sub,weights,tag)
def patch(name,grid,mat,cat,sub=1,weights=None,thick=.002,tag=None):
    rows=len(grid); cols=len(grid[0]); vs=[p for row in grid for p in row]
    fs=[(i*cols+j,i*cols+j+1,(i+1)*cols+j+1,(i+1)*cols+j) for i in range(rows-1) for j in range(cols-1)]
    o=mesh(name,vs,fs,mat,cat,sub,weights,tag)
    if thick:
        activate(o); m=o.modifiers.new('Panel thickness','SOLIDIFY'); m.thickness=thick
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o
def gauss(x,c,w): return exp(-((x-c)/w)**2)
def bodyweight(p):
    z=p.z
    if z<1.05:return {'Hips':1}
    if z<1.22:
        t=(z-1.05)/.17;return {'Hips':1-t,'Spine':t}
    t=min(1,(z-1.22)/.15); return {'Spine':1-t,'Chest':t}
def limbweight(side,limb,p):
    if limb=='leg':
        t=max(0,min(1,(p.z-.46)/.11));return {'UpperLeg.'+side:t,'LowerLeg.'+side:1-t}
    t=max(0,min(1,(abs(p.x)-.30)/.105));return {'UpperArm.'+side:1-t,'LowerArm.'+side:t}

# Deliberately shaped craniofacial shell, with cheek, muzzle, bridge and jaw fields.
head_profiles=[(1.505,.025,.035,.0),(1.519,.052,.068,-.006),(1.540,.086,.094,-.003),(1.568,.117,.11,.004),(1.60,.142,.121,.008),(1.635,.155,.127,.013),(1.675,.159,.132,.019),(1.715,.154,.132,.024),(1.755,.148,.129,.026),(1.797,.134,.12,.028),(1.831,.104,.092,.028),(1.86,.05,.051,.027),(1.868,.004,.004,.027)]
def interp(z,col):
    i=max(0,min(len(head_profiles)-2,int(np.searchsorted([r[0] for r in head_profiles],z)-1)))
    a=head_profiles[max(0,i-1)];b=head_profiles[i];c=head_profiles[i+1];d=head_profiles[min(len(head_profiles)-1,i+2)]
    t=(z-b[0])/(c[0]-b[0]);m0=(c[col]-a[col])/(c[0]-a[0])*(c[0]-b[0]);m1=(d[col]-b[col])/(d[0]-b[0])*(c[0]-b[0])
    return (2*t**3-3*t*t+1)*b[col]+(t**3-2*t*t+t)*m0+(-2*t**3+3*t*t)*c[col]+(t**3-t*t)*m1
def face_y(x,z):
    rx=interp(z,1); ry=interp(z,2); cy=interp(z,3)
    base=cy-ry*sqrt(max(.001,1-(x/max(.001,rx))**2))
    cheek=.014*(gauss(x,.095,.038)+gauss(x,-.095,.038))*gauss(z,1.645,.040)
    muzzle=.014*gauss(x,0,.065)*gauss(z,1.602,.035)
    nose=.036*gauss(x,0,.024)*gauss(z,1.646,.018)+.010*gauss(x,0,.017)*gauss(z,1.678,.034)+.008*(gauss(x,.020,.009)+gauss(x,-.020,.009))*gauss(z,1.639,.010)
    sockets=.009*(gauss(x,.063,.032)+gauss(x,-.063,.032))*gauss(z,1.695,.036)
    return base-cheek-muzzle-nose+sockets
vs=[];fs=[]; N=80; R=56
for i in range(R):
    z=1.505+(1.868-1.505)*i/(R-1);rx=interp(z,1);ry=interp(z,2);cy=interp(z,3)
    for j in range(N):
        a=2*pi*j/N; x=rx*sin(a); y=cy-ry*cos(a)
        if cos(a)>0: y=face_y(x,z)
        vs.append((x,y,z))
for i in range(R-1):
    for j in range(N):fs.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
fs.extend([tuple(range(N-1,-1,-1)),tuple((R-1)*N+j for j in range(N))])
head=mesh('Body_SculptedFace',vs,fs,'Skin','Body',0,rigid('Head'),'head')
zloft('Body_Neck',[(0,.015,z,rx,ry) for z,rx,ry in [(1.345,.06,.049),(1.36,.055,.047),(1.42,.044,.042),(1.49,.046,.046),(1.53,.05,.048)]],'Skin','Body',24,1,lambda p:{'Neck':max(0,min(1,(1.5-p.z)/.07)),'Head':max(0,min(1,(p.z-1.43)/.07))})

for sign,side in [(1,'L'),(-1,'R')]:
    # Auricle with helix, concha and antitragus, sculpted flattened surfaces.
    zloft('Ear_'+side,[(sign*x,y,z,rx,ry) for z,x,y,rx,ry in [(1.607,.142,.006,.008,.008),(1.613,.151,.008,.016,.017),(1.639,.155,.008,.022,.023),(1.67,.153,.01,.021,.025),(1.684,.147,.014,.009,.011)]],'Skin','Body',20,1,rigid('Head'))
    pts=[(sign*(.150+.012*sin(t*pi)), -.013-.004*sin(t*pi),1.620+.052*t) for t in np.linspace(0,1,9)]
    tube('Ear_Helix_'+side,pts,[.003,.005,.005,.005,.005,.005,.005,.004,.002],'Skin','Body',8,1,rigid('Head'))
    tube('Ear_Concha_'+side,[(sign*.153,-.016,1.631),(sign*.161,-.017,1.644),(sign*.156,-.015,1.660)],[.003,.008,.002],'Lip','Body',10,1,rigid('Head'))
    # Eye surface: almond boundary + concentric domed loops, not exposed eyeball spheres.
    cx=sign*.063;cz=1.694; ey=-.118
    def socket_offset(x,z):return .009*(gauss(x,.063,.032)+gauss(x,-.063,.032))*gauss(z,1.695,.036)
    def ocular_y(x,z,r):return face_y(x,z)-socket_offset(x,z)-.002-.009*(1-r*r)
    def almond(a,scale=1):
        return cx+.039*cos(a)*scale,cz+(.031 if sin(a)>0 else .025)*sin(a)*scale+sign*.003*cos(a)*scale
    vs=[(cx,ocular_y(cx,cz,0),cz)];fs=[]
    for k in range(1,7):
        r=k/6
        for j in range(48):
            x,z=almond(2*pi*j/48,r);vs.append((x,ocular_y(x,z,r),z))
    for j in range(48):fs.append((0,1+j,1+(j+1)%48))
    for k in range(5):
        for j in range(48):fs.append((1+k*48+j,1+k*48+(j+1)%48,1+(k+1)*48+(j+1)%48,1+(k+1)*48+j))
    # closed back, intentional eye shell seated in the orbital opening
    fs.append(tuple(1+5*48+j for j in range(47,-1,-1)))
    mesh('Eye_Sclera_'+side,vs,fs,'Sclera','Eyes',0,rigid('Head'),'eye'+side)
    # Iris and pupil radially modelled as convex disks.
    for label,radius,y,mat in [('Iris',.025,-.127,'Iris'),('Pupil',.014,-.1295,'Pupil')]:
        offset=.0012 if label=='Iris' else .0025
        vs=[(cx,ocular_y(cx,cz+.005,0)-offset,cz+.005)];fs=[]
        for k in range(1,5):
            for j in range(40):
                a=j*2*pi/40;r=radius*k/4;x=cx+r*cos(a);zz=cz+.005+r*sin(a)
                half=sqrt(max(0,1-((x-cx)/.039)**2));zz=max(cz-.0247*half+sign*.003*(x-cx)/.039,min(cz+.0307*half+sign*.003*(x-cx)/.039,zz))
                rr=sqrt(((x-cx)/.039)**2+((zz-cz)/(.031 if zz>cz else .025))**2)
                vs.append((x,ocular_y(x,zz,min(1,rr))-offset,zz))
        for j in range(40):fs.append((0,j+1,(j+1)%40+1))
        for k in range(3):
            for j in range(40):fs.append((1+k*40+j,1+k*40+(j+1)%40,1+(k+1)*40+(j+1)%40,1+(k+1)*40+j))
        fs.append(tuple(121+j for j in range(39,-1,-1)))
        mesh('Eye_'+label+'_'+side,vs,fs,mat,'Eyes',0,rigid('Head'),'eye'+side)
    # Orbital annulus blends raised lid margin into cheek/brow surfaces.
    grid=[]
    for k in range(5):
        t=k/4;row=[]
        for j in range(49):
            a=2*pi*j/48;x,z=almond(a,1+.27*t);ix,iz=almond(a,1)
            y=(ocular_y(ix,iz,1)-.0003)*(1-t)+(face_y(x,z)+.0005)*t-.0015*sin(pi*t)
            row.append((x,y,z))
        grid.append(row)
    # Fine lid margins join the carved facial socket without a raised orbital plate.
    for upper in [True,False]:
        pts=[]
        for a in np.linspace(0,pi,25) if upper else np.linspace(pi,2*pi,25):
            x,z=almond(a);pts.append((x,ocular_y(x,z,1)-.0003,z))
        tube('Face_LidContour_'+side+str(upper),pts,[.0006]+[.0018 if upper else .0012]*23+[.0006],'Skin','Body',8,1,rigid('Head'),'lid'+side)
    # Upper waterline/lash edge, subtly darker than the skin.
    pts=[]
    for a in np.linspace(.05,pi-.05,19):
        x,z=almond(a);pts.append((x,ocular_y(x,z,1)-.001,z+.0005))
    tube('Face_UpperLidMargin_'+side,pts,[.0004]+[.0011]*17+[.0004],'Hair','Body',6,1,rigid('Head'),'lid'+side)
    # Shaped brows, tapering at temples; neutral asymmetric lift.
    pts=[];rads=[]
    for t in np.linspace(0,1,10):
        x=sign*(.024+.079*t);z=1.744+.012*sin(t*pi)-.004*t+(0.0015 if side=='L' else 0)
        pts.append((x,face_y(x,z)-.005,z));rads.append((.002+.0065*sin(pi*(.12+.88*t)),.0035))
    tube('Face_Brow_'+side,pts,rads,'Hair','Body',8,2,rigid('Head'),'brow'+side)

# Small inset nostrils under the integrated nose wings.
for s in [-1,1]:
    tube('Face_Nostril_'+str(s),[(s*x,face_y(s*x,z)-.0005,z) for x,z in [(.011,1.633),(.016,1.632),(.020,1.635)]],[.0006,.0017,.0006],'Lip','Body',8,1,rigid('Head'),'nose')
# Shaped lip ribbons and a genuine inner mouth volume.
def mouthline(t):return 1.600+.010*abs(t)**1.8
vs=[];fs=[]
for i in range(6):
    v=i/5
    for j in range(33):
        t=-1+2*j/32;x=.043*t; z=mouthline(t)+(.0025-.005*v)*(1-t*t)
        vs.append((x,face_y(x,z)-.003,z))
for i in range(5):
    for j in range(32):fs.append((i*33+j,i*33+j+1,(i+1)*33+j+1,(i+1)*33+j))
o=mesh('Face_MouthCavity',vs,fs,'Mouth','Body',0,rigid('Head'),'mouthInner')
activate(o);m=o.modifiers.new('Inner mouth depth','SOLIDIFY');m.thickness=.012;m.offset=1;bpy.ops.object.modifier_apply(modifier=m.name)
for upper in [True,False]:
    grid=[]
    for i in range(5):
        v=i/4;row=[]
        for j in range(33):
            t=-1+2*j/32;x=.044*t;w=(1-t*t)
            fullness=(.0035 if upper else -.0055)*w
            if upper:fullness*=1-.25*gauss(t,0,.2)
            z=mouthline(t)+fullness*v
            y=face_y(x,z)-.0015-.002*sin(pi*v)*w
            row.append((x,y,z))
        grid.append(row)
    patch('Face_'+('UpperLip' if upper else 'LowerLip'),grid,'Lip','Body',0,rigid('Head'),.001,'lipUpper' if upper else 'lipLower')

# Garments: shaped torso loops and a separately tailored open-front jacket.
shirt_rs=[(0,.014,z,rx,ry) for z,rx,ry in [(1.003,.133,.086),(1.012,.135,.087),(1.07,.13,.08),(1.18,.146,.087),(1.29,.168,.09),(1.34,.172,.085),(1.38,.119,.071),(1.397,.066,.052)]]
zloft('Shirt_Torso',shirt_rs,'Chalk','Shirt',32,2,bodyweight)
pts=[(.063*cos(a),.014+.051*sin(a),1.397+.005*cos(a*2)) for a in np.linspace(0,2*pi,49)]
tube('Shirt_Crewneck',pts,.005,'Cream','Shirt',8,1,bodyweight)
jacket_rs=[(1.025,.152,.100),(1.032,.155,.103),(1.065,.16,.106),(1.10,.164,.104),(1.16,.158,.096),(1.23,.166,.101),(1.29,.183,.104),(1.34,.193,.102),(1.374,.160,.09),(1.412,.074,.063)]
for s,side in [(1,'L'),(-1,'R')]:
    grid=[]
    for i,(z,rx,ry) in enumerate(jacket_rs):
        row=[]
        for j in range(25):
            opening=.34+.055*cos((z-1.03)*8)
            a=opening+(pi-opening)*j/24;x=s*rx*sin(a); y=.018-ry*cos(a)
            fold=.007*sin(a*6+z*32)*sin(pi*i/(len(jacket_rs)-1))
            y+=fold*cos(a);x+=s*fold*sin(a)
            row.append((x,y,z))
        grid.append(row)
    patch('Jacket_FrontBack_'+side,grid,'Sunflower','Jacket',2,bodyweight,.004)
    # zipper placket and tailored hem, collar and hip pocket welt
    pts=[(s*rx*sin(.34+.055*cos((z-1.03)*8)),.018-ry*cos(.34+.055*cos((z-1.03)*8))-.004,z) for z,rx,ry in jacket_rs]
    tube('Jacket_ZipTape_'+side,pts,.006,'Sunflower','Jacket',8,1,bodyweight)
    tube('Jacket_ZipTeeth_'+side,[(x+s*.004,y-.003,z) for x,y,z in pts],.0016,'Ink','Jacket',6,1,bodyweight)
    pts=[(s*.155*sin(a),.018-.104*cos(a),1.047) for a in np.linspace(.4,pi,30)]
    tube('Jacket_WaistBand_'+side,pts,.012,'Sunflower','Jacket',8,1,bodyweight)
    pts=[(s*(.078+.050*t),-.084+.023*t,1.13+.037*t) for t in np.linspace(0,1,8)]
    tube('Jacket_PocketWelt_'+side,pts,.006,'Sunflower','Jacket',8,1,bodyweight)
    tube('Jacket_PocketOpening_'+side,[(x,y-.005,z+.003) for x,y,z in pts],.0018,'Ink','Jacket',6,1,bodyweight)
    # Standing collar has a distinct cream edge.
    pts=[(s*.073*sin(a),.018-.065*cos(a),1.407+.013*sin(a/2)) for a in np.linspace(.22,pi,24)]
    tube('Jacket_Collar_'+side,pts,[.009]*24,'Cream','Jacket',10,1,bodyweight)
    # Bent/tapered sleeve loops preserve shoulder, elbow and cuff volumes.
    armpts=[(s*x,y,z) for x,y,z in [(.123,.018,1.334),(.158,.014,1.342),(.212,.012,1.324),(.251,.006,1.278),(.29,0,1.226),(.309,-.004,1.199),(.321,-.008,1.18),(.337,-.012,1.16),(.366,-.017,1.121),(.397,-.021,1.081),(.411,-.023,1.063)]]
    rads=[(.063,.070),(.076,.080),(.077,.081),(.073,.077),(.071,.075),(.061,.064),(.073,.071),(.068,.074),(.071,.071),(.051,.057),(.046,.048)]
    sleeve=tube('Jacket_Sleeve_'+side,armpts,rads,'Sunflower','Jacket',24,2,lambda p,sd=side:limbweight(sd,'arm',p))
    sleeve.data.materials.append(mats['Orange']);sleeve.data.materials.append(mats['Chalk'])
    for p in sleeve.data.polygons:
        q=abs(p.center.x)+.25*p.center.y
        if .265<q<.305:p.material_index=1
        elif .305<q<.320:p.material_index=2
    for v in sleeve.data.vertices:
        x=abs(v.co.x);v.co.y+=.008*sin(x*130+v.co.z*30)*gauss(x,.365,.038)
    # Contrasting curved seam follows raglan shoulder, no logos.
    pts=[(s*x,y,z) for x,y,z in [(.10,-.053,1.397),(.14,-.064,1.369),(.177,-.058,1.338),(.203,-.051,1.31),(.226,-.045,1.287)]]
    tube('Jacket_RaglanPiping_'+side,pts,.003,'Chalk','Jacket',8,1,lambda p,sd=side:limbweight(sd,'arm',p))
    tube('Jacket_Cuff_'+side,[(s*.398,-.021,1.082),(s*.405,-.023,1.073),(s*.419,-.025,1.053),(s*.428,-.025,1.037)],[(.047,.049),(.048,.049),(.045,.047),(.042,.043)],'Sunflower','Jacket',24,1,rigid('LowerArm.'+side))

# Hands: palm plane, then three joint loops per individual finger.
finger_bones=[]
for s,side in [(1,'L'),(-1,'R')]:
    wrist=Vector((s*.425,-.025,1.043)); down=Vector((s*.53,0,-.848)); across=Vector((s*.848,0,.53))
    centers=[wrist+down*t for t in [-.018,.008,.035,.062,.075]]
    loft('Body_Palm_'+side,[(tuple(c),tuple(across*w),(0,d,0)) for c,w,d in zip(centers,[.023,.029,.035,.033,.027],[.022,.022,.021,.018,.014])],'Skin','Body',20,2,rigid('Hand.'+side))
    for k,(fn,length) in enumerate([('Index',.065),('Middle',.074),('Ring',.066),('Little',.052)]):
        offset=(k-1.5)*.018
        base=wrist+down*.066+across*offset
        direction=(down+across*((k-1.5)*.075)).normalized()
        joints=[base,base+direction*length*.42+Vector((0,-.004,0)),base+direction*length*.74+Vector((0,-.010,0)),base+direction*length+Vector((0,-.017,0))]
        for j in range(3): finger_bones.append((f'{fn}{j+1}.{side}',tuple(joints[j]),tuple(joints[j+1]),'Hand.'+side if j==0 else f'{fn}{j}.{side}'))
        pts=[];rads=[]
        for t in [0,.07,.30,.42,.50,.68,.75,.85,.94,1]:
            p=base+direction*length*t+Vector((0,-.017*t*t,0));pts.append(tuple(p))
            r=(.009 if k<3 else .0077)*(1-.28*t)
            if t==1:r=.003
            rads.append((r,r*.88))
        def fw(p,base=base,direction=direction,length=length,fn=fn,side=side):
            t=max(0,min(.999,(p-base).dot(direction)/length))
            q=t*3-.5; lo=max(0,min(2,int(math.floor(q)))); hi=min(2,lo+1);f=max(0,min(1,q-lo))
            if lo==hi:return {f'{fn}{lo+1}.{side}':1}
            return {f'{fn}{lo+1}.{side}':1-f,f'{fn}{hi+1}.{side}':f}
        tube('Body_'+fn+'_'+side,pts,rads,'Skin','Body',10,1,fw)
        # Small flattened, rounded nail plate follows the distal phalanx.
        nailgrid=[]
        for t in [.78,.82,.90,.95]:
            row=[]
            for u in [-1,-.7,.7,1]:
                p=base+direction*length*t+across*.0044*u+Vector((0,-.017*t*t-.006,0));row.append(tuple(p))
            nailgrid.append(row)
        # Nail beds are left within the finger surface to avoid floating micro-panels.
    base=wrist+down*.024-across*.023
    joints=[base,base+down*.013-across*.028+Vector((0,-.004,0)),base+down*.035-across*.036+Vector((0,-.012,0)),base+down*.047-across*.033+Vector((0,-.018,0))]
    for j in range(3):finger_bones.append((f'Thumb{j+1}.{side}',tuple(joints[j]),tuple(joints[j+1]),'Hand.'+side if j==0 else f'Thumb{j}.{side}'))
    tube('Body_Thumb_'+side,[tuple(p) for p in joints],[.016,.014,.010,.004],'Skin','Body',12,2,rigid('Thumb2.'+side))

# Joggers, with a broad seat, diagonal knee creases and a narrow ribbed ankle.
for s,side in [(1,'L'),(-1,'R')]:
    rs=[]
    for z,x,y,rx,ry in [(.158,.123,.025,.048,.052),(.175,.123,.025,.052,.055),(.21,.123,.025,.059,.059),(.27,.124,.024,.066,.065),(.37,.126,.018,.068,.074),(.455,.127,-.002,.067,.077),(.49,.127,-.009,.070,.079),(.525,.124,-.007,.073,.075),(.565,.121,.0,.076,.078),(.66,.111,.009,.085,.086),(.77,.100,.013,.091,.093),(.88,.09,.013,.097,.102),(.96,.081,.017,.096,.105),(1.00,.078,.017,.089,.10)]:
        fullness=1.0+.15*gauss(z,.30,.15)+.09*gauss(z,.73,.20)
        z+=.058*max(0,1-(z-.154)/.14)**2
        rs.append((s*x,y,z,rx*fullness,ry*fullness))
    o=zloft('Pants_TailoredLeg_'+side,rs,'Cobalt','Pants',28,2,lambda p,sd=side:limbweight(sd,'leg',p))
    # Authored fabric compression, not a uniform cylinder.
    for v in o.data.vertices:
        z=v.co.z;x=v.co.x
        front=max(0,min(1,(-v.co.y+.015)/.085))
        v.co.y+=front*(.005*sin((z-.47)*95+(abs(x)-.12)*32)*gauss(z,.50,.07)+.009*sin(z*94+(abs(x)-.12)*35)*gauss(z,.28,.09))
        v.co.x+=s*.005*cos(z*93+v.co.y*30)*gauss(z,.29,.075)
    zloft('Pants_AnkleCuff_'+side,[(s*.123,.025,z+.058,rx,ry) for z,rx,ry in [(.154,.047,.049),(.16,.049,.052),(.187,.051,.052),(.193,.05,.052)]],'Cobalt','Pants',24,1,rigid('LowerLeg.'+side))
    zloft('Body_Ankle_'+side,[(s*.123,.025,z,.037,.04) for z in [.176,.18,.223,.231]],'Skin','Body',20,1,rigid('LowerLeg.'+side))
    pts=[(s*x,y,z) for x,y,z in [(.168,-.03,.97),(.178,-.025,.91),(.188,-.018,.84),(.199,.012,.78),(.206,.017,.70)]]
    tube('Pants_SideSeam_'+side,pts,.0027,'Cobalt','Pants',6,1,lambda p,sd=side:limbweight(sd,'leg',p))
    # Side pocket panel with curved, finished corners.
    grid=[]
    for z in [.715,.725,.833,.843]:
        row=[]
        for a in [.68,.73,1.22,1.27]:
            xp=float(np.interp(z,[r[2] for r in rs],[r[0] for r in rs]));yp=float(np.interp(z,[r[2] for r in rs],[r[1] for r in rs]));rx=float(np.interp(z,[r[2] for r in rs],[r[3] for r in rs]));ry=float(np.interp(z,[r[2] for r in rs],[r[4] for r in rs]))
            row.append((xp+s*(rx*sin(a)+.006),yp-ry*cos(a)-.004,z))
        grid.append(row)
    patch('Pants_UtilityPocket_'+side,grid,'Cobalt','Pants',2,rigid('UpperLeg.'+side),.002)
    tube('Pants_YellowPocketTab_'+side,[(s*.206,-.033,.839),(s*.207,-.034,.820),(s*.207,-.034,.801)],[.006,.007,.006],'Sunflower','Pants',8,1,rigid('UpperLeg.'+side))
zloft('Pants_Waist',[(0,.017,z,.171,ry) for z,ry in [(.985,.096),(.995,.1),(1.024,.095),(1.031,.093)]],'Cobalt','Pants',32,1,rigid('Hips'))

# Layered running shoes. Each is a custom swept footprint, shaped instep and heel.
for s,side in [(1,'L'),(-1,'R')]:
    cx=s*.123
    def foot_outline(a,width,length):
        # front (-Y) is rounded and broad; heel is intentionally narrower.
        return cx+width*cos(a)*(1-.19*max(0,sin(a))),-.070+length*sin(a)
    for name,zs,scales,mat in [('Outsole',[.018,.022,.033,.038],[.96,1,1,.97],'Sole'),('Midsole',[.036,.041,.064,.072],[.97,1,1,.95],'Chalk'),('MidsoleAccent',[.045,.048,.052,.054],[1.005,1.008,1.008,1.005],'Sole')]:
        vs=[];fs=[];n=48
        for z,scale in zip(zs,scales):
            for j in range(n):
                a=j*2*pi/n;x,y=foot_outline(a,.083*scale,.153*scale)
                vs.append((x,y,z+.013*max(0,-sin(a))**5))
        for i in range(len(zs)-1):
            for j in range(n):fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
        fs.extend([tuple(range(n-1,-1,-1)),tuple((len(zs)-1)*n+j for j in range(n))])
        mesh('Shoes_'+name+'_'+side,vs,fs,mat,'Shoes',1,rigid('Foot.'+side))
    # Shoe upper has a tall heel collar and low domed toe.
    vs=[];fs=[];n=48
    for k in range(10):
        t=k/9;scale=cos(t*pi/2)*.96+.025
        for j in range(n):
            a=j*2*pi/n;x,y=foot_outline(a,.08*scale,.146*scale)
            y+=.035*t
            height=.076+.049*(sin(a)+1)/2
            z=.066+height*sin(t*pi/2)
            vs.append((x,y,z))
    for k in range(9):
        for j in range(n):fs.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
    fs.extend([tuple(range(n-1,-1,-1)),tuple(9*n+j for j in range(n))])
    upper=mesh('Shoes_Upper_'+side,vs,fs,'Chalk','Shoes',1,rigid('Foot.'+side))
    upper.data.materials.append(mats['Cobalt'])
    for p in upper.data.polygons:
        center=p.center
        if center.y>-.013 and .074<center.z<.152:p.material_index=1
    # Toe guard: arced reinforced panel hugging the front.
    grid=[]
    for k in range(4):
        row=[]
        for a in np.linspace(pi,2*pi,25):
            t=.025+.105*k;scale=cos(t*pi/2)*.96+.025
            x,y=foot_outline(a,.08*scale+.0015,.146*scale+.0015);y+=.035*t
            height=.076+.049*(sin(a)+1)/2
            row.append((x,y,.068+height*sin(t*pi/2)))
        grid.append(row)
    patch('Shoes_ToeGuard_'+side,grid,'Cream','Shoes',1,rigid('Foot.'+side),.002)
    # Blue heel support, yellow floating eyestay and white lacing.
    for side_sign in [-1,1]:
        grid=[]
        for t in [.08,.12,.46,.51]:
            row=[]
            for a in np.linspace(-.06,1.62,14):
                scale=cos(t*pi/2)*.96+.025
                x=cx+side_sign*(.08*scale+.002)*cos(a)*(1-.19*max(0,sin(a)))
                y=-.070+(.146*scale+.002)*sin(a)+.035*t
                height=.076+.049*(sin(a)+1)/2
                row.append((x,y,.068+height*sin(t*pi/2)))
            grid.append(row)
        # Heel support follows the upper's edge loops; avoid intersecting overlay shells.
        pts=[(cx+side_sign*(.03+.008*t),-.120+.097*t,.141+.032*t) for t in np.linspace(0,1,9)]
        tube('Shoes_Eyestay_'+side+str(side_sign),pts,[.006]*9,'Sunflower','Shoes',8,1,rigid('Foot.'+side))
    for k in range(5):
        y=-.116+.018*k;z=.146+.006*k
        pts=[(cx-.031,y,z),(cx-.015,y+.006,z+.007),(cx+.014,y-.002,z+.008),(cx+.033,y+.004,z)]
        tube('Shoes_Lace_'+side+str(k),pts,.0032,'Chalk','Shoes',8,1,rigid('Foot.'+side))
    tube('Shoes_PullTab_'+side,[(cx,.064,.122),(cx,.079,.153),(cx,.065,.187),(cx,.046,.173)],[.008,.009,.01,.008],'Sunflower','Shoes',8,1,rigid('Foot.'+side))
    # Outsole segmentation makes small-scale sneaker construction legible.
    for k in range(0):
        y=-.18+k*.044
        for ss in [-1,1]:
            tube('Shoes_Tread_'+side+str(k)+str(ss),[(cx+ss*.066,y,.027),(cx+ss*.071,y,.021),(cx+ss*.053,y-.006,.018)],.002,'Ink','Shoes',6,1,rigid('Foot.'+side))

# Hair cap conforms to the cranium, with a designed swept fringe and side locks.
vs=[];fs=[];n=64
for k in range(10):
    t=k/9
    for j in range(n):
        a=2*pi*j/n;bottom=1.674+(.065 if cos(a)>0 else .077)*cos(a)+.003*sin(7*a)
        z=bottom+(1.849-bottom)*t;rx=interp(z,1)+.004;ry=interp(z,2)+.004;cy=interp(z,3)
        vs.append((rx*sin(a),cy-ry*cos(a),z))
for k in range(9):
    for j in range(n):fs.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
hairbase=mesh('Hair_Base',vs,fs,'Hair','Hair',1,rigid('Head'))
activate(hairbase);hm=hairbase.modifiers.new('Hair shell','SOLIDIFY');hm.thickness=.003;bpy.ops.object.modifier_apply(modifier=hm.name)
locks=[([(-.128,-.041,1.773),(-.137,-.082,1.747),(-.128,-.099,1.716),(-.12,-.073,1.707)],[.014,.018,.014,.001]),
       ([(-.11,-.065,1.786),(-.099,-.13,1.751),(-.073,-.143,1.741),(-.053,-.13,1.732)],[.015,.020,.017,.001]),
       ([(-.065,-.067,1.789),(-.034,-.13,1.756),(.009,-.141,1.744),(.036,-.13,1.738)],[.016,.021,.018,.001]),
       ([(.006,-.056,1.785),(.056,-.12,1.763),(.087,-.126,1.744),(.107,-.103,1.727)],[.015,.02,.017,.001]),
       ([(.09,-.045,1.778),(.129,-.066,1.752),(.142,-.062,1.717),(.14,-.033,1.697)],[.016,.020,.016,.001])]
for k,(pts,r) in enumerate(locks):
    tube('Hair_SweptLock_'+str(k),pts,[(v,v*.55) for v in r],'Hair','Hair',12,2,rigid('Head'))
    # subtle raised flow ridge in the same material, not individual strands
    tube('Hair_FlowRidge_'+str(k),[(x,y-.009,z+.006) for x,y,z in pts],[.0008,.0025,.002,.0003],'Hair','Hair',6,1,rigid('Head'))
for s in [-1,1]:
    tube('Hair_Sideburn_'+str(s),[(s*.14,-.015,1.74),(s*.147,-.025,1.704),(s*.141,-.022,1.678)],[(.02,.012),(.018,.011),(.003,.002)],'Hair','Hair',12,2,rigid('Head'))
    for k in range(4):
        a=.42+k*.30;pts=[]
        for z in [1.709,1.652,1.604+.024*cos(a)]:
            pts.append((s*(interp(z,1)+.006)*cos(a),interp(z,3)+(interp(z,2)+.006)*sin(a),z))
        tube('Hair_Nape_'+str(s)+str(k),pts,[(.017,.006),(.014,.005),(.002,.001)],'Hair','Hair',10,1,rigid('Head'))
# Original low-profile five-panel cap; a short upturned bill, no graphic/logo.
rs=[(0,.031,z,rx,ry) for z,rx,ry in [(1.772,.148,.127),(1.78,.151,.13),(1.812,.145,.127),(1.846,.127,.112),(1.864,.089,.080),(1.87,.018,.02)]]
zloft('Cap_Crown',rs,'Sunflower','Cap',40,2,rigid('Head'))
pts=[(.15*cos(a),.031+.129*sin(a),1.783+.002*cos(a)) for a in np.linspace(0,2*pi,65)]
tube('Cap_Binding',pts,.0022,'Sunflower','Cap',8,1,rigid('Head'))
grid=[]
for i in range(7):
    t=i/6;row=[]
    for j in range(33):
        u=-1+2*j/32;x=.133*u*(1+.055*t)
        y=-.033-.068*sqrt(max(0,1-u*u))-.080*t*(1-.34*u*u)
        z=1.784-.026*(1-u*u)*t+.015*t*t
        row.append((x,y,z))
    grid.append(row)
patch('Cap_ShortCurvedBill',grid,'Sunflower','Cap',1,rigid('Head'),.006)
tube('Cap_BillEdge',[(x,y-.001,z-.001) for x,y,z in grid[-1]],.0015,'Cream','Cap',8,1,rigid('Head'))
for s in [-1,1]:
    pts=[(s*x,y,z) for x,y,z in [(.11,-.047,1.791),(.10,-.054,1.821),(.068,-.039,1.859),(.01,.023,1.872)]]
    tube('Cap_PanelSeam_'+str(s),pts,.0013,'Cream','Cap',6,1,rigid('Head'))
    # restrained side ventilation slots, functional details
    for k in range(3):
        x=s*(.143-.006*k);y=.020+.019*k;z=1.817
        tube('Cap_Vent_'+str(s)+str(k),[(x,y,z),(x,y+.005,z+.006)],[.0018,.0018],'Ink','Cap',8,1,rigid('Head'))
tube('Cap_BackAdjuster',[(-.034,.161,1.79),(0,.165,1.79),(.035,.161,1.79)],.008,'Ink','Cap',8,1,rigid('Head'))

# Approved-reference revision: replace the capped haircut with voluminous swept hair.
for o in list(parts):
    if meta[o.name] in ['Hair','Cap'] or o.name.startswith(('Jacket_Collar','Jacket_FrontBack')):
        parts.remove(o);bpy.data.objects.remove(o,do_unlink=True)
grid=[]
for i,(z,rx,ry) in enumerate(jacket_rs):
    row=[];opening=.34+.055*cos((z-1.03)*8)
    for j in range(49):
        a=opening+(2*pi-2*opening)*j/48
        fold=.007*sin(a*6+z*32)*sin(pi*i/(len(jacket_rs)-1))
        row.append(((rx+fold)*sin(a),.018-(ry-fold)*cos(a),z))
    grid.append(row)
patch('Jacket_FrontBack_L',grid,'Sunflower','Jacket',2,bodyweight,.004)
vs=[];fs=[];n=64
for k in range(12):
    t=k/11
    for j in range(n):
        a=2*pi*j/n;bottom=1.690+(.135 if cos(a)>0 else .077)*cos(a)+.005*sin(a*5)
        z=bottom+(1.918-bottom)*t
        rad=(1-t*t)**.46
        rx=(.167+.012*sin(pi*t))*rad;ry=(.137+.020*sin(pi*t))*rad
        vs.append((rx*sin(a),.025-ry*cos(a),z))
for k in range(11):
    for j in range(n):fs.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
fs.append(tuple(11*n+j for j in range(n)))
hairbase=mesh('Hair_SculptedVolume',vs,fs,'Hair','Hair',1,rigid('Head'))
activate(hairbase);mod=hairbase.modifiers.new('Closed hairline','SOLIDIFY');mod.thickness=.004;bpy.ops.object.modifier_apply(modifier=mod.name)
def hairlock(name,control,width,depth,highlight=False):
    control=[(x,y,1.88+(z-1.88)*.67 if z>1.88 else z) for x,y,z in control]
    width*=.89;depth*=.90
    pts=[];rs=[]
    for t in np.linspace(0,1,13):
        q=[Vector(p) for p in control]
        while len(q)>1:q=[a*(1-t)+b*t for a,b in zip(q[:-1],q[1:])]
        pts.append(tuple(q[0]));w=width*(.43*(1-t)+.83*sin(pi*t)**.65)
        rs.append((max(.0008,w),max(.0006,depth*(.55*(1-t)+.6*sin(pi*t)))))
    tube('Hair_'+name,pts,rs,'HairLight' if highlight else 'Hair','Hair',10,1,rigid('Head'))
    ridge=[(x,y-depth*.75,z+.001) for x,y,z in pts[1:-1]]
    # Broad locks carry their own highlights; no raised central ridge that reads as a leaf.
hairlock('Fringe_A',[(.05,-.09,1.895),(-.005,-.167,1.901),(-.112,-.180,1.855),(-.188,-.129,1.825)],.047,.023,True)
hairlock('Fringe_B',[(.028,-.102,1.883),(-.018,-.175,1.842),(-.115,-.183,1.802),(-.172,-.137,1.775)],.042,.022)
hairlock('Fringe_C',[(.005,-.117,1.865),(-.037,-.182,1.806),(-.068,-.185,1.767),(-.098,-.159,1.739)],.033,.021)
hairlock('PartForelock',[(.058,-.092,1.890),(.017,-.172,1.863),(-.001,-.176,1.796),(-.012,-.15,1.761)],.030,.022,True)
hairlock('TempleLeft', [(-.12,-.054,1.826),(-.17,-.103,1.784),(-.17,-.096,1.733),(-.159,-.069,1.702)],.025,.016)
hairlock('TempleRight',[(.055,-.065,1.892),(.118,-.12,1.874),(.152,-.128,1.795),(.171,-.075,1.770)],.038,.022,True)
hairlock('RightSweep',[(.068,-.035,1.88),(.164,-.071,1.874),(.159,-.090,1.809),(.194,-.042,1.805)],.033,.020)
hairlock('RightSide',[(.133,-.018,1.831),(.178,-.055,1.789),(.159,-.069,1.739),(.164,-.032,1.703)],.027,.014)
hairlock('CrownLeft',[(.043,.003,1.882),(-.027,-.032,1.973),(-.109,-.034,1.967),(-.182,-.01,1.945)],.042,.027,True)
hairlock('CrownWave',[(.073,.011,1.886),(.012,-.043,1.996),(-.071,-.028,1.989),(-.119,.001,2.019)],.037,.025)
hairlock('CrownSpire',[(.071,.042,1.883),(.067,.012,1.995),(.034,.030,2.029),(-.019,.057,2.024)],.032,.023,True)
hairlock('CrownRight',[(.066,.029,1.886),(.124,-.013,1.968),(.16,.015,1.952),(.199,.052,1.938)],.034,.025)
hairlock('SideFlickLeft',[(-.073,.025,1.856),(-.17,.026,1.917),(-.175,-.005,1.874),(-.208,-.01,1.887)],.035,.024)
hairlock('LeftMidFlick',[(-.08,-.07,1.846),(-.176,-.122,1.840),(-.187,-.098,1.804),(-.222,-.045,1.833)],.022,.013)
hairlock('LeftLowFlick',[(-.117,-.036,1.797),(-.172,-.093,1.768),(-.177,-.065,1.715),(-.199,-.016,1.727)],.020,.012)
hairlock('FringeFine',[(-.025,-.12,1.865),(-.072,-.178,1.822),(-.128,-.165,1.775),(-.152,-.129,1.756)],.018,.010,True)
for s,side in [(1,'L'),(-1,'R')]:
    for k in range(5):
        a=.32+k*.29
        hairlock('Rear_'+side+str(k),[(s*.10*cos(a),.025+.095*sin(a),1.89),(s*.175*cos(a),.025+.156*sin(a),1.842),(s*.159*cos(a),.032+.145*sin(a),1.72),(s*.14*cos(a),.02+.126*sin(a),1.618+.028*cos(a))],.023,.011,k%3==0)

# Raised hood: continuous outer drape, warm inner lining and substantial soft rim.
rim=[];grid=[]
for j in range(49):
    a=-pi/2+2*pi*j/48
    # Cut front opening into a U; endpoints flank the zip at the throat.
    a=-.92+ (pi+1.84)*j/48
    x=.164*cos(a);y=.026+.121*sin(a);z=1.455+.025*sin(a)+.024*cos(a*2)
    rim.append((x,y,z))
for k in range(7):
    t=k/6;row=[]
    for x,y,z in rim:
        bottom=(x*.80,y*.80,1.343)
        row.append((bottom[0]*(1-t)+x*t,bottom[1]*(1-t)+y*t+.013*sin(pi*t),bottom[2]*(1-t)+z*t))
    grid.append(row)
hood=patch('Jacket_HoodOuter',grid,'Sunflower','Jacket',1,bodyweight,0)
hood.data.materials.append(mats['Orange']);activate(hood)
hm=hood.modifiers.new('Lined fabric thickness','SOLIDIFY');hm.thickness=.007;hm.material_offset=1;bpy.ops.object.modifier_apply(modifier=hm.name)
tube('Jacket_HoodRolledRim',rim,.013,'Sunflower','Jacket',12,1,bodyweight)
for s,side in [(1,'L'),(-1,'R')]:
    pts=[(s*.085,-.079,1.424),(s*.087,-.111,1.383),(s*.085,-.117,1.323),(s*.091,-.120,1.256)]
    tube('Jacket_Drawstring_'+side,pts,.0035,'Chalk','Jacket',8,1,bodyweight)
    tube('Jacket_DrawstringAglet_'+side,[(s*.091,-.120,1.267),(s*.091,-.120,1.247)],.0047,'Chalk','Jacket',8,1,bodyweight)
    for k in range(0):
        a=2*pi*k/10;center=Vector((s*.414,-.024,1.06));axis=Vector((s*.61,0,-.79));u=Vector((s*.79,0,.61));v=Vector((0,1,0))
        start=center+u*.045*cos(a)+v*.047*sin(a)
        tube('Jacket_CuffRib_'+side+str(k),[tuple(start-axis*.014),tuple(start+axis*.014)],.001,'Sunflower','Jacket',5,0,rigid('LowerArm.'+side))
    cx=s*.123
    zloft('Shoes_BlueCollar_'+side,[(cx,.02,z,rx,ry) for z,rx,ry in [(.128,.047,.051),(.143,.054,.056),(.188,.051,.051),(.194,.045,.048)]],'Cobalt','Shoes',24,1,rigid('Foot.'+side))
    tongue=[[(cx+x,-.057+y,z) for x in [-.027,-.023,.023,.027]] for y,z in [(0,.142),(.008,.168),(.015,.193),(.020,.197)]]
    patch('Shoes_WhiteTongue_'+side,tongue,'Chalk','Shoes',1,rigid('Foot.'+side),.005)
    tube('Shoes_YellowTongue_'+side,[(cx,-.054,.15),(cx,-.044,.18),(cx,-.036,.195)],[.008,.010,.009],'Sunflower','Shoes',8,1,rigid('Foot.'+side))
    for ss in [-1,1]:
        pts=[(cx+ss*.071,-.098,.080),(cx+ss*.071,-.110,.11),(cx+ss*.066,-.093,.136),(cx+ss*.069,-.068,.124),(cx+ss*.074,-.063,.095)]
        tube('Shoes_YellowSidePanel_'+side+str(ss),pts,.0085,'Sunflower','Shoes',8,1,rigid('Foot.'+side))
        tube('Shoes_BlueInset_'+side+str(ss),[(x+ss*.002,y+.003,z-.005) for x,y,z in pts[1:-1]],.004,'Cobalt','Shoes',8,1,rigid('Foot.'+side))
    toegrid=[]
    for z in [.022,.03,.047,.06]:
        toegrid.append([(cx+x,-.218+.014*(abs(x)/.031)**2,z) for x in [-.031,-.026,0,.026,.031]])
    patch('Shoes_YellowToeBumper_'+side,toegrid,'Sunflower','Shoes',1,rigid('Foot.'+side),.004)

print('GEOMETRY_CREATED',len(parts),flush=True)

# Consistent normal orientation and logical object consolidation.
for o in parts:
    activate(o);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
def union_into(base,other):
    activate(base);mod=base.modifiers.new('Resolve constructed seam','BOOLEAN');mod.operation='UNION';mod.solver='EXACT';mod.object=other
    bpy.ops.object.modifier_apply(modifier=mod.name)
    parts.remove(other);bpy.data.objects.remove(other,do_unlink=True)
union_into(bpy.data.objects['Pants_TailoredLeg_L'],bpy.data.objects['Pants_TailoredLeg_R'])
if 'Jacket_FrontBack_R' in bpy.data.objects:union_into(bpy.data.objects['Jacket_FrontBack_L'],bpy.data.objects['Jacket_FrontBack_R'])
for sd in ['L','R']:
    union_into(bpy.data.objects['Jacket_FrontBack_L'],bpy.data.objects['Jacket_Sleeve_'+sd])
    palm=bpy.data.objects['Body_Palm_'+sd]
    for fn in ['Index','Middle','Ring','Little','Thumb']:
        union_into(palm,bpy.data.objects['Body_'+fn+'_'+sd])
    activate(palm)
    mod=palm.modifiers.new('Continuous finger webbing','REMESH');mod.mode='VOXEL';mod.voxel_size=.0012;mod.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=palm.modifiers.new('Palm surface relaxation','SMOOTH');mod.factor=.28;mod.iterations=3;bpy.ops.object.modifier_apply(modifier=mod.name)
    nt=sum(len(p.vertices)-2 for p in palm.data.polygons)
    mod=palm.modifiers.new('Hand surface budget','DECIMATE');mod.ratio=min(1,3200/nt);bpy.ops.object.modifier_apply(modifier=mod.name)
character=[]
groups={cat:[o for o in parts if meta[o.name]==cat] for cat in ['Body','Eyes','Hair','Cap','Jacket','Shirt','Pants','Shoes']}
for cat in ['Body','Eyes','Hair','Cap','Jacket','Shirt','Pants','Shoes']:
    obs=groups[cat]
    if not obs:continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=cat;character.append(o)
    o['design_note']='Original Dash mesh, authored for myTwin. Metres, forward -Y.'
    if cat=='Jacket':
        for mn in ['Orange','Chalk','Sleeve']:
            if mats[mn].name not in o.data.materials:o.data.materials.append(mats[mn])
        si=list(o.data.materials).index(mats['Sleeve'])
        for p in o.data.polygons:
            c=p.center
            if 1.05<c.z<1.37 and abs(c.x)>.215:p.material_index=si
    if cat=='Shoes':
        for v in o.data.vertices:
            cx=.123 if v.co.x>0 else -.123
            v.co.x=cx+(v.co.x-cx)*1.12;v.co.y=.02+(v.co.y-.02)*1.12
            if v.co.z>.02:v.co.z=.02+(v.co.z-.02)*1.12
print('TRIANGLES_PRE_OPTIMIZE',sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in character),flush=True)

# A restrained studio scene used for all review renders.
ground=material('Studio_WarmGrey',(.72,.74,.78),.85)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,.002));floor=bpy.context.object;floor.name='Studio_Ground';floor.data.materials.append(ground)
for c in list(floor.users_collection):c.objects.unlink(floor)
collections['Studio'].objects.link(floor)
scene.world.color=(.25,.25,.25);scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.20,.25,.32,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
def area(name,loc,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new(name,data);collections['Lighting'].objects.link(o);o.location=loc;aim(o,(0,0,1));return o
area('Key_Softbox',(-3,-4,5),350,3,(1,.88,.78))
area('Fill_Softbox',(3,-2,2.5),90,3,(.78,.87,1))
area('Rim_Softbox',(1,2.5,4),320,2.5,(1,.94,.83))
def camera(name,loc,target,scale):
    data=bpy.data.cameras.new(name);data.type='ORTHO';data.ortho_scale=scale
    o=bpy.data.objects.new(name,data);collections['Camera'].objects.link(o);o.location=loc;aim(o,target);return o
cameras={
 'Hero':camera('Camera_Hero',(2.7,-5,2.4),(0,-.01,.98),2.22),
 'ThreeQuarter':camera('Camera_ThreeQuarter',(3.7,-6,1.55),(0,0,.96),2.18),
 'Front':camera('Camera_Front',(0,-6,1.13),(0,0,.96),2.18),
 'Side':camera('Camera_Side',(6,0,1.15),(0,0,.96),2.18),
 'Back':camera('Camera_Back',(0,6,1.2),(0,0,.96),2.18),
 'Face':camera('Camera_Face',(.55,-3,1.86),(0,-.02,1.67),.56)}
scene.camera=cameras['Hero'];scene.render.engine='CYCLES';scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=900;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
scene.render.filepath=os.path.join(ROOT,'renders','Dash_Review_01.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'Dash_Working.blend'))
if '--skip-review' in sys.argv:sys.exit(0)
bpy.ops.render.render(write_still=True)
scene.camera=cameras['Face'];scene.render.resolution_x=1000;scene.render.resolution_y=1000
scene.render.filepath=os.path.join(ROOT,'renders','Dash_Face_Review_01.png');bpy.ops.render.render(write_still=True)
print('REVIEW_COMPLETE',flush=True)
