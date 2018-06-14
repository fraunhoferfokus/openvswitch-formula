{# On system w/o the resolvconf pkg just manage 
   /etc/resolv.conf, but on Linux assume this pkg 
   will show up Linux sooner or later... #}
{% if not( grains['kernel'] == 'Linux' or salt['pkg.version']('resolvconf')) %}
/etc/resolv.conf:
  file.managed:
    - source: salt://networking/files/resolv.conf
    - user: root
    - mode: 0644
    - template: jinja
{% if grains['os'] == 'Ubuntu' and ( 
    grains['osmajorrelease'] | int > 17 or 
    grains['oscodename'] == 'arful' ) %}
# Ubuntu since 17.10 "artful" uses systemd's `resolved`
# so we need to make sure it's configured, too:
/etc/systemd/resolvd.conf:
  file.managed:
    - contents: |
        # !! MANAGED VIA SALTSTACK !!
        # See resolved.conf(5) for details
        [Resolve]
        DNS={{ salt['pillar.get']('dns:servers')|join(' ') }}
        #FallbackDNS=
        Domains={{ salt['pillar.get']('dns:domains')|join(' ') }}
        #LLMNR=no
        #MulticastDNS=no
        #DNSSEC=no
        #Cache=yes
        #DNSStubListener=yes
    - user: root
    - mode: 644
{% endif %}

{% else %}
  {% if salt['pkg.version']('resolvconf') %}
resolvconf:
  service.running:
    - require:
      - file: /etc/resolvconf/resolv.conf.d
    - watch:  
      - file: /etc/resolvconf/resolv.conf.d
  {% endif %}

  {# Prepare the configfiles for resolvconf #}
  {# even if currently not installed: #}
/etc/resolvconf:
  file.directory:
    - user: root
    - group: root
    - mode: 0755

/etc/resolvconf/resolv.conf.d:
  file.directory:
    - user: root
    - group: root
    - mode: 0755
    - require: 
        - file: /etc/resolvconf

  {# In theory there's a command to do this but I 
     couldn't figure out how to invoke it correctly #}
/etc/resolv.conf:
  cmd.run:
    - name: cp /etc/resolv.conf /tmp/resolv.conf_old; cat /etc/resolvconf/resolv.conf.d/head /etc/resolvconf/resolv.conf.d/base /etc/resolvconf/resolv.conf.d/tail | tee /etc/resolv.conf | (diff -u /tmp/resolv.conf_old - || true)
    {# unless as in "unless this check succeeds run..." #}
    - unless: cat /etc/resolvconf/resolv.conf.d/head /etc/resolvconf/resolv.conf.d/base /etc/resolvconf/resolv.conf.d/tail | diff -u /tmp/resolv.conf -
    - require:
      - file: /etc/resolvconf/resolv.conf.d
      - file: /etc/resolvconf/resolv.conf.d/base
      - file: /etc/resolvconf/resolv.conf.d/head
      - file: /etc/resolvconf/resolv.conf.d/tail

  {% for file in ['head','base','tail'] %}
  {# These use 'servers', 'options' and 'domains' under pillar['dns']: #}
  {# (And the first one defaults to ['8.8.8.8'] #}
  {#  if pillar['dns:servers'] is empty) #}
/etc/resolvconf/resolv.conf.d/{{file}}:
  file.managed:
    - source: salt://networking/files/resolv.conf.d_{{file}}
    - user: root
    - group: root
    - mode: 0644
    - template: jinja
    - require:
      - file: /etc/resolvconf/resolv.conf.d
  {% endfor%}
{% endif %}
