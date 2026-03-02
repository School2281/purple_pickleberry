#!/usr/bin/env python3
"""
Mandelbrot Fractal Generator - Fixed version
"""

import os
os.environ['MPLCONFIGDIR'] = '/tmp/matplotlib'

from flask import Flask, request, Response
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import io
from werkzeug.middleware.proxy_fix import ProxyFix

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

@app.route('/')
def root():
    """Root endpoint with instructions"""
    return """<h1>Fractal Generator</h1>
    <p>Access via:</p>
    <ul>
        <li><a href="/status">/status</a></li>
        <li><a href="/light">/light</a> (test)</li>
        <li><a href="/viewer">Interactive viewer</a></li>
        <li><a href="/fractal?w=800&h=600">/fractal?w=800&h=600</a></li>
        <li><a href="/fractal?w=4000&h=4000&iter=1000">Heavy load test</a></li>
    </ul>"""

@app.route('/status')
def status():
    return "Fractal generator is running\nUse /light for test, /fractal?w=W&h=H&iter=I for generation"

@app.route('/light')
def light_fractal():
    """Lightweight test - minimal resources"""
    width, height = 400, 300
    x = np.linspace(-2.5, 1.5, width)
    y = np.linspace(-2.0, 2.0, height)
    c = x[:, np.newaxis] + 1j * y[np.newaxis, :]
    
    z = np.zeros(c.shape, dtype=np.complex128)
    fractal = np.zeros(c.shape, dtype=int)
    
    for i in range(30):
        mask = np.abs(z) < 4
        z[mask] = z[mask]**2 + c[mask]
        fractal[mask] = i
    
    fig, ax = plt.subplots(figsize=(4, 3))
    ax.imshow(fractal.T, cmap='hot', origin='lower')
    ax.axis('off')
    fig.tight_layout(pad=0)
    
    buf = io.BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight', pad_inches=0)
    plt.close(fig)
    buf.seek(0)
    
    return Response(buf.getvalue(), mimetype='image/png')

@app.route('/fractal')
def generate_fractal():
    """Generate Mandelbrot - CPU intensive!"""
    width = int(request.args.get('w', 800))
    height = int(request.args.get('h', 600))
    zoom = float(request.args.get('zoom', 1.0))
    max_iter = int(request.args.get('iter', 100))
    
    print(f"[Fractal] Generating {width}x{height} (iter={max_iter})")
    
    # Limit for safety (but you can remove for DoS testing)
    width = min(width, 5000)
    height = min(height, 5000)
    max_iter = min(max_iter, 2000)
    
    x = np.linspace(-2.5/zoom, 1.5/zoom, width)
    y = np.linspace(-2.0/zoom, 2.0/zoom, height)
    c = x[:, np.newaxis] + 1j * y[np.newaxis, :]
    
    z = np.zeros(c.shape, dtype=np.complex128)
    fractal = np.zeros(c.shape, dtype=int)
    
    for i in range(max_iter):
        mask = np.abs(z) < 50
        z[mask] = z[mask]**2 + c[mask]
        fractal[mask] = i
    
    fig, ax = plt.subplots(figsize=(width/100, height/100), dpi=100)
    ax.imshow(fractal.T, cmap='hot', origin='lower')
    ax.axis('off')
    fig.tight_layout(pad=0)
    
    buf = io.BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight', pad_inches=0)
    plt.close(fig)
    buf.seek(0)
    
    return Response(buf.getvalue(), mimetype='image/png')

@app.route('/viewer')
def fractal_viewer():
    """Interactive viewer that cycles through iterations"""
    
    html_content = f'''
<!DOCTYPE html>
<html>
<head>
    <title>Fractal Viewer - Live Iteration Cycling</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        
        body {{ 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: white;
        }}
        
        .container {{ 
            max-width: 1200px; 
            margin: 0 auto;
        }}
        
        header {{ 
            text-align: center; 
            margin-bottom: 30px;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }}
        
        h1 {{ 
            font-size: 2.5rem; 
            margin-bottom: 10px; 
        }}
        
        .viewer-container {{ 
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.2);
        }}
        
        .status-bar {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: rgba(0,0,0,0.3);
            padding: 15px 20px;
            border-radius: 15px;
            margin-bottom: 20px;
            font-size: 1.2rem;
        }}
        
        .iteration-display {{
            font-size: 2rem;
            font-weight: bold;
            font-family: 'Monaco', 'Consolas', monospace;
            background: rgba(255,255,255,0.2);
            padding: 10px 20px;
            border-radius: 15px;
            animation: pulse 1s ease-in-out;
        }}
        
        @keyframes pulse {{
            0% {{ transform: scale(1); }}
            50% {{ transform: scale(1.05); background: rgba(255,255,255,0.3); }}
            100% {{ transform: scale(1); }}
        }}
        
        .controls {{
            background: rgba(255, 255, 255, 0.15);
            padding: 15px 20px;
            border-radius: 15px;
            margin-bottom: 20px;
            display: flex;
            flex-wrap: wrap;
            gap: 15px;
            align-items: center;
        }}
        
        .control-group {{ 
            display: flex; 
            align-items: center; 
            gap: 10px; 
        }}
        
        label {{ 
            font-weight: 600; 
            min-width: 80px;
        }}
        
        .slider-container {{ 
            flex: 1; 
            min-width: 200px;
        }}
        
        input[type="range"] {{ 
            width: 100%; 
            height: 6px;
            -webkit-appearance: none;
            background: rgba(255,255,255,0.2);
            border-radius: 10px;
            outline: none;
        }}
        
        input[type="range"]::-webkit-slider-thumb {{
            -webkit-appearance: none;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: #ffffff;
            cursor: pointer;
            box-shadow: 0 4px 8px rgba(0,0,0,0.3);
        }}
        
        .value-display {{ 
            background: rgba(255,255,255,0.2);
            padding: 5px 12px;
            border-radius: 20px;
            min-width: 60px;
            text-align: center;
            font-family: 'Monaco', 'Consolas', monospace;
        }}
        
        .image-wrapper {{ 
            position: relative; 
            overflow: hidden;
            border-radius: 15px;
            background: #000;
            min-height: 500px;
            cursor: grab;
        }}
        
        .image-wrapper:active {{ cursor: grabbing; }}
        
        #fractalImage {{ 
            position: absolute;
            top: 50%;
            left: 50%;
            transform-origin: center center;
            will-change: transform;
            user-select: none;
            -webkit-user-drag: none;
            transition: opacity 0.3s ease;
        }}
        
        .loading {{ 
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(0,0,0,0.8);
            padding: 20px 40px;
            border-radius: 15px;
            font-size: 1.2rem;
            z-index: 10;
        }}
        
        .coordinates {{ 
            position: absolute;
            bottom: 15px;
            left: 15px;
            background: rgba(0,0,0,0.7);
            padding: 8px 15px;
            border-radius: 10px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.9rem;
            pointer-events: none;
        }}
        
        .dos-warning {{
            display: none;
            background: linear-gradient(45deg, #ff0000, #ff6b6b);
            color: white;
            padding: 20px;
            border-radius: 15px;
            text-align: center;
            font-size: 1.5rem;
            font-weight: bold;
            margin-bottom: 20px;
            animation: flash 0.5s infinite;
        }}
        
        @keyframes flash {{
            0%, 100% {{ opacity: 1; }}
            50% {{ opacity: 0.5; }}
        }}
        
        .cycle-controls {{
            display: flex;
            gap: 10px;
            align-items: center;
            background: rgba(255,255,255,0.1);
            padding: 10px;
            border-radius: 10px;
        }}
        
        button {{
            background: rgba(255,255,255,0.9);
            color: #333;
            border: none;
            padding: 10px 20px;
            border-radius: 10px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
        }}
        
        button:hover {{ 
            background: white;
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.2);
        }}
        
        button:disabled {{
            opacity: 0.5;
            cursor: not-allowed;
        }}
        
        .speed-control {{
            display: flex;
            align-items: center;
            gap: 10px;
        }}
        
        .metric {{
            background: rgba(0,0,0,0.3);
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 0.9rem;
        }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🎨 Live Fractal Iteration Cycling</h1>
            <p>Watch the fractal evolve as iterations cycle from 10 to 100</p>
        </header>
        
        <div class="viewer-container">
            <div class="status-bar">
                <div>
                    <span class="metric">📊 Current Iteration: <span id="currentIteration">10</span></span>
                    <span class="metric">⏱️ Response Time: <span id="responseTime">0ms</span></span>
                </div>
                <div class="iteration-display" id="iterationDisplay">10</div>
            </div>
            
            <div id="dosWarning" class="dos-warning">
                🚨 SERVER UNDER DOS ATTACK - SLOW RESPONSE 🚨
            </div>
            
            <div class="controls">
                <div class="cycle-controls">
                    <button onclick="toggleCycle()" id="cycleButton">⏸️ Pause</button>
                    <div class="speed-control">
                        <label>Speed:</label>
                        <input type="range" id="speedSlider" min="100" max="2000" value="500" step="50">
                        <span id="speedValue">500ms</span>
                    </div>
                </div>
                
                <div class="control-group">
                    <label>Zoom:</label>
                    <div class="slider-container">
                        <input type="range" id="zoom" min="0.1" max="5" value="1" step="0.01">
                    </div>
                    <span class="value-display" id="zoomValue">1.00x</span>
                </div>
                
                <div class="button-group">
                    <button onclick="resetView()">↺ Reset</button>
                    <button onclick="toggleInfo()">ℹ Info</button>
                </div>
            </div>
            
            <div class="image-wrapper" id="imageWrapper">
                <div class="loading" id="loading">Loading fractal...</div>
                <img id="fractalImage" src="/fractal?w=800&h=600&iter=10" alt="Fractal">
                <div class="coordinates" id="coords">Iteration: 10 | Zoom: 1.00x</div>
            </div>
        </div>
    </div>

        <script>
        // State
        let scale = 1.0;
        let posX = 0;
        let posY = 0;
        let isDragging = false;
        let startX, startY, startPosX, startPosY;
        
        // Cycling state
        let currentIter = 10;
        let cycleDirection = 1; // 1 for up, -1 for down
        let isCycling = true;
        let cycleSpeed = 500; // ms
        let cycleTimer;
        let lastLoadTime = 0;
        let failedLoads = 0;
        
        // Elements
        const image = document.getElementById('fractalImage');
        const loading = document.getElementById('loading');
        const wrapper = document.getElementById('imageWrapper');
        const currentIterSpan = document.getElementById('currentIteration');
        const iterationDisplay = document.getElementById('iterationDisplay');
        const responseTimeSpan = document.getElementById('responseTime');
        const dosWarning = document.getElementById('dosWarning');
        const cycleButton = document.getElementById('cycleButton');
        const speedSlider = document.getElementById('speedSlider');
        const speedValue = document.getElementById('speedValue');
        const zoomSlider = document.getElementById('zoom');
        const zoomValue = document.getElementById('zoomValue');
        const coordsDisplay = document.getElementById('coords');
        
        // Initialize
        function init() {{
            centerImage();
            
            // Event listeners
            zoomSlider.addEventListener('input', updateZoom);
            wrapper.addEventListener('mousedown', startDrag);
            wrapper.addEventListener('touchstart', handleTouchStart);
            document.addEventListener('mousemove', handleDrag);
            document.addEventListener('touchmove', handleTouchMove);
            document.addEventListener('mouseup', endDrag);
            document.addEventListener('touchend', endDrag);
            wrapper.addEventListener('wheel', handleWheel);
            wrapper.addEventListener('contextmenu', e => e.preventDefault());
            
            // Speed slider
            speedSlider.addEventListener('input', function() {{
                cycleSpeed = parseInt(this.value);
                speedValue.textContent = cycleSpeed + 'ms';
                if (isCycling) {{
                    restartCycle();
                }}
            }});
            
            // Start cycling
            startCycle();
            updateDisplay();
        }}
        
        // Cycle functions
        function startCycle() {{
            if (cycleTimer) clearTimeout(cycleTimer);
            cycleTimer = setTimeout(loadNextIteration, cycleSpeed);
        }}
        
        function stopCycle() {{
            if (cycleTimer) {{
                clearTimeout(cycleTimer);
                cycleTimer = null;
            }}
        }}
        
        function restartCycle() {{
            stopCycle();
            startCycle();
        }}
        
        function toggleCycle() {{
            isCycling = !isCycling;
            cycleButton.textContent = isCycling ? '⏸️ Pause' : '▶️ Resume';
            if (isCycling) {{
                startCycle();
            }} else {{
                stopCycle();
            }}
        }}
        
        function loadNextIteration() {{
            if (!isCycling) return;
            
            // Update iteration
            currentIter += cycleDirection;
            
            // Bounce between 10 and 100
            if (currentIter >= 100) {{
                currentIter = 100;
                cycleDirection = -1;
            }} else if (currentIter <= 10) {{
                currentIter = 10;
                cycleDirection = 1;
            }}
            
            // Update displays
            currentIterSpan.textContent = currentIter;
            iterationDisplay.textContent = currentIter;
            iterationDisplay.style.animation = 'none';
            iterationDisplay.offsetHeight; // Trigger reflow
            iterationDisplay.style.animation = 'pulse 1s ease-in-out';
            
            // Load new image with timestamp to prevent caching
            const startTime = Date.now();
            const baseUrl = '/fractal?w=800&h=600&iter=' + currentIter;
            image.src = baseUrl + '&t=' + startTime;
            
            // Show loading
            loading.style.display = 'block';
            
            // Schedule next iteration
            cycleTimer = setTimeout(loadNextIteration, cycleSpeed);
        }}
        
        // Image events
        image.onload = function() {{
            loading.style.display = 'none';
            lastLoadTime = Date.now() - (image.src.split('t=')[1] || Date.now());
            responseTimeSpan.textContent = lastLoadTime + 'ms';
            
            // Check for DoS (slow response)
            if (lastLoadTime > 2000) {{ // More than 2 seconds
                failedLoads++;
                if (failedLoads > 2) {{
                    dosWarning.style.display = 'block';
                }}
            }} else {{
                failedLoads = 0;
                dosWarning.style.display = 'none';
            }}
            
            // Adjust cycle speed based on response time (cool effect!)
            if (lastLoadTime > cycleSpeed * 0.8) {{
                // Server is struggling, slow down
                cycleSpeed = Math.min(2000, lastLoadTime * 1.2);
                speedSlider.value = cycleSpeed;
                speedValue.textContent = cycleSpeed + 'ms';
            }}
        }};
        
        image.onerror = function() {{
            loading.style.display = 'none';
            dosWarning.style.display = 'block';
            dosWarning.innerHTML = '🚨 IMAGE FAILED TO LOAD - SERVER OVERLOADED 🚨';
            failedLoads++;
            
            // Still try to continue cycling
            if (isCycling) {{
                startCycle();
            }}
        }};
        
        // Center image
        function centerImage() {{
            const rect = wrapper.getBoundingClientRect();
            image.style.top = rect.height / 2 + 'px';
            image.style.left = rect.width / 2 + 'px';
        }}
        
        // Transform
        function updateImageTransform() {{
            image.style.transform = `translate(-50%, -50%) scale(${{scale}}) translate(${{posX}}px, ${{posY}}px)`;
            updateDisplay();
        }}
        
        // Zoom
        function updateZoom() {{
            scale = parseFloat(zoomSlider.value);
            zoomValue.textContent = scale.toFixed(2) + 'x';
            updateImageTransform();
        }}
        
        // Display update
        function updateDisplay() {{
            coordsDisplay.textContent = `Iteration: ${{currentIter}} | Zoom: ${{scale.toFixed(2)}}x`;
        }}
        
        // Drag handlers
        function startDrag(e) {{
            e.preventDefault();
            isDragging = true;
            startX = e.clientX || e.touches[0].clientX;
            startY = e.clientY || e.touches[0].clientY;
            startPosX = posX;
            startPosY = posY;
            wrapper.style.cursor = 'grabbing';
        }}
        
        function handleDrag(e) {{
            if (!isDragging) return;
            e.preventDefault();
            
            const currentX = e.clientX || e.touches[0].clientX;
            const currentY = e.clientY || e.touches[0].clientY;
            
            const deltaX = (currentX - startX) / scale;
            const deltaY = (currentY - startY) / scale;
            
            posX = startPosX + deltaX;
            posY = startPosY + deltaY;
            
            updateImageTransform();
        }}
        
        function handleTouchStart(e) {{
            if (e.touches.length === 1) startDrag(e);
        }}
        
        function handleTouchMove(e) {{
            if (e.touches.length === 1) handleDrag(e);
        }}
        
        function endDrag() {{
            isDragging = false;
            wrapper.style.cursor = 'grab';
        }}
        
        // Wheel zoom
        function handleWheel(e) {{
            e.preventDefault();
            
            const zoomIntensity = 0.1;
            const zoomAmount = e.deltaY > 0 ? (1 - zoomIntensity) : (1 + zoomIntensity);
            
            const rect = wrapper.getBoundingClientRect();
            const mouseX = e.clientX - rect.left;
            const mouseY = e.clientY - rect.top;
            
            const imageCenterX = rect.width / 2;
            const imageCenterY = rect.height / 2;
            
            const mouseOffsetX = (mouseX - imageCenterX) / scale;
            const mouseOffsetY = (mouseY - imageCenterY) / scale;
            
            const oldScale = scale;
            scale = Math.max(0.1, Math.min(5, scale * zoomAmount));
            
            if (oldScale !== scale) {{
                posX += mouseOffsetX * (1 - scale / oldScale);
                posY += mouseOffsetY * (1 - scale / oldScale);
            }}
            
            zoomSlider.value = scale;
            updateImageTransform();
        }}
        
        // Reset
        function resetView() {{
            scale = 1.0;
            posX = 0;
            posY = 0;
            zoomSlider.value = 1.0;
            updateImageTransform();
        }}
        
        // Info
        function toggleInfo() {{
            alert(`Fractal Viewer - Live Iteration Cycling\nIterations: 10 → 100\nCycle Speed: ${{cycleSpeed}}ms\nServer Response: ${{lastLoadTime}}ms`);
        }}
        
        // Initialize on load
        window.addEventListener('DOMContentLoaded', init);
        window.addEventListener('resize', centerImage);
    </script>
</body>
</html>
'''
    
    return html_content

if __name__ == '__main__':
    # Create matplotlib temp dir
    os.makedirs('/tmp/matplotlib', exist_ok=True)
    
    app.run(
        host='0.0.0.0', 
        port=5000, 
        threaded=False,  # Single-threaded = easier to DoS
        debug=False
    )
