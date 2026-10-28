<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }

// Uses the host's existing private MAL configuration. No app secret is sent to Android.
const YS_ORIGIN = 'https://hk-br035.gt.tc/seasonav1/';
const YS_STATUSES = ['reading','completed','on_hold','dropped','plan_to_read'];
function ys_schema(PDO $db): void {
  $db->exec('CREATE TABLE IF NOT EXISTS sa1_yomashi_devices (id VARCHAR(64) PRIMARY KEY, token_hash VARCHAR(64) NOT NULL UNIQUE, tokens TEXT NULL, mal_user_id BIGINT NULL, mal_name VARCHAR(60) NULL, expires_at BIGINT NOT NULL, created_at BIGINT NOT NULL)');
}
function ys_id(mixed $input): int {
  if (!is_int($input) || $input<1 || $input>999999999) throw new WebError('ID de manga inválido.');
  return $input;
}
function ys_crypt(string $input, string $device, bool $decrypt=false): string {
  $key=base64_decode(mal_require_config()['encryption_key'],true);
  if($decrypt) {
    $raw=base64_decode($input,true);
    $result=$raw && strlen($raw)>28?openssl_decrypt(substr($raw,28),'aes-256-gcm',$key,OPENSSL_RAW_DATA,substr($raw,0,12),substr($raw,12,16),'YomaShi:'.$device):false;
  } else {
    $iv=random_bytes(12);$tag='';
    $cipher=openssl_encrypt($input,'aes-256-gcm',$key,OPENSSL_RAW_DATA,$iv,$tag,'YomaShi:'.$device);
    $result=$cipher===false?false:base64_encode($iv.$tag.$cipher);
  }
  if($result===false) throw new WebError('Vuelve a conectar MyAnimeList.',401);
  return $result;
}
function ys_start(PDO $db): array {
  mal_require_config();ys_schema($db);
  rate($db,'ys-pair-ip:'.hash('sha256',(string)($_SERVER['REMOTE_ADDR']??'')),6,600);
  rate($db,'ys-pair-global',100,3600);
  sql($db,'DELETE FROM sa1_yomashi_devices WHERE expires_at<?',[time()]);
  $id=bin2hex(random_bytes(16));$token=bin2hex(random_bytes(32));$expires=time()+600;
  sql($db,'INSERT INTO sa1_yomashi_devices (id,token_hash,expires_at,created_at) VALUES (?,?,?,?)',[$id,hash('sha256',$token),$expires,time()]);
  return ['device_id'=>$id,'device_token'=>$token,'connect_url'=>YS_ORIGIN.'yomashi-connect.php?device='.$id,'expires_at'=>$expires,'code'=>strtoupper(substr($id,0,6))];
}
function ys_begin(PDO $db,string $id): string {
  if(!preg_match('/^[a-f0-9]{32}$/D',$id)) throw new WebError('Conexión inválida.');
  ys_schema($db);$row=sql($db,'SELECT id FROM sa1_yomashi_devices WHERE id=? AND expires_at>? AND tokens IS NULL',[$id,time()])->fetch();
  if(!$row) throw new WebError('La conexión caducó. Iníciala otra vez desde YomaShi.',410);
  $config=mal_require_config();$state='ys_'.bin2hex(random_bytes(24));$verifier=bin2hex(random_bytes(48));
  $_SESSION['yomashi_oauth']=['device'=>$id,'state'=>$state,'verifier'=>$verifier,'issued_at'=>time()];
  return 'https://myanimelist.net/v1/oauth2/authorize?'.http_build_query(['response_type'=>'code','client_id'=>$config['client_id'],'redirect_uri'=>$config['redirect_uri'],'state'=>$state,'code_challenge'=>$verifier,'code_challenge_method'=>'plain'],'','&',PHP_QUERY_RFC3986);
}
function ys_complete(PDO $db,array $query): array {
  $flow=$_SESSION['yomashi_oauth']??null;
  if(!is_array($flow) || !is_string($query['state']??null) || !hash_equals($flow['state'],$query['state'])) throw new WebError('La autorización no corresponde a esta conexión.',400);
  unset($_SESSION['yomashi_oauth']);
  if(time()-$flow['issued_at']>600 || isset($query['error'])) throw new WebError('Autorización cancelada o caducada.',410);
  $code=$query['code']??null;
  if(!is_string($code) || strlen($code)<1 || strlen($code)>4096) throw new WebError('Código de autorización inválido.',400);
  $config=mal_require_config();
  $tokens=mal_tokens(mal_http('token',['grant_type'=>'authorization_code','client_id'=>$config['client_id'],'client_secret'=>$config['client_secret'],'redirect_uri'=>$config['redirect_uri'],'code'=>$code,'code_verifier'=>$flow['verifier']]));
  $profile=mal_profile_data(mal_http('profile',[],$tokens['access_token']));
  $cipher=ys_crypt(json_encode($tokens,JSON_THROW_ON_ERROR),$flow['device']);
  $changed=sql($db,'UPDATE sa1_yomashi_devices SET tokens=?,mal_user_id=?,mal_name=?,expires_at=? WHERE id=? AND tokens IS NULL AND expires_at>?',[$cipher,$profile['id'],$profile['name'],time()+90*86400,$flow['device'],time()])->rowCount();
  if($changed!==1) throw new WebError('La conexión caducó. Vuelve a iniciarla en YomaShi.',410);
  return $profile;
}
function ys_callback_page(): never {
  try {
    if($_SERVER['REQUEST_METHOD']!=='GET') throw new WebError('Método no permitido.',405);
    ys_complete(db(),$_GET);$message='Cuenta conectada. Vuelve a YomaShi para continuar.';
  } catch(WebError $e) { http_response_code($e->status);$message=$e->getMessage(); }
  catch(Throwable $e) { http_response_code(502);$message='No se pudo conectar MyAnimeList. Vuelve a intentarlo desde YomaShi.'; }
  header('Content-Type: text/html; charset=utf-8');header('Referrer-Policy: no-referrer');
  echo '<!doctype html><html lang="es"><meta name="viewport" content="width=device-width"><title>YomaShi</title><body><h1>YomaShi · MyAnimeList</h1><p>'.htmlspecialchars($message,ENT_QUOTES,'UTF-8').'</p></body></html>';exit;
}
function ys_normalize(array $m): array {
  $id=ys_id($m['id']??null);$title=$m['title']??null;
  if(!is_string($title) || $title==='') throw new MalRemoteError(502);
  $state=$m['my_list_status']??[];
  return ['id'=>$id,'title'=>$title,'picture'=>(string)($m['main_picture']['medium']??''),'num_chapters'=>(int)($m['num_chapters']??0),'publishing_status'=>(string)($m['status']??''),'status'=>in_array($state['status']??'',YS_STATUSES,true)?$state['status']:'plan_to_read','chapters_read'=>max(0,(int)($state['num_chapters_read']??0))];
}
function ys_manga(string $token,int $id): array {
  return ys_normalize(mal_http('manga:'.$id,['fields'=>'id,title,main_picture,num_chapters,status,my_list_status{status,num_chapters_read}'],$token));
}
function ys_dispatch(PDO $db,array $input,string $bearer): array {
  ys_schema($db);$action=$input['action']??'';
  if($action==='start') return ys_start($db);
  if(!preg_match('/^[a-f0-9]{64}$/D',$bearer)) throw new WebError('Conecta tu cuenta de MyAnimeList.',401);
  // Reject bad inputs before a possible OAuth refresh with rotating credentials.
  if(!in_array($action,['status','disconnect','search','detail','update'],true)) throw new WebError('Operación no disponible.',404);
  if($action==='search' && (!is_string($input['query']??null) || strlen(trim($input['query']))<3 || strlen(trim($input['query']))>192)) throw new WebError('Escribe al menos tres caracteres o usa el ID.');
  if(in_array($action,['detail','update'],true)) ys_id($input['id']??null);
  if($action==='update' && (!is_int($input['chapters_read']??null) || $input['chapters_read']<0 || $input['chapters_read']>100000 || !in_array($input['status']??null,YS_STATUSES,true))) throw new WebError('Capítulos o estado inválidos.');
  rate($db,'ys-device:'.hash('sha256',$bearer),120,60);
  $refreshed=false;
  $db->beginTransaction();
  try {
    $row=sql($db,'SELECT * FROM sa1_yomashi_devices WHERE token_hash=? AND expires_at>?'.($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[hash('sha256',$bearer),time()])->fetch();
    if(!$row) throw new WebError('La conexión caducó. Vuelve a conectar MyAnimeList.',401);
    if($action==='disconnect') { sql($db,'DELETE FROM sa1_yomashi_devices WHERE id=?',[$row['id']]);$db->commit();return ['connected'=>false]; }
    if($action==='status') { $db->commit();return ['connected'=>$row['tokens']!==null,'profile'=>$row['tokens']!==null?['id'=>(int)$row['mal_user_id'],'name'=>$row['mal_name']]:null]; }
    if($row['tokens']===null) throw new WebError('Termina la autorización en el navegador.',409);
    if(isset($input['owner_id']) && $input['owner_id']!==(int)$row['mal_user_id']) throw new WebError('La cuenta cambió. Vuelve a seleccionar el manga.',409);
    $tokens=json_decode(ys_crypt($row['tokens'],$row['id'],true),true,16,JSON_THROW_ON_ERROR);
    if($tokens['expires_at']<time()+60) {
      $config=mal_require_config();
      $tokens=mal_tokens(mal_http('token',['grant_type'=>'refresh_token','client_id'=>$config['client_id'],'client_secret'=>$config['client_secret'],'refresh_token'=>$tokens['refresh_token']]),$tokens['refresh_token']);
      sql($db,'UPDATE sa1_yomashi_devices SET tokens=? WHERE id=?',[ys_crypt(json_encode($tokens,JSON_THROW_ON_ERROR),$row['id']),$row['id']]);
      $refreshed=true;
    }
    $token=$tokens['access_token'];
    if($action==='search') {
      $q=trim((string)($input['query']??''));
      if(strlen($q)<3 || strlen($q)>192) throw new WebError('Escribe al menos tres caracteres o usa el ID.');
      $results=mal_http('manga-search',['q'=>$q,'limit'=>10,'fields'=>'id,title,main_picture,num_chapters,status,my_list_status{status,num_chapters_read}'],$token);
      $result=['items'=>array_map(fn($e)=>ys_normalize($e['node']),$results['data']??[])];
    } elseif($action==='detail') $result=['manga'=>ys_manga($token,ys_id($input['id']??null))];
    elseif($action==='update') {
      $id=ys_id($input['id']??null);$chapters=$input['chapters_read']??null;$status=$input['status']??null;
      if(!is_int($chapters) || $chapters<0 || $chapters>100000 || !in_array($status,YS_STATUSES,true)) throw new WebError('Capítulos o estado inválidos.');
      $m=ys_manga($token,$id);
      if(($input['automatic']??false)===true) {
        $chapters=max($chapters,$m['chapters_read']);
        $status=in_array($m['status'],['completed','on_hold','dropped'],true)?$m['status']:'reading';
        if($status==='reading' && $m['publishing_status']==='finished' && $m['num_chapters']>0 && $chapters>=$m['num_chapters']) $status='completed';
      }
      if($m['num_chapters']>0 && $chapters>$m['num_chapters']) throw new WebError('El progreso supera los capítulos del manga en MAL. Comprueba el vínculo o ajusta el número.');
      $saved=mal_http('manga-list-status:'.$id,['status'=>$status,'num_chapters_read'=>$chapters],$token,'PATCH');
      $result=['manga'=>[...$m,'status'=>$saved['status'],'chapters_read'=>(int)$saved['num_chapters_read']]];
    } else throw new WebError('Operación no disponible.',404);
    $db->commit();return $result;
  } catch(Throwable $e) {
    if($e instanceof MalRemoteError && ($e->httpStatus===401 || $e->kind==='invalid_grant') && isset($row['id'])) {
      sql($db,'DELETE FROM sa1_yomashi_devices WHERE id=?',[$row['id']]);
      if($db->inTransaction())$db->commit();
      throw new WebError('La autorización de MyAnimeList caducó. Conecta tu cuenta otra vez.',401);
    }
    // The refresh token can be single-use. Keep its replacement even if a later
    // manga request fails; these transactions contain no other local mutations.
    if($db->inTransaction()) { if($refreshed)$db->commit();else $db->rollBack(); }
    throw $e;
  }
}
