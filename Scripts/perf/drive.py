#!/usr/bin/python3
"""drive.py <step> …: each step a notchisland:// URL (settings/widgets, close, …) sent to NI_APP, or seconds to wait."""
import sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import url
for step in sys.argv[1:]:
    if step.replace('.', '').isdigit(): time.sleep(float(step))
    else: url(step)
