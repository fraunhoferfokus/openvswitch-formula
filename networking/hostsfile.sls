{% set domain = salt['pillar.get']('dns:domains')[0] %}
{% if domain not in opts.id %}
    {% set fqdn = opts.id + '.' + domain %}
{% else %}
    {% set fqdn = opts.id %}
{% endif %}
{% set interfaces = salt['pillar.get']('interfaces') %}
{% if interfaces.keys()|length == 1 %}
    {% set iface, settings = interfaces.items()[0] %}
{% elif inferfaces.keys()|length > 1 %}
    {% for iface, settings in interfaces.items() 
        if settings.has('default_gw') %}
        {#  we just wanted this list to be filtered.
            networking.config would break anyway if 
            there's more than one iface with default_gw #}
    {% endfor %}
{% endif %}
{% set ips = {} %}
{% if settings.has_key('ipv4') %}
    {% set ipv4 = settings['ipv4'].split('/')[0] %}
{% endif %}
{% if settings.has_key('ipv6') %}
    {% set ipv6 = settings['ipv6'].split('/')[0] %}
{% endif %}

{{ fqdn }} in /etc/hosts:
    host.present:
        - ip: 
{% if ipv4 is defined %}
            - {{ ipv4 }}
{% endif %}
{% if ipv6 is defined %}
            - {{ ipv6 }}
{% endif %}
        - names:
            - {{ fqdn }}
            - {{ grains['nodename'] }}

{% if grains['os'] == 'Ubuntu' %}
no 127.0.1.1 in /etc/hosts:
    host.absent:
        - name: {{ grains['nodename'] }}
        - ip: 127.0.1.1
{% endif %}

{% for id, details in salt['pillar.get']('hosts', {}).items() %}
{{ id }} in /etc/hosts:
    host.present:
    {% if not details.has_key('names') %}
        - name: {{ id }}
    {% else %}
        - names: {{ details['names'] }}
    {% endif %}
        - ip: {{ details['ips']  }}
{% endfor %}
