# Split the tall gvim overview screenshot (43.png) into vertical slices
# so each slice stays legible when read by a vision model.
from PIL import Image
import os

base = (r"C:\Users\Taylor.Yu\AppData\Local\Temp\claude"
        r"\d--Users-Taylor-Yu-Documents-1-D-robotics-1------1-X7A-4-TR4-2-MCUSys---5-FuSa-2-parity"
        r"\865c9b88-65ed-4dd6-867d-b51f09e0b44e\images")
out = os.path.dirname(os.path.abspath(__file__))

im = Image.open(os.path.join(base, "43.png"))
w, h = im.size
print("size", w, h)
n = 5
ov = 80  # ~4 lines of overlap so no source line is cut in half
for i in range(n):
    top = max(0, i * h // n - ov)
    bot = min(h, (i + 1) * h // n + ov)
    im.crop((0, top, w, bot)).save(os.path.join(out, "43_%d.png" % i))
    print("43_%d.png rows %d-%d" % (i, top, bot))
