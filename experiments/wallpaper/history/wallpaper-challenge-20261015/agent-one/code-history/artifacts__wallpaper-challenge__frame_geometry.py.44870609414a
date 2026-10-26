import bpy
from mathutils import Vector
def frame_geometry(camera,objects,center=(.63,.5),height=.76):
 bpy.context.view_layer.update(); inv=camera.matrix_world.inverted(); dg=bpy.context.evaluated_depsgraph_get();pts=[]
 for ob in objects:
  ev=ob.evaluated_get(dg);mesh=ev.to_mesh()
  pts.extend(inv @ (ob.matrix_world @ v.co) for v in mesh.vertices);ev.to_mesh_clear()
 xmin=min(p.x for p in pts);xmax=max(p.x for p in pts);ymin=min(p.y for p in pts);ymax=max(p.y for p in pts)
 aspect=bpy.context.scene.render.resolution_x/bpy.context.scene.render.resolution_y
 scale=max((ymax-ymin)/height*aspect,(xmax-xmin)/.58)
 camera.data.ortho_scale=scale
 dx=(xmin+xmax)/2-(center[0]-.5)*scale;dy=(ymin+ymax)/2-(.5-center[1])*scale/aspect
 camera.location += camera.matrix_world.to_quaternion() @ Vector((dx,dy,0))
 print('FRAME_GEOMETRY: projected spans',xmax-xmin,ymax-ymin,'scale',scale,'center',center)
