import subprocess,sys
from terminal_ui import run
ROWS = [('Status', ['bash', 'pilive.sh', 'status']), ('Configure stream', ['bash', 'pilive.sh', 'config']), ('Start X11 stream', ['bash', 'pilive.sh', 'start']), ('Pause stream', ['bash', 'pilive.sh', 'pause']), ('Resume stream', ['bash', 'pilive.sh', 'resume']), ('Stop stream', ['bash', 'pilive.sh', 'stop']), ('Original GUI / CLI', ['bash', 'pilive.sh'])]
def session(ui):
 while True:
  n=ui.menu('PILIVE - X11 streaming still needs a display',[r[0] for r in ROWS]+['Quit'])
  if n is None or n==len(ROWS):return
  if False and not ui.confirm('Continue? This runs the original script with its package/service/terms effects.'):continue
  ui.external(lambda:subprocess.run(ROWS[n][1],check=False))
  ui.message('Original command finished. No success claim is inferred. See its terminal output.')
if __name__=='__main__':raise SystemExit(run('pilive',session))
