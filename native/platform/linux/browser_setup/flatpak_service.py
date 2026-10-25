#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Session-activated host companion. Install never starts it or configures NSS."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import pwd
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parent))
from flatpak_helper import Companion, SetupError, MAX_REQUEST

BUS = 'it.giancarloezza.FirmaConCIE.BrowserHelper1'
PATH = '/it/giancarloezza/FirmaConCIE/BrowserHelper1'
XML = """<node><interface name='it.giancarloezza.FirmaConCIE.BrowserHelper1'>
<method name='Request'><arg name='request' type='s' direction='in'/>
<arg name='response' type='s' direction='out'/></method></interface></node>"""


class Service:
    def __init__(self, connection, companion):
        from gi.repository import Gio, GLib
        self.connection, self.companion = connection, companion
        self.executor = ThreadPoolExecutor(max_workers=1)
        self.lock, self.pending = threading.Lock(), set()
        self.info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.registration = connection.register_object(PATH, self.info.interfaces[0], self.request, None, None)

    def reply(self, invocation, value):
        from gi.repository import GLib
        invocation.return_value(GLib.Variant('(s)', (json.dumps(value, ensure_ascii=False),)))

    def request(self, connection, sender, path, interface, method, parameters, invocation):
        from gi.repository import Gio, GLib
        try:
            uid = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                'org.freedesktop.DBus', 'GetConnectionUnixUser', GLib.Variant('(s)', (sender,)),
                GLib.VariantType.new('(u)'), Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
            if uid != os.getuid() or os.geteuid() == 0:
                raise SetupError('unsupported_user')
            if method != 'Request':
                raise SetupError('invalid_request')
            raw = parameters.unpack()[0]
            if len(raw.encode()) > MAX_REQUEST:
                raise SetupError('invalid_request')
            request = json.loads(raw)
            Companion.validate(request)
            with self.lock:
                if sender in self.pending or len(self.pending) >= 8:
                    raise SetupError('configuration_busy')
                self.pending.add(sender)
        except SetupError as error:
            self.reply(invocation, dict(ok=False, code=str(error)))
            return
        except Exception:
            self.reply(invocation, dict(ok=False, code='invalid_request'))
            return

        def work():
            try:
                value = self.companion.request(sender, request)
            except SetupError as error:
                value = dict(ok=False, code=str(error))
            except Exception:
                # Do not expose paths, profile contents or certificate data.
                value = dict(ok=False, code='configuration_unavailable')
            def finish():
                with self.lock:
                    self.pending.discard(sender)
                self.reply(invocation, value)
                return False
            GLib.idle_add(finish)
        self.executor.submit(work)


def main():
    from gi.repository import Gio, GLib
    if os.geteuid() == 0:
        raise SystemExit('Run the browser companion in the user session.')
    companion = Companion(Path(pwd.getpwuid(os.getuid()).pw_dir), Path(__file__).resolve().parent.parent)
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    # Export the object before claiming the activatable name. D-Bus may route
    # the queued first call immediately after RequestName succeeds.
    service = Service(connection, companion)
    try:
        result = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'RequestName', GLib.Variant('(su)', (BUS, 4)),
            GLib.VariantType.new('(u)'), Gio.DBusCallFlags.NONE, 1000, None)
        if result.unpack()[0] != 1:
            return
        loop = GLib.MainLoop()
        connection.connect('closed', lambda *_: GLib.idle_add(loop.quit))
        if not connection.is_closed():
            loop.run()
    finally:
        connection.unregister_object(service.registration)
        service.executor.shutdown(wait=True)


if __name__ == '__main__':
    main()
