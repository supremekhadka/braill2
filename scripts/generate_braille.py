import cv2
import numpy as np
import random

class BrailleGeneratorV5:
    def __init__(self, img_size=(1024, 1024)):
        self.img_size = img_size
        self.dot_rad = 5 
        self.h_space, self.v_space = 24, 24
        self.cell_w, self.line_h = 60, 90

    def create_soft_bump(self, radius):
        size = radius * 6
        # size = radius * 10
        kernel = np.zeros((size, size), dtype=np.float32)
        center = size // 2
        for i in range(size):
            for j in range(size):
                d = np.sqrt((i - center)**2 + (j - center)**2)
                if d < radius * 1.6:
                    # Slightly steeper slope than V4 for better shadows
                    kernel[i,j] = np.cos(min(1, d/(radius*1.6)) * (np.pi/2))**1.5
        return kernel

    def apply_vignette(self, img, strength=0.2):
        """Adds a global lighting falloff to the corners."""
        rows, cols = img.shape
        kernel_x = cv2.getGaussianKernel(cols, cols/2)
        kernel_y = cv2.getGaussianKernel(rows, rows/2)
        vignette = kernel_y * kernel_x.T
        vignette = vignette / vignette.max()
        # Blend vignette
        return img * ((1 - strength) + strength * vignette)

    def generate_page(self):
        # 1. Build the Height Map (Same logic as V4)
        recto_h = np.zeros(self.img_size, dtype=np.float32)
        verso_h = np.zeros(self.img_size, dtype=np.float32)
        bump = self.create_soft_bump(self.dot_rad)
        bh, bw = bump.shape
        
        for r in range(12):
            for c in range(14):
                px, py = 100 + c * self.cell_w, 100 + r * self.line_h
                
                # Recto (Front)
                bits = random.randint(1, 63)
                for i in range(6):
                    if (bits >> i) & 1:
                        y, x = int(py + (i%3)*self.v_space), int(px + (i//3)*self.h_space)
                        if y+bh < 1024 and x+bw < 1024:
                            recto_h[y:y+bh, x:x+bw] = np.maximum(recto_h[y:y+bh, x:x+bw], bump)

                # Verso (Back - Offset)
                vx, vy = px + 30, py + 45
                v_bits = random.randint(0, 63)
                for i in range(6):
                    if (v_bits >> i) & 1:
                        vy_idx, vx_idx = int(vy + (i%3)*self.v_space), int(vx + (i//3)*self.h_space)
                        if vy_idx+bh < 1024 and vx_idx+bw < 1024:
                            verso_h[vy_idx:vy_idx+bh, vx_idx:vx_idx+bw] = np.maximum(verso_h[vy_idx:vy_idx+bh, vx_idx:vx_idx+bw], bump)

        # 2. Shading Math
        total_h = (recto_h * 1.0) - (verso_h * 0.5)
        total_h = cv2.GaussianBlur(total_h, (5, 5), 0)

        dzdx = cv2.Sobel(total_h, cv2.CV_32F, 1, 0, ksize=3)
        dzdy = cv2.Sobel(total_h, cv2.CV_32F, 0, 1, ksize=3)
        
        # LIGHTING: Slightly sharper angle to define the bumps
        L = np.array([-0.8, -0.8, 1.2], dtype=np.float32)
        L /= np.linalg.norm(L)

        mag = np.sqrt(dzdx**2 + dzdy**2 + 1)
        nx, ny, nz = -dzdx/mag, -dzdy/mag, 1/mag
        
        # 3. Color Tuning
        ambient = 0.65  # LOWERED: Moves paper from "pure white" to "neutral gray"
        shading_strength = 0.35 # RAISED: Makes highlights/shadows pop more
        
        diffuse = (nx * L[0] + ny * L[1] + nz * L[2])
        final = ambient + (diffuse - 1.0) * shading_strength
        
        # 4. Final Processing
        final = self.apply_vignette(final, strength=0.25) # Darken edges
        final += np.random.normal(0, 0.015, self.img_size) # Real sensor noise
        
        return (np.clip(final, 0, 1) * 255).astype(np.uint8)

gen = BrailleGeneratorV5()
img = gen.generate_page()
cv2.imwrite("braille_v5.jpg", img)