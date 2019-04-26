#!py
"""
Py-renderer based state for openvswitch.init
"""
import yaml

def run(): 
    """
    Function generating the state-data for openvswitch.init
    """
    # TODO: Oh for the love of Giudo, use functions
    # and variables to reduce the nesting in here!
    map_yaml = \
    """
    default:
        pkg: openvswitch-switch
        service: openvswitch-switch
    """
    openvswitch = salt['grains.filter_by'](
        yaml.load(map_yaml),
        merge=salt['pillar.get']('openvswitch:lookup')
    )
    state = {'openvswitch': 
        {
            'pkg': 
                [ 
                    'installed',
                    {'name': openvswitch['pkg'] },
                ],
            'service':
                [
                    'running',
                    {'name': openvswitch['service'] },
                    {'enable': True},
                ],
        }
    }
    # On Ubuntu this module is only needed on 
    # releases previous to trusty/14.04:
    if salt['grains.get']('os') == 'Ubuntu' and \
            salt['grains.get']('osrelease') < 14.04:
        state['openvswitch']['kmod.present'] = [
            {'persist': True},
            {'require': 
                [
                    {'pkg': 'openvswitch-datapath-dkms'},
                ]
            }
        ]
        state['openvswitch-datapath-dkms'] = { 'pkg': 'installed' }

    br_pillar = salt['pillar.get']('openvswitch:bridges', {})
    interfaces = salt['network.interfaces']()
    for bridge, config in br_pillar.iteritems():
        br_state = 'configure {0}'.format(bridge)
        state[br_state] = { 
            'ovs_bridge.managed':
               [
                    {'name': bridge},
                    {'require': 
                        [
                            {'pkg': 'openvswitch-switch'},
                        ]
                    }
               ]
        }
        if 'clean' in config and config.clean:
            state[br_state]['ovs_bridge.managed'].append({'clean': True})
        
        if 'ports' in br_pillar[bridge]:
            state[br_state]['ovs_bridge.managed'].append(
                {'ports': 
                    br_pillar[bridge]['ports']
                })

        reuse_pillar = 'openvswitch:bridges:'+bridge+':reuse_netcfg'
        uplink_iface = salt['pillar.get'](reuse_pillar, False)
        if uplink_iface:
            netcfg = salt['pillar.get']('interfaces:{0}'.format(uplink_iface))
            #- require:
            #   - network: uplink_iface 
            #   - module: ovs_bridge
            if 'ipv4' in netcfg:
                state[br_state]['cmd.run'] = [
                    {'name': ('ip addr show {1} | grep {0} || ' +\
                             'ip addr add {0} dev {1}').format(
                                netcfg['ipv4'], bridge)},
                    {'require': [
                        {'ovs_bridge': br_state}
                        ]
                    },
                ]
                if 'default_gw' in netcfg and 'primary' in netcfg:
                    if netcfg['primary']:
                        gw_state = 'set gateway on {0}'.format(bridge)
                        state[gw_state] = {}
                        state[gw_state]['cmd.run'] = \
                            [
                                {'name': ('ip route change default via {0}'+ \
                                            ' || ip route add default via {0}'
                                            ).format(netcfg['default_gw'])
                                    }, 
                                # salt['network.interfaces']()[uplink_iface]
                                {'require': [
                                    {'cmd': br_state},
                                    ]
                                }
                            ]
                if uplink_iface in interfaces and \
                    'inet' in interfaces[uplink_iface]:
                    if netcfg['ipv4'].split('/')[0] == \
                        interfaces[uplink_iface]['inet'][0]['address']:
                        state['strip netcfg from {0}'.format(uplink_iface)] = \
                            {
                                'cmd.run':
                                    [
                                        {'name': 
                                            ('ip link set promisc on dev ' +\
                                            '{0} && ip addr del {1} dev {0}'
                                                ).format(
                                                    uplink_iface, 
                                                    netcfg['ipv4']) 
                                            },
                                        {'require': [
                                            {'ovs_bridge': br_state},
                                            {'cmd': br_state},
                                            ]}
                                    ]
                            }
    return state
