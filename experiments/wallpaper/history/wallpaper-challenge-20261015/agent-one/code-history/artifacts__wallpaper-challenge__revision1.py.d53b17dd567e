import bpy, math, os, sys, random
from mathutils import Vector
OUT='/workspace/artifacts/wallpaper-challenge'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=32
sys.path.insert(0,OUT); from render_support import configure_cycles; configure_cycles(scene,96); scene.render.resolution_x=1920; scene.render.resolution_y=1080; scene.render.resolution_percentage=100
scene.world.color=(0.025,0.025,0.025)
def mat(name,col,metal=0,rough=.3,emit=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*col,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 if emit: p.inputs['Emission Color'].default_value=(*col,1); p.inputs['Emission Strength'].default_value=emit
 return m
gold=mat('Champagne alloy',(.66,.36,.13),.78,.23)
ivory=mat('Pearlescent porcelain',(.75,.88,.83),.4,.25)
dark=mat('Petrol velvet',(.007,.028,.035),.15,.54)
def curve(name,pts,radius,material):
 c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=2; c.bevel_depth=radius; c.bevel_resolution=3
 s=c.splines.new('POLY'); s.points.add(len(pts)-1)
 for p,co in zip(s.points,pts): p.co=(*co,1)
 ob=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(ob); ob.data.materials.append(material); return ob
for j,eta in enumerate([.48,.68,.88]):
 for k in range(16):
  phi=2*math.pi*k/16+j*.09; pts=[]
  for n in range(401):
   t=2*math.pi*n/400; d=1-math.sin(eta)*math.sin(t)
   pts.append((math.cos(eta)*math.cos(t+phi)/d,math.cos(eta)*math.sin(t+phi)/d,math.sin(eta)*math.cos(t)/d))
  ob=curve('Hopf fiber %d %d'%(j,k),pts,.010 if j==1 else .017,ivory if k%5==0 else gold); ob.rotation_euler=(.45,-.38,.22); ob.location=(.65,0,.1)
scene.render.film_transparent=True; scene.render.image_settings.color_mode='RGBA'
def area(name,loc,power,color,size,target=(0,0,0)):
 d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size; o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm broad key',(1,-4,6),1800,(1,.76,.48),5)
area('Cool rim',(-4,2,3),2400,(.22,.76,1),4)
area('Soft silk',(4,3,5),1600,(1,.94,.81),3)
bpy.ops.object.camera_add(location=(6,-10,5.3)); cam=bpy.context.object; cam.rotation_euler=(Vector((-.2,0,.05))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=10.8; scene.camera=cam
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'; scene.render.filepath=OUT+'/revision1-alpha.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/revision1.blend'); bpy.ops.render.render(write_still=True)
