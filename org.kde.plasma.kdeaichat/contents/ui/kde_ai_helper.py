#!/usr/bin/env python3
import sys
import os
import json
import base64
import shutil
import subprocess
import configparser

def cmd_toggle_schedule(payload):
    p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    data = json.load(open(p)) if os.path.exists(p) else {'version': 1, 'schedules': []}
    if isinstance(data, list):
        data = {'version': 1, 'schedules': data}
    for s in data.get('schedules', []):
        if s.get('id') == payload['schedId']:
            s['enabled'] = payload['enabled']
            if payload['enabled']:
                s['nextRunAt'] = ''
    json.dump(data, open(p, 'w'), indent=2)

def cmd_update_schedule_history_status(payload):
    p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    if os.path.exists(p):
        try:
            data = json.load(open(p))
            history = data.setdefault('history', [])
            for entry in reversed(history):
                if entry.get('scheduleId') == payload['schedId']:
                    entry['status'] = payload['status']
                    break
            json.dump(data, open(p, 'w'), indent=2)
        except Exception:
            pass

def cmd_migrate_history(payload):
    old_p = os.path.expanduser(payload['oldFullPath']) if payload['oldFullPath'] else ''
    new_p = os.path.expanduser(payload['newFullPath']) if payload['newFullPath'] else ''
    current_b64 = payload['currentB64']
    res = {'status': 'ok', 'action': 'none'}
    try:
        if not new_p:
            if old_p and os.path.exists(old_p):
                res['action'] = 'load'
                res['content'] = base64.b64encode(open(old_p, 'rb').read()).decode('utf-8')
        else:
            folder = os.path.dirname(new_p)
            if folder:
                os.makedirs(folder, exist_ok=True)
            if os.path.exists(new_p):
                res['action'] = 'load'
                res['content'] = base64.b64encode(open(new_p, 'rb').read()).decode('utf-8')
            elif old_p and os.path.exists(old_p):
                shutil.copy2(old_p, new_p)
                res['action'] = 'copied'
            else:
                data = base64.b64decode(current_b64).decode('utf-8')
                with open(new_p, 'w', encoding='utf-8') as f:
                    f.write(data)
                res['action'] = 'exported'
    except Exception as e:
        res['status'] = 'error'
        res['message'] = str(e)
    print(base64.b64encode(json.dumps(res).encode('utf-8')).decode('utf-8'))

def cmd_write_history(payload):
    path = os.path.expanduser(payload['fullPath'])
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(base64.b64decode(payload['b64Str']).decode('utf-8'))
    print('OK')

def cmd_delete_session_schedules(payload):
    p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    if os.path.exists(p):
        try:
            data = json.load(open(p))
            if isinstance(data, dict):
                scheds = data.get('schedules', [])
                data['schedules'] = [s for s in scheds if s.get('chatId') != payload['sessionId']]
                json.dump(data, open(p, 'w'), indent=2)
        except Exception:
            pass

def cmd_poll_pending_triggers(payload):
    d = os.path.expanduser('~/.local/share/kdeaichat/pending')
    res = []
    if os.path.exists(d):
        for f in os.listdir(d):
            if f.endswith('.json'):
                p = os.path.join(d, f)
                try:
                    res.append(json.load(open(p)))
                    os.remove(p)
                except Exception:
                    pass
    ps = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    scheds = []
    if os.path.exists(ps):
        try:
            s_data = json.load(open(ps))
            scheds = s_data.get('schedules', []) if isinstance(s_data, dict) else s_data
        except Exception:
            pass
    print(json.dumps({'pending': res, 'schedules': scheds}))

def cmd_delete_schedule(payload):
    p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    data = json.load(open(p)) if os.path.exists(p) else {'version': 1, 'schedules': []}
    if isinstance(data, list):
        data = {'version': 1, 'schedules': data}
    data['schedules'] = [s for s in data.get('schedules', []) if s.get('id') != payload['schedId']]
    json.dump(data, open(p, 'w'), indent=2)

def cmd_add_schedule(payload):
    p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    data = json.load(open(p)) if os.path.exists(p) else {'version': 1, 'schedules': []}
    if isinstance(data, list):
        data = {'version': 1, 'schedules': data}
    data.setdefault('schedules', []).append(payload['entry'])
    json.dump(data, open(p, 'w'), indent=2)

def cmd_sync_config_keys(payload):
    path = os.path.expanduser(payload['configPath'])
    data = payload['keys']
    config = configparser.ConfigParser()
    config.optionxform = str
    if os.path.exists(path):
        config.read(path)
    if 'General' not in config:
        config['General'] = {}
    for k, v in data.items():
        config['General'][k] = str(v)
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, 'w') as f:
        config.write(f)

def cmd_clear_config_keys(payload):
    path = os.path.expanduser(payload['configPath'])
    keys = payload['keys']
    config = configparser.ConfigParser()
    config.optionxform = str
    if os.path.exists(path):
        config.read(path)
    if 'General' in config:
        for k in keys:
            config['General'].pop(k, None)
        with open(path, 'w') as f:
            config.write(f)

def cmd_load_config_keys(payload):
    path = os.path.expanduser(payload.get('configPath', '~/.config/kdeaichatrc'))
    config = configparser.ConfigParser()
    config.optionxform = str
    if os.path.exists(path):
        config.read(path)
    res = dict(config['General']) if 'General' in config else {}
    print(json.dumps(res))

def cmd_setup_scheduler_service(payload):
    src = os.path.expanduser(payload['srcPath'])
    dest = os.path.expanduser(payload['destPath'])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    os.makedirs(os.path.expanduser('~/.local/share/kdeaichat/results'), exist_ok=True)
    if os.path.exists(src):
        shutil.copy2(src, dest)
        os.chmod(dest, 0o755)
    sjson = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')
    if not os.path.exists(sjson):
        with open(sjson, 'w') as f:
            f.write('{"version":1,"schedules":[]}')
        os.chmod(sjson, 0o600)
    sdir = os.path.expanduser('~/.config/systemd/user')
    os.makedirs(sdir, exist_ok=True)
    sfile = sdir + '/kde-ai-scheduler.service'
    with open(sfile, 'w') as f:
        f.write(payload['serviceContent'])
    os.system('systemctl --user daemon-reload')
    if os.system('systemctl --user is-enabled kde-ai-scheduler.service >/dev/null 2>&1') == 0:
        print('AUTO_ENABLED')
    else:
        print('AUTO_DISABLED')

def cmd_save_all_schedules(payload):
    p = os.path.expanduser('~/.local/share/kdeaichat')
    os.makedirs(p, exist_ok=True)
    with open(os.path.join(p, 'schedules.json'), 'w', encoding='utf-8') as f:
        json.dump(payload, f, indent=2)
    print('SCHED_SAVE_OK')

def cmd_get_memory_usage(payload):
    def mem_kb(name):
        r = subprocess.run(['pgrep', '-f', name], capture_output=True, text=True)
        pids = r.stdout.strip().split()
        total = 0
        for pid in pids:
            try:
                with open(f'/proc/{pid}/status') as f:
                    for line in f:
                        if line.startswith('VmRSS:'):
                            total += int(line.split()[1])
            except:
                pass
        return total
    d = {
        'scheduler': mem_kb('kde-ai-scheduler'),
        'opencode': mem_kb('opencode')
    }
    print(json.dumps(d))

def cmd_export_chat(payload):
    path = os.path.expanduser(payload['filePath'])
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(base64.b64decode(payload['b64Content']).decode('utf-8'))
    print('OK')

def main():
    if len(sys.argv) < 2:
        print("Usage: kde_ai_helper.py <command> [b64payload]")
        sys.exit(1)
    
    command = sys.argv[1]
    payload = {}
    if len(sys.argv) > 2:
        try:
            payload = json.loads(base64.b64decode(sys.argv[2].encode('utf-8') if isinstance(sys.argv[2], str) else sys.argv[2]).decode('utf-8'))
        except Exception as e:
            print(f"Error parsing payload: {e}")
            sys.exit(1)
            
    commands = {
        'toggle_schedule': cmd_toggle_schedule,
        'update_schedule_history_status': cmd_update_schedule_history_status,
        'migrate_history': cmd_migrate_history,
        'write_history': cmd_write_history,
        'delete_session_schedules': cmd_delete_session_schedules,
        'poll_pending_triggers': cmd_poll_pending_triggers,
        'delete_schedule': cmd_delete_schedule,
        'add_schedule': cmd_add_schedule,
        'sync_config_keys': cmd_sync_config_keys,
        'clear_config_keys': cmd_clear_config_keys,
        'load_config_keys': cmd_load_config_keys,
        'setup_scheduler_service': cmd_setup_scheduler_service,
        'save_all_schedules': cmd_save_all_schedules,
        'get_memory_usage': cmd_get_memory_usage,
        'export_chat': cmd_export_chat
    }
    
    if command not in commands:
        print(f"Unknown command: {command}")
        sys.exit(1)
        
    try:
        commands[command](payload)
    except Exception as e:
        print(f"Error executing {command}: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
