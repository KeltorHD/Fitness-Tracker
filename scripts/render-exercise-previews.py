#!/usr/bin/env python3
"""Render explicitly labelled SVG/PNG interface mockups; never Xcode screenshots.

Uses only bundled photos and system librsvg/cairo. No SwiftUI rendering or Liquid Glass
validation is implied. Run on Linux with librsvg-2 and cairo shared libraries installed.
"""
from pathlib import Path
import base64
import ctypes as c
import ctypes.util
import html
import json
import textwrap

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'docs/previews'
DATA = json.loads((ROOT / 'Sources/FitSessionCore/Resources/ExerciseLibrary.ru.json').read_text())
ENTRIES = {item['sourceID']: item for item in DATA['entries']}
INK, MUTED, GREEN, BG = '#142b29', '#74837f', '#009e78', '#f3f6f5'

def rect(x, y, w, h, color, radius=0, stroke=None):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{color}"' + (f' stroke="{stroke}"' if stroke else '') + '/>'

def text(x, y, value, size=15, color=INK, weight=400, anchor='start'):
    return f'<text x="{x}" y="{y}" font-family="DejaVu Sans,sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{html.escape(str(value))}</text>'

def wrap(x, y, value, chars=42, size=14, color=INK, limit=6, line=21, weight=400):
    lines = textwrap.wrap(value, chars, break_long_words=False)[:limit]
    return ''.join(text(x, y + i * line, word, size, color, weight) for i, word in enumerate(lines))

def photo(source_id, index, x, y, w, h):
    path = ROOT / 'Resources/ExerciseMedia' / ENTRIES[source_id]['images'][index]
    data = base64.b64encode(path.read_bytes()).decode()
    return rect(x, y, w, h, '#e6edeb', 12) + f'<image x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="xMidYMid meet" href="data:image/jpeg;base64,{data}"/>'

def shell():
    s = rect(0, 0, 390, 900, BG)
    s += rect(0, 0, 390, 28, '#fff0d1') + text(195, 19, 'МАКЕТ · НЕ СКРИНШОТ ИЗ XCODE', 10, '#795821', 700, 'middle')
    s += text(24, 57, '9:41', 14, INK, 700)
    s += rect(143, 37, 104, 27, '#101b19', 15)
    s += rect(333, 44, 29, 13, 'none', 4, INK) + rect(336, 47, 21, 7, INK, 1)
    s += text(312, 55, '▮▮▮', 10, INK, 700)
    s += rect(142, 857, 106, 5, '#152724', 3)
    s += text(195, 885, 'Превью на Linux · фото free-exercise-db / Unlicense', 8, MUTED, 400, 'middle')
    return s

def library():
    s = shell() + text(20, 94, '‹ Сегодня', 14, GREEN)
    s += text(20, 132, 'Упражнения', 30, INK, 700)
    s += rect(20, 151, 350, 42, '#e7ecea', 13) + text(35, 178, '⌕  Название, мышца или инвентарь', 13, MUTED)
    s += rect(20, 210, 168, 40, 'white', 14) + text(36, 236, 'Все мышцы  ⌄', 13, GREEN, 700)
    s += rect(200, 210, 170, 40, 'white', 14) + text(215, 236, 'Инвентарь  ⌄', 13, GREEN, 700)
    s += text(22, 273, '100 упражнений · Доступно без интернета', 10, MUTED)
    items = sorted(DATA['entries'], key=lambda item: item['name'].lower().replace('ё', 'е'))[:6]
    for i, entry in enumerate(items):
        y = 289 + i * 85
        s += rect(20, y, 350, 77, 'white', 16)
        s += photo(entry['sourceID'], 0, 28, y + 10, 78, 57)
        s += wrap(119, y + 26, entry['name'], chars=24, size=12, limit=2, line=17, weight=700)
        labels = {'arms': 'Руки', 'legs': 'Ноги', 'back': 'Спина', 'core': 'Пресс', 'chest': 'Грудь', 'shoulders': 'Плечи'}
        s += text(119, y + 63, labels[entry['group']], 10, MUTED) + text(350, y + 43, '›', 20, MUTED)
    s += text(29, 827, 'ⓘ  Источник данных и фотографии', 12, GREEN)
    return s

def detail():
    entry = ENTRIES['Barbell_Squat']
    s = shell() + text(20, 94, '‹ Упражнения', 14, GREEN)
    s += text(195, 128, entry['name'], 21, INK, 700, 'middle')
    s += photo('Barbell_Squat', 0, 20, 146, 350, 228)
    s += rect(20, 387, 37, 33, 'white', 16) + text(38, 410, '‹', 23, GREEN, 400, 'middle')
    s += text(195, 409, 'Положение 1 из 2', 12, MUTED, 400, 'middle')
    s += rect(333, 387, 37, 33, 'white', 16) + text(351, 410, '›', 23, GREEN, 400, 'middle')
    s += rect(20, 435, 168, 68, 'white', 17) + rect(200, 435, 170, 68, 'white', 17)
    s += text(35, 462, 'Штанга', 17, INK, 700) + text(35, 487, 'инвентарь', 11, MUTED)
    s += text(215, 462, 'Начальный', 17, INK, 700) + text(215, 487, 'уровень', 11, MUTED)
    s += text(20, 534, 'Работающие мышцы', 18, INK, 700)
    s += text(20, 558, ', '.join(entry['primaryMuscles']), 13)
    s += text(20, 593, 'Техника выполнения', 19, INK, 700)
    for i, step in enumerate(entry['steps']):
        y = 616 + i * 62
        s += rect(20, y, 25, 25, '#dcefe8', 13) + text(32, y + 17, i + 1, 12, GREEN, 700, 'middle')
        s += wrap(57, y + 12, step, chars=44, size=11, line=16, limit=3)
    s += rect(44, 808, 302, 42, GREEN, 21) + text(195, 835, '+  Добавить упражнение', 14, 'white', 700, 'middle')
    return s

def workout():
    s = shell() + text(20, 94, '⌄ Свернуть', 14, GREEN)
    s += text(195, 131, 'Всё тело · A', 23, INK, 700, 'middle')
    s += rect(20, 150, 350, 69, 'white', 20) + text(37, 178, 'АКТИВНОЕ ВРЕМЯ', 10, MUTED, 700)
    s += text(37, 205, '00:18:24', 24, INK, 700) + text(350, 194, '1 / 3', 18, GREEN, 700, 'end')
    s += rect(86, 235, 218, 44, '#e0eee9', 22, '#c7e2d7') + text(195, 263, 'Отдых     00:53', 17, GREEN, 700, 'middle')
    s += text(195, 302, 'Пропустить отдых', 12, GREEN, 400, 'middle')
    s += text(24, 338, 'ПРИСЕДАНИЯ', 12, MUTED, 700)
    s += rect(20, 351, 350, 45, 'white', 14) + text(35, 379, 'Техника выполнения', 14, GREEN) + text(347, 381, '›', 22, MUTED)
    for i in range(3):
        y = 408 + i * 80
        s += rect(20, y, 350, 70, 'white', 16)
        s += text(37, y + 28, '40', 22, INK, 700) + text(83, y + 28, 'кг', 12, MUTED)
        s += text(166, y + 28, '8', 22, INK, 700) + text(190, y + 28, 'повторов', 12, MUTED)
        s += text(337, y + 30, '✓' if i == 0 else '○', 26, GREEN, 700, 'middle')
        s += text(37, y + 54, 'Подход выполнен' if i == 0 else 'Разминочный подход', 11, MUTED)
        if i > 0: s += rect(316, y + 40, 30, 17, '#e3e9e6', 9)
    s += text(33, 676, '+ Добавить подход', 14, GREEN)
    s += rect(20, 695, 350, 43, 'white', 15) + text(35, 722, '+ Добавить упражнение', 14, GREEN)
    s += text(30, 767, 'Заметка о тренировке', 13, MUTED)
    s += rect(38, 807, 139, 42, '#e1eee9', 21, '#cbe0d6') + text(107, 834, 'Ⅱ  Пауза', 14, GREEN, 700, 'middle')
    s += rect(192, 807, 160, 42, GREEN, 21) + text(272, 834, '✓  Завершить', 14, 'white', 700, 'middle')
    return s

def svg(width, height, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>'

class Rectangle(c.Structure):
    _fields_ = [('x', c.c_double), ('y', c.c_double), ('width', c.c_double), ('height', c.c_double)]

def render(path, width, height, scale=2):
    rsvg = c.CDLL(ctypes.util.find_library('rsvg-2'))
    cairo = c.CDLL(ctypes.util.find_library('cairo'))
    objects = c.CDLL(ctypes.util.find_library('gobject-2.0'))
    rsvg.rsvg_handle_new_from_file.argtypes = [c.c_char_p, c.POINTER(c.c_void_p)]
    rsvg.rsvg_handle_new_from_file.restype = c.c_void_p
    rsvg.rsvg_handle_render_document.argtypes = [c.c_void_p, c.c_void_p, c.POINTER(Rectangle), c.POINTER(c.c_void_p)]
    rsvg.rsvg_handle_render_document.restype = c.c_int
    cairo.cairo_image_surface_create.argtypes = [c.c_int, c.c_int, c.c_int]
    cairo.cairo_image_surface_create.restype = c.c_void_p
    cairo.cairo_create.argtypes = [c.c_void_p]
    cairo.cairo_create.restype = c.c_void_p
    cairo.cairo_scale.argtypes = [c.c_void_p, c.c_double, c.c_double]
    cairo.cairo_surface_write_to_png.argtypes = [c.c_void_p, c.c_char_p]
    cairo.cairo_surface_write_to_png.restype = c.c_int
    cairo.cairo_destroy.argtypes = [c.c_void_p]
    cairo.cairo_surface_destroy.argtypes = [c.c_void_p]
    objects.g_object_unref.argtypes = [c.c_void_p]
    error = c.c_void_p()
    handle = rsvg.rsvg_handle_new_from_file(str(path).encode(), c.byref(error))
    assert handle, 'SVG loading failed'
    surface = cairo.cairo_image_surface_create(0, width * scale, height * scale)
    context = cairo.cairo_create(surface)
    cairo.cairo_scale(context, scale, scale)
    assert rsvg.rsvg_handle_render_document(handle, context, c.byref(Rectangle(0, 0, width, height)), c.byref(error)), 'SVG rendering failed'
    target = path.with_suffix('.png')
    assert cairo.cairo_surface_write_to_png(surface, str(target).encode()) == 0
    cairo.cairo_destroy(context)
    cairo.cairo_surface_destroy(surface)
    objects.g_object_unref(handle)
    print(target.relative_to(ROOT))

if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    screens = [('exercise-library', library()), ('exercise-detail', detail()), ('active-workout', workout())]
    for name, content in screens:
        file = OUT / (name + '.svg')
        file.write_text(svg(390, 900, content))
        render(file, 390, 900, scale=3)
    board = rect(0, 0, 1270, 1020, '#e5efeb')
    board += text(30, 38, 'FitSession · превью интерфейса', 25, INK, 700)
    board += text(30, 63, 'Макеты по текущим SwiftUI-экранам. Не запуск в Xcode; Liquid Glass требует проверки на Mac.', 12, MUTED)
    for i, (_, content) in enumerate(screens):
        board += f'<svg x="{30 + i * 410}" y="85" width="390" height="900" viewBox="0 0 390 900">{content}</svg>'
    file = OUT / 'overview.svg'
    file.write_text(svg(1270, 1020, board))
    render(file, 1270, 1020)
