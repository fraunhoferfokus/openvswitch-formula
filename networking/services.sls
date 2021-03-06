{% if grains['os_family'] == 'RedHat' %}
networking:
  service:
    - enabled
    - name: network
{% endif %}
{#  Won't work together with OVS and generally just messes
    with the network configuration #}

{# Don't try this on *BSD #}
{% if grains['os_family'] == 'Debian' %}
network-manager:
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
{% elif grains['os_family'] == 'RedHat' or
    ( grains['os'] == 'Ubuntu' and grains['osmajorrelease'] >= 16 ) %}
network-manager:
  service:
    - dead
    - enable: false
    - name: NetworkManager
  pkg.removed:
    - name: NetworkManager
{% endif %}

{% if grains.os_family in ['RedHat','Debian'] %}
/etc/NetworkManager:
  file.directory:
    - user: root
    - group: root
    - mode: 0755
{% endif %}

{#  This file isn't templated yet as we just disable management
    of ifupdown (NICs configured via /etc/network/interfaces)
    via NetworkManager
    No RedHat-version of the file yet and th pkgname probably 
    is different on RH, too #}
{% if 'network-manager' in salt['pkg.list_pkgs']() %}
/etc/NetworkManager/NetworkManager.conf:
  file.managed:
    - source: salt://networking/files/NetworkManager.conf_{{
        grains['os_family'] }}
    - user: root
    - group: root
    - mode: 0444
    - require:
      - file: /etc/NetworkManager
{% endif %}
