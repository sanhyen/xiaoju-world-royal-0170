"""Measure screenshot hue angles and CIE76 color difference; never edits source images."""
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion

ROOT = Path('D:/xiaojuWorld/renewal/work')
OFF = ROOT / 'testprofile/Godot/app_userdata/小鞠世界 · 海风与星光'
ON = ROOT / 'session_20261105/T2_on_profile/Godot/app_userdata/小鞠世界 · 海风与星光'


def lab(rgb):
    rgb = np.asarray(rgb, dtype=float)
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    xyz = linear @ np.array([[.4124564, .3575761, .1804375],
                             [.2126729, .7151522, .0721750],
                             [.0193339, .1191920, .9503041]]).T
    xyz /= [.95047, 1, 1.08883]
    f = np.where(xyz > (6 / 29) ** 3, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])], axis=-1)


def read(name, suffix, root):
    return np.asarray(Image.open(root / f'T2_{name}_{suffix}.png').convert('RGB'), float) / 255


def sampled_metrics(name, predicate, pixel_predicate):
    a, b = read(name, 'off', OFF), read(name, 'on', ON)
    records = json.loads((OFF / f'T2_{name}_off.json').read_text('utf-8'))
    eligible = []
    for record in records:
        if not record['collider'].startswith('Terrain') or not predicate(record):
            continue
        uv = record.get('uv', [record['pixel'][0] / 1920, record['pixel'][1] / 1080])
        x, y = int(uv[0] * a.shape[1]), int(uv[1] * a.shape[0])
        if pixel_predicate(a[y, x]):
            eligible.append((x, y, record))
    if len(eligible) < 20:
        raise RuntimeError(f'{name}: only {len(eligible)} eligible samples')
    selected = [eligible[i] for i in np.linspace(0, len(eligible) - 1, 20, dtype=int)]
    result = []
    for x, y, record in selected:
        delta = float(np.linalg.norm(lab(a[y, x]) - lab(b[y, x])))
        result.append({'pixel': [x, y], 'world': record['position'], 'deltaE76': delta})
    return {'eligible': len(eligible), 'samples': result, 'max_deltaE76': max(r['deltaE76'] for r in result)}


mask_rgb = np.asarray(Image.open(ON / 'T2_slope_mask.png').convert('RGB'), float) / 255
mask = ((mask_rgb[..., 0] > .5) & (mask_rgb[..., 2] > .5) & (mask_rgb[..., 1] < .45)
        & (mask_rgb[..., 0] > mask_rgb[..., 1] * 1.5) & (mask_rgb[..., 2] > mask_rgb[..., 1] * 1.5))
mask = binary_erosion(mask, iterations=3)
positions = np.argwhere(mask)
if len(positions) < 20:
    raise RuntimeError(f'Only {len(positions)} visible natural steep-slope mask pixels')
a, b = read('slope', 'off', OFF), read('slope', 'on', ON)
slope_samples = []
for index in np.linspace(0, len(positions) - 1, 20, dtype=int):
    y, x = positions[index]
    la, lb = lab(a[y, x]), lab(b[y, x])
    ha, hb = np.degrees(np.arctan2(la[2], la[1])), np.degrees(np.arctan2(lb[2], lb[1]))
    delta = float(abs((hb - ha + 180) % 360 - 180))
    slope_samples.append({'pixel': [int(x), int(y)], 'hue_angle_delta_degrees': delta})
report = {
    'method': 'CIE Lab D65, CIE76 deltaE; shader-rasterized visible >35 degree natural-face mask; 20 spatially distributed samples per class',
    'steep_slope': {'mask_pixels': len(positions), 'samples': slope_samples,
                    'min_hue_delta': min(r['hue_angle_delta_degrees'] for r in slope_samples)},
    'beach': sampled_metrics('beach', lambda r: 0 < r['position'][1] < 4 and r['normal_y'] > .98 and r['color'][0] - r['color'][2] > .06,
                            lambda c: c[0] > c[2] + .05 and c[1] > c[2] + .04),
    'flat': sampled_metrics('flat', lambda r: r['position'][1] > 0 and r['normal_y'] > .9962,
                           lambda c: abs(c[0]-c[1]) < .12 and c[0] > c[2] + .02),
}
report['pass'] = (report['steep_slope']['min_hue_delta'] > 20 and report['beach']['max_deltaE76'] < 3
                  and report['flat']['max_deltaE76'] < 3)
output = ROOT / 'session_20261105/T2_color_audit.json'
output.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
print(json.dumps({k: v for k, v in report.items() if k == 'pass'}, ensure_ascii=False))
print('slope min hue delta:', report['steep_slope']['min_hue_delta'],
      'beach max deltaE:', report['beach']['max_deltaE76'], 'flat max deltaE:', report['flat']['max_deltaE76'])
if not report['pass']:
    raise SystemExit(1)
