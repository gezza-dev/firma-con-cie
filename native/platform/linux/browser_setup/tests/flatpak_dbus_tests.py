#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Run under dbus-run-session in an isolated build root with synthetic HOME."""
import json
import os
from pathlib import Path
import sys
import threading
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from gi.repository import Gio, GLib
from flatpak_service import Service,BUS,PATH
import flatpak_helper_tests as fixtures

class IPC(unittest.TestCase):
    def setUp(self):
        # Tests never instantiate the production service's main/home discovery.
        self.fixture=fixtures.Policy('test_readonly_health_inspection_plan_no_subprocess_or_changes')
        self.fixture.setUp();self.addCleanup(self.fixture.doCleanups)
        self.server=self.connection();self.clients=[]
        self.server.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus',
            'RequestName',GLib.Variant('(su)',(BUS,4)),GLib.VariantType.new('(u)'),Gio.DBusCallFlags.NONE,1000,None)
        self.service=Service(self.server,self.fixture.companion)
        self.loop=GLib.MainLoop();self.thread=threading.Thread(target=self.loop.run);self.thread.start()
        self.client=self.connection();self.clients.append(self.client)
        self.addCleanup(self.stop)
    def connection(self):
        return Gio.DBusConnection.new_for_address_sync(os.environ['DBUS_SESSION_BUS_ADDRESS'],
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT|Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,None,None)
    def stop(self):
        self.server.unregister_object(self.service.registration);self.service.executor.shutdown(wait=True)
        self.loop.quit();self.thread.join(5)
        for connection in [*self.clients,self.server]:connection.close_sync(None)
    def request(self,operation,client=None,**kwargs):
        raw=json.dumps(dict(protocol=1,op=operation,certificates=self.fixture.certificates,**kwargs))
        result=(client or self.client).call_sync(BUS,PATH,BUS,'Request',GLib.Variant('(s)',(raw,)),
            GLib.VariantType.new('(s)'),Gio.DBusCallFlags.NONE,10000,None)
        return json.loads(result.unpack()[0])
    def test_health_readonly_inspect_and_explicit_registration(self):
        before=self.fixture.snapshot(self.fixture.home)
        self.assertTrue(self.request('status')['fullPinRequired'])
        self.assertEqual(self.request('firefox.inspect')['profiles'][0]['state'],'needs_setup')
        self.assertEqual(self.request('chrome.inspect')['state'],'not_installed')
        self.assertEqual(before,self.fixture.snapshot(self.fixture.home))
        identity=self.fixture.identity();plan=self.request('firefox.plan',profile=identity)
        self.assertTrue(self.request('firefox.apply',profile=identity,fingerprint=plan['fingerprint'])['ok'])
        self.assertEqual(self.request('firefox.apply',profile=identity,fingerprint=plan['fingerprint'])['code'],'plan_changed')
        self.assertEqual(self.request('firefox.inspect')['profiles'][0]['state'],'configured')
    def test_other_connection_cannot_use_plan_and_forbidden_fields_rejected(self):
        identity=self.fixture.identity();plan=self.request('firefox.plan',profile=identity)
        other=self.connection();self.clients.append(other)
        self.assertEqual(self.request('firefox.apply',client=other,profile=identity,fingerprint=plan['fingerprint'])['code'],'plan_changed')
        self.assertEqual(self.request('status',pin='NEVER A REAL PIN')['code'],'invalid_request')
        self.assertEqual(self.request('status',path='/arbitrary/host/path')['code'],'invalid_request')
        self.assertFalse(self.fixture.commands)

if __name__=='__main__':unittest.main(verbosity=2)
