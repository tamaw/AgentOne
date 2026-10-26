import bpy, math, os, sys
from mathutils import Vector
from math import sin, cos, pi, exp
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
version=int(args[0]) if args else 0
W=int(args[1]) if len(args)>1 else 1280
out=args[2] if len(args)>2 else '/workspace/artifacts/wallpaper-challenge/initial.png'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=96 if W<2000 else 384; scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED'; scene.render.threads=6
scene.render.resolution_x=W; scene.render.resolution_y=W*9//16; scene.render.resolution_percentage=100
scene.world.color=(0.015,0.015,0.015)
scene.view_settings.view_transform='Filmic'; scene.view_settings.look='Medium High Contrast'; scene.view_settings.exposure=-0.5
def mat(name,col,metal=0,rough=.35):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*col,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 return m
opal=mat('Deep opaline turquoise',(.045,.30,.28),.38,.28)
gold=mat('Brushed champagne rim',(.74,.42,.12),.76,.24)
pearl=mat('Porcelain underside',(.32,.44,.37),.28,.34)
back=mat('Midnight blue',(.008,.021,.035),.1,.85)
def curve(name,pts,r,material):
 c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=2; c.bevel_depth=r; c.bevel_resolution=3
 p=c.splines.new('POLY'); p.points.add(len(pts)-1)
 for pnt,co in zip(p.points,pts): pnt.co=(*co,1)
 ob=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(ob); ob.data.materials.append(material); return ob
T=5.8*pi
FRACTION=.34
GROWTH=math.log((1+FRACTION)/(1-FRACTION))/(2*pi)+.016
SCALE=.21 if version==0 else 3.55/exp(GROWTH*T)
print('GEOMETRY_AUDIT',{'growth':GROWTH,'gap':exp(2*pi*GROWTH)*(1-FRACTION)-(1+FRACTION)})
def point(t,u):
 r=SCALE*exp(GROWTH*t); a=t
 tube=FRACTION*r
 rib=1+(.016 if version==0 else .002)*cos(64*t+2*u)
 rr=r+tube*cos(u)*rib
 return (rr*cos(a),rr*sin(a),.12*r+tube*sin(u)*rib)
N=1000; K=96; T=5.8*pi
verts=[]; faces=[]
for i in range(N+1):
 t=T*i/N
 for j in range(K+1):
  u=-pi+pi*j/K
  verts.append(point(t,u))
for i in range(N):
 for j in range(K):
  a=i*(K+1)+j; faces.append((a,a+1,a+K+2,a+K+1))
mesh=bpy.data.meshes.new('Logarithmic shell membrane'); mesh.from_pydata(verts,[],faces); mesh.update()
ob=bpy.data.objects.new('Pelagic',mesh); bpy.context.collection.objects.link(ob)
ob.data.materials.append(opal); ob.data.materials.append(pearl)
for p in mesh.polygons: p.use_smooth=True
sol=ob.modifiers.new('Thin ceramic membrane','SOLIDIFY'); sol.thickness=.025; sol.material_offset=1
for u in [-pi,0]: curve('Gold lip', [point(T*i/N,u) for i in range(N+1)],.015,gold)
curve('Aperture', [point(T,-pi+pi*j/240) for j in range(241)],.024,gold)
nodes=back.node_tree.nodes; nodes.clear(); output=nodes.new('ShaderNodeOutputMaterial'); em=nodes.new('ShaderNodeEmission'); em.inputs[0].default_value=(.009,.018,.032,1); em.inputs[1].default_value=.65; back.node_tree.links.new(em.outputs[0],output.inputs['Surface'])
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.4)); bpy.context.object.data.materials.append(back)
def area(name,loc,power,color,size,target=(0,0,0)):
 d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size
 o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Silk key',(-4,-3,9),650,(.66,.88,1),7)
area('Copper rim',(4,4,5),1100,(1,.68,.39),5)
area('Cool fill',(-5,4,2),480,(.20,.67,1),4)
bpy.ops.object.camera_add(location=(4,-6,18))
cam=bpy.context.object; target=Vector((-1.9,-1.2,.3)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler(); cam.rotation_euler.rotate_axis('Z',-.72); cam.data.type='ORTHO'; cam.data.ortho_scale=15.8; scene.camera=cam
sys.path.insert(0,'/workspace/artifacts/wallpaper-challenge'); from framing import fit_ortho
fit_ortho(cam,verts,W/(W*9//16),center=(.65,.49),extent=(.48,.66))
scene.render.film_transparent=True
bpy.data.objects.get('Plane').hide_render=True
scene.render.image_settings.color_mode='RGBA'
scene.render.image_settings.file_format='PNG'; scene.render.filepath=out
bpy.ops.wm.save_as_mainfile(filepath='/workspace/artifacts/wallpaper-challenge/scene-v%d.blend'%version)
bpy.ops.render.render(write_still=True)
