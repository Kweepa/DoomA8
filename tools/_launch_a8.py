import subprocess
cmd = (
    r"C:\app\altirra\Altirra64.exe"
    r" /hardware:800xl /ntsc /nobasic /memsize:64K /w /debug"
    r' /debugcmd:".batch C:\dev\da8m\tools\a8dbg.at"'
    r" /diskemu:1050 /disk C:\dev\da8m\dooma8.atr"
)
print(cmd)
subprocess.Popen(cmd)
