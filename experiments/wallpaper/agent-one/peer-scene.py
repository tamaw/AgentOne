import bpy, math, os, sys
from mathutils import Vector
from math import sin, cos, pi, exp
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
version=int(args[0]) if args else 0
W=int(args[1]) if len(args)>1 else 1280
out=args[2] if len(args)>2 else '/workspace/artifacts/wallpaper-challenge/initial.png'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=128; scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED'; scene.render.threads=6
scene.render.resolution_x=W; scene.render.resolution_y=W*9//16; scene.render.resolution_percentage=100
scene.world.color=(0.015,0.015,0.015)
scene.view_settings.view_transform='Filmic'; scene.view_settings.look='Medium High Contrast'; scene.view_settings.exposure=0.3
def mat(name,col,metal=0,rough=.35):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*col,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 return m
opal=mat('Deep opaline turquoise',(0.055,.32,.31),.38,.27)
gold=mat('Brushed champagne rim',(.62,.38,.15),.72,.26)
pearl=mat('Porcelain underside',(.72,.78,.64),.22,.32)
back=mat('Midnight blue',(.008,.021,.035),.1,.85)
def curve(name,pts,r,material):
 c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=2; c.bevel_depth=r; c.bevel_resolution=3
 p=c.splines.new('POLY'); p.points.add(len(pts)-1)
 for pnt,co in zip(p.points,pts): pnt.co=(*co,1)
 ob=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(ob); ob.data.materials.append(material); return ob
def point(t,u):
 r=.21*exp(.155*t); a=t
 tube=.53*r
 rib=1+.016*cos(64*t+2*u)
 rr=r+tube*cos(u)*rib
 return (rr*cos(a),rr*sin(a),.30*r+tube*sin(u)*rib)
N=1000; K=96; T=5.8*pi
verts=[]; faces=[]
for i in range(N+1):
 t=T*i/N
 for j in range(K+1):
  u=-.90*pi+1.80*pi*j/K
  verts.append(point(t,u))
for i in range(N):
 for j in range(K):
  a=i*(K+1)+j; faces.append((a,a+1,a+K+2,a+K+1))
mesh=bpy.data.meshes.new('Logarithmic shell membrane'); mesh.from_pydata(verts,[],faces); mesh.update()
ob=bpy.data.objects.new('Pelagic',mesh); bpy.context.collection.objects.link(ob)
ob.data.materials.append(opal); ob.data.materials.append(pearl)
for p in mesh.polygons: p.use_smooth=True
sol=ob.modifiers.new('Thin ceramic membrane','SOLIDIFY'); sol.thickness=.025; sol.material_offset=1
for u in [-.90*pi,.90*pi]: curve('Gold lip', [point(T*i/N,u) for i in range(N+1)],.015,gold)
curve('Aperture', [point(T,-.90*pi+1.80*pi*j/240) for j in range(241)],.024,gold)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.4)); bpy.context.object.data.materials.append(back)
def area(name,loc,power,color,size,target=(0,0,0)):
 d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size
 o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Silk key',(-4,-3,9),1800,(.77,.91,1),7)
area('Copper rim',(4,4,5),2400,(1,.65,.34),5)
area('Cool fill',(-5,4,2),1000,(.23,.69,1),4)
bpy.ops.object.camera_add(location=(8,-11,12))
cam=bpy.context.object; target=Vector((-.7,0,.5)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=14.8; scene.camera=cam
scene.render.image_settings.file_format='PNG'; scene.render.filepath=out
bpy.ops.wm.save_as_mainfile(filepath='/workspace/artifacts/wallpaper-challenge/scene-v%d.blend'%version)
bpy.ops.render.render(write_still=True)
