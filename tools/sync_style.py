"""Copies the MaterialCraftUI style kit into InstanceGPS/UI/Style.lua, and its Cognac and Classic skins into UI/Skins.

    py -I -X utf8 tools/sync_style.py

MATERIALCRAFTUI overrides where the MaterialCraftUI repo is (default: next to this repo).
"""
import os, runpy, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.environ.get('MATERIALCRAFTUI', os.path.join(ROOT, '..', 'MaterialCraftUI'))
sys.argv = [sys.argv[0], ROOT, 'InstanceGPS', 'Cognac', 'Classic']
runpy.run_path(os.path.join(LIB, 'tools', 'sync_style.py'), run_name='__main__')
