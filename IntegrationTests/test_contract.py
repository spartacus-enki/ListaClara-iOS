"""Exercise the EXISTING backend code using an ephemeral database only.
Never import server/app.py against its default database. No production HTTP calls.
Run with the existing server venv, PYTHONDONTWRITEBYTECODE=1.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
import asyncio
import httpx
import anyio.to_thread

# The SPARTA execution sandbox stalls cross-thread event-loop wakeups.
# Test-only inline executor: preserves ASGI routing/validation/auth/middleware,
# but does NOT test threadpool scheduling or real HTTP concurrency.
if os.environ.get('LISTACLARA_INLINE_TEST_EXECUTOR') == '1':
    async def inline_executor(func, *args, **kwargs):
        return func(*args)
    anyio.to_thread.run_sync = inline_executor

class ASGIClient:
    def __init__(self, app): self.app = app
    def request(self, method, path, **kwargs):
        async def send():
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app), base_url="http://testserver", timeout=10) as client:
                return await client.request(method, path, **kwargs)
        return asyncio.run(send())
    def post(self, path, **kwargs): return self.request("POST", path, **kwargs)

ANDROID = Path(os.environ.get('LISTACLARA_ANDROID_SOURCE', '/home/dexanox/Servicios/TaskFamily/ListaClara')).resolve()
TEMP = tempfile.TemporaryDirectory(prefix='listaclara-ios-contract-')
os.environ['LISTACLARA_DB'] = str(Path(TEMP.name) / 'test.sqlite3')
os.environ['PUBLIC_ORIGIN'] = 'http://testserver'
assert Path(os.environ['LISTACLARA_DB']).parent == Path(TEMP.name)
spec = importlib.util.spec_from_file_location('ios_contract_backend', ANDROID / 'server/app.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

class ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = ASGIClient(backend.app)
        cls.family = 'ios-test-family'
        with backend.db(True) as c:
            c.execute('INSERT INTO families VALUES (?,?,?)', (cls.family, 'Test family', 0))
        cls.parent = backend.create_user('ios-parent', 'test-password-12345', 'padre', cls.family)['id']
        cls.child = backend.create_user('ios-child', 'test-password-12345', 'hijo', cls.family)['id']
        cls.other = backend.create_user('ios-other', 'test-password-12345', 'user')['id']
        cls.headers = {}
        for name in ['ios-parent', 'ios-child', 'ios-other']:
            r = cls.client.post('/api/v1/auth/login', json={'username': name, 'password': 'test-password-12345', 'client': 'android'})
            assert r.status_code == 200, r.text
            cls.headers[name] = {'Authorization': 'Bearer ' + r.json()['token']}
    def request(self, method, path, who='ios-parent', **kwargs):
        return self.client.request(method, '/api/v1' + path, headers=self.headers[who], **kwargs)
    def mutation(self, kind, rid, data, version=0, op=None):
        return {'opId': op or rid.replace('~', '-') + '-op-' + str(version), 'kind': kind, 'id': rid, 'baseVersion': version, 'data': data}
    def test_01_login_bearer_alias_and_protocol(self):
        response = self.request('GET', '/auth/me').json()
        self.assertEqual(response['protocol'], 1)
        self.assertEqual(response['id'], self.parent)
        r = self.client.post('/api/v1/auth/login', json={'username': 'ios-parent', 'password': 'test-password-12345', 'client': 'ios'})
        self.assertEqual(r.status_code, 422)
    def test_02_record_roundtrip_conflict_idempotency_tombstone(self):
        data = {'name': 'Compras iPhone', 'category': 'Compras', 'color': 0, 'icon': '🛒', 'kind': 'SHOPPING', 'reminderAt': None,
                'items': [{'id': 'item-ios', 'name': 'Leche', 'quantity': 2, 'unit': 'L', 'completed': False, 'position': 0}]}
        body = self.mutation('list', 'roundtrip', data)
        one = self.request('POST', '/mutations', json=body)
        self.assertEqual(one.status_code, 200, one.text)
        self.assertFalse(one.json()['conflict'])
        self.assertEqual(one.json(), self.request('POST', '/mutations', json=body).json())
        conflict = self.request('POST', '/mutations', json=self.mutation('list', 'roundtrip', {**data, 'name': 'Android concurrent'}, op='concurrent')).json()
        self.assertTrue(conflict['conflict'])
        self.assertEqual(conflict['record']['data']['name'], 'Compras iPhone')
        deleted = self.request('POST', '/mutations', json=self.mutation('list', 'roundtrip', None, version=1)).json()
        self.assertIsNone(deleted['record']['data']); self.assertEqual(deleted['record']['version'], 2)
        self.assertEqual(self.request('GET', '/records/list/roundtrip', who='ios-child').status_code, 404)
    def test_03_all_synced_payloads_and_event_revision(self):
        event = {'title': 'Medicina', 'note': '', 'start': 1794848400000, 'repeat': 'WEEKLY', 'hours': 8, 'days': None, 'weekdays': [1,3,5], 'times': ['23:59'], 'zone': 'America/Mexico_City', 'voice': True, 'enabled': True, 'revision': 'rev-1'}
        r = self.request('POST', '/mutations', json=self.mutation('event', 'event-ios', event)).json()
        self.assertFalse(r['conflict']); self.assertNotEqual(r['record']['data']['times'], ['23:59'])
        invalid = self.request('POST', '/mutations', json=self.mutation('event', 'event-ios', {**event, 'title': 'Changed'}, version=1))
        self.assertEqual(invalid.status_code, 422)
        for kind, rid, data in [
            ('categories', 'catalog', {'names': ['Compras','Tareas','Revisiones']}),
            ('occurrence', 'event-ios~1794848400000', {'eventId': 'event-ios', 'at': 1794848400000, 'revision': 'rev-1', 'status': 'DONE', 'silenced': False})]:
            r = self.request('POST', '/mutations', json=self.mutation(kind, rid, data))
            self.assertEqual(r.status_code, 200, r.text)
    def test_04_paginated_change_feed_and_restore_guard(self):
        for index in range(3):
            r = self.request('POST', '/mutations', json=self.mutation('list', f'page-list-{index}', {'name': f'Page {index}', 'category': 'General', 'color': 0, 'icon': '', 'kind': 'TASKS', 'reminderAt': None, 'items': []}))
            self.assertEqual(r.status_code, 200)
        cursor = 0; keys = []; more = True
        while more:
            page = self.request('GET', f'/changes?cursor={cursor}&limit=1').json()
            if page['hasMore']: self.assertGreater(page['cursor'], cursor)
            cursor = page['cursor']; more = page['hasMore']; keys.extend(r['kind'] for r in page['records'])
        self.assertTrue(keys)
        self.assertEqual(self.request('GET', '/changes?cursor=999999999').status_code, 409)
        self.assertEqual(self.request('GET', '/changes', who='ios-other').json()['records'], [])
    def test_05_family_permissions_completion_recurrence_history(self):
        self.assertEqual(self.request('GET', '/family/current').json()['family']['id'], self.family)
        created = self.request('POST', '/family/tasks', json={'id': 'task-ios', 'title': 'Limpiar', 'note': '', 'assignedTo': self.child, 'dueAt': 1794848400000, 'repeat': 'WEEKLY', 'priority': 'HIGH'})
        self.assertEqual(created.status_code, 201, created.text)
        self.assertEqual(self.request('DELETE', '/family/tasks/task-ios', who='ios-child').status_code, 403)
        self.assertEqual(self.request('POST', '/family/tasks/task-ios/complete', who='ios-other', json={'status': 'DONE'}).status_code, 400)
        self.assertEqual(self.request('POST', '/family/tasks/task-ios/complete', who='ios-child', json={'status': 'DONE'}).status_code, 200)
        count = len(self.request('GET', '/family/tasks?scope=all').json()['tasks'])
        self.request('POST', '/family/tasks/task-ios/complete', who='ios-child', json={'status': 'DONE'})
        self.assertEqual(len(self.request('GET', '/family/tasks?scope=all').json()['tasks']), count)
        tasks = self.request('GET', '/family/tasks?scope=all').json()['tasks']
        self.assertTrue(any(t['status']=='DONE' for t in tasks)); self.assertTrue(any(t['status']=='PENDING' for t in tasks))
        self.assertEqual(self.request('GET', '/chismografo/stats?year=2026&month=11').status_code, 200)
        r = self.request('PUT', '/family/tasks/task-ios', json={'clearDueAt': True})
        self.assertIsNone(r.json()['dueAt'])
    def test_06_native_clients_cannot_use_web_admin(self):
        self.assertEqual(self.request('GET', '/admin/users').status_code, 403)
    def test_07_payload_fixtures_match_swift_keys(self):
        root = Path(__file__).resolve().parents[1]
        swift = (root/'Sources/App/Editors.swift').read_text()
        for key in backend.ListData.model_fields:
            self.assertIn('"'+key+'"', swift)
        for key in backend.EventData.model_fields:
            self.assertIn('"'+key+'"', swift)
        self.assertIn('"client": .string("android")', (root/'Sources/Core/API.swift').read_text())

if __name__ == '__main__':
    print('Backend source SHA256:', hashlib.sha256((ANDROID/'server/app.py').read_bytes()).hexdigest())
    print('Database: disposable temporary test database; no network or production database access')
    unittest.main(verbosity=2)
