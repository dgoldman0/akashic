"""Put the Akashic root on the module path.

The image tool, toolchain/image, sits in the Akashic root.  pytest started
from that root finds it there, but a file of local_testing run as a script,
as a test file with a command line of its own or a subprocess worker is,
starts with only local_testing on the path.  Each module that imports the
image tool imports this one first, so that it works however it is started.
The root goes last on the path, so it shadows nothing.
"""

import sys
from pathlib import Path

AKASHIC_ROOT = Path(__file__).resolve().parents[1]

if str(AKASHIC_ROOT) not in sys.path:
    sys.path.append(str(AKASHIC_ROOT))
