import time
import os
import sys

def _preload_nvidia_libs():
    if not hasattr(sys, 'prefix'): return
    nvidia_base_path = os.path.join(sys.prefix, 'lib64', 'python3.13', 'site-packages', 'nvidia')
    if not os.path.exists(nvidia_base_path):
        nvidia_base_path = os.path.join(sys.prefix, 'lib', 'python3.13', 'site-packages', 'nvidia')
    if not os.path.exists(nvidia_base_path):
        return

    cuda_libs = [
        os.path.join(nvidia_base_path, 'cublas', 'lib'),
        os.path.join(nvidia_base_path, 'cudnn', 'lib'),
        os.path.join(nvidia_base_path, 'cufft', 'lib'),
        os.path.join(nvidia_base_path, 'cusparse', 'lib'),
        os.path.join(nvidia_base_path, 'cusolver', 'lib'),
        os.path.join(nvidia_base_path, 'curand', 'lib'),
        os.path.join(nvidia_base_path, 'nccl', 'lib'),
        os.path.join(nvidia_base_path, 'nvtx', 'lib'),
        os.path.join(nvidia_base_path, 'cuda_cupti', 'lib'),
        os.path.join(nvidia_base_path, 'cuda_nvrtc', 'lib'),
        os.path.join(nvidia_base_path, 'cuda_runtime', 'lib'),
        os.path.join(nvidia_base_path, 'cublas', 'lib'),
    ]

    existing_paths = os.environ.get('LD_LIBRARY_PATH', '')
    for lib in cuda_libs:
        if os.path.exists(lib) and lib not in existing_paths:
            existing_paths = f"{lib}:{existing_paths}" if existing_paths else lib

    os.environ['LD_LIBRARY_PATH'] = existing_paths
    print("LD_LIBRARY_PATH set to", os.environ['LD_LIBRARY_PATH'])

_preload_nvidia_libs()

# Now we must restart this script with the new LD_LIBRARY_PATH if it changed, 
# but _preload_nvidia_libs only works if torch is imported AFTER.
import torch
from kokoro import KPipeline

start = time.time()
pipeline = KPipeline(lang_code='a')
print("Pipeline init:", time.time() - start)

text = """
Elephants are fascinating creatures with many unique traits! Here are some amazing facts about them:
1. Largest Land Animals
African elephants are the largest land animals on Earth.
Weight: Up to 6,000–13,000 lbs (2,700–5,900 kg)
Height: Up to 10–13 feet (3–4 meters) tall
Asian elephants are smaller but still massive:
Weight: Up to 4,500–11,000 lbs (2,000–5,000 kg)
Height: Up to 6.6–9.8 feet (2–3 meters) tall
2. Trunk: A Multi-Tool
An elephant’s trunk has 40,000 muscles (humans have ~600 in their entire body!) and can lift 700 lbs (317 kg).
It’s used for:
Breathing (they can’t breathe through their mouths)
Drinking (sucks up to 2 gallons (7.5 liters) of water at a time)
Grabbing food (can pick up a single peanut or tear down a tree)
"""

start = time.time()
chunks = 0
for _, _, audio in pipeline(text, voice="af_bella"):
    chunks += 1

print(f"Generated {chunks} chunks in {time.time() - start:.2f} seconds")
