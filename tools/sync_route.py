"""Copies RouteUtils into InstanceGPS/RouteUtils.

    py -I -X utf8 tools/sync_route.py

ROUTEUTILS overrides where the RouteUtils repo is (default: next to this repo).
"""
import os, runpy, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.environ.get('ROUTEUTILS', os.path.join(ROOT, '..', 'RouteUtils'))
sys.argv = [sys.argv[0], ROOT, 'InstanceGPS']
runpy.run_path(os.path.join(LIB, 'tools', 'sync.py'), run_name='__main__')
