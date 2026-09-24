"""
Remove the black background from the Kraken image.
Dark pixels become transparent, bright neon glow is preserved.
Uses luminance-based alpha mapping with a smooth threshold.
"""
from PIL import Image
import numpy as np

img = Image.open("assets/images/electric_kraken.png").convert("RGBA")
data = np.array(img, dtype=np.float32)

r, g, b, a = data[:,:,0], data[:,:,1], data[:,:,2], data[:,:,3]

# Calculate perceived luminance (weighted for human vision)
luminance = 0.299 * r + 0.587 * g + 0.114 * b

# Smooth alpha mapping:
# - Below threshold_low: fully transparent
# - Above threshold_high: fully opaque
# - In between: smooth gradient
threshold_low = 12.0   # pixels darker than this are fully transparent
threshold_high = 45.0  # pixels brighter than this keep full alpha

# Create alpha channel based on luminance
new_alpha = np.clip((luminance - threshold_low) / (threshold_high - threshold_low), 0.0, 1.0)
new_alpha = new_alpha * 255.0

# Apply: only where original alpha was opaque
final_alpha = np.minimum(a, new_alpha)
data[:,:,3] = final_alpha.astype(np.uint8)

result = Image.fromarray(data.astype(np.uint8))
result.save("assets/images/electric_kraken.png")
print(f"Done. Image saved: {result.size}, mode: {result.mode}")
