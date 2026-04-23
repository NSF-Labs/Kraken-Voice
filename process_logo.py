from PIL import Image, ImageDraw

def flood_fill_transparency(img_path, out_path, tolerance=50):
    img = Image.open(img_path).convert('RGBA')
    width, height = img.size
    pixels = img.load()
    
    # We will do a BFS from the border
    visited = set()
    queue = []
    
    # Add border pixels to queue
    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))
        
    # Pick a reference background color from the corners, or just average them
    corners = [(0,0), (width-1, 0), (0, height-1), (width-1, height-1)]
    ref_colors = [pixels[cx, cy] for cx, cy in corners]
    avg_r = sum(c[0] for c in ref_colors) / 4
    avg_g = sum(c[1] for c in ref_colors) / 4
    avg_b = sum(c[2] for c in ref_colors) / 4
    
    def color_dist(c1, c2):
        return sum(abs(a - b) for a, b in zip(c1[:3], c2[:3]))
        
    while queue:
        x, y = queue.pop(0)
        if (x, y) in visited:
            continue
        visited.add((x, y))
        
        c = pixels[x, y]
        # Check distance to average background color
        if color_dist(c, (avg_r, avg_g, avg_b)) <= tolerance * 3:
            pixels[x, y] = (c[0], c[1], c[2], 0) # Make transparent
            # Add neighbors
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height and (nx, ny) not in visited:
                    queue.append((nx, ny))
                    
    img = img.transpose(Image.FLIP_LEFT_RIGHT)
    img.save(out_path)

flood_fill_transparency('assets/images/Gemini_Generated_Image_21ybko21ybko21yb.png', 'assets/images/kraken_logo_transparent.png', tolerance=120)
print("Done")
