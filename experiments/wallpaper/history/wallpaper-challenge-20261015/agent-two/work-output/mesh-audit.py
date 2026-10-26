import bpy,json,math
from bpy_extras.object_utils import world_to_camera_view
s=bpy.context.scene;ob=bpy.data.objects['Pelagic'];dg=bpy.context.evaluated_depsgraph_get();ev=ob.evaluated_get(dg);mesh=ev.to_mesh()
area=[p.area for p in mesh.polygons];pts=[world_to_camera_view(s,s.camera,ob.matrix_world@v.co) for v in mesh.vertices]
report={'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),'degenerate_polygons':sum(a<1e-12 for a in area),'area_min':min(area),'area_max':max(area),'projected_surface_bounds':[min(p.x for p in pts),min(p.y for p in pts),max(p.x for p in pts),max(p.y for p in pts)],'surface_outside_camera':sum(p.x<0 or p.x>1 or p.y<0 or p.y>1 for p in pts),'solidify_thickness':ob.modifiers[0].thickness,'native_resolution':[s.render.resolution_x,s.render.resolution_y],'samples':s.cycles.samples}
ev.to_mesh_clear()
print('MESH_AUDIT',json.dumps(report))
open('/workspace/artifacts/wallpaper-challenge/mesh-audit.json','w').write(json.dumps(report,indent=2))
