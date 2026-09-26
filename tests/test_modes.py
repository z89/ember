"""Run Ember's actual mode/fade logic in Qt, without a desktop or DMS daemon.

Usage: python3 tests/test_modes.py [path/to/EmberWidget.qml]
Requires Qt 6 qmltestrunner; no Python packages are needed.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'EmberWidget.qml'
runner = '/usr/lib/qt6/bin/qmltestrunner' if Path('/usr/lib/qt6/bin/qmltestrunner').exists() else shutil.which('qmltestrunner')
widget = source.read_text()
logic = widget[widget.index('    // Three user-facing'):widget.index('    // ---- presentation')]
if 'readonly property var nightService:' in widget:
    logic = next(line for line in widget.splitlines() if 'readonly property var nightService:' in line) + '\n' + logic
for original, stub in [('DisplayService', 'display'), ('NightModeService', 'modernService'), ('SessionData', 'session'), ('DMSService', 'daemon')]:
    logic = logic.replace(original, stub)

preamble = '''import QtQuick
import QtTest
TestCase {
 id: root
 name: "EmberModes"
 property var pluginData: ({fadeDuration: 1})
 QtObject {
  id: session
  property bool nightModeEnabled: true
  property bool nightModeAutoEnabled: false
  property int nightModeTemperature: 4500
  property int nightModeHighTemperature: 6500
  property string nightModeAutoMode: "time"
  property int nightModeEndHour: 7
  property int nightModeEndMinute: 0
  property int nightModeStartHour: 18
  property int nightModeStartMinute: 0
  property int nightModeTransitionMinutes: 0
  function setNightModeAutoEnabled(v) { nightModeAutoEnabled = v; }
  function setNightModeTemperature(v) { nightModeTemperature = v; }
  function setNightModeHighTemperature(v) { nightModeHighTemperature = v; }
 }
 QtObject {
  id: service
  property bool nightModeEnabled: true
  property bool gammaControlAvailable: true
  property int gammaCurrentTemp: 4500
  property int evaluations: 0
  function enableNightMode() { nightModeEnabled = true; session.nightModeEnabled = true; evaluateNightMode(); }
  function disableNightMode() { nightModeEnabled = false; session.nightModeEnabled = false; }
  function evaluateNightMode() { evaluations++; gammaCurrentTemp = session.nightModeTemperature; }
 }
 QtObject {
  id: daemon
  function sendRequest(method, params, callback) {
   if (method === "wayland.gamma.setTemperature") service.gammaCurrentTemp = params.low;
   if (callback) callback({result: {isDay: false}});
  }
 }
'''
tests = '''
 function init() {
  cancelFade();
  rampPrimed = false;
  previewTemp = 0;
  pendingNight = -1;
  pendingDay = -1;
 }
 function test_modes_data() {
  let rows = [];
  for (const duration of [0, 1])
   for (let from = 0; from < 3; from++)
    for (let to = 0; to < 3; to++)
     if (from !== to) rows.push({tag: duration + ":" + from + "->" + to, duration, from, to});
  return rows;
 }
 function test_modes(data) {
  pluginData = {fadeDuration: data.duration};
  service.nightModeEnabled = data.from !== 2;
  session.nightModeEnabled = service.nightModeEnabled;
  session.nightModeAutoEnabled = data.from === 1;
  service.gammaCurrentTemp = data.from === 2 ? 6500 : 4500;
  setMode(data.to);
  tryCompare(root, "fadeBusy", false, 500);
  compare(modeIndex, data.to);
  compare(session.nightModeEnabled, data.to !== 2);
  if (data.to === 2 && data.duration > 0) compare(service.gammaCurrentTemp, 6500);
  if (data.to !== 2) compare(service.gammaCurrentTemp, 4500);
 }
 function test_preview_restores_mode() {
  service.nightModeEnabled = true;
  const before = service.evaluations;
  previewTemperature(3000);
  compare(service.gammaCurrentTemp, 3000);
  commitPending();
  compare(service.evaluations, before + 1);
  compare(service.gammaCurrentTemp, 4500);
 }
 function test_failed_fade_restores_mode() {
  service.nightModeEnabled = true;
  fadeBusy = true;
  const before = service.evaluations;
  abortFade();
  compare(fadeBusy, false);
  compare(service.evaluations, before + 1);
 }
}
'''
failed = False
with tempfile.TemporaryDirectory(prefix='ember-modes-') as tmp:
    for layout in ['modern', 'legacy']:
        # Modern DisplayService retains properties but no enable/disable/evaluate methods.
        services = ('property var modernService: service\n QtObject { id: display\n'
                    'readonly property bool nightModeEnabled: service.nightModeEnabled\n'
                    'readonly property bool gammaControlAvailable: service.gammaControlAvailable\n'
                    'readonly property int gammaCurrentTemp: service.gammaCurrentTemp\n }\n') if layout == 'modern' else 'property var display: service\n'
        path = Path(tmp) / 'tst_modes.qml'
        path.write_text(preamble + services + logic + tests)
        print(f'\nDMS service layout: {layout}', flush=True)
        result = subprocess.run([runner, '-input', str(path)], env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}, timeout=30)
        failed |= result.returncode != 0
sys.exit(int(failed))
