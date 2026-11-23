import subprocess, sys
# default: quiet trap. `python tools/_launch_a8_e1m3.py log` runs the verbose trace instead.
modes = {"log": "a8dbg_e1m3.at", "force_old": "a8dbg_force_old.at", "force_new": "a8dbg_force_new.at"}
script = modes.get(sys.argv[1] if len(sys.argv) > 1 else "", "a8dbg_e1m3_trap.at")
cmd = (
    r"C:\app\altirra\Altirra64.exe"
    r" /hardware:800xl /ntsc /nobasic /memsize:64K /w /debug"
    rf' /debugcmd:".batch C:\dev\da8m\tools\{script}"'
    r" /diskemu:1050 /disk C:\dev\da8m\dooma8.atr"
)
print(cmd)
subprocess.Popen(cmd)
