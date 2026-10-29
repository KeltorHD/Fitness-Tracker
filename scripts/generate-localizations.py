#!/usr/bin/env python3
"""Generate native String Catalogs from the reviewed Russian-to-English UI dictionary."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parent.parent

def catalog(translations):
    return {'sourceLanguage':'ru','strings':{
        key:{'extractionState':'manual','localizations':{
            'ru':{'stringUnit':{'state':'translated','value':ru}},
            'en':{'stringUnit':{'state':'translated','value':en}}
        }} for key,(ru,en) in sorted(translations.items())},'version':'1.0'}

def write(path, value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def generate():
    values=json.loads((ROOT/'Data/Localization/Interface.en.json').read_text())
    russian=json.loads((ROOT/'Data/Localization/Interface.ru.json').read_text())
    pairs={key:(russian.get(key,key),en) for key,en in values.items()}
    write(ROOT/'Resources/Localizable.xcstrings',catalog(pairs))
    info={
      'NSHealthShareUsageDescription':('FitSession запрашивает доступ к тренировкам только для функций «Здоровья». Чтение данных сейчас не используется.','FitSession requests workout access only for Health features. Reading health data is not currently used.'),
      'NSHealthUpdateUsageDescription':('Сохранять завершённые силовые тренировки в «Здоровье» по вашему запросу.','Save completed strength workouts to Health when you request it.'),
      'CFBundleDisplayName':('FitSession','FitSession')
    }
    write(ROOT/'Resources/InfoPlist.xcstrings',catalog(info))
    print(f'Generated {len(pairs)} RU/EN UI strings and {len(info)} Info.plist strings.')
if __name__=='__main__':generate()
