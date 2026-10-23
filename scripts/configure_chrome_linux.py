#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Plan or explicitly register the CIE provider in desktop Chrome's NSS database.

The default is read-only and does not initialize NSS or load any module.
--apply/--remove require an existing database and closed desktop browsers.
Never import certificates, change trust, connect Snap interfaces or request a PIN.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

NAME = 'Firma con CIE Linux'
DEFAULT_MODULE = Path('/opt/firma-con-cie/cie_native/libcie_linux_pkcs11.so')


def default_database(home, data_home=None):
    # Match Chromium M146+: legacy directory has priority even when XDG is set.
    legacy = home / '.pki/nssdb'
    if legacy.is_dir():
        return legacy
    data = Path(data_home) if data_home and Path(data_home).is_absolute() else home / '.local/share'
    return data / 'pki/nssdb'


def browser_running():
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid == os.getuid() and (proc / 'comm').read_text().strip() in {
                    'chrome', 'chromium', 'chromium-browse', 'google-chrome'}:
                return True
        except FileNotFoundError:
            pass  # Process exited between the two reads.
        except PermissionError:
            raise ValueError('Impossibile verificare la chiusura dei browser.')
    return False


def entries(raw):
    result = []
    for record in re.split(r'\n\s*\n', raw):
        fields = {}
        for match in re.finditer(r'(?:^|\s)(library|name)=(?:"((?:\\.|[^"\\])*)"|([^\s]*))', record):
            value = match[2] if match[2] is not None else match[3]
            fields[match[1]] = re.sub(r'\\(.)', r'\1', value)
        if 'name' in fields and 'library' in fields:
            result.append(fields)
    return result


def configure(module, database, *, action='plan', tool=None):
    module, database = Path(module).absolute(), Path(database).absolute()
    if module.name != 'libcie_linux_pkcs11.so' or any(c in str(module) for c in '\n\r"'):
        raise ValueError('Selezionare il provider libcie_linux_pkcs11.so del bundle completo.')
    if action not in {'plan', 'apply', 'remove'}:
        raise ValueError('Operazione non valida.')
    command = [tool or 'modutil', '-dbdir', 'sql:' + str(database),
               *(['-delete', NAME] if action == 'remove' else ['-add', NAME, '-libfile', str(module)]), '-force']
    result = dict(action=action, database=str(database), module=str(module), command=command,
                  configurationChanged=False, browserLoginTested=False, pinRequested=False)
    if action == 'plan':
        # Even listing modules through NSS would initialize their transports.
        result['databaseExists'] = database.is_dir()
        return result
    if os.geteuid() == 0:
        raise ValueError('Eseguire come utente del browser, senza sudo.')
    if browser_running():
        raise ValueError('Chiudere Chrome/Chromium, inclusi i processi in background.')
    # Do not silently create/reset a user's certificate/key database or follow links.
    for path in [database, *database.parents]:
        if path.is_symlink():
            raise ValueError('Il percorso del database contiene collegamenti simbolici.')
    if not database.is_dir() or database.stat().st_uid != os.getuid() or database.stat().st_mode & 0o022:
        raise ValueError('Database NSS assente o non privato. Avviare e chiudere prima Chrome.')
    for name in ['cert9.db', 'key4.db', 'pkcs11.txt']:
        path = database / name
        if (not path.is_file() or path.is_symlink() or path.stat().st_uid != os.getuid()
                or path.stat().st_mode & 0o022):
            raise ValueError('Database NSS SQL non valido; nessun file viene inizializzato o riparato.')
    if action == 'apply' and not module.is_file():
        raise ValueError('Provider non trovato. Conservare il bundle completo in un percorso stabile.')
    tool = tool or shutil.which('modutil')
    if not tool:
        raise ValueError('Serve modutil, fornito dal pacchetto libnss3-tools.')
    command[0] = tool
    env = dict(os.environ, LC_ALL='C')

    def run(arguments):
        completed = subprocess.run(arguments, stdin=subprocess.DEVNULL, capture_output=True,
                                   text=True, env=env, timeout=20)
        if completed.returncode:
            raise RuntimeError('Comando NSS non riuscito. Nessun nuovo tentativo automatico.')
        return completed.stdout

    listing = [tool, '-dbdir', 'sql:' + str(database), '-rawlist']
    existing = entries(run(listing))
    ours = [item for item in existing if item['name'] == NAME]
    duplicates = [item for item in existing if item['library'] == str(module) and item['name'] != NAME]
    if len(ours) > 1 or duplicates or (ours and ours[0]['library'] != str(module)):
        raise ValueError('Registrazione preesistente differente: nessun modulo viene sostituito o rimosso.')
    should_change = bool(ours) if action == 'remove' else not ours
    if should_change:
        run(command)
    after = entries(run(listing))
    foreign = lambda items: [item for item in items if item['name'] != NAME]
    expected = [] if action == 'remove' else [{'library': str(module), 'name': NAME}]
    if foreign(after) != foreign(existing) or [item for item in after if item['name'] == NAME] != expected:
        raise RuntimeError('Verifica della registrazione non riuscita; controllare NSS prima di riprovare.')
    result.update(configurationChanged=should_change, registered=action != 'remove')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module', type=Path, default=DEFAULT_MODULE)
    parser.add_argument('--database', type=Path,
                        help='Database NSS SQL desktop; non un profilo Firefox o un percorso Snap')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Registra esplicitamente il solo modulo CIE')
    mode.add_argument('--remove', action='store_true', help='Rimuove la sola registrazione CIE corrispondente')
    args = parser.parse_args()
    database = args.database or default_database(Path.home(), os.environ.get('XDG_DATA_HOME'))
    try:
        result = configure(args.module, database,
                           action='apply' if args.apply else 'remove' if args.remove else 'plan')
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, str(error) + '\n')
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
