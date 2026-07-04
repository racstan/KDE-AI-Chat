import os, time, subprocess

# Start plasmawindowed
proc = subprocess.Popen(["plasmawindowed", "org.kde.plasma.kdeaichat"])
time.sleep(4)

# Take screenshot
os.system("import -window root /home/home/.gemini/antigravity/brain/4bda8486-fa11-42b8-897c-e0cde95e54cd/scratch/test_plasmoid.png")

# Kill plasmawindowed
proc.terminate()
