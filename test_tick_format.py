"""Offline full-run contract: no HTTP call can leave the curl fixture."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class TickFormatTests(unittest.TestCase):
    def test_failure_literal_diagnostics_and_success_silence(self):
        bash = r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt' else shutil.which('bash')
        def posix(path):
            value = str(path).replace('\\', '/')
            return '/' + value[0].lower() + value[2:] if os.name == 'nt' else value
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            curl = root / 'curl'
            curl.write_text('''#!/usr/bin/env bash
case "$*" in
  *time_total*)
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then shift; printf '%s' '<b>&_* [literal] `body`' > "$1"; break; fi
      shift
    done
    printf '%s 0.125' "$HTTP_FIXTURE" ;;
  */api/cron/heartbeat*) printf '%s' "$*" > "$HEARTBEAT"; printf 200 ;;
  *) printf '%s\\n' "$@" > "$CAPTURE"; printf '{"ok":true}' ;;
esac
''', encoding='utf-8')
            curl.chmod(0o755)
            capture = root / 'message'
            heartbeat = root / 'heartbeat'
            env = dict(os.environ, MOCK_BIN=posix(root), TARGET=posix(Path(__file__).with_name('tick.sh').resolve()),
                       CAPTURE=posix(capture), HEARTBEAT=posix(heartbeat), XPHERE_BASE_URL='https://offline.invalid',
                       XPHERE_CRON_SECRET='fixture', TELEGRAM_BOT_TOKEN_XPHERE='123:offline', TELEGRAM_ALERT_CHAT_ID_XPHERE='-123')
            for status in ('503', '200'):
                if capture.exists(): capture.unlink()
                env['HTTP_FIXTURE'] = status
                result = subprocess.run([bash, '-c', 'PATH="$MOCK_BIN:$PATH" bash "$TARGET" XPHERE fixture https://offline.invalid/job 600 2'], env=env, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('xphere/fixture', heartbeat.read_text(encoding='utf-8'))
                if status == '503':
                    message = capture.read_text(encoding='utf-8')
                    self.assertIn('🔴 Crítico — Falha em tarefa agendada\n\nAplicativo: XPHERE\nTarefa: fixture', message)
                    self.assertIn('Estado HTTP: 503\nDuração: 125 ms', message)
                    self.assertIn('<b>&_* [literal] `body`', message)
                    self.assertNotIn('parse_mode=', message)
                else:
                    self.assertFalse(capture.exists())


if __name__ == '__main__':
    unittest.main()
