#!/usr/bin/env python3
"""The Page-Flip Runner - motion prototype renderer v2.

Source of truth for the Flutter CustomPainter port and the Rive spec.
Frame = one 1/30s tick; the loop shows progress 0->92 + the finish jump.
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

W = H = 480
CX, GROUND = W // 2, 322
NAVY = (10, 14, 30, 255)
ICE = (255, 255, 255, 255)
ICE_BACK = (212, 227, 244, 235)
SKY = (135, 206, 235, 255)
OCEAN = (0, 119, 190, 255)
PAPER = (238, 244, 252, 255)
PAPER_EDGE = (135, 206, 235, 210)
COVER_L = (26, 37, 66, 255)
COVER_R = (33, 47, 82, 255)
RIM = (135, 206, 235, 130)

FPS = 30
RAMP = 96
FINISH = 38
TOTAL = RAMP + FINISH
RUNNER_LIFT = 30

def clamp(v, lo, hi): return max(lo, min(hi, v))
def ease_in_cubic(t): return t * t * t
def ease_in_out(t):
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2

def progress_at(frame):
    if frame < RAMP:
        return ease_in_out(frame / (RAMP - 1)) * 92.0
    return 92.0

def stride_freq(progress):
    if progress <= 30:
        return 2.0 + (progress / 30.0) * 0.6
    t = (progress - 30) / 60.0
    return 2.6 + ease_in_cubic(t) * 2.6

def lean_deg(progress):
    if progress <= 30:
        return 5 + (progress / 30.0) * 3
    return 8 + ease_in_cubic(clamp((progress - 30) / 60.0, 0, 1)) * 15

def trail_len(progress):
    if progress <= 30:
        return 0.15 + (progress / 30.0) * 0.15
    t = ease_in_cubic(clamp((progress - 30) / 60.0, 0, 1))
    return 0.30 + t * 0.65

def rot(p, deg, origin=(0, 0)):
    r = math.radians(deg)
    cr, sr = math.cos(r), math.sin(r)
    ox, oy = origin
    return ((p[0] - ox) * cr - (p[1] - oy) * sr + ox,
            (p[0] - ox) * sr + (p[1] - oy) * cr + oy)

def pose(phase, lean, speed01, tuck=0.0, air=0.0):
    s = math.sin(phase * 2 * math.pi)
    bob = -abs(s) * 6 * (1 - tuck)
    hip = (0, -46 + bob - air)
    sh = (5 + lean * 0.24, -88 + bob * 0.8 - air + tuck * 7)
    head = (11 + lean * 0.42, -106 + bob * 0.7 - air + tuck * 9)
    stride = 27 + speed01 * 17
    lift = 24 + speed01 * 15
    kneeF = (s * stride * 0.62, 2 - lift * max(0, s) * (1 - tuck * 0.8))
    footF = (s * stride, 30 - lift * max(0, s) * (1 - tuck * 0.9) - air * 0.15)
    kneeB = (-s * stride * 0.55, 2 - lift * max(0, -s) * 0.7 * (1 - tuck))
    footB = (-s * stride * 0.92, 30 - lift * max(0, -s) * (1 - tuck) - air * 0.15)
    armS = -s * 0.95
    elbowF = (sh[0] + 15 + armS * 9, sh[1] + 27 - tuck * 12)
    handF = (sh[0] + 24 + armS * 15, sh[1] + 42 - tuck * 26 + armS * 5)
    elbowB = (sh[0] - 11 + armS * 7, sh[1] + 25 - tuck * 14)
    handB = (sh[0] - 18 + armS * 13, sh[1] + 38 - tuck * 30 - armS * 5)
    return dict(hip=hip, sh=sh, head=head, kneeF=kneeF, footF=footF,
                kneeB=kneeB, footB=footB, elbowF=elbowF, handF=handF,
                elbowB=elbowB, handB=handB, bob=bob)

def limb(dr, pts, width, color):
    dr.line(pts, fill=color, width=width, joint='curve')
    r = width / 2
    for (x, y) in (pts[0], pts[-1]):
        dr.ellipse([x - r, y - r, x + r, y + r], fill=color)

def iso(x, y):
    return (CX + (x - y), GROUND + (x + y) * 0.5 - 26)

BOOK_HALF = 92

def page_arc(flip_phase):
    rows = 8
    pts = []
    lift = math.sin(flip_phase * math.pi)
    side = math.cos(flip_phase * math.pi)
    for i in range(rows + 1):
        t = i / rows
        d = BOOK_HALF * (1 - 2 * t)
        z = lift * 96 * (0.55 + 0.45 * math.cos(t * math.pi))
        x = side * d * (0.82 + 0.18 * math.cos(flip_phase * math.pi))
        y = -d * (0.25 + 0.20 * (1 - abs(side)))
        p = iso(x, y)
        pts.append((p[0], p[1] - z))
    quads = []
    for i in range(rows):
        quads.append([pts[i], pts[i + 1],
                      (pts[i + 1][0], pts[i + 1][1] + 6),
                      (pts[i][0], pts[i][1] + 6)])
    return quads, pts

def render(frame):
    img = Image.new('RGBA', (W, H), NAVY)
    dr = ImageDraw.Draw(img, 'RGBA')
    prog = progress_at(frame)

    if frame < RAMP:
        speed01 = clamp((prog - 30) / 60.0, 0, 1)
        tuck = air = 0.0
        finish_t = -1.0
    else:
        speed01 = 1.0
        finish_t = (frame - RAMP) / (FINISH - 1)
        tuck = ease_in_out(clamp((finish_t - 0.10) / 0.32, 0, 1))
        air = (math.sin(clamp((finish_t - 0.08) / 0.52, 0, 1) * math.pi) * 84
               if finish_t > 0.08 else 0.0)

    t_sec = frame / FPS
    if frame < RAMP:
        phase = (stride_freq(prog) * t_sec) % 1.0
    else:
        phase = 0.18 + finish_t * 0.35

    lean = lean_deg(prog) * (1 - tuck * 0.6)
    gy = GROUND - RUNNER_LIFT - air

    cover_l = [iso(-BOOK_HALF - 9, -78), iso(1, -78), iso(1, 78),
               iso(-BOOK_HALF - 9, 78)]
    cover_r = [iso(-1, -78), iso(BOOK_HALF + 9, -78), iso(BOOK_HALF + 9, 78),
               iso(-1, 78)]
    dr.polygon(cover_l, fill=COVER_L)
    dr.polygon(cover_r, fill=COVER_R)
    dr.line(cover_l + [cover_l[0]], fill=RIM, width=2)
    dr.line(cover_r + [cover_r[0]], fill=RIM, width=2)
    for off in (4, 8):
        stack = [iso(-BOOK_HALF - 9 + off * 0.6, -78 + off),
                 iso(-2, -78 + off), iso(-2, 78 - off),
                 iso(-BOOK_HALF - 9 + off * 0.6, 78 - off)]
        dr.polygon(stack, fill=(205, 220, 240, 55))
        stack2 = [iso(2, -78 + off), iso(BOOK_HALF + 9 - off * 0.6, -78 + off),
                  iso(BOOK_HALF + 9 - off * 0.6, 78 - off), iso(2, 78 - off)]
        dr.polygon(stack2, fill=(198, 214, 238, 48))
    deck_l = [iso(-BOOK_HALF, -74), iso(-3, -74), iso(-3, 74), iso(-BOOK_HALF, 74)]
    deck_r = [iso(3, -74), iso(BOOK_HALF, -74), iso(BOOK_HALF, 74), iso(3, 74)]
    dr.polygon(deck_l, fill=(232, 240, 252, 110))
    dr.polygon(deck_r, fill=(232, 240, 252, 110))

    if frame < RAMP:
        flips = [(phase * 0.9 + f) % 1.0 for f in (0.0, 0.33, 0.66)]
    else:
        flips = [min(1.0, finish_t * 1.3), max(0.0, 0.5 - finish_t * 0.9),
                 max(0.0, 0.85 - finish_t * 1.1)]
    for k, fp in enumerate(flips):
        fp_k = clamp(fp, 0.0, 1.0)
        quads, arc = page_arc(fp_k)
        alpha = int(240 - 60 * fp_k)
        for quad in quads:
            dr.polygon(quad, fill=(PAPER[0], PAPER[1], PAPER[2], alpha))
        dr.line(arc, fill=PAPER_EDGE, width=4, joint='curve')
    dr.line([iso(0, -78), iso(0, 78)], fill=(135, 206, 235, 70), width=2)

    # trails are drawn anchored to the runner's limbs (see streaks below)

    alive = 0 <= finish_t < 0.42 or finish_t < 0
    foot_world = None
    if alive:
        P = pose(phase, lean, speed01, tuck=tuck, air=air)
        P = {k: rot(v, lean, P['hip']) if isinstance(v, tuple) else v
             for k, v in P.items()}
        def T(pt): return (CX + pt[0], gy + pt[1])
        limb(dr, [T(P['hip']), T(P['kneeB']), T(P['footB'])], 8, ICE_BACK)
        limb(dr, [T(P['sh']), T(P['elbowB']), T(P['handB'])], 7, ICE_BACK)
        perp = (-(P['sh'][1] - P['hip'][1]), P['sh'][0] - P['hip'][0])
        plen = math.hypot(*perp) or 1
        nx, ny = perp[0] / plen, perp[1] / plen
        sw, hw = 10.5, 6.5
        torso = [(P['sh'][0] + nx * sw, P['sh'][1] + ny * sw),
                 (P['sh'][0] - nx * sw, P['sh'][1] - ny * sw),
                 (P['hip'][0] - nx * hw, P['hip'][1] - ny * hw),
                 (P['hip'][0] + nx * hw, P['hip'][1] + ny * hw)]
        dr.polygon([T(p) for p in torso], fill=ICE)
        h = T(P['head'])
        dr.ellipse([h[0] - 13, h[1] - 13, h[0] + 13, h[1] + 13], fill=ICE)
        hair = [(h[0] - 7, h[1] - 5)]
        for seg in range(1, 6):
            fx = h[0] - 7 - seg * (10 + speed01 * 7)
            fy = h[1] - 5 + seg * 3.2 + math.sin(t_sec * 14 + seg) * (2 + 4 * speed01)
            hair.append((fx, fy))
        dr.line(hair, fill=ICE, width=5, joint='curve')
        for ribbon in (0, 1):
            pts = [T(P['sh'])]
            for seg in range(1, 7):
                fx = CX + P['sh'][0] - seg * (9 + speed01 * 9)
                fy = gy + P['sh'][1] + 4 + seg * 2.4 + math.sin(
                    t_sec * (11 + ribbon * 2.3) + seg * 1.1 + ribbon) * (2 + 6 * speed01)
                pts.append((fx, fy))
            dr.line(pts, fill=(198, 222, 246, 225), width=4, joint='curve')
        if frame < RAMP and speed01 > 0.12:
            streak = trail_len(prog) * 130
            anchors = [(P['handF'], 4), (P['footF'], 5)]
            if speed01 > 0.5:
                anchors.append((P['head'], 3))
            for joint, wd in anchors:
                j = T(joint)
                mid = (j[0] - streak * 0.55, j[1] + 2 - speed01 * 2)
                tip = (j[0] - streak, j[1] + 5 - speed01 * 5)
                dr.line([j, mid],
                        fill=(SKY[0], SKY[1], SKY[2], int(120 + 90 * speed01)),
                        width=wd)
                dr.line([mid, tip],
                        fill=(SKY[0], SKY[1], SKY[2], int(50 + 70 * speed01)),
                        width=max(2, wd - 2))
        limb(dr, [T(P['hip']), T(P['kneeF']), T(P['footF'])], 10, ICE)
        limb(dr, [T(P['sh']), T(P['elbowF']), T(P['handF'])], 9, ICE)
        foot_world = T(P['footF'])

    if frame < RAMP and foot_world is not None:
        strike = math.sin(phase * 2 * math.pi)
        if strike > 0.90:
            t0 = (strike - 0.90) / 0.10
            for i in range(5):
                ang = math.radians(-64 + i * 26)
                spd = 20 + (i % 3) * 9
                px = foot_world[0] + math.cos(ang) * spd * t0 * 1.6
                py = foot_world[1] + math.sin(ang) * spd * t0 * 1.2 + 26 * t0 * t0
                r = 3.0 * (1 - t0) + 0.8
                col = OCEAN if i % 2 else SKY
                dr.ellipse([px - r, py - r, px + r, py + r],
                           fill=(col[0], col[1], col[2], int(225 * (1 - t0))))

    if finish_t >= 0.40:
        air_apex = math.sin(clamp((0.42 - 0.08) / 0.52, 0, 1) * math.pi) * 84
        bx, by = CX + 18, GROUND - RUNNER_LIFT - air_apex - 104
        bt = clamp((finish_t - 0.40) / 0.60, 0, 1)
        if bt < 0.32:
            k = bt / 0.32
            rr = 14 + 86 * k
            aa = int(200 * (1 - k))
            dr.ellipse([bx - rr, by - rr * 0.8, bx + rr, by + rr * 0.8],
                       outline=(OCEAN[0], OCEAN[1], OCEAN[2], aa), width=4)
        for i in range(130):
            # staggered ejection: every particle is born at its own moment
            # and flies its own speed, so the cloud fills space radially —
            # never a shell / ring / pinwheel.
            j1 = (((i + 1) * 2654435761) % 1000) / 1000.0
            j2 = (((i + 1) * 40503) % 997) / 997.0
            j3 = (((i + 1) * 69069) % 991) / 991.0
            delay = 0.30 * j3
            pt_t = clamp((bt - delay) / max(0.001, 1.0 - delay), 0, 1)
            if pt_t <= 0:
                continue
            ang = 2 * math.pi * ((i * 0.6180339887) % 1.0) + (j1 - 0.5) * 0.5
            spd = 34 + 118 * j2
            dist = spd * pt_t * (1.0 - 0.22 * pt_t)
            px = bx + math.cos(ang) * dist * 2.3
            py = by + math.sin(ang) * dist * 1.65 - 52 * pt_t + 96 * pt_t * pt_t
            r = (1.6 + 3.0 * j2) * (1 - 0.7 * pt_t) + 0.5
            col = OCEAN if i % 3 else SKY
            fade = (1 - pt_t) * (1 - bt * 0.35)
            aa = min(255, int(240 * fade + 15))
            tail = max(0.0, pt_t - 0.14)
            tdist = spd * tail * (1.0 - 0.22 * tail)
            ppx = bx + math.cos(ang) * tdist * 2.3
            ppy = by + math.sin(ang) * tdist * 1.65 - 52 * tail + 96 * tail * tail
            dr.line([(ppx, ppy), (px, py)],
                    fill=(col[0], col[1], col[2], int(aa * 0.5)),
                    width=max(2, int(r)))
            dr.ellipse([px - r, py - r, px + r, py + r],
                       fill=(col[0], col[1], col[2], aa))
            if i % 5 == 0 and pt_t < 0.25:
                cr = max(0.5, r * 0.4)
                dr.ellipse([px - cr, py - cr, px + cr, py + cr],
                           fill=(255, 255, 255, int(220 * (1 - pt_t * 4))))

    glow = img.filter(ImageFilter.GaussianBlur(6))
    return Image.alpha_composite(glow, img)

def main():
    os.makedirs('/tmp/pfr', exist_ok=True)
    frames = [render(f) for f in range(TOTAL)]
    frames[0].save('/tmp/pfr/page_flip_runner.gif', save_all=True,
                   append_images=frames[1:], duration=int(1000 / FPS), loop=0,
                   optimize=True)
    for f in (8, 40, 78, 95, RAMP + 8, RAMP + 20, RAMP + 27, TOTAL - 2):
        render(f).save(f'/tmp/pfr/still_{f:03d}.png')
    print('frames:', len(frames))

main()
