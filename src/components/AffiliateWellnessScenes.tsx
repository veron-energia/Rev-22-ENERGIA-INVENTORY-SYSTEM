import React from 'react';

// The art of the affiliate Sign in and Join pages (6 Nov 2026): three of
// Energia's services, drawn from the pictures on energia.sg and kept symbolic.
// No numbers, labels, readings or results on the screen, and no machine detail
// those pictures do not show. Every picture is decoration: aria-hidden here,
// and pointer-events off in affiliate-wellness.css.
//
// What moves is named by a class and animated in affiliate-wellness.css, and
// only for someone who has not asked for reduced motion. Each element's own
// resting style is a finished picture, so with no animation nothing is missing.
//
// `quiet` is the Sign in page's version: the same scenes with fewer moving parts.

export type SceneProps = { quiet?: boolean };

const TIFFANY = '#0ABAB5';
const TIFFANY_DEEP = '#079A96';
const TIFFANY_SOFT = '#7FDCD9';
const TIFFANY_PALE = '#D4F3F1';
const INK = '#33464D';
const SLATE = '#5C7076';
const SLATE_DEEP = '#4A5C62';
const CREAM = '#FBF8F1';
const SAND = '#EFE9DC';
const STONE = '#CEC6B5';
const STONE_DEEP = '#B4AB98';
const FLOOR = '#F1EBDF';
const SKIN = '#EDC8AA';
const SKIN_DEEP = '#DDAF8D';
const HAIR = '#5B4A42';

const Art: React.FC<{ viewBox: string; children: React.ReactNode }> = ({ viewBox, children }) => (
  <svg className="aff-wellness-svg" viewBox={viewBox} aria-hidden="true" focusable="false">{children}</svg>
);

// ── Power Recharge Therapy: a person resting on a recliner, in the headphones
// and dark glasses of Energia's photograph, with the rings of its diagram. A
// ring is two halves, one behind the person and one in front, so it goes round them.

const RING_BEHIND = 'M-240 0 A240 92 0 0 1 240 0';
const RING_IN_FRONT = 'M-240 0 A240 92 0 0 0 240 0';
const RECLINER = 'M112 170 C170 192 230 226 300 232 C360 236 400 216 450 217 C490 218 520 226 552 236';
const LEG = 'M320 181 C352 177 384 170 410 167.5 C444 168 480 173 510 179 Q520 190 508 205 C476 203 444 199 416 197 C388 204 358 212 330 219Z';
const FOOT = 'M504 184 C515 183 523 172 529 157 C532 149 542 150 542 158 C542 171 536 190 527 203 C522 209 513 207 504 202Z';

export const RechargeScene: React.FC<SceneProps> = ({ quiet }) => {
  const rings = (half: string) => (
    <g transform="translate(330 178)">
      {(quiet ? [1, 2] : [1, 2, 3]).map(n => (
        <g key={n} className={`aff-wellness-ring aff-wellness-ring--${n}`}>
          <path d={half} fill="none" stroke={TIFFANY} strokeWidth="2.4" />
        </g>
      ))}
    </g>
  );
  return (
    <Art viewBox="0 40 640 300">
      <defs>
        <radialGradient id="aff-wellness-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0" stopColor={TIFFANY_SOFT} stopOpacity=".5" />
          <stop offset=".65" stopColor={TIFFANY_PALE} stopOpacity=".4" />
          <stop offset="1" stopColor={TIFFANY_PALE} stopOpacity="0" />
        </radialGradient>
        <linearGradient id="aff-wellness-shirt" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#2CCBC6" />
          <stop offset="1" stopColor={TIFFANY} />
        </linearGradient>
      </defs>

      <rect x="-600" y="296" width="1840" height="140" fill={FLOOR} />
      <ellipse className="aff-wellness-glow" cx="330" cy="178" rx="300" ry="150" fill="url(#aff-wellness-glow)" />
      {!quiet && <LeafSprig />}
      {rings(RING_BEHIND)}
      <ellipse cx="352" cy="298" rx="176" ry="8" fill={INK} opacity=".08" />

      {/* The recliner */}
      <path d="M268 246 L234 296 M436 242 L470 296" fill="none" stroke={STONE_DEEP} strokeWidth="9" strokeLinecap="round" />
      <path d="M214 297 H490" fill="none" stroke={STONE_DEEP} strokeWidth="8" strokeLinecap="round" />
      <path d={RECLINER} transform="translate(0 7)" fill="none" stroke={STONE} strokeWidth="32" strokeLinecap="round" />
      <path d={RECLINER} fill="none" stroke={SAND} strokeWidth="32" strokeLinecap="round" />
      <path d={RECLINER} transform="translate(0 -7)" fill="none" stroke={CREAM} strokeWidth="14" strokeLinecap="round" />
      <ellipse cx="152" cy="158" rx="50" ry="19" transform="rotate(22 152 158)" fill="#FFFFFF" stroke="#E6E0D3" strokeWidth="1.5" />

      {/* The legs, far then near, and the bare feet */}
      <path d={FOOT} transform="translate(-5 -11)" fill={SKIN_DEEP} />
      <path d={LEG} transform="translate(2 -11)" fill={SLATE_DEEP} />
      <path d={FOOT} fill={SKIN} />
      <path d={LEG} fill={SLATE} />

      {/* The body, which rises a little with each breath; hands folded */}
      <path d="M190 141 L212 156" fill="none" stroke={SKIN_DEEP} strokeWidth="17" strokeLinecap="round" />
      <g className="aff-wellness-breath">
        <path d="M196 152 C212 147 230 151 246 159 C268 170 302 175 338 178 L340 219 C312 221 282 217 258 209 C232 201 208 189 193 172Z" fill="url(#aff-wellness-shirt)" />
        <ellipse cx="314" cy="179" rx="10" ry="7.5" transform="rotate(-14 314 179)" fill={SKIN_DEEP} />
        <path d="M216 164 L234 180" fill="none" stroke={TIFFANY_DEEP} strokeWidth="21" strokeLinecap="round" />
        <path d="M236 182 L258 197 L296 180" fill="none" stroke={SKIN} strokeWidth="14.5" strokeLinecap="round" strokeLinejoin="round" />
        <ellipse cx="303" cy="177" rx="11.5" ry="8" transform="rotate(-18 303 177)" fill={SKIN} />
      </g>

      {/* The head, drawn upright facing right and turned up to rest on the pillow */}
      <g transform="translate(168 131) rotate(-65)">
        <circle cx="24.5" cy="1" r="4.8" fill={SKIN} />
        <ellipse rx="25" ry="27" fill={SKIN} />
        <path d="M17 -21 A26 27 0 0 0 -21 17 Q-9 20 -8 9 Q-5 -11 17 -21Z" fill={HAIR} />
        <path d="M11 14 Q16 17 20 12.5" fill="none" stroke="#B9835F" strokeWidth="2" strokeLinecap="round" />
        <path d="M-4 -1 L9 -5.5" fill="none" stroke={INK} strokeWidth="2.4" strokeLinecap="round" />
        <rect x="7" y="-10.5" width="15.5" height="9.5" rx="4" fill={INK} />
        <path d="M-6 -8 Q-8 -20 -5 -30" fill="none" stroke={INK} strokeWidth="5" strokeLinecap="round" />
        <rect x="-13" y="-10" width="15" height="24" rx="7.5" fill={INK} />
        <rect x="-9" y="-5" width="7" height="14" rx="3.5" fill={TIFFANY} />
      </g>

      {rings(RING_IN_FRONT)}
    </Art>
  );
};

const LeafSprig: React.FC = () => (
  <g fill={TIFFANY_PALE}>
    <path d="M592 296 C590 262 594 236 604 214" fill="none" stroke={TIFFANY_SOFT} strokeWidth="2.5" strokeLinecap="round" opacity=".7" />
    <path d="M593 270 C574 262 566 246 568 230 C586 234 596 250 593 270Z" />
    <path d="M596 248 C612 244 622 230 622 214 C606 216 594 230 596 248Z" />
    <path d="M601 222 C592 212 590 200 594 188 C606 196 610 210 601 222Z" />
  </g>
);

// ── Power Foot Detox Therapy: the white tub of Energia's photograph, feet
// resting in the water, with ripples and a few bubbles.

const WATERLINE = 98;
const HEM = 34;
const FEET = [118, 202];
const BUBBLES = [
  { x: 72, y: 128, r: 3.4, delay: 0 },
  { x: 248, y: 106, r: 3, delay: -2.4 },
  { x: 160, y: 138, r: 3.6, delay: -4.6 },
  { x: 84, y: 104, r: 2.4, delay: -1.2 },
  { x: 252, y: 142, r: 2.6, delay: -3.4 },
  { x: 160, y: 108, r: 2.2, delay: -5.6 },
];

// A foot seen from above, from the ankle at the waterline (0, 0) down to the
// toes: narrow at the ankle and widest at the ball, the big toe on the inner side
// (+x), the others smaller and falling away towards the outer side.
const FOOT_TOP = 'M11 0 C12 12 16 22 18 33 Q2 42 -18 30 C-18 20 -13 10 -11 0Z';
const TOES = [
  { x: 11.5, y: 41, rx: 6.6, ry: 8.6, turn: -4, nail: 2.9 },
  { x: 2, y: 44.5, rx: 4.1, ry: 6.6, turn: 3, nail: 1.6 },
  { x: -5, y: 43, rx: 3.7, ry: 5.9, turn: 7, nail: 1.4 },
  { x: -11, y: 40, rx: 3.4, ry: 5.2, turn: 12, nail: 1.2 },
  { x: -16, y: 35.5, rx: 3, ry: 4.4, turn: 18, nail: 1 },
];

// Mirrored for the other foot, so each big toe is on the inner side; both turn out a little.
const Foot: React.FC<{ x: number; mirrored?: boolean }> = ({ x, mirrored }) => (
  <g transform={`translate(${x} ${WATERLINE}) scale(${mirrored ? -1 : 1} 1) rotate(7)`}>
    <path d={FOOT_TOP} transform="translate(1 4)" fill={TIFFANY_DEEP} opacity=".12" />
    <path d={FOOT_TOP} fill={SKIN} />
    {TOES.map(t => (
      <g key={t.x} transform={`translate(${t.x} ${t.y}) rotate(${t.turn})`}>
        <ellipse rx={t.rx} ry={t.ry} fill={SKIN} />
        <ellipse cy={t.ry * 0.46} rx={t.nail} ry={t.nail * 1.1} fill="#F6DFCD" />
      </g>
    ))}
  </g>
);

// A shin going into the water, narrower at the ankle; its lower edge is the
// curve of the waterline. `lean` is how far the knee is to the side.
const Leg: React.FC<{ x: number; lean: number }> = ({ x, lean }) => {
  const knee = x + lean;
  const hem = x + lean * 0.62;
  return (
    <g>
      <path d={`M${knee - 21} -14 L${hem - 18} ${HEM} H${hem + 18} L${knee + 21} -14Z`} fill={SLATE} />
      <path d={`M${knee + 7} -14 L${hem + 6} ${HEM} H${hem + 18} L${knee + 21} -14Z`} fill={SLATE_DEEP} opacity=".35" />
      <path d={`M${hem - 15} ${HEM + 2} L${x - 11} ${WATERLINE} A11 4 0 0 0 ${x + 11} ${WATERLINE} L${hem + 15} ${HEM + 2}Z`} fill={SKIN} />
      <path d={`M${hem + 5} ${HEM + 2} L${x + 4} ${WATERLINE + 3.6} A11 4 0 0 0 ${x + 11} ${WATERLINE} L${hem + 15} ${HEM + 2}Z`} fill={SKIN_DEEP} opacity=".4" />
      <rect x={hem - 20} y={HEM - 6} width="40" height="11" rx="4.5" fill={SLATE_DEEP} />
    </g>
  );
};

export const FootSpaScene: React.FC<SceneProps> = ({ quiet }) => (
  <Art viewBox="0 0 320 200">
    <defs>
      <linearGradient id="aff-wellness-water" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#B4EDEA" />
        <stop offset="1" stopColor="#6FDAD6" />
      </linearGradient>
      <linearGradient id="aff-wellness-tub" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#FFFFFF" />
        <stop offset="1" stopColor="#E7E2D7" />
      </linearGradient>
      <clipPath id="aff-wellness-surface">
        <rect x="53" y="90" width="214" height="70" rx="19" />
      </clipPath>
    </defs>

    <circle cx="160" cy="84" r="84" fill={TIFFANY_PALE} opacity=".4" />
    <rect x="-600" y="150" width="1520" height="120" fill={FLOOR} />
    <ellipse cx="160" cy="193" rx="118" ry="6" fill={INK} opacity=".1" />

    {/* The tub */}
    <path d="M43 130 H277 L262 180 Q259 193 246 193 H74 Q61 193 58 180Z" fill="url(#aff-wellness-tub)" stroke={STONE} strokeWidth="1.2" />
    <rect x="40" y="76" width="240" height="94" rx="28" fill="#FFFFFF" stroke={STONE} strokeWidth="1.2" />
    <rect x="50" y="83" width="220" height="80" rx="22" fill="#E9E5DB" />

    {/* Water, with the feet under its surface */}
    <g clipPath="url(#aff-wellness-surface)">
      <rect x="53" y="90" width="214" height="70" fill="url(#aff-wellness-water)" />
      <Foot x={FEET[0]} />
      <Foot x={FEET[1]} mirrored />
      <rect x="53" y="90" width="214" height="70" fill="url(#aff-wellness-water)" opacity=".08" />
      {(quiet ? [FEET[0]] : FEET).map(x => (
        <g key={x} transform={`translate(${x} ${WATERLINE})`}>
          {[1, 2].map(n => (
            <ellipse key={n} className={`aff-wellness-ripple aff-wellness-ripple--${n}`} rx="40" ry="13" fill="none" stroke="#FFFFFF" strokeWidth="1.8" />
          ))}
        </g>
      ))}
      {(quiet ? BUBBLES.slice(0, 2) : BUBBLES).map((b, i) => (
        <circle key={i} className="aff-wellness-bubble" style={{ animationDelay: `calc(${b.delay}s * var(--aff-wellness-tempo))` }}
          cx={b.x} cy={b.y} r={b.r} fill="#FFFFFF" />
      ))}
    </g>

    <Leg x={FEET[0]} lean={-12} />
    <Leg x={FEET[1]} lean={12} />
  </Art>
);

// ── AcuGraph Energy Analysis: a small screen with bars and two lines, in one
// colour family (high and low colours would read as somebody's result).

const BARS = [46, 64, 38, 58, 72, 42, 62, 50, 74, 40, 56, 68];

export const AnalysisScene: React.FC<SceneProps> = ({ quiet }) => {
  const bars = quiet ? BARS.filter((_, i) => i % 2 === 0) : BARS;
  const step = 164 / bars.length;
  const width = Math.min(step * 0.62, 12);
  return (
    <Art viewBox="0 0 320 200">
      <circle cx="160" cy="84" r="84" fill={TIFFANY_PALE} opacity=".4" />
      <rect x="-600" y="178" width="1520" height="60" fill={FLOOR} />
      <ellipse cx="160" cy="180" rx="66" ry="4.5" fill={INK} opacity=".1" />
      <path d="M148 150 L144 174 H176 L172 150Z" fill={STONE} />
      <rect x="116" y="172" width="88" height="8" rx="4" fill={STONE_DEEP} />
      <rect x="58" y="24" width="204" height="130" rx="12" fill="#46595F" />
      <rect x="64" y="30" width="192" height="118" rx="7" fill="#FFFFFF" />
      <rect x="76" y="39" width="82" height="7" rx="3" fill={SAND} />
      <rect x="162" y="39" width="82" height="7" rx="3" fill={SAND} />
      <path d="M76 138 H244" stroke={STONE} strokeWidth="1.4" strokeLinecap="round" />
      {bars.map((h, i) => (
        <g key={i} transform={`translate(${78 + step * (i + 0.5)} 138)`}>
          <rect className="aff-wellness-bar" style={{ animationDelay: `calc(${-i * 0.9}s * var(--aff-wellness-tempo))` }}
            x={-width / 2} y={-h} width={width} height={h} rx="3" fill={i % 3 === 1 ? TIFFANY_SOFT : TIFFANY} />
        </g>
      ))}
      <path d="M76 92 H244" stroke={TIFFANY_DEEP} strokeWidth="1.2" strokeDasharray="1 5" strokeLinecap="round" opacity=".55" />
      <path d="M76 112 H244" stroke={INK} strokeWidth="1.2" strokeDasharray="1 5" strokeLinecap="round" opacity=".28" />
    </Art>
  );
};

// ── People connected to one another: sharing wellness with friends (Join only).

const PEOPLE = [
  { x: 20, s: 0.72, fill: TIFFANY_PALE, line: TIFFANY_SOFT },
  { x: 70, s: 0.86, fill: TIFFANY_SOFT, line: TIFFANY_SOFT },
  { x: 122, s: 1, fill: TIFFANY, line: TIFFANY },
  { x: 174, s: 0.86, fill: TIFFANY_SOFT, line: TIFFANY_SOFT },
  { x: 224, s: 0.72, fill: TIFFANY_PALE, line: TIFFANY_SOFT },
];

export const ConnectedPeople: React.FC = () => (
  <svg className="aff-wellness-people" viewBox="0 0 244 56" aria-hidden="true" focusable="false">
    <path className="aff-wellness-link" d="M28 26 Q49 12 62 22 M80 20 Q98 6 112 18 M132 18 Q150 6 164 20 M182 22 Q199 12 216 26"
      fill="none" stroke={TIFFANY} strokeWidth="1.8" strokeLinecap="round" strokeDasharray="1 6" />
    {PEOPLE.map((p, i) => (
      <g key={p.x} transform={`translate(${p.x} 52) scale(${p.s})`}>
        <g className="aff-wellness-person" style={{ animationDelay: `calc(${-i * 1.1}s * var(--aff-wellness-tempo))` }}>
          <circle cy="-30" r="10" fill={p.fill} stroke={p.line} strokeWidth="1.2" />
          <path d="M-16 0 C-16 -13 -8 -18 0 -18 C8 -18 16 -13 16 0Z" fill={p.fill} stroke={p.line} strokeWidth="1.2" />
        </g>
      </g>
    ))}
  </svg>
);
