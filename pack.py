#!/usr/bin/env python3
"""
Packages c6g3Transformers into a BeamNG-compliant mod zip.
Usage:
    python pack.py           # Builds c6g3Transformers.zip in repo root
    python pack.py --install # Builds and copies into BeamNG user mods folder
"""

import os
import sys
import shutil
import zipfile

REPO_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(REPO_DIR, 'c6g3Transformers')
ZIP_NAME = 'c6g3Transformers.zip'
OUTPUT_ZIP = os.path.join(REPO_DIR, ZIP_NAME)

USER_MODS_DIR = os.path.expandvars(r'%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods')

def pack():
    if not os.path.isdir(SOURCE_DIR):
        print(f"Error: source directory not found: {SOURCE_DIR}")
        sys.exit(1)

    print(f"Packing {SOURCE_DIR} -> {OUTPUT_ZIP}...")
    with zipfile.ZipFile(OUTPUT_ZIP, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(SOURCE_DIR):
            for file in sorted(files):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, SOURCE_DIR).replace('\\', '/')
                z.write(full_path, rel_path)
                print(f"  + {rel_path}")

    print(f"\nSuccessfully built {OUTPUT_ZIP} ({os.path.getsize(OUTPUT_ZIP):,} bytes)")

    if '--install' in sys.argv:
        if os.path.isdir(USER_MODS_DIR):
            dest = os.path.join(USER_MODS_DIR, ZIP_NAME)
            shutil.copy2(OUTPUT_ZIP, dest)
            print(f"Installed to: {dest}")
        else:
            print(f"Warning: User mods directory not found: {USER_MODS_DIR}")

if __name__ == '__main__':
    pack()
