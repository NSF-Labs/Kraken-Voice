#!/usr/bin/env python3
"""Compatibility entry point: all new builds are unified."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('verify_unified_artifact.py')), run_name='__main__')
