"""HTTP contract tests: real PHP endpoints, OAuth/session/CSRF and a local MAL fixture.

No credentials are read and no real MAL account is modified.
"""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.cookiejar,json,os,re,shutil,socket,sqlite3,subprocess,tempfile,threading,time,unittest,urllib.error,urllib.parse,urllib.request

ROOT=Path(__file__).resolve().parents[2]
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args):return None

class Fixture(BaseHTTPRequestHandler):
    records=[];patches=[];chapters=0;status='plan_to_read';token_calls=0
    def log_message(self,*args):pass
    def respond(self,data,status=200):
        raw=json.dumps(data).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        type(self).records.append(('GET',self.path))
        if self.path=='/profile':return self.respond({'id':7,'name':'MangaTester'})
        node={'id':2,'title':'Berserk fixture','num_chapters':100,'status':'finished','main_picture':{},'my_list_status':{'status':self.status,'num_chapters_read':self.chapters}}
        if self.path.startswith('/manga-search?'):return self.respond({'data':[{'node':node}]})
        if self.path.startswith('/manga:2?'):return self.respond(node)
        return self.respond({'error':'not found'},404)
    def do_POST(self):
        values=urllib.parse.parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode());type(self).records.append(('POST',self.path))
        if self.path=='/token':
            if values.get('grant_type')==['refresh_token'] and values.get('refresh_token')!=['fixture-refresh-token-'+str(self.token_calls)]:
                return self.respond({'error':'invalid_grant'},400)
            type(self).token_calls+=1
            assert 'client_secret' in values
            return self.respond({'access_token':'fixture-access-token','refresh_token':'fixture-refresh-token-'+str(self.token_calls),'token_type':'bearer','expires_in':30})
        return self.respond({},404)
    def do_PATCH(self):
        values=urllib.parse.parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode());type(self).records.append(('PATCH',self.path))
        if self.path!='/manga-list-status:2':return self.respond({},404)
        assert set(values)=={'status','num_chapters_read'}
        type(self).patches.append(values);type(self).chapters=int(values['num_chapters_read'][0]);type(self).status=values['status'][0]
        return self.respond({'num_chapters_read':self.chapters,'status':self.status,'score':8,'num_volumes_read':3})

class TestMangaBridge(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='yomashi-mal-');cls.folder=Path(cls.temp.name)
        (cls.folder/'private').mkdir()
        shutil.copy(ROOT/'test/backend/host_bootstrap.php',cls.folder/'private/app.php')
        for source in (ROOT/'server').rglob('*.php'):
            target=cls.folder/source.relative_to(ROOT/'server');target.parent.mkdir(exist_ok=True,parents=True);shutil.copy(source,target)
        (cls.folder/'mal-callback.php').write_text("<?php define('SEASON_BOOTSTRAPPED',true);require __DIR__.'/private/app.php';require __DIR__.'/private/yomashi-mal.php';ys_callback_page();",encoding='utf-8')
        cls.mock=ThreadingHTTPServer(('127.0.0.1',0),Fixture);threading.Thread(target=cls.mock.serve_forever,daemon=True).start()
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env={**os.environ,'YS_TEST_DB':str(cls.folder/'fixture.sqlite'),'YS_TEST_MOCK':f'http://127.0.0.1:{cls.mock.server_port}'}
        cls.log=open(cls.folder/'php.log','wb');cls.php=subprocess.Popen(['php','-S',f'127.0.0.1:{port}','-t',str(cls.folder)],env=env,stdout=cls.log,stderr=cls.log)
        cls.base=f'http://127.0.0.1:{port}/'
        cls.opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),NoRedirect())
        for _ in range(100):
            try:urllib.request.urlopen(cls.base,timeout=.3);break
            except urllib.error.HTTPError as e:e.close();break
            except OSError:time.sleep(.05)
        cls.token=None
    @classmethod
    def tearDownClass(cls):
        cls.php.terminate();cls.php.wait(timeout=10);cls.mock.shutdown();cls.mock.server_close();cls.log.close()
        cls.temp.cleanup()
    def request(self,path='yomashi-api.php',payload=None,token=None,form=False):
        data=None;headers={}
        if payload is not None:
            data=(urllib.parse.urlencode(payload) if form else json.dumps(payload)).encode();headers['Content-Type']='application/x-www-form-urlencoded' if form else 'application/json'
        if token:headers['Authorization']='Bearer '+token
        request=urllib.request.Request(self.base+path,data=data,headers=headers)
        try:r=self.opener.open(request,timeout=10)
        except urllib.error.HTTPError as e:r=e
        raw=r.read()
        return r.status,raw,r.headers
    def test_complete_manga_authorization_and_updates(self):
        code,raw,_=self.request(payload={'action':'start'});self.assertEqual(code,200,raw)
        pair=json.loads(raw);token=pair['device_token'];device=pair['device_id']
        self.assertNotIn('client_secret',raw.decode());self.assertNotIn('access_token',raw.decode())
        self.assertEqual(self.request(payload={'action':'status'})[0],401)
        self.assertEqual(self.request()[0],405)
        status,raw,_=self.request('yomashi-connect.php?device='+device);self.assertEqual(status,200)
        csrf=re.search(rb'name="csrf" value="([a-f0-9]+)"',raw)[1].decode()
        self.assertEqual(self.request('yomashi-connect.php',{'device':device,'csrf':'bad'},form=True)[0],403)
        status,raw,headers=self.request('yomashi-connect.php',{'device':device,'csrf':csrf},form=True);self.assertEqual(status,303,raw)
        params=urllib.parse.parse_qs(urllib.parse.urlparse(headers['Location']).query)
        self.assertEqual(params['code_challenge_method'],['plain']);self.assertNotIn('client_secret',headers['Location'])
        state=params['state'][0]
        self.assertEqual(self.request('mal-callback.php?state=ys_wrong&code=fixture')[0],400)
        status,raw,_=self.request('mal-callback.php?'+urllib.parse.urlencode({'state':state,'code':'fixture'}));self.assertEqual(status,200,raw)
        self.assertNotIn(b'fixture-access-token',raw)
        status,raw,_=self.request(payload={'action':'status'},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['profile']['id'],7)
        conn=sqlite3.connect(self.folder/'fixture.sqlite');cipher=conn.execute('SELECT tokens FROM sa1_yomashi_devices WHERE id=?',(device,)).fetchone()[0];conn.close()
        self.assertNotIn('fixture-access-token',cipher);self.assertNotIn('fixture-refresh-token',cipher)
        status,raw,_=self.request(payload={'action':'search','query':'Berserk'},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['items'][0]['id'],2)
        self.assertGreaterEqual(Fixture.token_calls,2) # Expires-in=30 exercises refresh.
        # A refresh followed by a failed lookup must retain the rotated token.
        self.assertEqual(self.request(payload={'action':'detail','id':404},token=token)[0],404)
        self.assertEqual(self.request(payload={'action':'search','query':'Berserk'},token=token)[0],200)
        for state_to_preserve in ['on_hold','dropped']:
            Fixture.status=state_to_preserve
            status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':100,'status':'reading','automatic':True},token=token)
            self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['manga']['status'],state_to_preserve)
        Fixture.status='plan_to_read';Fixture.chapters=0
        status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':30,'status':'reading','owner_id':7},token=token);self.assertEqual(status,200,raw)
        status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':10,'status':'reading','automatic':True,'owner_id':7},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['manga']['chapters_read'],30)
        self.assertEqual(self.request(payload={'action':'update','id':2,'chapters_read':31,'status':'reading','owner_id':8},token=token)[0],409)
        status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':100,'status':'reading','automatic':True},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['manga']['status'],'completed')
        before=len(Fixture.patches)
        for changes in [{'chapters_read':101},{'chapters_read':-1},{'status':'watching'},{'id':0}]:
            self.assertEqual(self.request(payload={'action':'update','id':2,'chapters_read':40,'status':'reading',**changes},token=token)[0],422)
        self.assertEqual(len(Fixture.patches),before)
        self.assertTrue(all('anime' not in path for method,path in Fixture.records))
        self.assertEqual(self.request(payload={'action':'disconnect'},token=token)[0],200)
        self.assertEqual(self.request(payload={'action':'status'},token=token)[0],401)
        self.assertEqual(self.request('mal-callback.php?'+urllib.parse.urlencode({'state':state,'code':'fixture'}))[0],400)
        status,raw,_=self.request(payload={'action':'start'});pair=json.loads(raw)
        conn=sqlite3.connect(self.folder/'fixture.sqlite');conn.execute('UPDATE sa1_yomashi_devices SET expires_at=0 WHERE id=?',(pair['device_id'],));conn.commit();conn.close()
        self.assertEqual(self.request(payload={'action':'status'},token=pair['device_token'])[0],401)

if __name__=='__main__':unittest.main(verbosity=2)
