import React, { useEffect, useRef } from 'react';

interface Particle {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  size: number;
  alpha: number;
  pulseSpeed: number;
  color: string;
}

/**
 * Decorative particle field behind the hero.
 *
 * - Honours `prefers-reduced-motion`: draws a single static frame instead of
 *   animating (and reacts if the setting changes while the page is open).
 * - Only animates while the canvas is on screen and the tab is visible.
 * - Renders at device-pixel-ratio resolution (capped at 2x) so particles stay
 *   crisp without exploding the backing-store size on 3x phones.
 * - Fewer particles on narrow viewports (the line pass is O(n²)).
 */
export const GlacialParticlesCanvas: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animationFrameId = 0;
    let width = 0;
    let height = 0;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    const resize = () => {
      const parent = canvas.parentElement;
      width = parent?.clientWidth || window.innerWidth;
      height = parent?.clientHeight || window.innerHeight;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();

    const colors = ['#00e5bf', '#4de6f7', '#73fbc4', '#ffffff', '#008093'];
    const particleCount = width < 640 ? 32 : 65;
    const particles: Particle[] = [];

    for (let i = 0; i < particleCount; i++) {
      particles.push({
        x: Math.random() * width,
        y: Math.random() * height,
        z: Math.random() * 2 + 0.5,
        vx: (Math.random() - 0.5) * 0.4,
        vy: -Math.random() * 0.5 - 0.15, // Gentle upwards glacial drift
        size: Math.random() * 2.2 + 0.8,
        alpha: Math.random() * 0.6 + 0.2,
        pulseSpeed: Math.random() * 0.02 + 0.01,
        color: colors[Math.floor(Math.random() * colors.length)],
      });
    }

    let mouseX = width / 2;
    let mouseY = height / 2;
    let targetMouseX = mouseX;
    let targetMouseY = mouseY;

    const handleMouseMove = (e: MouseEvent) => {
      const rect = canvas.getBoundingClientRect();
      targetMouseX = e.clientX - rect.left;
      targetMouseY = e.clientY - rect.top;
    };

    const drawFrame = (advance: boolean) => {
      ctx.clearRect(0, 0, width, height);

      if (advance) {
        // Smooth mouse interpolation
        mouseX += (targetMouseX - mouseX) * 0.05;
        mouseY += (targetMouseY - mouseY) * 0.05;
      }

      // Subtle connective glacial constellation lines
      ctx.lineWidth = 0.75;
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const distSq = dx * dx + dy * dy;
          if (distSq < 8100) {
            const dist = Math.sqrt(distSq);
            ctx.strokeStyle = `rgba(77, 230, 247, ${(1 - dist / 90) * 0.15})`;
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.stroke();
          }
        }
      }

      for (const p of particles) {
        if (advance) {
          p.x += p.vx;
          p.y += p.vy;

          // Subtle mouse repulsion drift (guard against dist === 0 -> NaN)
          const dx = mouseX - p.x;
          const dy = mouseY - p.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist > 0.001 && dist < 180) {
            p.x -= (dx / dist) * 0.6;
            p.y -= (dy / dist) * 0.6;
          }

          // Screen wrap
          if (p.y < -10) p.y = height + 10;
          if (p.x < -10) p.x = width + 10;
          if (p.x > width + 10) p.x = -10;
        }

        ctx.save();
        ctx.globalAlpha = p.alpha;
        ctx.fillStyle = p.color;
        ctx.shadowColor = p.color;
        ctx.shadowBlur = 10;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size * p.z, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
      }
    };

    const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    let onScreen = true;

    const loop = () => {
      drawFrame(true);
      animationFrameId = requestAnimationFrame(loop);
    };

    const stop = () => {
      cancelAnimationFrame(animationFrameId);
      animationFrameId = 0;
    };

    const sync = () => {
      const shouldAnimate = !motionQuery.matches && onScreen && document.visibilityState === 'visible';
      if (shouldAnimate && !animationFrameId) {
        animationFrameId = requestAnimationFrame(loop);
      } else if (!shouldAnimate) {
        stop();
        drawFrame(false); // keep a static, still-pretty frame
      }
    };

    const handleResize = () => {
      resize();
      if (!animationFrameId) drawFrame(false);
    };

    const observer =
      'IntersectionObserver' in window
        ? new IntersectionObserver((entries) => {
            onScreen = entries.some((e) => e.isIntersecting);
            sync();
          })
        : null;
    observer?.observe(canvas);

    window.addEventListener('resize', handleResize);
    window.addEventListener('mousemove', handleMouseMove, { passive: true });
    document.addEventListener('visibilitychange', sync);
    motionQuery.addEventListener?.('change', sync);
    sync();

    return () => {
      stop();
      observer?.disconnect();
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('visibilitychange', sync);
      motionQuery.removeEventListener?.('change', sync);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      className="absolute inset-0 pointer-events-none z-10 w-full h-full"
      style={{ opacity: 0.85 }}
    />
  );
};
