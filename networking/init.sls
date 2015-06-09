include:
  - networking.config
  - networking.resolvconf
  - networking.hostsfile

{% if salt['grains.get']('os_family') != 'Debian' %}
networking service:
  service.running:
    - name: networking
    - full_restart: True
    - watch: 
      # yes, I know, this makes no sense on non-Debian...
      - file: /etc/network/interfaces
{% endif %}

# you can't "restart" the networking service on Debian and
# derivates (like Ubuntu) so run those commands instead:
{% for iface in salt['pillar.get']('interfaces', {}).keys() %}
  {% if iface in salt['grains.get']('hwaddr_interfaces').keys() %}
ifdown/ifup {{ iface }}:
  cmd.run:
    - name: "ifup {{ iface }} || (ifdown {{ iface }}; ifup {{ iface }})"
    {% if salt['grains.get']('os_family') != 'Debian' %}
    - onfail:
      - service: networking
    {% endif %}
    - require: 
      - file: /etc/network/interfaces
    - watch: 
      - file: /etc/network/interfaces
  {% endif %}
{% endfor %}

{#  Won't work together with OVS and generally just messes
    with the network configuration #}
network-manager:
{% if grains['os_family'] == 'Debian' %}
  service:
    - disabled
  {# That's the Upstart way of disabling a service: #}
  {% if grains['os'] == 'Ubuntu' %}
  file.managed:
    - name: /etc/init/network-manager.override
    - content: manual
    - user: root
    - group: root
    - mode: 0444
  {% endif %}
{% elif grains['os_family'] == 'RedHat' %}
  service:
    - dead
    - enable: false
    - name: NetworkManager
  pkg.removed:
    - name: NetworkManager
{% endif %}

{#  This file isn't templated yet as we just disable management 
    of ifupdown (NICs configured via /etc/network/interfaces)
    via NetworkManager #}
{% if salt['pkg.list_pkgs']().has_key('network-manager') %}
/etc/NetworkManager/NetworkManager.conf:
  file.managed:
    - source: salt://networking/files/NetworkManager.conf_{{grains['os_family']}}
    - user: root
    - group: root
    - mode: 0444
    - require:
      - file: /etc/NetworkManager
{% endif %}

{% if grains.os_family in ['RedHat','Debian'] %}
/etc/NetworkManager:
  file.directory:
    - user: root
    - group: root
    - mode: 0755
{% endif %}
