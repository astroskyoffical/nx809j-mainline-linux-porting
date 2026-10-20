@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
  echo The project Python environment is missing. Open this project in Codex to repair it.
  pause
  exit /b 1
)
start "" ".venv\Scripts\pythonw.exe" "tools\port_map_server.py" --open
