#!py

def run():
    ret = {}
    dhcp = False
    domain = __salt__['pillar.get']('dns:domains')[0]
    # TODO: check is opts[id] contains dots first
    if domain not in __opts__['id']:
        fqdn = __opts__['id'] + '.' + domain 
    else:
        fqdn = __opts__['id']

    interfaces = salt['pillar.get']('interfaces') 
    if len(interfaces.keys()) == 1:
       iface, settings = interfaces.items()[0] 
    elif len(interfaces.keys()) > 1:
       for iface, settings in interfaces.items():
            if settings.has_key('default_gw') or \
                    settings.has_key('primary'):
                break
            # We just wanted this list to be filtered.
            # networking.config would break anyway if 
            # there's more than one iface with 'default_gw'.
            # The 'primary' key is a legacy thing.

    ips = [] 
    if settings.has_key('ipv4'):
        ipv4 = settings['ipv4'].split('/')[0] 
        ips += [ipv4]
        if ipv4 == 'dhcp':
            dhcp = True
    
    if settings.has_key('ipv6'):
        ipv6 = settings['ipv6'].split('/')[0] 
        ips += [ipv6]

    if not dhcp:
        ret['fqdn in /etc/hosts'] = {
            'host.present': [
                {'ip': ips},
                {'names': [
                        fqdn,
                        __salt__['grains.get']('nodename')
                    ]
                }
            ]
        }

        if __grains__['os'] == 'Ubuntu':
            ret['no 127.0.1.1 in /etc/hosts'] = {
                'host.absent': [
                    {'names': [
                        __grains__['nodename'],
                        fqdn,
                        ]},
                    {'ip': '127.0.1.1'}
                ]
            }
    else: 
        ret['no 127.0.1.1 in /etc/hosts'] = {
            'host.present': [
                {'name': __grains__['nodename']},
                {'ip': '127.0.1.1'}
            ]
        }
    
    for host_id, details in salt['pillar.get']('hosts', {}).items():
        if not details.has_key('names'):
            names = host_id
        else:
            names = details['names'] 
        ret[host_id + ' in /etc/hosts'] = {
            'host.present': [
                {'names': names},
                {'ip': details['ips']}
            ]
        }
    return ret
