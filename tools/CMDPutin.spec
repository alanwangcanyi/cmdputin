from pathlib import Path
import os

root = Path(SPECPATH).parent
name = 'CMDPutin'
icon = os.environ['TYPIST_ICON']
analysis = Analysis([str(root / 'console_typist.py')])
archive = PYZ(analysis.pure)
exe = EXE(archive, analysis.scripts, [], exclude_binaries=True, name=name, console=False, icon=icon)
collection = COLLECT(exe, analysis.binaries, analysis.datas, name=name)
app = BUNDLE(collection, name=f'{name}.app', icon=icon, bundle_identifier='com.local.cmdputin',
             info_plist={'CFBundleDisplayName': name, 'CFBundleShortVersionString': '1.0.0',
                         'CFBundleVersion': '1', 'NSHighResolutionCapable': True,
                         'NSAppleEventsUsageDescription': '读取目标窗口列表，并按你的选择向窗口输入命令。'})
