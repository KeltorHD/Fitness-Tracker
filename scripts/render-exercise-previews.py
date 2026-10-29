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
INK, MUTED, ACCENT, BG = '#191919', '#8e8e93', '#ff4f33', '#ffffff'

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

def icon(kind, x, y, size=25, color=INK):
    common = f'fill="none" stroke="{color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"'
    if kind == 'book':
        drawing = '<path d="M12 4C9 2 5 2 2 3v17c3-1 7-1 10 1 3-2 7-2 10-1V3c-3-1-7-1-10 1Z"/><path d="M12 4v17"/>'
    elif kind == 'chart':
        drawing = '<path d="M3 3v18h19M8 16V9m5 7V5m5 11V8"/>'
    elif kind == 'gear':
        drawing = '<circle cx="12" cy="12" r="6.5"/><circle cx="12" cy="12" r="2.5"/>' + ''.join(f'<path d="M12 2v3" transform="rotate({a} 12 12)"/>' for a in range(0,360,45))
    elif kind == 'dumbbell':
        drawing = '<g transform="rotate(-42 12 12)"><path d="M7 12h10M3 8v8m4-11v14m10-14v14m4-11v8M3 8h4M3 16h4m10-8h4m-4 8h4"/></g>'
    elif kind == 'trophy':
        drawing = '<path d="M7 3h10v7a5 5 0 0 1-10 0V3ZM7 5H3v4a4 4 0 0 0 4 4m10-8h4v4a4 4 0 0 1-4 4M12 15v5m-4 1h8"/>'
    else:
        drawing = '<circle cx="12" cy="3.5" r="1.5"/><path d="M9 7h6l3 7M9 7l-3 7m5-7-1 7-3 8m6-15 1 7 3 8M3 15h18M3 12v6m3-5v4m12-4v4m3-5v6"/>'
    return f'<g transform="translate({x} {y}) scale({size/24})" {common}>{drawing}</g>'

def shell():
    s = rect(0, 0, 390, 900, BG)
    s += rect(0, 0, 390, 28, '#fff0e8') + text(195, 19, 'ДЕМО-МАКЕТ · НЕ СКРИНШОТ XCODE', 10, '#9b4b25', 700, 'middle')
    s += text(28, 63, '9:41', 14, INK, 700)
    s += text(307, 63, '▮▮▮', 10, INK, 700)
    s += rect(338, 51, 27, 13, 'none', 4, INK) + rect(341, 54, 19, 7, INK, 1)
    s += text(195, 897, 'Демонстрационные данные · проверка SwiftUI на Mac', 8, MUTED, 400, 'middle')
    return s

def toolbar(leading=None):
    s = ''
    if leading:
        w = 126 if len(leading) > 5 else 74
        s += rect(16, 83, w, 40, '#fcfcfc', 20, '#ededed') + text(16+w/2, 109, leading, 15, INK, 400, 'middle')
    s += rect(280, 83, 94, 40, '#fcfcfc', 20, '#ededed')
    s += text(303, 110, '•••', 13, INK, 700, 'middle') + text(351, 112, '+', 29, INK, 400, 'middle')
    return s

def tabbar(selected):
    labels = ['Дневник', 'Каталог', 'Результаты', 'Настройки']
    s = rect(15, 811, 360, 59, '#fdfdfd', 29, '#e8e8e8')
    s += rect(20+selected*89, 816, 85, 49, '#e8e8e8', 24)
    icons = ['book', 'dumbbell', 'chart', 'gear']
    for i, label in enumerate(labels):
        x = 61 + i*89
        s += icon(icons[i], x-13, 823, 26) + text(x, 861, label, 10, INK, 500, 'middle')
    s += rect(142, 879, 106, 5, '#171717', 3)
    return s

def diary():
    s = shell() + toolbar() + text(16, 164, 'Дневник', 34, INK, 700)
    for i, (letter, day) in enumerate(zip('ПВСЧПСВ', [26,27,28,29,30,31,1])):
        x = 36+i*53
        if day == 29: s += rect(x-22, 184, 44, 69, '#ffebe6', 24)
        s += text(x, 202, letter, 11, ACCENT if day == 29 else MUTED, 400, 'middle')
        s += f'<circle cx="{x}" cy="230" r="16" fill="{ACCENT if day == 27 else 'none'}" stroke="{'none' if day == 27 else '#e7e7e7'}" stroke-width="1.5"/>'
        s += text(x, 236, '✓' if day == 27 else day, 17, 'white' if day == 27 else MUTED, 400, 'middle')
    def group(y, heading, rows, achievements):
        v = text(16, y, heading, 23, INK, 700)
        v += rect(16, y+18, 78, 34, '#f2f2f2', 17) + icon('trophy',28,y+27,17) + text(68, y+41, f'{achievements} ЛР', 13, INK, 400, 'middle')
        v += rect(102, y+18, 122, 34, '#f2f2f2', 17) + text(163, y+41, '1 тренировка' if len(rows)==1 else '2 тренировки', 13, INK, 400, 'middle')
        for i, (day,name,summary) in enumerate(rows):
            r = y+80+i*113
            v += rect(30,r-8,3,94,'#f2f2f2') + f'<circle cx="31" cy="{r-8}" r="4" fill="#bdbdbd"/>'
            v += text(57,r,day,13,INK)
            v += icon('fitness',20,r+22,22,ACCENT)
            v += rect(55,r+13,319,77,'#f2f2f2',25)
            v += text(69,r+42,name,19,INK,700) + text(69,r+66,summary,12)
        return v
    s += group(295,'На этой неделе',[('Вторник','Грудь бицепс','1 ч 20 мин   6 240 кг · 9 подх.')],2)
    s += group(524,'19–25 октября',[('Четверг','Спина трицепс','1 ч 5 мин   5 180 кг · 8 подх.'),('Вторник','Грудь бицепс','1 ч 15 мин   5 760 кг · 9 подх.')],3)
    return s + tabbar(0)

def catalogue():
    s = shell() + toolbar('Упражнения') + text(16,164,'Тренировки',34,INK,700)
    for i,name in enumerate(['Грудь бицепс','Жим лёжа','Ноги','Ноги плечи','Спина трицепс','Всё тело · A','Всё тело · B']):
        y=190+i*77
        s += rect(16,y,358,58,'#f2f2f2',29) + icon('fitness',28,y+17,25,ACCENT) + text(61,y+36,name,19,INK,700)
    return s+tabbar(1)

def detail():
    s=shell()+rect(0,83,390,174,ACCENT,29)+rect(0,151,390,106,ACCENT)
    s+=text(28,112,'⌄',24,'white',700,'middle')+text(195,112,'ВТОРНИК, 18:27',13,'white',400,'middle')+text(362,112,'•••',14,'white',700,'middle')
    s+=rect(16,132,358,0.5,'#ff9983')+icon('fitness',18,201,32,'white')+text(58,226,'Грудь бицепс',29,'white',700)
    for i,(label,value) in enumerate([('Время','1 ч 20 мин'),('Объём','6 240 кг'),('Подходы','9')]):
        x=16+i*124
        s+=rect(x,273,116,61,'#f2f2f2',17)+text(x+58,295,label,12,MUTED,400,'middle')+text(x+58,319,value,16,INK,700,'middle')
    data=[('Barbell_Incline_Bench_Press_-_Medium_Grip','Жим штанги на наклонной скамье','30 кг × 8, 40 кг × 8, 50 кг × 8'),('Dumbbell_Bench_Press','Жим гантелей лёжа','18 кг × 8, 20 кг × 8, 22 кг × 8'),('EZ-Bar_Curl','Сгибания рук с EZ-грифом','20 кг × 10, 25 кг × 8, 25 кг × 8'),('Butterfly','Сведение рук в тренажёре','35 кг × 10, 40 кг × 8, 40 кг × 8')]
    for i,(key,name,summary) in enumerate(data):
        y=371+i*99
        s+=text(33,y,i+1,14)+wrap(58,y,name,chars=23,size=17,weight=500,limit=2,line=21)
        s+=wrap(58,y+49,summary,chars=35,size=12,line=16,limit=2)+photo(key,0,328,y+1,46,46)
        s+=rect(58,y+76,316,0.6,'#dcdcdc')
    s+=rect(16,799,48,48,'#f2f2f2',24)+text(40,832,'+',30,ACCENT,400,'middle')
    s+=rect(139,799,112,48,ACCENT,24)+text(195,830,'Повторить',17,'white',700,'middle')
    s+=rect(326,799,48,48,'#f2f2f2',24)+text(350,831,'✎',27,ACCENT,400,'middle')
    s+=rect(142,879,106,5,'#171717',3)
    return s

def results():
    import calendar
    s=shell()+toolbar('2026')+text(16,164,'Результаты',34,INK,700)+text(20,212,'◷  История',23,INK,700)
    s+=rect(16,233,358,270,'#f2f2f2',27)+text(29,260,'Октябрь',14,MUTED)
    dates=list(calendar.Calendar(firstweekday=0).itermonthdates(2026,10))
    trained=[1,4,6,8,13,15,18,20,22,27]
    for i,day in enumerate(dates):
        x=39+(i%7)*34; y=292+(i//7)*38
        active=day.month==10 and day.day in trained
        s+=f'<circle cx="{x}" cy="{y}" r="14" fill="{ACCENT if active else 'none'}" stroke="{'none' if active or day.month!=10 else '#dbdbdb'}"/>'
        s+=text(x,y+5,day.day,12,'white' if active else INK if day.month==10 else '#b9b9b9',400,'middle')
    s+=rect(282,251,1,231,'#dadada')+text(328,263,'Всего',13,MUTED,400,'middle')+text(328,295,'10',28,INK,500,'middle')
    s+=f'<circle cx="328" cy="383" r="23" fill="none" stroke="#d9d9d9" stroke-width="12"/><circle cx="328" cy="383" r="23" fill="none" stroke="{ACCENT}" stroke-width="12" stroke-dasharray="47 145" transform="rotate(-90 328 383)"/>'
    s+=icon('dumbbell',20,530,26)+text(56,551,'Жим штанги лёжа',22,INK,700)+rect(16,572,358,204,'#f2f2f2',27)+text(30,600,'Объём за тренировку, кг',12,MUTED)
    values=[83,110,95,91,128,116,87,100,126,113,75,93]
    for i,val in enumerate(values):
        s+=rect(32+i*25,749-val,16,val,ACCENT,4)
    s+=rect(30,750,321,0.5,'#d3d3d3')+text(38,767,'фев.          апр.          июль          окт.',10,MUTED)
    return s+tabbar(2)

def library():
    s=shell()+toolbar('Каталог')+text(16,164,'Упражнения',34,INK,700)
    s+=rect(16,185,358,40,'#f2f2f2',13)+text(30,211,'⌕  Название, мышца или инвентарь',12,MUTED)
    s+=text(20,250,'Все мышцы ⌄',13,ACCENT)+text(242,250,'Инвентарь ⌄',13,ACCENT)
    s+=text(20,277,'100 упражнений · Без интернета',11,MUTED)
    items=sorted(DATA['entries'],key=lambda item:item['name'].lower().replace('ё','е'))[:6]
    for i,entry in enumerate(items):
        y=294+i*79
        s+=photo(entry['sourceID'],0,19,y,65,59)+wrap(98,y+21,entry['name'],chars=26,size=14,limit=2,line=18,weight=500)
        s+=text(98,y+62,'Техника и 2 фотографии',10,MUTED)+rect(98,y+74,276,0.5,'#dfdfdf')
    s+=text(24,803,'ⓘ  Источник данных и фотографии',12,ACCENT)
    return s

def workout():
    s=shell()+rect(0,83,390,166,ACCENT,29)+rect(0,145,390,104,ACCENT)
    s+=text(28,111,'⌄',24,'white',700,'middle')+text(195,111,'ЧЕТВЕРГ, 18:30',13,'white',400,'middle')+text(360,111,'•••',14,'white',700,'middle')
    s+=rect(16,132,358,0.5,'#ff9983')+icon('fitness',19,191,32,'white')+text(58,218,'Всё тело · A',30,'white',700)
    for i,(label,value) in enumerate([('Время','00:18:24'),('Объём','320 кг'),('Подходы','1/3')]):
        x=16+i*124
        s+=rect(x,265,116,61,'#f2f2f2',17)+text(x+58,287,label,12,MUTED,400,'middle')+text(x+58,311,value,17,INK,700,'middle')
    s+=rect(102,346,186,41,'#fff0eb',21)+text(195,373,'Отдых  00:53',16,ACCENT,700,'middle')
    s+=text(20,422,'ПРИСЕДАНИЯ',12,MUTED,700)+text(20,453,'Техника выполнения  ›',14,ACCENT)
    for i in range(3):
        y=493+i*70
        s+=text(22,y,'40',23,INK,500)+text(66,y,'кг',13,MUTED)+text(153,y,'8',23,INK,500)+text(180,y,'повторов',13,MUTED)
        s+=text(349,y,'✓' if i==0 else '○',26,ACCENT,500,'middle')
        s+=text(22,y+25,'Подход выполнен' if i==0 else 'Разминочный подход',11,MUTED)+rect(20,y+40,354,0.5,'#dedede')
    s+=text(20,708,'+ Добавить упражнение',15,ACCENT)+text(20,752,'Заметка о тренировке',13,MUTED)
    s+=rect(42,809,137,44,'#f2f2f2',22)+text(110,837,'Ⅱ  Пауза',15,ACCENT,700,'middle')+rect(193,809,156,44,ACCENT,22)+text(270,837,'✓  Завершить',15,'white',700,'middle')
    s+=rect(142,879,106,5,'#171717',3)
    return s

def settings():
    s=shell()+rect(0,78,390,791,'#f1f1f1')+text(16,151,'Настройки',34,INK,700)
    s+=text(29,200,'Тренировка',14,MUTED,700)
    s+=rect(16,216,358,179,'white',26)
    rows=[('Уведомления',True),('Отключить автоблокировку',False),('Live Activities',True)]
    for i,(name,on) in enumerate(rows):
        y=246+i*52
        s+=rect(30,y-16,27,27,'#929292',7)+text(44,y+4,'○',19,'white',500,'middle')+wrap(67,y+2,name,chars=24,size=14,limit=2,line=16)
        s+=rect(312,y-14,48,27,'#30c75a' if on else '#cacaca',14)+f'<circle cx="{346 if on else 326}" cy="{y-0.5}" r="11" fill="white"/>'
        if i<2:s+=rect(67,y+31,292,0.6,'#dedede')
    s+=text(29,437,'Основные',14,MUTED,700)+rect(16,455,358,158,'white',26)
    for i,(name,value) in enumerate([('Тема','Авто'),('Единицы измерения','кг'),('Здоровье','›')]):
        y=486+i*49
        s+=rect(30,y-16,27,27,'#929292',7)+text(44,y+3,'○',19,'white',500,'middle')+text(67,y+2,name,15)+text(356,y+2,value,14,MUTED,400,'end')
        if i<2:s+=rect(67,y+27,292,0.6,'#dedede')
    s+=text(29,655,'Данные',14,MUTED,700)+rect(16,672,358,95,'white',26)+text(32,705,'Синхронизация iCloud',15)+text(32,747,'Сводка для виджета',15)
    return s+tabbar(3)

def exercise_detail():
    entry=ENTRIES['Barbell_Squat']
    s=shell()+text(20,109,'‹ Упражнения',15,ACCENT)+text(195,146,'Приседания',22,INK,700,'middle')
    s+=photo('Barbell_Squat',0,16,166,358,224)
    s+=text(36,419,'‹',25,ACCENT)+text(195,416,'Положение 1 из 2',12,MUTED,400,'middle')+text(352,419,'›',25,ACCENT)
    for x,label,value in [(16,'инвентарь','Штанга'),(202,'уровень','Начальный')]:
        s+=rect(x,438,172,63,'#f2f2f2',20)+text(x+16,466,value,17,INK,700)+text(x+16,488,label,11,MUTED)
    s+=text(16,536,'Работающие мышцы',20,INK,700)+text(16,562,'Квадрицепс',14)+text(16,600,'Техника выполнения',20,INK,700)
    for i,step in enumerate(entry['steps']):
        y=622+i*58
        s+=rect(16,y,25,25,'#ffebe6',13)+text(28,y+17,i+1,12,ACCENT,700,'middle')+wrap(52,y+11,step,chars=45,size=11,line=16,limit=3)
    s+=rect(65,818,260,42,ACCENT,21)+text(195,845,'+ Добавить упражнение',15,'white',700,'middle')+rect(142,879,106,5,'#171717',3)
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
    screens = [('diary', diary()), ('catalogue', catalogue()), ('results', results()),
               ('workout-detail', detail()), ('exercise-library', library()),
               ('exercise-detail', exercise_detail()), ('active-workout', workout()), ('settings', settings())]
    for name, content in screens:
        file = OUT / (name + '.svg')
        file.write_text(svg(390, 900, content))
        render(file, 390, 900, scale=3)
    for name, selected in [('overview', [diary(), catalogue(), detail()]),
                           ('results-overview', [results(), workout(), settings()])]:
        board = rect(0, 0, 1270, 1020, '#ebebeb')
        board += text(30, 38, 'FitSession · дизайн по вашим референсам', 25, INK, 700)
        board += text(30, 63, 'Демонстрационные данные. Это макеты, не скриншоты Xcode; Liquid Glass проверяется на Mac.', 12, MUTED)
        for i, content in enumerate(selected):
            board += f'<svg x="{30 + i * 410}" y="85" width="390" height="900" viewBox="0 0 390 900">{content}</svg>'
        file = OUT / (name + '.svg')
        file.write_text(svg(1270, 1020, board))
        render(file, 1270, 1020)
