import React from 'react';

/**
 * AliveGlacialRiver
 * High-performance animated SVG river currents mapped 1:1 to the 1376x768 glacial landscape.
 * Uses preserveAspectRatio="xMidYMid slice" to perfectly align with the object-cover background image.
 */
export const AliveGlacialRiver: React.FC = () => {
  return (
    <div className="absolute inset-0 pointer-events-none overflow-hidden z-[5]">
      <svg
        className="w-full h-full object-cover"
        viewBox="0 0 1376 768"
        preserveAspectRatio="xMidYMid slice"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          {/* Cyan / Teal Radiant Fluid Gradients */}
          <linearGradient id="riverGrad1" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#00e5bf" stopOpacity="0">
              <animate
                attributeName="stop-color"
                values="#00e5bf;#38ef7d;#4de6f7;#00e5bf"
                dur="8s"
                repeatCount="indefinite"
              />
            </stop>
            <stop offset="20%" stopColor="#00e5bf" stopOpacity="0.85" />
            <stop offset="50%" stopColor="#4de6f7" stopOpacity="1" />
            <stop offset="80%" stopColor="#73fbc4" stopOpacity="0.85" />
            <stop offset="100%" stopColor="#4de6f7" stopOpacity="0" />
          </linearGradient>

          <linearGradient id="riverGrad2" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#4de6f7" stopOpacity="0" />
            <stop offset="30%" stopColor="#00f5a0" stopOpacity="0.9" />
            <stop offset="65%" stopColor="#ffffff" stopOpacity="0.95" />
            <stop offset="85%" stopColor="#00e5bf" stopOpacity="0.8" />
            <stop offset="100%" stopColor="#006575" stopOpacity="0" />
          </linearGradient>

          <linearGradient id="coreLight" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#ffffff" stopOpacity="0" />
            <stop offset="25%" stopColor="#ffffff" stopOpacity="0.95" />
            <stop offset="50%" stopColor="#86f2e4" stopOpacity="1" />
            <stop offset="75%" stopColor="#ffffff" stopOpacity="0.9" />
            <stop offset="100%" stopColor="#ffffff" stopOpacity="0" />
          </linearGradient>

          {/* Glacial Aura Filters */}
          <filter id="riverGlowWide" x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur stdDeviation="8" result="blur1" />
            <feGaussianBlur stdDeviation="16" result="blur2" />
            <feMerge>
              <feMergeNode in="blur2" />
              <feMergeNode in="blur1" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>

          <filter id="riverGlowTight" x="-10%" y="-10%" width="120%" height="120%">
            <feGaussianBlur stdDeviation="3.5" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>

          {/* Water caustic shimmering gradient */}
          <radialGradient id="waterCaustic" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="#4de6f7" stopOpacity="0.4" />
            <stop offset="60%" stopColor="#00e5bf" stopOpacity="0.15" />
            <stop offset="100%" stopColor="#0b1528" stopOpacity="0" />
          </radialGradient>
        </defs>

        {/* --- WATER SURFACE AMBIENT GLOW BEDS --- */}
        {/* Soft atmospheric glow pooled under the main water channel */}
        <ellipse
          cx="620"
          cy="580"
          rx="320"
          ry="70"
          fill="url(#waterCaustic)"
          className="animate-pulse"
          style={{ animationDuration: '4s' }}
        />
        <ellipse
          cx="260"
          cy="640"
          rx="240"
          ry="60"
          fill="url(#waterCaustic)"
          className="animate-pulse"
          style={{ animationDuration: '6s' }}
        />

        {/* --- STREAM 1: MAIN FOREGROUND SWEEPING RIVER CURRENT --- */}
        {/* Deep undercurrent wide glow */}
        <path
          d="M -30 710 C 140 680, 260 635, 420 620 C 530 610, 610 565, 680 525 C 730 495, 780 485, 850 480"
          stroke="url(#riverGrad1)"
          strokeWidth="28"
          strokeLinecap="round"
          className="opacity-40 blur-md"
          style={{
            strokeDasharray: '400 150',
            animation: 'riverFlow 7s linear infinite',
          }}
        />

        {/* Sharp luminous flowing stream */}
        <path
          d="M -30 710 C 140 680, 260 635, 420 620 C 530 610, 610 565, 680 525 C 730 495, 780 485, 850 480"
          stroke="url(#riverGrad1)"
          strokeWidth="9"
          strokeLinecap="round"
          filter="url(#riverGlowWide)"
          style={{
            strokeDasharray: '320 100',
            animation: 'riverFlow 5.5s linear infinite',
          }}
        />

        {/* Core white-cyan laser energy ribbon */}
        <path
          d="M -30 710 C 140 680, 260 635, 420 620 C 530 610, 610 565, 680 525 C 730 495, 780 485, 850 480"
          stroke="url(#coreLight)"
          strokeWidth="3.2"
          strokeLinecap="round"
          filter="url(#riverGlowTight)"
          style={{
            strokeDasharray: '180 200',
            animation: 'riverFlow 4.2s linear infinite',
          }}
        />

        {/* --- STREAM 2: BRANCH FLOWING TOWARDS RIGHT COLOSSAL GLACIER --- */}
        {/* Wide ambient flow */}
        <path
          d="M 580 560 C 690 540, 780 525, 910 525 C 1030 525, 1120 550, 1260 545 C 1315 542, 1370 535, 1410 530"
          stroke="url(#riverGrad2)"
          strokeWidth="22"
          strokeLinecap="round"
          className="opacity-35 blur-sm"
          style={{
            strokeDasharray: '350 140',
            animation: 'riverFlow 6.8s linear infinite',
          }}
        />

        {/* Crisp energetic right stream */}
        <path
          d="M 580 560 C 690 540, 780 525, 910 525 C 1030 525, 1120 550, 1260 545 C 1315 542, 1370 535, 1410 530"
          stroke="url(#riverGrad2)"
          strokeWidth="8"
          strokeLinecap="round"
          filter="url(#riverGlowWide)"
          style={{
            strokeDasharray: '280 90',
            animation: 'riverFlow 5s linear infinite',
          }}
        />

        {/* Core ribbon right glacier */}
        <path
          d="M 580 560 C 690 540, 780 525, 910 525 C 1030 525, 1120 550, 1260 545 C 1315 542, 1370 535, 1410 530"
          stroke="url(#coreLight)"
          strokeWidth="2.8"
          strokeLinecap="round"
          filter="url(#riverGlowTight)"
          style={{
            strokeDasharray: '150 180',
            animation: 'riverFlow 3.8s linear infinite',
          }}
        />

        {/* --- STREAM 3: MEANDERING UPPER TRIBUTARY UNDER LEFT PYRAMID --- */}
        <path
          d="M 50 495 C 160 495, 270 500, 370 510 C 470 518, 550 530, 640 535 C 710 540, 770 530, 840 510"
          stroke="url(#riverGrad1)"
          strokeWidth="5"
          strokeLinecap="round"
          filter="url(#riverGlowWide)"
          style={{
            strokeDasharray: '200 120',
            animation: 'riverFlowDelayed 6.2s linear infinite',
          }}
        />

        <path
          d="M 50 495 C 160 495, 270 500, 370 510 C 470 518, 550 530, 640 535 C 710 540, 770 530, 840 510"
          stroke="url(#coreLight)"
          strokeWidth="2"
          strokeLinecap="round"
          filter="url(#riverGlowTight)"
          style={{
            strokeDasharray: '110 160',
            animation: 'riverFlowDelayed 4.8s linear infinite',
          }}
        />

        {/* --- STREAM 4: WATER CAUSTIC RIPPLE WAVES (SHIMMER) --- */}
        <path
          d="M -10 745 C 180 705, 310 655, 480 635 C 590 620, 670 575, 740 535 C 790 505, 830 495, 900 488"
          stroke="url(#riverGrad2)"
          strokeWidth="3.5"
          strokeLinecap="round"
          className="opacity-75"
          style={{
            strokeDasharray: '120 180',
            animation: 'riverFlowDelayed 3.6s linear infinite',
          }}
        />

        {/* --- MOVING LUMINOUS CURRENT PARTICLES TRAVELING ON PATHS --- */}
        <circle r="4.5" fill="#ffffff" filter="url(#riverGlowWide)">
          <animateMotion
            path="M -30 710 C 140 680, 260 635, 420 620 C 530 610, 610 565, 680 525 C 730 495, 780 485, 850 480"
            dur="5.5s"
            repeatCount="indefinite"
          />
        </circle>
        <circle r="3.5" fill="#4de6f7" filter="url(#riverGlowTight)">
          <animateMotion
            path="M -30 710 C 140 680, 260 635, 420 620 C 530 610, 610 565, 680 525 C 730 495, 780 485, 850 480"
            dur="5.5s"
            begin="2.2s"
            repeatCount="indefinite"
          />
        </circle>
        <circle r="4" fill="#00f5a0" filter="url(#riverGlowWide)">
          <animateMotion
            path="M 580 560 C 690 540, 780 525, 910 525 C 1030 525, 1120 550, 1260 545 C 1315 542, 1370 535, 1410 530"
            dur="5s"
            repeatCount="indefinite"
          />
        </circle>
        <circle r="3" fill="#ffffff" filter="url(#riverGlowTight)">
          <animateMotion
            path="M 580 560 C 690 540, 780 525, 910 525 C 1030 525, 1120 550, 1260 545 C 1315 542, 1370 535, 1410 530"
            dur="5s"
            begin="2.5s"
            repeatCount="indefinite"
          />
        </circle>
      </svg>

      <style>{`
        @keyframes riverFlow {
          0% {
            stroke-dashoffset: 1200;
          }
          100% {
            stroke-dashoffset: 0;
          }
        }
        @keyframes riverFlowDelayed {
          0% {
            stroke-dashoffset: 1000;
          }
          100% {
            stroke-dashoffset: 0;
          }
        }
      `}</style>
    </div>
  );
};
