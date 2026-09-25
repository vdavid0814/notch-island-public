import sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import rusage
p = int(sys.argv[1]); secs = float(sys.argv[2])
a = rusage(p); t = time.time(); time.sleep(secs); b = rusage(p)
print(f"CPU {(b[0]-a[0])/1e9/(time.time()-t)*100:.2f}%  MB {b[1]:.1f}")
