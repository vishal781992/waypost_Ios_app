#!/usr/bin/env python3
"""Writes the artboards for the live-stamping canvas.

Everything here is transcribed from the shipped app: the ground is PageTint's
#EFF2F0, the stamp face is StampFace's radial gradient inside StampShape's
26-spike scallop, the rule headings are PassportBook.heading, and the type ramp
is WP (headingUI = system semibold at 0.86x, display = Cormorant Garamond).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
STAR = open(os.path.join(HERE, "star.txt")).read()

BG = "#EFF2F0"
INK = "#201F1D"
ACC = "#B68235"
ACC700 = "#7D5411"
ACC800 = "#5A3B0A"
LIME = "#DBE64C"
PLATE = "#2A2829"
N600 = "#7D7979"
N400 = "#BAB6B6"
DIV = "rgba(32,31,29,0.16)"

HEAD = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@600;700&display=swap">
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
           color: #201F1D; -webkit-font-smoothing: antialiased; }
    a { color: #7D5411; } a:hover { color: #5A3B0A; }
    .dsp { font-family: "Cormorant Garamond", Georgia, "Times New Roman", serif; font-weight: 600; }
    .kick { font-size: 11px; letter-spacing: 1.3px; text-transform: uppercase; color: #7D5411; }
    .ital { font-style: italic; }
    .stamp { clip-path: __STAR__;
             background: radial-gradient(circle at 32% 24%, #FCFAF3 0%, #FFF3E4 46%, #E4BE7C 100%); }
    .ring { position: absolute; inset: 12%; border-radius: 50%; border: 1px solid rgba(160,111,36,0.65); }
  </style>
</helmet>
""".replace("__STAR__", STAR)

FOOT = """</x-dc>
</body>
</html>
"""


def stamp(name, caption, size=76, rot=-2, shadow=True):
    sh = "filter: drop-shadow(0 5px 5px rgba(60,38,10,0.26));" if shadow else ""
    return f"""<div style="position: relative; width: {size}px; height: {size}px; flex: none; transform: rotate({rot}deg); {sh}">
  <div class="stamp" style="position: absolute; inset: 0;"></div>
  <div class="ring"></div>
  <div style="position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; padding: {size*0.16:.0f}px; text-align: center; color: {ACC800};">
    <div style="font-size: {size*0.135:.1f}px; font-weight: 600; line-height: 1.12;">{name}</div>
    <div style="font-size: {size*0.077:.1f}px; letter-spacing: 1px; text-transform: uppercase; opacity: 0.7;">{caption}</div>
  </div>
</div>"""


def dashed(name, size=76, glow=False):
    edge = f"2px solid {ACC}" if glow else f"1.5px dashed {N400}"
    halo = f"box-shadow: 0 0 0 5px rgba(182,130,53,0.14);" if glow else ""
    cap = "ready" if glow else "unstamped"
    capcol = ACC700 if glow else "inherit"
    return f"""<div style="position: relative; width: {size}px; height: {size}px; flex: none;">
  <div style="position: absolute; inset: 0; border-radius: 50%; border: {edge}; {halo}"></div>
  <div style="position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; padding: {size*0.12:.0f}px; text-align: center; color: {N600};">
    <div style="font-size: {size*0.138:.1f}px; font-weight: 600; line-height: 1.12; opacity: 0.85;">{name}</div>
    <div style="font-size: {size*0.086:.1f}px; letter-spacing: 0.9px; text-transform: uppercase; opacity: 0.75; color: {capcol};">{cap}</div>
  </div>
</div>"""


def rule(title):
    return f"""<div style="display: flex; align-items: center; gap: 8px; padding-top: 18px; padding-bottom: 10px;">
  <div class="kick">{title}</div>
  <div style="flex-grow: 1; height: 1px; background: {DIV};"></div>
</div>"""


def livedot(color="#3FA46A", size=6):
    return f'<div style="width: {size}px; height: {size}px; border-radius: 50%; background: {color}; flex: none; box-shadow: 0 0 0 3px rgba(63,164,106,0.18);"></div>'


PIN = """<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>"""

TABBAR = f"""<div style="position: absolute; left: 0; right: 0; bottom: 0; display: flex; justify-content: center; padding-bottom: 22px; padding-top: 8px;">
  <div style="display: flex; align-items: center; gap: 4px; padding: 7px; border-radius: 999px; background: rgba(255,255,255,0.92); box-shadow: 0 8px 24px rgba(32,31,29,0.14), 0 0 0 0.5px rgba(32,31,29,0.06);">
    <div style="display: flex; flex-direction: column; align-items: center; gap: 2px; width: 74px; padding: 7px 0;">
      <svg width="21" height="21" viewBox="0 0 24 24" fill="currentColor" style="color: {INK};"><path d="M21 3 3 10.5l7.3 2.9L13.2 21 21 3Z"/></svg>
      <div style="font-size: 10.5px; font-weight: 500;">Nearby</div>
    </div>
    <div style="display: flex; flex-direction: column; align-items: center; gap: 2px; width: 74px; padding: 7px 0;">
      <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" style="color: {INK};"><rect x="2.5" y="7" width="19" height="13" rx="2.5"/><path d="M9 7V5.2A1.7 1.7 0 0 1 10.7 3.5h2.6A1.7 1.7 0 0 1 15 5.2V7"/></svg>
      <div style="font-size: 10.5px; font-weight: 500;">Trips</div>
    </div>
    <div style="display: flex; flex-direction: column; align-items: center; gap: 2px; width: 74px; padding: 7px 0; border-radius: 999px; background: {LIME};">
      <svg width="21" height="21" viewBox="0 0 24 24" fill="currentColor" style="color: {INK};"><path d="M6 3h12a1 1 0 0 1 1 1v17l-7-4.4L5 21V4a1 1 0 0 1 1-1Z"/></svg>
      <div style="font-size: 10.5px; font-weight: 600;">Saved</div>
    </div>
    <div style="display: flex; flex-direction: column; align-items: center; gap: 2px; width: 74px; padding: 7px 0;">
      <div style="font-size: 20px; line-height: 21px;">&#127965;</div>
      <div style="font-size: 10.5px; font-weight: 500;">Profile</div>
    </div>
  </div>
</div>"""


def header(kicker, title, tall=False):
    return f"""<div style="padding: 52px 20px 14px 20px; background: rgba(243,242,242,0.72); border-bottom: 1px solid rgba(32,31,29,0.10);">
  <div class="kick" style="padding-bottom: 4px;">{kicker}</div>
  <div class="dsp" style="font-size: 44px; line-height: 1.02; letter-spacing: -0.5px;">{title}</div>
  <div style="display: flex; gap: 0; margin-top: 16px; padding: 3px; border-radius: 999px; background: rgba(32,31,29,0.07);">
    <div style="flex-grow: 1; text-align: center; padding: 9px 0; font-size: 15px; color: rgba(32,31,29,0.62);">Parks</div>
    <div style="flex-grow: 1; text-align: center; padding: 9px 0; font-size: 15px; font-weight: 600; border-radius: 999px; background: {LIME}; box-shadow: 0 1px 3px rgba(32,31,29,0.16);">Passport</div>
  </div>
</div>"""


# --------------------------------------------------------------------------
# Main — the Passport page, driven by where the phone is.
# --------------------------------------------------------------------------

reach_card = f"""<div style="border-radius: 20px; background: {PLATE}; color: #F3F2F2; padding: 16px 16px 14px 16px;">
  <div style="display: flex; align-items: center; gap: 7px; padding-bottom: 12px;">
    {livedot()}
    <div style="font-size: 11px; letter-spacing: 1.3px; text-transform: uppercase; color: {LIME};">You are here</div>
  </div>
  <div style="display: flex; align-items: center; gap: 14px;">
    {dashed("Hovenweep", 74, glow=True)}
    <div style="display: flex; flex-direction: column; gap: 3px;">
      <div style="font-size: 17px; font-weight: 600; line-height: 1.15;">Hovenweep</div>
      <div style="font-size: 12.5px; opacity: 0.72;">National Monument &middot; Utah</div>
      <div style="display: flex; align-items: center; gap: 4px; font-size: 12px; opacity: 0.6; padding-top: 2px;">{PIN}<span>Inside the boundary &middot; 0.4 mi in</span></div>
    </div>
  </div>
  <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-top: 15px; min-height: 46px; border-radius: 999px; background: {LIME}; color: {INK}; font-size: 16px; font-weight: 600;">
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"><path d="M12 3v10"/><path d="m8 9 4 4 4-4"/><path d="M4 17h16v3H4z"/></svg>
    Stamp it
  </div>
  <div class="ital" style="font-size: 11.5px; line-height: 1.5; opacity: 0.55; padding-top: 10px; text-align: center;">Or leave it. Stay fifteen minutes and it stamps itself.</div>
</div>"""


def nearby_row(name, desig, dist, note=None):
    return f"""<div style="display: flex; align-items: center; gap: 12px; padding: 11px 13px; border-radius: 16px; background: rgba(255,255,255,0.66); box-shadow: inset 0 0 0 0.5px rgba(32,31,29,0.08);">
  {dashed(name.split()[0], 40)}
  <div style="display: flex; flex-direction: column; gap: 2px; flex-grow: 1;">
    <div style="font-size: 14.5px; font-weight: 600;">{name}</div>
    <div style="font-size: 11.5px; color: {N600};">{desig}</div>
  </div>
  <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 2px;">
    <div style="font-size: 13px; font-weight: 600; font-variant-numeric: tabular-nums;">{dist}</div>
    <div class="ital" style="font-size: 10.5px; color: {N600};">{note or "&nbsp;"}</div>
  </div>
</div>"""


MAIN = HEAD + f"""<div style="position: relative; width: 390px; min-height: 1240px; background: {BG}; overflow: hidden;">
  {header("2 stamps collected", "Saved")}

  <div style="padding: 16px 20px 150px 20px; display: flex; flex-direction: column;">
    {reach_card}

    {rule("Nearby, not yet in reach")}
    <div class="ital" style="font-size: 11.5px; color: rgba(32,31,29,0.55); line-height: 1.5; padding-bottom: 11px;">Sorted by how far you are from each one&rsquo;s edge, not its middle.</div>
    <div style="display: flex; flex-direction: column; gap: 8px;">
      {nearby_row("Canyonlands", "National Park &middot; Moab, UT", "14 mi", "31 min")}
      {nearby_row("Natural Bridges", "National Monument &middot; UT", "38 mi", "52 min")}
      {nearby_row("Goosenecks", "State Park &middot; Mexican Hat, UT", "46 mi", "1 h 04")}
    </div>

    {rule("Collected")}
    <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 11px;">
      <div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">
        {stamp("Mesa Verde", "stamped", 96, -2)}
        <div class="ital" style="font-size: 10.5px; color: rgba(32,31,29,0.6);">4 June</div>
      </div>
      <div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">
        {stamp("Arches", "stamped", 96, 1)}
        <div class="ital" style="font-size: 10.5px; color: rgba(32,31,29,0.6);">2 June</div>
      </div>
      <div></div>
    </div>

    {rule("On this trip")}
    <div class="ital" style="font-size: 11.5px; color: rgba(32,31,29,0.55); line-height: 1.5; padding-bottom: 11px;">The twelve stops along your Utah loop. They fill as you pass them.</div>
    <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 11px;">
      {dashed("Canyonlands", 96)}
      {dashed("Dinosaur", 96)}
      {dashed("Cedar Breaks", 96)}
      {dashed("Bryce Canyon", 96)}
      {dashed("Pipe Spring", 96)}
      {dashed("Capitol Reef", 96)}
    </div>

    <div class="ital" style="font-size: 11.5px; color: rgba(32,31,29,0.5); line-height: 1.55; padding-top: 18px;">The paper book still wants a rubber stamp at the visitor centre. This one just remembers where you stood.</div>
  </div>

  {TABBAR}
</div>
""" + FOOT


# --------------------------------------------------------------------------
# Reach — the four states of the band at the top.
# --------------------------------------------------------------------------

def state_label(n, title, sub):
    return f"""<div style="display: flex; align-items: baseline; gap: 9px; padding-bottom: 9px;">
  <div style="font-size: 11px; letter-spacing: 1.3px; text-transform: uppercase; color: {ACC700};">{n}</div>
  <div style="font-size: 14px; font-weight: 600;">{title}</div>
  <div class="ital" style="font-size: 11.5px; color: {N600};">{sub}</div>
</div>"""


far_card = f"""<div style="border-radius: 20px; background: rgba(255,255,255,0.66); box-shadow: inset 0 0 0 0.5px rgba(32,31,29,0.08); padding: 14px 15px;">
  <div style="display: flex; align-items: center; gap: 13px;">
    {dashed("Hovenweep", 54)}
    <div style="display: flex; flex-direction: column; gap: 2px; flex-grow: 1;">
      <div style="font-size: 15px; font-weight: 600;">Hovenweep</div>
      <div style="font-size: 11.5px; color: {N600};">National Monument &middot; 6.2 mi away</div>
    </div>
    <div class="ital" style="font-size: 11.5px; color: {N600};">out of reach</div>
  </div>
</div>"""

dwell_card = f"""<div style="border-radius: 20px; background: {PLATE}; color: #F3F2F2; padding: 16px;">
  <div style="display: flex; align-items: center; gap: 14px;">
    <div style="position: relative; width: 74px; height: 74px; flex: none;">
      <svg width="74" height="74" viewBox="0 0 74 74" style="position: absolute; inset: 0; transform: rotate(-90deg);">
        <circle cx="37" cy="37" r="35" fill="none" stroke="rgba(243,242,242,0.16)" stroke-width="2.5"/>
        <circle cx="37" cy="37" r="35" fill="none" stroke="{LIME}" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="220" stroke-dashoffset="79"/>
      </svg>
      <div style="position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1px;">
        <div style="font-size: 20px; font-weight: 600; font-variant-numeric: tabular-nums;">4:12</div>
        <div style="font-size: 8px; letter-spacing: 1px; text-transform: uppercase; opacity: 0.6;">left</div>
      </div>
    </div>
    <div style="display: flex; flex-direction: column; gap: 3px;">
      <div style="font-size: 16px; font-weight: 600;">Hovenweep</div>
      <div style="font-size: 12.5px; opacity: 0.72;">Stamps itself when the clock runs out.</div>
      <div style="display: flex; align-items: center; gap: 4px; font-size: 12px; opacity: 0.6; padding-top: 2px;">{PIN}<span>Been inside 10 min 48 s</span></div>
    </div>
  </div>
  <div style="display: flex; gap: 8px; margin-top: 14px;">
    <div style="flex-grow: 1; text-align: center; min-height: 44px; line-height: 44px; border-radius: 999px; background: {LIME}; color: {INK}; font-size: 15.5px; font-weight: 600;">Stamp it now</div>
    <div style="width: 118px; text-align: center; min-height: 44px; line-height: 44px; border-radius: 999px; box-shadow: inset 0 0 0 1px rgba(243,242,242,0.28); font-size: 15.5px;">Not now</div>
  </div>
</div>"""

done_card = f"""<div style="border-radius: 20px; background: rgba(255,255,255,0.66); box-shadow: inset 0 0 0 0.5px rgba(32,31,29,0.08); padding: 15px;">
  <div style="display: flex; align-items: center; gap: 14px;">
    {stamp("Hovenweep", "stamped", 74, -2)}
    <div style="display: flex; flex-direction: column; gap: 3px;">
      <div style="font-size: 16px; font-weight: 600;">Collected</div>
      <div style="font-size: 12.5px; color: {N600};">Today, 5:49 pm &middot; stamped where you stood</div>
      <div class="ital" style="font-size: 11.5px; color: {N600}; padding-top: 2px;">A stamp is a fact. Nothing takes it back.</div>
    </div>
  </div>
</div>"""

REACH = HEAD + f"""<div style="position: relative; width: 390px; min-height: 844px; background: {BG}; padding: 48px 20px 40px 20px; box-sizing: border-box;">
  <div class="kick" style="padding-bottom: 4px;">The band at the top</div>
  <div class="dsp" style="font-size: 38px; line-height: 1.04; letter-spacing: -0.4px;">Four states</div>
  <div class="ital" style="font-size: 12.5px; color: rgba(32,31,29,0.6); line-height: 1.55; padding: 8px 0 22px 0;">One card, one place on the page. It only appears when there is something to say.</div>

  <div style="display: flex; flex-direction: column; gap: 20px;">
    <div>{state_label("01", "Out of reach", "nothing near enough")}{far_card}</div>
    <div>{state_label("02", "In reach", "notified, waiting on you")}{reach_card}</div>
    <div>{state_label("03", "Dwelling", "the fifteen minutes are running")}{dwell_card}</div>
    <div>{state_label("04", "Collected", "irreversible")}{done_card}</div>
  </div>
</div>
""" + FOOT


# --------------------------------------------------------------------------
# Notify — what arrives on the lock screen.
# --------------------------------------------------------------------------

def notif(title, body, when):
    return f"""<div style="border-radius: 20px; background: rgba(255,255,255,0.82); box-shadow: 0 8px 22px rgba(0,0,0,0.22); padding: 13px 15px; backdrop-filter: blur(20px);">
  <div style="display: flex; align-items: center; gap: 8px; padding-bottom: 6px;">
    <div style="width: 17px; height: 17px; border-radius: 4px; background: {ACC800}; display: flex; align-items: center; justify-content: center; color: #FFF3E4; font-size: 10px; font-weight: 700;">P</div>
    <div style="font-size: 11.5px; letter-spacing: 0.3px; text-transform: uppercase; color: rgba(32,31,29,0.55); flex-grow: 1;">ParkHop</div>
    <div style="font-size: 11.5px; color: rgba(32,31,29,0.5);">{when}</div>
  </div>
  <div style="font-size: 14.5px; font-weight: 600; padding-bottom: 2px;">{title}</div>
  <div style="font-size: 14px; line-height: 1.35; color: rgba(32,31,29,0.78);">{body}</div>
</div>"""


NOTIFY = HEAD + f"""<div style="position: relative; width: 390px; min-height: 844px; background: linear-gradient(170deg, #3B4A44 0%, #1E2724 55%, #141917 100%); padding: 60px 18px 40px 18px; box-sizing: border-box;">
  <div style="font-size: 11px; letter-spacing: 1.3px; text-transform: uppercase; color: rgba(219,230,76,0.8); padding-bottom: 4px;">What arrives</div>
  <div class="dsp" style="font-size: 38px; line-height: 1.04; color: #F3F2F2; letter-spacing: -0.4px;">Two notices</div>
  <div class="ital" style="font-size: 12.5px; color: rgba(243,242,242,0.6); line-height: 1.55; padding: 8px 0 26px 0;">One when you arrive. One only if the fifteen minutes ran out without you.</div>

  <div style="display: flex; flex-direction: column; gap: 12px;">
    {notif("You&rsquo;re at Hovenweep", "Stamp the page while you&rsquo;re here. Or don&rsquo;t &mdash; it stamps itself in 15 minutes.", "now")}
    <div style="display: flex; gap: 8px; padding-left: 4px;">
      <div style="padding: 8px 15px; border-radius: 999px; background: {LIME}; color: {INK}; font-size: 13.5px; font-weight: 600;">Stamp it</div>
      <div style="padding: 8px 15px; border-radius: 999px; background: rgba(243,242,242,0.16); color: #F3F2F2; font-size: 13.5px;">Not this one</div>
    </div>
  </div>

  <div style="display: flex; align-items: center; gap: 10px; padding: 30px 4px 16px 4px;">
    <div style="height: 1px; flex-grow: 1; background: rgba(243,242,242,0.16);"></div>
    <div style="font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: rgba(243,242,242,0.5);">fifteen minutes later</div>
    <div style="height: 1px; flex-grow: 1; background: rgba(243,242,242,0.16);"></div>
  </div>

  {notif("Hovenweep is in the book", "You stayed, so it stamped itself. Collected today at 5:49 pm.", "5:49 pm")}

  <div style="margin-top: 30px; border-radius: 18px; padding: 15px 16px; background: rgba(243,242,242,0.07); box-shadow: inset 0 0 0 0.5px rgba(243,242,242,0.14);">
    <div style="font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: rgba(219,230,76,0.82); padding-bottom: 7px;">Honest about the second one</div>
    <div style="font-size: 13px; line-height: 1.6; color: rgba(243,242,242,0.8);">iOS will not run a fifteen-minute timer for an app nobody is looking at. The stamp lands the moment the phone next tells us anything &mdash; leaving the boundary, opening the app, a background wake. It is dated to the visit, never to the noticing, so it is right even when it is late.</div>
  </div>

  <div style="margin-top: 12px; border-radius: 18px; padding: 15px 16px; background: rgba(243,242,242,0.07); box-shadow: inset 0 0 0 0.5px rgba(243,242,242,0.14);">
    <div style="font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: rgba(219,230,76,0.82); padding-bottom: 7px;">What it costs</div>
    <div style="font-size: 13px; line-height: 1.6; color: rgba(243,242,242,0.8);">Arriving-notices need <strong style="font-weight: 600;">Always</strong> location and notification permission. With <strong style="font-weight: 600;">While Using</strong> only, everything still works &mdash; it just waits until the app is open. Asked for at the first stamp, never at launch.</div>
  </div>
</div>
""" + FOOT


# --------------------------------------------------------------------------
# Rules — how the match is decided.
# --------------------------------------------------------------------------

def block(kicker, title, body, extra=""):
    return f"""<div style="border-radius: 20px; background: rgba(255,255,255,0.7); box-shadow: inset 0 0 0 0.5px rgba(32,31,29,0.09); padding: 20px 21px;">
  <div class="kick" style="padding-bottom: 6px;">{kicker}</div>
  <div style="font-size: 19px; font-weight: 600; line-height: 1.2; padding-bottom: 9px;">{title}</div>
  <div style="font-size: 13.5px; line-height: 1.62; color: rgba(32,31,29,0.78);">{body}</div>
  {extra}
</div>"""


BLOB = "M 40 92 C 18 74 14 40 38 24 C 62 8 106 6 138 18 C 176 32 198 58 190 84 C 182 112 150 128 112 126 C 78 124 58 110 40 92 Z"

wrong = f"""<div style="display: flex; flex-direction: column; gap: 7px;">
  <svg width="230" height="140" viewBox="0 0 230 140">
    <path d="{BLOB}" fill="rgba(11,43,38,0.09)" stroke="rgba(11,43,38,0.34)" stroke-width="1.4"/>
    <circle cx="106" cy="70" r="17" fill="none" stroke="{ACC}" stroke-width="1.6" stroke-dasharray="4 3"/>
    <circle cx="106" cy="70" r="2.6" fill="{ACC800}"/>
    <circle cx="56" cy="98" r="4.6" fill="#C0392B"/>
    <text x="66" y="102" font-size="10.5" fill="#C0392B" font-family="system-ui">you, inside the park</text>
    <text x="92" y="47" font-size="9.5" fill="{ACC800}" font-family="system-ui">1 mi</text>
  </svg>
  <div style="font-size: 12.5px; color: #C0392B; font-weight: 600;">Never offered. You are 24 miles from a pin in the middle.</div>
</div>"""

right = f"""<div style="display: flex; flex-direction: column; gap: 7px;">
  <svg width="230" height="140" viewBox="0 0 230 140">
    <circle cx="106" cy="70" r="66" fill="rgba(182,130,53,0.10)" stroke="{ACC}" stroke-width="1.6" stroke-dasharray="4 3"/>
    <path d="{BLOB}" fill="rgba(11,43,38,0.09)" stroke="rgba(11,43,38,0.34)" stroke-width="1.4"/>
    <circle cx="106" cy="70" r="2.6" fill="{ACC800}"/>
    <circle cx="56" cy="98" r="4.6" fill="#2F7D4F"/>
    <text x="66" y="102" font-size="10.5" fill="#2F7D4F" font-family="system-ui">you, inside the park</text>
    <text x="120" y="18" font-size="9.5" fill="{ACC800}" font-family="system-ui">&radic;(area/&pi;) + 1 mi</text>
  </svg>
  <div style="font-size: 12.5px; color: #2F7D4F; font-weight: 600;">Offered. The circle is the size of the park, plus your mile.</div>
</div>"""

examples = f"""<div style="display: flex; flex-direction: column; gap: 0; margin-top: 14px; border-top: 1px solid {DIV};">
  <div style="display: flex; padding: 9px 0 5px 0; font-size: 10.5px; letter-spacing: 1.1px; text-transform: uppercase; color: {N600};">
    <div style="flex-grow: 1;">Unit</div><div style="width: 92px; text-align: right;">Area</div><div style="width: 74px; text-align: right;">Reach</div>
  </div>
  {"".join(f'''<div style="display: flex; padding: 6px 0; font-size: 13px; border-top: 1px solid rgba(32,31,29,0.07);">
    <div style="flex-grow: 1;">{n}</div><div style="width: 92px; text-align: right; color: {N600}; font-variant-numeric: tabular-nums;">{a}</div><div style="width: 74px; text-align: right; font-weight: 600; font-variant-numeric: tabular-nums;">{r}</div></div>'''
   for n, a, r in [("Hovenweep NM", "785 acres", "3.0 mi"),
                   ("Arches NP", "76,679 acres", "7.2 mi"),
                   ("Goosenecks SP", "10 acres", "3.0 mi"),
                   ("Yellowstone NP", "2,219,791 acres", "34.4 mi")])}
</div>"""

timeline = f"""<div style="margin-top: 16px;">
  <svg width="100%" height="86" viewBox="0 0 520 86" preserveAspectRatio="none">
    <line x1="16" y1="30" x2="504" y2="30" stroke="rgba(32,31,29,0.18)" stroke-width="1.5"/>
    <line x1="16" y1="30" x2="330" y2="30" stroke="{ACC}" stroke-width="3"/>
    <circle cx="16" cy="30" r="6" fill="{ACC800}"/>
    <circle cx="120" cy="30" r="6" fill="{ACC800}"/>
    <circle cx="330" cy="30" r="7" fill="#2F7D4F"/>
    <text x="8" y="55" font-size="11.5" fill="#201F1D" font-family="system-ui" font-weight="600">cross the edge</text>
    <text x="8" y="70" font-size="10.5" fill="#7D7979" font-family="system-ui">geofence wakes the app</text>
    <text x="112" y="55" font-size="11.5" fill="#201F1D" font-family="system-ui" font-weight="600">notice</text>
    <text x="112" y="70" font-size="10.5" fill="#7D7979" font-family="system-ui">tap to stamp, any time from here</text>
    <text x="322" y="55" font-size="11.5" fill="#201F1D" font-family="system-ui" font-weight="600">+15 min &mdash; it stamps</text>
    <text x="322" y="70" font-size="10.5" fill="#7D7979" font-family="system-ui">only if you never left</text>
  </svg>
</div>"""

UNDO_BODY = ("Nothing in the app takes a stamp back, so the two thresholds are deliberately "
             "different. <strong style='font-weight: 600;'>Offering</strong> is loose: if you might be "
             "there, it says so, and one tap is yours to make. <strong style='font-weight: 600;'>Stamping "
             "for you</strong> is tight: inside the reach, fifteen unbroken minutes, and a fix good to a "
             "hundred metres or better. Anything less waits for your thumb.")

UNDO_EXTRA = f'''<div style="display: flex; gap: 10px; margin-top: 15px;">
             <div style="flex-grow: 1; border-radius: 14px; padding: 12px 14px; background: rgba(182,130,53,0.12);">
               <div style="font-size: 11px; letter-spacing: 1.1px; text-transform: uppercase; color: {ACC700}; padding-bottom: 4px;">Offered</div>
               <div style="font-size: 12.5px; line-height: 1.5;">inside the reach &middot; any fix</div>
             </div>
             <div style="flex-grow: 1; border-radius: 14px; padding: 12px 14px; background: rgba(47,125,79,0.12);">
               <div style="font-size: 11px; letter-spacing: 1.1px; text-transform: uppercase; color: #2F7D4F; padding-bottom: 4px;">Stamped for you</div>
               <div style="font-size: 12.5px; line-height: 1.5;">inside &middot; 15 min unbroken &middot; fix &le; 100 m</div>
             </div>
           </div>'''

B_PROBLEM = block("The problem", "A mile from the middle of Yellowstone is still Yellowstone",
    "Yellowstone is sixty miles across. You can spend four days inside it and never come within "
    "thirty miles of the pin. Hovenweep is half a square mile &mdash; there, a mile is generous and "
    "right. One number cannot serve both.",
    f'<div style="display: flex; gap: 16px; margin-top: 14px;">{wrong}{right}</div>')

B_RULE = block("The rule", "The reach is the park&rsquo;s own size, plus your mile",
    "Treat the park as a circle of the same area, and add a mile of grace on top &mdash; your number, "
    "kept as the thing it is good at: forgiving a GPS fix, a car park outside the gate, a boundary the "
    "data draws roughly. Never less than three miles all in, so the smallest monuments and a bad fix "
    "are both covered.", examples)

B_DWELL = block("The dwell", "Fifteen minutes inside, and only then",
    "The notice comes the moment you cross. The automatic stamp waits out the fifteen minutes and "
    "checks you are still there &mdash; a drive-through on the highway that clips the circle leaves and "
    "never stamps. Leaving stops the clock; coming back starts it again.", timeline)

B_UNDO = block("Because it cannot be undone", "Generous with the offer, strict with the automatic",
               UNDO_BODY, UNDO_EXTRA)

RULES = HEAD + f"""<div style="width: 1040px; min-height: 900px; background: {BG}; padding: 40px 40px 44px 40px; box-sizing: border-box;">
  <div class="kick" style="padding-bottom: 5px;">How a stamp is decided</div>
  <div class="dsp" style="font-size: 46px; line-height: 1.02; letter-spacing: -0.6px;">Standing in a park is not standing on its pin</div>
  <div class="ital" style="font-size: 14px; color: rgba(32,31,29,0.6); line-height: 1.55; padding: 10px 0 26px 0; max-width: 680px;">Every coordinate the app holds &mdash; the sixty-two national parks, the three thousand state parks, the park service&rsquo;s own units &mdash; is one point in the middle. A flat mile around that point is wrong at both ends of the scale.</div>

  <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px;">
    {B_PROBLEM}

    {B_RULE}

    {B_DWELL}

    {B_UNDO}
  </div>

  <div style="margin-top: 18px; border-radius: 20px; background: {PLATE}; color: rgba(243,242,242,0.86); padding: 20px 22px;">
    <div style="font-size: 11px; letter-spacing: 1.3px; text-transform: uppercase; color: {LIME}; padding-bottom: 8px;">What has to be built first</div>
    <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px; font-size: 13px; line-height: 1.6;">
      <div><strong style="font-weight: 600; color: #F3F2F2;">An area for each park.</strong> Nothing on the phone knows how big anything is. One column, added at build time from Wikidata, next to the coordinates already shipped.</div>
      <div><strong style="font-weight: 600; color: #F3F2F2;">A book that is not written down.</strong> The twelve stops are hard-coded in <span style="font-family: ui-monospace, monospace; font-size: 12px;">curated.json</span> with no coordinates at all. That list is why the page cannot move.</div>
      <div><strong style="font-weight: 600; color: #F3F2F2;">Watching instead of asking once.</strong> Location is fetched once per screen today. Stamping needs regions the system watches for us &mdash; twenty at a time, the nearest twenty.</div>
    </div>
  </div>
</div>
""" + FOOT


CANVAS = """{
  "artboards": [
    { "file": "Main.dc.html",   "x": 0,    "y": 0,    "w": 390,  "h": 1240 },
    { "file": "Reach.dc.html",  "x": 500,  "y": 0,    "w": 390,  "h": 844 },
    { "file": "Notify.dc.html", "x": 990,  "y": 0,    "w": 390,  "h": 844 },
    { "file": "Rules.dc.html",  "x": 0,    "y": 1400, "w": 1040, "h": 900 }
  ],
  "annotations": [
    { "id": "open-question", "x": 1490, "y": 0, "w": 300,
      "text": "One thing to decide.\\n\\nThe twelve-stop book at the foot of Main is the only part still hard-coded. Keep it as the trip's own book with a denominator to fill, or drop it and let the page be nothing but what is near you and what you have?\\n\\nDrawn here as kept." },
    { "id": "reach-note", "x": 1490, "y": 300, "w": 300,
      "text": "The band is one card in one place. It is absent entirely when nothing is within reach, so the page does not carry a permanent empty slot." },
    { "id": "rules-note", "x": 1100, "y": 1400, "w": 300,
      "text": "This board is the argument, not a screen. The four blocks are the decisions I need you to agree with before any of it is built." }
  ],
  "launch": { "view": "canvas" }
}
"""

for name, text in [("Main.dc.html", MAIN), ("Reach.dc.html", REACH),
                   ("Notify.dc.html", NOTIFY), ("Rules.dc.html", RULES),
                   ("canvas.json", CANVAS)]:
    open(os.path.join(HERE, name), "w").write(text)
    print(f"{name}: {len(text)} bytes")
