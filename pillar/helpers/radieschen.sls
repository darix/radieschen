
{%- macro sentinel_default_acls(sentinel_username="sentinel", sentinel_key=None) %}
    - 'default off nopass'
{%- if sentinel_key != None %}
    - '{{ sentinel_username }} ON >{{ sentinel_key | gopass(quoted=False) }} allchannels -@all +auth +client|getname +client|id +client|setname +command +hello +ping +role +sentinel|get-master-addr-by-name +sentinel|master +sentinel|myid +sentinel|replicas +sentinel|sentinels'
{%- endif %}
{%- endmacro %}

{%- macro sentinel_auth_config(sentinel_username="sentinel", sentinel_key=None) %}
{%- if sentinel_key != None %}
    - 'sentinel sentinel-user {{ sentinel_username }}'
    - 'sentinel sentinel-pass {{ sentinel_key | gopass(quoted=False) }}'
{%- endif %}
{%- endmacro %}

{%- macro redis_sentinel_auth_config(sentinel_username="sentinel", sentinel_key=None) %}
{%- if sentinel_key != None %}
        auth-user: {{ sentinel_username }}'
        auth-pass: {{ sentinel_key | gopass(quoted=False) }}'
{%- endif %}
{%- endmacro %}

{%- macro redis_default_acls(replication_user="replicator", healthcheck_user="haproxy", sentinel_username="sentinel", replication_key=None, healthcheck_key=None, sentinel_key=None) %}
        - "default on -@all"
{%- if replication_key != None %}
        - '{{ replication_user }} on +@admin ~* >{{ replication_key | gopass(quoted=False) }}'
{%- endif %}
{%- if healthcheck_key != None %}
        - '{{ healthcheck_user }} on -@all +ping >{{ healthcheck_key | gopass(quoted=False) }}'
{%- endif %}
{%- if sentinel_key != None %}
- '{{ sentinel_username }} on >{{ sentinel_key | gopass(quoted=False) }} +subscribe +publish +failover +script|kill +ping +info +multi +slaveof +config +client +exec &__sentinel__:hello'
{%- endif %}
{%- endmacro %}

{%- macro tls_cert_dependencies() %}
        - step_client_user_generic_acl_0
        - step_client_host_generic_acl_0
{%- endmacro %}

{%- macro redis_default_settings_with_tls(tls_ca_cert, tls_port=6380, non_tls_port=0, bind_ips=["0.0.0.0"], host_cert="/etc/step/certs/generic.host.full.pem", client_cert="/etc/step/certs/generic.user.full.pem", tls_client_auth="'yes'", replication_user = 'replicator') %}
{{ redis_default_settings(non_tls_port=non_tls_port, bind_ips=bind_ips, replication_user = replication_user) }}
        tls-port: {{ tls_port }}
        tls-ca-cert-file: {{ tls_ca_cert }}
        tls-cert-file: {{ host_cert }}
        tls-key-file:  {{ host_cert }}
        tls-client-cert-file: {{ client_cert }}
        tls-client-key-file:  {{ client_cert }}
        tls-auth-clients: {{ tls_client_auth }}
        tls-replication: 'yes'
        tls-cluster: 'yes'
        tls-protocols: TLSv1.3
{%- endmacro %}

{%- macro redis_default_settings(non_tls_port=0, bind_ips=["0.0.0.0"], replication_user = 'replicator') %}
        masteruser: {{ replication_user }}
        bind: {{ bind_ips }}
        port: {{ non_tls_port }}
{%- endmacro %}

{%- macro sentinel_default_settings_with_tls(tls_ca_cert, host_cert="/etc/step/certs/generic.host.full.pem", client_cert="/etc/step/certs/generic.user.full.pem") %}
    - 'tls-ca-cert-file     {{ tls_ca_cert }}'
    - 'tls-cert-file        {{ host_cert }}'
    - 'tls-key-file         {{ host_cert }}'
    - 'tls-client-cert-file {{ client_cert }}'
    - 'tls-client-key-file  {{ client_cert }}'
    - 'tls-auth-clients     yes'
    - 'tls-replication      yes'
    - 'tls-cluster          yes'
    - 'tls-protocols        TLSv1.3'
{%- endmacro %}
