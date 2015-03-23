#!py
"""
State gathering data from pillar[interfaces] and pillar[openvswitch]
to check which bridges already exist before passing network 
configuration data to the template for /etc/network/interfaces.
"""

from salt.exceptions import SaltInvocationError

# Helper functions:
def quaddot2int(quaddot):
    """
    Returns an integer for given quad-dotted IP
    """
    ip_bytes = quaddot.split('.')
    result  = int(ip_bytes[0]) << 24
    result += int(ip_bytes[1]) << 16
    result += int(ip_bytes[2]) <<  8
    result += int(ip_bytes[3])
    return result

def int2quaddot(num):
    """
    Returns a quad-dotted IP for given integer
    """
    # There's a prettier way to to this, right?
    byte_a = (num & 0xff000000) >> 24
    byte_b = (num & 0x00ff0000) >> 16
    byte_c = (num & 0x0000ff00) >>  8
    byte_d = (num & 0x000000ff)
    return '{0}.{1}.{2}.{3}'.format(byte_a, byte_b, byte_c, byte_d)

def netmask2prefixlen(netmask):
    '''
    Takes a netmask like '255.255.255.0'
    and returns a prefix length like '24'.
    '''
    netmask = netmask.split('.')
    bitmask = 0
    for idx in range(3, -1, -1):
        bitmask += int(netmask[idx]) << (idx * 8)
    prefixlen = format(bitmask, '0b').count('1')
    return '{0}'.format(prefixlen)

def prefixlen2netmask(prefixlen):
    """
    Returns prefix length for given IPv4 netmask
    """
    return int2quaddot( 2**32 - 2** ( 32 - int(prefixlen) ))

def cidr2broadcast(cidr):
    """
    Returns the broadcast address for given CIDR-IP.
    """
    netmask = prefixlen2netmask(cidr.split('/')[1])
    netmask_int = quaddot2int(netmask)
    addr_int = quaddot2int(cidr.split('/')[0]) 
    network_int = addr_int & netmask_int
    broadcast_int = network_int | (netmask_int ^ 0xFFFFFFFF)
    return int2quaddot(broadcast_int)

def cidr2network_options(cidr):
    """
    Return a dictionary with netmask, network, broadcast
    derivated from given IPv4 address in CIDR format.
    """
    options = {}
    try:
        netmask = prefixlen2netmask(cidr.split('/')[1])
    except IndexError:
        raise ValueError, "IPv4 address needs to be in" \
            + " CIDR format, i.e. 192.0.2.17/24"
    options['ipv4'] = cidr
    options['netmask'] = netmask
    options['network'] = "{0}/{1}".format(
        int2quaddot(
            quaddot2int(cidr.split('/')[0]) & quaddot2int(netmask)),
        cidr.split('/')[1])
    options['broadcast'] = cidr2broadcast(cidr)
    return options

# "Prepare pillar data for template" function:
def iface_settings(iface, set_gw = True):
    iface_pillar = salt['pillar.get'](
        'interfaces:{0}'.format(iface))
    settings = {}
    if iface_pillar.has_key('ipv4'):
        # don't do anything in this case so the
        # configuration will be set to DHCP
        if iface_pillar['ipv4'] == 'dhcp':
            settings['ipv4'] = 'dhcp'
        else:
            settings = cidr2network_options(iface_pillar['ipv4'])
            if set_gw:
                # if no 'default_gw' or default_gw is a True bool:
                if not iface_pillar.has_key('default_gw') or (\
                        isinstance(iface_pillar['default_gw'], bool) \
                        and iface_pillar['default_gw']
                    ):
                    # default to 1st IP of network as GW
                    subnet = settings['network'].split('/')[0]
                    subnet_int = quaddot2int(subnet)
                    gateway = int2quaddot(subnet_int + 1)
                    if gateway == iface_pillar['ipv4']:
                        raise ValueError, "Can't set the default route " + \
                            "to the same IP as configured on this interface"
                    settings['default_gw'] = gateway
                # if 'default_gw' is False bool:
                elif iface_pillar.has_key('default_gw') and \
                        not iface_pillar['default_gw']:
                    pass
                # if 'default_gw' is not a bool use its value:
                else:
                    if not isinstance(iface_pillar['default_gw'], bool):
                        try:
                            quaddot2int(iface_pillar['default_gw'])
                        except ValueError:
                            raise SaltInvocationError, "need QuadDot or Bool"
                    settings['default_gw'] = iface_pillar['default_gw']
                    
    if iface_pillar.has_key('comment'):
        settings['comment'] = iface_pillar['comment']

    return settings

# Actual state function:
def run():
    """
    Generate the states for networking.config.
    """
    state = {}
    # REWRITTEN:
    # 1st: Iterate over bridges and add the existing ones
    #      with config-data from their reuse_netcfg to the
    #      dict 'interfaces'.
    # 2nd: Iterate over interfaces and check which are not
    #      listed in a interfaces[bridge]['uplink']. 
    #      Add the remaining interfaces to the dict interfaces.

    # TODO: for bridges check uplink in ifs_w_gw.keys()

    pillar_interfaces = salt['pillar.get']('interfaces', False)
    # TODO: if not pillar_interfaces: exit; else: go on as usual
    if pillar_interfaces:
        ifs_dhcp = []
        ifs_w_gw = {}
        ifs_not_gw = []
        for iface, settings in salt['pillar.get']('interfaces').items():
            if settings.has_key('ipv4') and settings['ipv4'] == 'dhcp':
                ifs_dhcp += [iface]
            if settings.has_key('default_gw'):
                if settings['default_gw']:
                    ifs_w_gw[iface] = settings['default_gw']
                # Would cause a SaltInvocationError later:
                #elif iface in ifs_dhcp:
                #    pass
                else:
                    ifs_not_gw += [iface]
            # Only interfaces w/ default_gw = False should
            # get into this list at this point:
            #else: ifs_not_gw += [iface]

        # Works:
        if len(ifs_dhcp) > 1:
            # Would need a mechanism to keep the DHCP-client 
            # from setting the default route.
            raise SaltInvocationError, "More than one interface to " + \
                "configure for DHCP: {0}".format(ifs_dhcp)
         
        # Works:
        if len(ifs_w_gw.keys()) > 1:
            raise SaltInvocationError, "More than one interface to " + \
                "configure for default gateways: {0}".format(ifs_w_gw)

        # Check if default_gw is set on a DHCP-Interface:
        for iface in pillar_interfaces.keys():
            if iface in ifs_w_gw and iface in ifs_dhcp:
                raise SaltInvocationError, "Can't both set the gateway "\
                    + "and configure via DHCP for interface " + \
                    "{0}.".format(iface)
            if iface in ifs_dhcp and iface in ifs_not_gw:
                raise NotImplementedError, "Keeping the DHCP-client " + \
                    "from settings the default gateway is not implemented" 

        # Make sure we don't try to set the gw on any other 
        # device when one will be configured via DHCP:
        if len(ifs_dhcp) == 1:
            for iface in pillar_interfaces.keys():
                if iface != ifs_dhcp[0]:
                    ifs_not_gw.append(iface)
            #raise Exception, "One DHCP-interface found: " + ifs_dhcp[0] + \
            #    "\nThe following interfaces are listed in ifs_not_gw: " + \
            #    "\n" + str(ifs_not_gw)

        # If there's no DHCP-iface and none has set a gw check if 
        # there's one that doesn't have default_gw set to False:
        if not ifs_dhcp and not ifs_w_gw.keys():
            leftovers = []
            for iface in pillar_interfaces.keys():
                if iface not in ifs_not_gw:
                    leftovers.append(iface)
            if len(leftovers) != 1:
                raise SaltInvocationError, "No interface chosen to " + \
                    "set the default route on."
            else:
                ifs_w_gw[leftovers[0]] = True

        # Missing ovs_bridge module or Pillar-data for OVS-bridge
        # Configuration on this minion:
        if not 'ovs_bridge.exists' in salt or \
                not salt['pillar.get']('openvswitch:bridges', False):
            interfaces = {}
            for iface in salt['pillar.get']('interfaces', {}).keys():
                if iface not in ifs_w_gw.keys() and iface not in ifs_dhcp:
                    interfaces[iface] = iface_settings(iface, set_gw = False)
                else:
                    interfaces[iface] = iface_settings(iface)
        else:
            interfaces = {}
            br_pillar = salt['pillar.get']('openvswitch:bridges', {})
            for bridge, br_config in br_pillar.items():
                if not br_config.has_key('reuse_netcfg'):
                    continue
                uplink = br_config['reuse_netcfg']
                if uplink not in salt['network.interfaces']().keys():
                    raise SaltInvocationError, \
                        """
                        Iface {0} set in bridge {1}'s option 
                        'reuse_netcfg' doesn't exist.
                        All interfaces:\n{2}
                        """.format(uplink, bridge, 
                            salt['network.interfaces']().keys())
                if salt['ovs_bridge.exists'](bridge):
                    if uplink not in ifs_w_gw.keys() \
                            and uplink not in ifs_dhcp:
                        interfaces[bridge] = iface_settings(
                            uplink, set_gw = False)
                    else:
                        interfaces[bridge] = iface_settings(
                            uplink)
                    if interfaces[bridge].has_key('comment'):
                        interfaces[bridge]['uplink_comment'] = \
                            interfaces[bridge]['comment']
                    if br_config.has_key('comment'):
                        interfaces[bridge]['comment'] = \
                            br_config['comment']
                    else:
                        try:
                            interfaces[bridge].pop('comment')
                        except KeyError:
                            pass
                    interfaces[bridge]['uplink'] = uplink
            #raise Exception, \
            #    "Interfaces w/ Default Gateway:" + str(ifs_w_gw) +\
            #    "\nDHCP Interfaces:" + str(ifs_dhcp) +\
            #    "\nInterfaces NOT settings the Def GW:" + str(ifs_dhcp) +\
            #    "\n\nAll Interfaces: " + str(interfaces.values())
            #  # TODO: IPv6 config
            #   if settings.has_key('ipv6'):
            #     interfaces[bridge]['ipv6'] = salt['pillar.get'](
            #         'interfaces:{0}:ipv6'.format(iface))
            # get a list of all interfaces used as uplinks...:
            uplink_list = []
            for br_conf in interfaces.values():
                if br_conf.has_key('uplink'):
                    uplink_list += [ br_conf['uplink'] ]
            # ...and interfaces not in this list will be passed
            # to the template for /etc/network/interfaces:
            for iface, settings in salt['pillar.get'](
                    'interfaces', {}).items():
                if iface not in uplink_list:
                    if iface not in ifs_w_gw.keys() and iface not in ifs_dhcp:
                        interfaces[iface] = iface_settings(iface, set_gw=False)
                    else:
                        interfaces[iface] = iface_settings(iface)
                    #comment = \
                    #    "Bridge {0} doesn't exist yet\n".format(bridge)
                    if settings.has_key('comment'):
                        #comment += settings['comment']
                        interfaces[iface]['comment'] = \
                            settings['comment']
    
    # And now pass all this data to the template:              
    state['/etc/network/interfaces'] = {
            'file.managed': [
                {'source': 'salt://networking/files/interfaces'},
                {'template': 'jinja'},
                {'defaults': { 'interfaces': interfaces, }
                    },
                {'require_in': [ 'neutron.openvswitch' ]},
                ]
            }
    return state

# make sure we got /some/ nameserver configured:
#{% if not salt['file.search'](
#        '/etc/resolv.conf', 'nameserver {0}'.format(
#            salt['pillar.get'](
#                'dns:servers', ['8.8.8.8']
#            )[0]
#        )) %}
#add nameserver(s) to /etc/resolv.conf:
#  file.append:
#    - name: /etc/resolv.conf
#    - text: 
#  {%- for server in salt['pillar.get']('dns:servers', ['8.8.8.8']) %}
#        - nameserver {{ server }}
#  {%- endfor %}
#{%- endif %}
