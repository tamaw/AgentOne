from mathutils import Vector
def fit_ortho(camera,points,aspect,center=(.65,.49),extent=(.46,.69),margin=1.04):
 basis=camera.rotation_euler.to_matrix();right=basis@Vector((1,0,0));up=basis@Vector((0,1,0));back=basis@Vector((0,0,1))
 xs=[Vector(p).dot(right) for p in points];ys=[Vector(p).dot(up) for p in points];zs=[Vector(p).dot(back) for p in points]
 spanx=max(xs)-min(xs);spany=max(ys)-min(ys)
 scale=max(spanx/extent[0],spany*aspect/extent[1])*margin
 x=(max(xs)+min(xs))/2-(center[0]-.5)*scale
 y=(max(ys)+min(ys))/2-(.5-center[1])*scale/aspect
 z=sum(zs)/len(zs)
 target=right*x+up*y+back*z
 camera.location=target+back*25;camera.data.ortho_scale=scale
 print('FRAME_AUDIT',{'scale':scale,'requested_center':center,'projected_extent':(spanx/scale,spany*aspect/scale),'margin':margin})
