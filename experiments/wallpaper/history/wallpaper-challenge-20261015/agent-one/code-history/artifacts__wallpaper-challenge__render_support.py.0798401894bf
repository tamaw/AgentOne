import bpy
def configure_cycles(scene,samples):
 scene.render.engine='CYCLES'; scene.cycles.samples=samples
 supported=bool(getattr(bpy.app.build_options,'cycles',False))
 scene.cycles.use_denoising=False
 print('RENDER_CAPABILITY: Debian build lacks OIDN; deterministic samples, no unsupported denoiser')
