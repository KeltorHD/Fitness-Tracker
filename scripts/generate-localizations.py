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
      'NSAlarmKitUsageDescription':('Устанавливать будильники сна с обязательным сигналом к выбранному времени.','Schedule sleep alarms with a fallback alert at the selected time.'),
      'NSMotionUsageDescription':('Оценивать движения запястья в выбранном окне умного будильника.','Estimate wrist movement during your chosen smart alarm window.'),
      'NSCameraUsageDescription':('Сканировать штрихкоды упаковок, чтобы найти продукт и добавить его в дневник питания.','Scan barcodes on food packaging to find products and add them to your food diary.'),
      'NSHealthShareUsageDescription':('Читать сон, пульс и другие показатели из «Здоровья» для дневника и статистики; по вашему запросу — данные тренировки для приёма измерений AirPods Pro 3.','Read sleep, heart rate and other Health metrics for your diary and statistics; when requested, read workout data to receive AirPods Pro 3 measurements.'),
      'NSHealthUpdateUsageDescription':('Включать системную тренировку для получения пульса AirPods Pro 3 по вашему запросу. Завершённая тренировка сохраняется в «Здоровье» только при отдельном экспорте.','Start a system workout to receive AirPods Pro 3 heart rate when you request it. The completed workout is saved to Health only through a separate export.'),
      'NSBluetoothAlwaysUsageDescription':('Подключать Bluetooth-пульсометр, например Mi Band или HUAWEI WATCH, и записывать пульс во время тренировки.','Connect a Bluetooth heart rate monitor, such as a Mi Band or HUAWEI WATCH, and record heart rate during your workout.'),
      'CFBundleDisplayName':('FitnessTracker','FitnessTracker')
    }
    write(ROOT/'Resources/InfoPlist.xcstrings',catalog(info))
    print(f'Generated {len(pairs)} RU/EN UI strings and {len(info)} Info.plist strings.')
if __name__=='__main__':generate()
