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
      'NSHealthShareUsageDescription':('Показывать шаги, активную энергию, сон и пульс из «Здоровья» и загружать измерения пульса для вашей тренировки по вашему запросу.','Show steps, active energy, sleep and heart rate from Health, and load heart rate measurements for your workout when you request it.'),
      'NSHealthUpdateUsageDescription':('Сохранять завершённые силовые тренировки в «Здоровье» по вашему запросу.','Save completed strength workouts to Health when you request it.'),
      'NSBluetoothAlwaysUsageDescription':('Подключать Bluetooth-пульсометр, например Mi Band или HUAWEI WATCH, и записывать пульс во время тренировки.','Connect a Bluetooth heart rate monitor, such as a Mi Band or HUAWEI WATCH, and record heart rate during your workout.'),
      'CFBundleDisplayName':('FitSession','FitSession')
    }
    write(ROOT/'Resources/InfoPlist.xcstrings',catalog(info))
    print(f'Generated {len(pairs)} RU/EN UI strings and {len(info)} Info.plist strings.')
if __name__=='__main__':generate()
