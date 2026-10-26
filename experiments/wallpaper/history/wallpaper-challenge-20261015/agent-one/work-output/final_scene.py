import bpy, math, os, sys, random
from mathutils import Vector
OUT='/workspace/artifacts/wallpaper-challenge'
variant='oblique'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=32
sys.path.insert(0,OUT); from render_support import configure_cycles; configure_cycles(scene,256); scene.render.resolution_x=3840; scene.render.resolution_y=2160; scene.render.resolution_percentage=100
scene.world.color=(0.025,0.025,0.025)
def mat(name,col,metal=0,rough=.3,emit=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*col,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 if emit: p.inputs['Emission Color'].default_value=(*col,1); p.inputs['Emission Strength'].default_value=emit
 return m
gold=mat('Champagne alloy',(.55,.29,.09),.72,.31)
copper=mat('Burnished copper',(.48,.14,.07),.75,.32)
teal=mat('Oxidized teal',(.025,.23,.23),.65,.29)
ivory=mat('Pearlescent porcelain',(.75,.88,.83),.4,.25)
dark=mat('Petrol velvet',(.007,.028,.035),.15,.54)
def curve(name,pts,radius,material):
 c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=2; c.bevel_depth=radius; c.bevel_resolution=5
 s=c.splines.new('POLY'); s.points.add(len(pts)-1)
 for p,co in zip(s.points,pts): p.co=(*co,1)
 ob=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(ob); ob.data.materials.append(material); return ob
for j,eta in enumerate([.50]):
 for k in range(24):
  phi=2*math.pi*k/24+j*.09; pts=[]
  for n in range(401):
   t=2*math.pi*n/400; d=1-math.sin(eta)*math.sin(t)
   pts.append((math.cos(eta)*math.cos(t+phi)/d,math.cos(eta)*math.sin(t+phi)/d,math.sin(eta)*math.cos(t)/d))
  ob=curve('Hopf fiber %d %d'%(j,k),pts,.026 if k%4==0 else .017,ivory if k%6==0 else (teal if 6<=k<12 else copper if 15<=k<19 else gold)); ob.rotation_euler=(.45,-.38,.22); ob.location=(1.1,0,.1)
scene.render.film_transparent=True; scene.render.image_settings.color_mode='RGBA'
def area(name,loc,power,color,size,target=(0,0,0)):
 d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size; o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm broad key',(1,-4,6),1800,(1,.76,.48),5)
area('Cool rim',(-4,2,3),2400,(.22,.76,1),4)
area('Soft silk',(4,3,5),1600,(1,.94,.81),3)
bpy.ops.object.camera_add(location={'oblique':(3,-4,13),'axial':(2,-3,17),'diagonal':(6,-4,11)}[variant]); cam=bpy.context.object; cam.rotation_euler=(Vector((-.2,0,.05))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=8.5; scene.camera=cam
from frame_geometry import frame_geometry
frame_geometry(cam,[o for o in scene.objects if o.type=='CURVE'],center=(.63,.50),height=.72)
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=-.5
scene.render.image_settings.file_format='PNG'; scene.render.filepath=OUT+'/final-alpha.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/final.blend'); bpy.ops.render.render(write_still=True)
