#!/usr/bin/env python3
"""Exercise probe failure recovery against a fake interactive srcds console."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

PROBE = Path(__file__).resolve().with_name('console-probe.exp')
FAKE = '''#!/usr/bin/env python3
import os, sys
print('Loading map "de_dust2"', flush=True)
for line in sys.stdin:
    cmd = line.strip()
    with open(os.environ['COMMAND_LOG'], 'a') as log:
        log.write(cmd + '\\n')
    response = {
        'status': 'hostname: test',
        'version': 'Protocol version 7',
        'meta version': 'Metamod:Source version 1.12\\nBuild ID: 1226',
        'sm version': 'SourceMod Version 1.13',
        'sm_cvar sv_cheats 0': 'Changed cvar "sv_cheats"',
        'sm exts load sdkhooks': 'SDK Hooks',
        'sm exts list': '[SM] Displaying 6 extensions:',
        'sm plugins list': '[SM] Listing 17 plugins:',
    }.get(cmd)
    if cmd.startswith('sm exts load ') and response is None:
        name = cmd.split()[-1]
        if name == 'dbi.pgsql.ext' and os.environ['MODE'] == 'failure':
            response = '[SM] Extension dbi.pgsql.ext.so failed to load: undefined symbol: explicit_bzero'
        elif name == 'dbi.pgsql.ext' and os.environ['MODE'] == 'timeout':
            continue
        else:
            response = '[SM] Loaded extension ' + name + ' successfully'
    if cmd == 'quit':
        break
    if response:
        print(response, flush=True)
'''


class ConsoleProbe(unittest.TestCase):
    def test_remaining_commands_after_failure_and_timeout(self):
        for mode in ['success', 'failure', 'timeout']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                fake = root / 'srcds'
                fake.write_text(FAKE)
                fake.chmod(0o755)
                # No real engine to warm up; preserve production timeout logic.
                wrapper = root / 'test.exp'
                wrapper.write_text('rename sleep real_sleep\nproc sleep {seconds} {}\n'
                                   'source {' + str(PROBE) + '}\n')
                env = dict(os.environ, SERVER_DIR=tmp, SRCDS_BINARY=str(fake),
                           COMMAND_LOG=str(root / 'commands'), MODE=mode,
                           CONSOLE_PROBE_LOG=str(root / 'console.log'),
                           CONSOLE_PROBE_TIMEOUT='1', LD_LIBRARY_PATH=os.environ.get('LD_LIBRARY_PATH', ''))
                result = subprocess.run([os.environ.get('EXPECT', 'expect'), str(wrapper)],
                                        env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0 if mode == 'success' else 1,
                                 result.stdout + result.stderr)
                commands = (root / 'commands').read_text().splitlines()
                self.assertEqual(commands[-3:], ['sm exts list', 'sm plugins list', 'quit'])
                self.assertIn('sm exts load regex.ext', commands)


if __name__ == '__main__':
    unittest.main()
