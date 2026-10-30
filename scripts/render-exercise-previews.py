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
DATA = json.loads((ROOT / 'Sources/FitnessTrackerCore/Resources/ExerciseLibrary.ru.json').read_text())
ENTRIES = {item['sourceID']: item for item in DATA['entries']}
INK, MUTED, ACCENT, BG = '#191919', '#8e8e93', '#ff4f33', '#ffffff'

def rect(x, y, w, h, color, radius=0, stroke=None):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{color}"' + (f' stroke="{stroke}"' if stroke else '') + '/>'

def text(x, y, value, size=15, color=INK, weight=400, anchor='start'):
    return f'<text x="{x}" y="{y}" font-family="DejaVu Sans,sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{html.escape(str(value))}</text>'

def wrap(x, y, value, chars=42, size=14, color=INK, limit=6, line=21, weight=400):
    lines = textwrap.wrap(value, chars, break_long_words=False)[:limit]
    return ''.join(text(x, y + i * line, word, size, color, weight) for i, word in enumerate(lines))

def photo(source_id, index, x, y, w, h, surface='#e6edeb'):
    path = ROOT / 'Resources/ExerciseMedia' / ENTRIES[source_id]['images'][index]
    data = base64.b64encode(path.read_bytes()).decode()
    return rect(x, y, w, h, surface, 12) + f'<image x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="xMidYMid meet" href="data:image/jpeg;base64,{data}"/>'

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

SESSION_EXERCISES = [
    ('Wide-Grip_Lat_Pulldown', [(35,12),(40,12),(45,10),(50,8)]),
    ('Seated_Cable_Rows', [(25,15),(30,12),(35,12)]),
    ('Seated_Triceps_Press', [(16,15),(18,12),(20,10)]),
    ('Triceps_Pushdown_-_Rope_Attachment', [(20,15),(25,12),(30,10)]),
]

def session_overview(active=False):
    s=shell()+rect(0,83,390,168,ACCENT,29)+rect(0,148,390,103,ACCENT)
    s+=text(28,112,'⌄',24,'white',700,'middle')+text(195,112,'ПЯТНИЦА, 18:15',13,'white',400,'middle')+text(362,112,'•••',14,'white',700,'middle')
    s+=rect(16,132,358,0.5,'#ff9983')+icon('fitness',18,189,32,'white')+text(59,215,'Спина и руки',29,'white',700)
    volume=420 if active else sum(w*r for _,sets in SESSION_EXERCISES for w,r in sets)
    count=sum(len(sets) for _,sets in SESSION_EXERCISES)
    for i,(label,value) in enumerate([('Время','18 мин' if active else '48 мин'),('Объём',f'{volume:,} кг'.replace(',',' ')),('Подходы',f'1/{count}' if active else str(count))]):
        x=16+i*122
        s+=rect(x,267,114,59,'#f2f2f2',16)+text(x+57,289,label,12,MUTED,400,'middle')+text(x+57,313,value,16,INK,700,'middle')
    for i,(key,sets) in enumerate(SESSION_EXERCISES):
        y=354+i*92
        name=ENTRIES[key]['name']
        summary=', '.join(f'{w} кг × {r}' for w,r in sets)
        s+=text(30,y,i+1,15,MUTED)+wrap(58,y,name,chars=24,size=17,weight=600,limit=2,line=21)
        s+=wrap(58,y+45,summary,chars=31,size=12,color=MUTED,line=16,limit=2)
        s+=photo(key,0,328,y+5,46,46,surface='white')+rect(328,y+5,46,46,'none',12,'#dedede')
        s+=rect(58,y+73,316,0.6,'#dcdcdc')
    s+=rect(16,724,358,67,'#f2f2f2',22)+text(32,750,'Вес тела',14)+text(356,750,'76,2 кг',14,INK,500,'end')+text(32,776,'Изменить вес',13,ACCENT)
    s+=rect(0,801,390,72,'white')
    if active:
        s+=rect(18,811,117,44,'#f2f2f2',22)+text(77,839,'Ⅱ Пауза',14,ACCENT,600,'middle')
        s+=rect(146,811,228,44,ACCENT,22)+text(260,839,'✓ Завершить тренировку',14,'white',600,'middle')
    else:
        s+=rect(16,811,48,48,'#f2f2f2',24)+text(40,843,'+',30,ACCENT,400,'middle')
        s+=rect(132,811,126,48,ACCENT,24)+text(195,842,'Повторить',17,'white',700,'middle')
        s+=rect(326,811,48,48,'#f2f2f2',24)+text(350,842,'✎',27,ACCENT,400,'middle')
    return s+rect(142,879,106,5,'#171717',3)

def detail():
    return session_overview()

def exercise_in_workout():
    s=shell()+rect(0,78,390,793,'#f1f1f1')
    s+=rect(0,78,390,199,ACCENT)
    s+=text(20,125,'1/4',17,'#ffdfd7')+text(195,128,'0:18:24',29,'white',400,'middle')+text(367,124,'⌄',24,'white',400,'middle')
    s+=rect(12,154,366,609,'#e4e4e4',28)+rect(12,151,366,608,'white',28)
    s+=text(36,181,'⌄',23,MUTED,700,'middle')+text(354,181,'•••',15,MUTED,700,'middle')
    s+=text(195,208,'Тяга верхнего блока',22,ACCENT,700,'middle')+text(195,236,'широким хватом',22,ACCENT,700,'middle')
    s+=text(195,268,'СПИНА',12,MUTED,500,'middle')
    for i,(weight,reps) in enumerate(SESSION_EXERCISES[0][1]):
        y=324+i*66
        s+=rect(24,y-28,33,38,'#ffebe6' if i==1 else '#f2f2f2',12)
        s+=text(40,y-3,i+1,16,ACCENT if i==1 else MUTED,400,'middle')
        s+=text(167,y,weight,34,INK,400,'end')+text(171,y,'кг',16,MUTED)+text(217,y-3,'×',22,MUTED,'middle')+text(248,y,reps,34,INK)
        if i==0:s+=text(350,y-5,'✓',13,ACCENT,600,'middle')
        if i<3:s+=rect(24,y+20,342,0.6,'#dcdcdc')
    s+=icon('chart',28,708,25,MUTED)+photo('Wide-Grip_Lat_Pulldown',0,295,699,37,37,surface='white')+text(353,727,'i',24,MUTED,500,'middle')
    for x,label in [(30,'‹'),(108,'+'),(282,'Ⅱ'),(360,'›')]:
        s+=text(x,812,label,32,MUTED,400,'middle')
    s+=f'<circle cx="195" cy="801" r="32" fill="{ACCENT}" stroke="white" stroke-width="4"/>'
    s+=text(195,812,'✓',31,'white',700,'middle')
    s+=text(195,855,'✓ Завершить тренировку',13,ACCENT,600,'middle')
    return s+rect(142,879,106,5,'#171717',3)

def set_types():
    # A separate demonstration of mixed set types; no private/user workout data.
    s=exercise_in_workout()+rect(22,288,346,402,'white')
    def values(y,number,weight,reps,selected=False,done=False):
        v=rect(24,y-28,35,38,'#ffebe6' if selected else '#f2f2f2',12)
        v+=text(41,y-3,number,15,ACCENT if selected else MUTED,400,'middle')
        v+=text(167,y,weight,34,INK,400,'end')+text(171,y,'кг',16,MUTED)+text(217,y-3,'×',22,MUTED,'middle')+text(248,y,reps,34,INK)
        if done:v+=text(350,y-5,'✓',13,ACCENT,600,'middle')
        return v
    s+=values(322,'1',20,15,done=True)
    s+=rect(77,335,86,22,'#ffebe6',11)+text(120,350,'♨ Разминка',11,ACCENT,500,'middle')
    s+=rect(24,371,342,0.6,'#dcdcdc')
    s+=values(412,'2',40,12,done=True)+rect(24,432,342,0.6,'#dcdcdc')
    s+=rect(20,443,350,240,'#f7f7f7',16)
    s+=values(483,'3',50,8,done=True)
    s+=rect(77,495,158,22,'#ffebe6',11)+text(156,510,'Дропсет · этапов: 3',11,ACCENT,600,'middle')
    s+=rect(76,528,281,0.5,'#dedede')
    s+=values(565,'↓1',40,8,selected=True)+rect(76,586,281,0.5,'#dedede')
    s+=values(627,'↓2',30,10)
    s+=text(77,664,'Без отдыха между этапами',11,MUTED)
    return s

def heart_rate_live():
    s=shell()+rect(0,78,390,793,'#f2f2f7')+text(16,110,'‹ Настройки',14,ACCENT)+text(16,150,'Трекер',32,INK,700)
    s+=rect(16,173,358,103,'white',22)+text(30,202,'Модель трекера',14)+text(358,202,'AirPods Pro 3  ⌄',14,MUTED,400,'end')
    s+=rect(30,221,344,0.5,'#e5e5e5')+text(30,252,'Режим трекера',14)+text(358,252,'Apple «Здоровье»  ⌄',13,MUTED,400,'end')
    s+=text(30,307,'ПУЛЬС ВО ВРЕМЯ ТРЕНИРОВКИ',11,MUTED,500)+rect(16,321,358,375,'white',22)
    s+=wrap(30,347,'Наденьте AirPods Pro 3 и подключите их к iPhone. В настройках iOS → AirPods → Пульс включите измерение. Затем начните тренировку в FitnessTracker и включите приём пульса.',chars=46,size=12,line=18,limit=5)
    s+=wrap(30,449,'Этот режим предназначен для AirPods Pro 3 с датчиком пульса. iOS выбирает доступный источник; вместе с AirPods может использоваться Apple Watch.',chars=48,size=11,color=MUTED,line=16,limit=4)
    s+=text(30,536,'♥',23,'#ef4b4b')+text(63,536,'128 уд/мин',19,INK,500)
    s+=wrap(30,563,'Приём пульса включён. Если измерения нет, проверьте посадку AirPods и доступ к пульсу.',chars=48,size=11,color=MUTED,line=16,limit=3)
    s+=text(30,632,'Остановить приём пульса',15,ACCENT)+text(30,672,'Инструкция производителя  ↗',13,ACCENT)
    s+=wrap(30,718,'Для приёма нужен доступ к пульсу и тренировкам в «Здоровье». Запись тренировки в «Здоровье» остаётся отдельным действием.',chars=51,size=10,color=MUTED,line=15,limit=3)
    s+=rect(16,775,358,79,'white',22)+text(30,800,'День',14)+text(358,800,'30 октября 2026',13,MUTED,400,'end')+text(30,834,'Прочитать показатели',15,ACCENT)
    return s+rect(142,879,106,5,'#171717',3)

def heart_rate_history():
    s=shell()+rect(0,83,390,52,ACCENT)+text(28,115,'⌄',24,'white',700,'middle')+text(195,114,'ПЯТНИЦА, 18:15',13,'white',400,'middle')+text(362,114,'•••',14,'white',700,'middle')
    s+=text(18,167,'История · Спина и руки',19,INK,700)
    s+=rect(16,190,358,78,'#f2f2f2',24)+text(32,219,'Вес тела',14)+text(358,219,'76,2 кг',14,INK,500,'end')+text(32,250,'Изменить вес',14,ACCENT)
    s+=rect(16,288,358,375,'#f2f2f2',24)+text(32,319,'♥  Пульс',17,INK,700)
    values=[91,98,108,132,146,138,117,112,130,151,142,116,105,122,145,156,141,126,109,118,138,150,131,110]
    average=round(sum(values)/len(values))
    s+=text(32,352,f'Средний: {average}',13)+text(358,352,f'Максимум: {max(values)}',13,INK,400,'end')
    for v in [90,110,130,150]:
        y=539-(v-90)*2.15
        s+=rect(36,y,283,0.5,'#dedede')+text(326,y+4,v,10,MUTED)
    for indices in [list(range(0,11)),list(range(12,len(values)))]:
        points=' '.join(f'{38+i*11.6},{539-(values[i]-90)*2.15}' for i in indices)
        s+=f'<polyline points="{points}" fill="none" stroke="{ACCENT}" stroke-width="2.5" stroke-linejoin="round"/>'
    for x,label in [(38,'18:15'),(145,'18:35'),(277,'19:00')]:s+=text(x,565,label,10,MUTED)
    s+=text(32,597,'Источник: пульс во время тренировки',11,MUTED)
    s+=wrap(32,622,'Разрывы графика означают отсутствие измерений. Средний пульс рассчитан по сохранённым точкам.',chars=48,size=10,color=MUTED,line=15,limit=3)
    s+=text(20,704,'♥  Экспорт в «Здоровье»',15,ACCENT)
    s+=wrap(20,736,'Калории и пульс не рассчитываются из веса снарядов. В «Здоровье» передаются тип, длительность и паузы тренировки.',chars=51,size=10,color=MUTED,line=16,limit=3)
    s+=rect(16,811,48,48,'#f2f2f2',24)+text(40,843,'+',30,ACCENT,400,'middle')+rect(132,811,126,48,ACCENT,24)+text(195,842,'Повторить',17,'white',700,'middle')+rect(326,811,48,48,'#f2f2f2',24)+text(350,842,'✎',27,ACCENT,400,'middle')
    return s+rect(142,879,106,5,'#171717',3)

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
    return session_overview(active=True)

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
               ('exercise-detail', exercise_detail()), ('active-workout', workout()), ('settings', settings()),
               ('exercise-in-workout', exercise_in_workout()), ('workout-set-types', set_types()), ('heart-rate-live', heart_rate_live()),
               ('heart-rate-history', heart_rate_history())]
    for name, content in screens:
        file = OUT / (name + '.svg')
        file.write_text(svg(390, 900, content))
        render(file, 390, 900, scale=3)
    for name, selected in [('overview', [diary(), catalogue(), detail()]),
                           ('results-overview', [results(), workout(), settings()]),
                           ('workout-flow', [detail(), workout(), set_types()]),
                           ('set-types-overview', [exercise_in_workout(), set_types()]),
                           ('heart-rate-overview', [heart_rate_live(), heart_rate_history()])]:
        board_width = 40 + len(selected) * 410
        board = rect(0, 0, board_width, 1020, '#ebebeb')
        board += text(30, 38, 'FitnessTracker · дизайн по вашим референсам', 25, INK, 700)
        board += text(30, 63, 'Демонстрационные данные. Это макеты, не скриншоты Xcode; Liquid Glass проверяется на Mac.', 12, MUTED)
        for i, content in enumerate(selected):
            board += f'<svg x="{30 + i * 410}" y="85" width="390" height="900" viewBox="0 0 390 900">{content}</svg>'
        file = OUT / (name + '.svg')
        file.write_text(svg(board_width, 1020, board))
        render(file, board_width, 1020)
