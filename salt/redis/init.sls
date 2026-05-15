#!py
#
# radieschen
#
# Copyright (C) 2025   darix
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

from salt.exceptions import SaltConfigurationError

import os.path

def run():
    config = {}

    if "redis" in __pillar__:
        redis_pillar = __pillar__["redis"]

        redis_implementation = redis_pillar.get("redis_implementation", "redis")
        use_sentinel         = redis_pillar.get("use_sentinel", False)

        redis_packages = [redis_implementation]
        redis_use_apparmor = redis_pillar.get("use_apparmor", False) # and redis_implementation == "redis"

        if redis_use_apparmor:
            redis_packages.append(f"{redis_implementation}-apparmor")

        config["redis_packages"] = {
            "pkg.installed": [
                {'pkgs': redis_packages},
            ]
        }

        for instance_name, instance_data in redis_pillar["instances"].items():
            redis_config = f"redis_config_{instance_name}"
            redis_apparmor = f"redis_apparmor_{instance_name}"
            redis_apparmor_load = f"redis_apparmor_{instance_name}_load"
            redis_datadir = f"redis_datadir_{instance_name}"
            redis_service = f"redis_services_{instance_name}"

            redis_service_deps = [redis_datadir, redis_config]

            default_config_file = f"/etc/{redis_implementation}/{instance_name}.conf"
            default_pidfile = f"/run/{redis_implementation}/{instance_name}.pid"
            default_dir = f"/var/lib/{redis_implementation}/{instance_name}"
            default_logfile = f"/var/log/{redis_implementation}/{instance_name}.log"
            apparmor_profile_path = f"/etc/apparmor.d/{redis_implementation}.d/{redis_implementation}.{instance_name}"

            sentinel_etc_config_file = f"/etc/{redis_implementation}/sentinel-{instance_name}.conf"
            sentinel_instance_dir = f"/var/lib/{redis_implementation}/sentinel-{instance_name}"
            sentinel_var_config_file = f"{sentinel_instance_dir}/sentinel.conf"

            sentinel_pidfile = f"/run/{redis_implementation}/sentinel-{instance_name}.pid"
            sentinel_logfile = f"/var/log/{redis_implementation}/sentinel-{instance_name}.log"

            instance_is_enabled = instance_data.get("enable", True)

            if instance_is_enabled:
                if not("port" in instance_data["config"]):
                    raise SaltConfigurationError(f"Must specify 'port' for redis instance {instance_name}")

                if "require" in instance_data:
                    redis_service_deps.extend(instance_data["require"])

                context = {
                    "instance_name": instance_name,
                    "config_file": default_config_file,
                    "dir":     instance_data["config"].get("dir",     default_dir),
                    "pidfile": instance_data["config"].get("pidfile", default_pidfile),
                    "logfile": instance_data["config"].get("logfile", default_logfile),
                    "apparmor_local": instance_data.get("apparmor_local", []),
                    "redis_implementation": redis_implementation,
                    "replicaof": None,
                    "replica_announce_ip": None,
                }

                if 'mine_target' in redis_pillar and 'mine_function' in redis_pillar and 'primary_node' in redis_pillar:
                  current_minion = __salt__['grains.get']('id')
                  if instance_data.get('replication_use_tls', False):
                    replication_port = instance_data['config']['tls-port']
                  else:
                    replication_port = instance_data['config']['port']

                  cluster_ips = __salt__['mine.get'](redis_pillar['mine_target'], redis_pillar['mine_function'], tgt_type='compound')
                  primary_ip = cluster_ips.get(redis_pillar['primary_node'])[0]
                  own_ip = cluster_ips.get(current_minion)[0]

                  if current_minion != redis_pillar['primary_node']:
                    context['replicaof'] = f"{primary_ip} {replication_port}"
                    # context['replicaof'] = f"{redis_pillar['primary_node']} {replication_port}"
                    context['replica_announce_ip'] = own_ip

                  if use_sentinel:
                    sentinel_etc_config_state  = f"sentinel_etc_config_{instance_name}"
                    sentinel_var_config_state  = f"sentinel_var_config_{instance_name}"
                    sentinel_service_state     = f"sentinel_service_{instance_name}"
                    sentinel_quorum = instance_data.get('sentinel_quorum', len(cluster_ips)-1)
                    sentinel_port = instance_data.get('sentinel_port', 20000+replication_port)

                    sentinel_config = [
                      "# salt managed - dont cry if your changes are lost",
                      "include /etc/valkey/includes/sentinel.defaults.conf",
                      f"dir {sentinel_instance_dir}",
                      f"port {sentinel_port}",
                      f"pidfile {sentinel_pidfile}",
                      f"logfile {sentinel_logfile}",
                    ]
                    sentinel_config.extend(__salt__['pillar.get']('redis:sentinel_global_config', []))

                    sentinel_config.append(f"sentinel monitor {instance_name} {primary_ip} {replication_port} {sentinel_quorum}")
                    sentinel_config.append(f"sentinel announce-ip {own_ip}")
                    # sentinel_config.append(f"sentinel monitor {instance_name} {redis_pillar['primary_node']} {replication_port} {sentinel_quorum}")

                    sentinel_default_instance_settings = {
                      'down-after-milliseconds': 60000,
                      'failover-timeout': 180000,
                      'parallel-syncs': sentinel_quorum
                    }

                    sentinel_settings_key = 'sentinel_config'
                    sentinel_settings = __salt__['pillar.get'](f"redis:instances:{instance_name}:{sentinel_settings_key}",
                                default=__salt__['pillar.get'](f"redis:{sentinel_settings_key}", sentinel_default_instance_settings), merge=True)

                    for setting_name, setting_value in sentinel_settings.items():
                      sentinel_config.append(f"sentinel {setting_name} {instance_name} {setting_value}")

                    sentinel_users_key = 'sentinel_users'
                    sentinel_users = __salt__['pillar.get'](f'redis:{sentinel_users_key}', [])

                    for user_acl in sentinel_users:
                      sentinel_config.append(f"user {user_acl}")

                    config[sentinel_etc_config_state] = {
                        "file.managed": [
                            {"name": sentinel_etc_config_file},
                            {"user": "root"},
                            {"group":  redis_implementation},
                            {"mode": "0640"},
                            {"require": ["redis_packages"]},
                            {"contents": "\n".join(sentinel_config)},
                        ]
                    }

                    config[f"sentinel_instance_dir_{instance_name}"] = {
                      "file.directory": [
                        {'name': sentinel_instance_dir},
                        {"user": redis_implementation},
                        {"group":  redis_implementation},
                        {"mode": "0750"},
                        {"require": ["redis_packages"]},
                        {'require_in': [sentinel_var_config_state]}
                      ]
                    }

                    config[sentinel_var_config_state] = {
                        "file.managed": [
                            {"name": sentinel_var_config_file},
                            {"user": redis_implementation},
                            {"group":  redis_implementation},
                            {"mode": "0640"},
                            {"require": ["redis_packages"]},
                            {"contents": f"include {sentinel_etc_config_file}"},
                            {'require': [sentinel_etc_config_state]},

                        ]
                    }

                    # Why is this on changes here?
                    # every time we change the config in /etc/valkey/ we need to reset this file to make sentinel recalculate the cluster_ips
                    # otherwise it runs into duplicated master entries
                    if os.path.exists(sentinel_var_config_file):
                      config[sentinel_var_config_state]["file.managed"].append({'onchanges': [sentinel_etc_config_state]})
                    else:
                      config[sentinel_var_config_state]["file.managed"].append({'creates': sentinel_var_config_file})

                    config[sentinel_service_state] = {
                        "service.running": [
                            {"name": f"{redis_implementation}-sentinel@{instance_name}.service"},
                            {"enable": True},
                            {"require": [sentinel_var_config_state, redis_service]},
                            {"watch": [sentinel_etc_config_state] },
                        ]
                    }

                    for dependency in ["require_in", "on_changes", "on_changes_in"]:
                        if dependency in instance_data:
                            config[sentinel_service_state]["service.running"].append({dependency: instance_data[dependency]})

                config[redis_config] = {
                    "file.managed": [
                        {"name": default_config_file},
                        {"user": "root"},
                        {"group":  redis_implementation},
                        {"mode": "0640"},
                        {"template": "jinja"},
                        {"source": "salt://redis/files/etc/redis/redis.conf.j2"},
                        {"require": ["redis_packages"]},
                        {"context": context},
                    ]
                }

                config[redis_datadir] = {
                    "file.directory": [
                        {"user": redis_implementation},
                        {"group": redis_implementation},
                        {"mode": "0750"},
                        {"name": context["dir"]},
                        {"require": ["redis_packages"]},
                    ]
                }

                if redis_use_apparmor:

                    config[redis_apparmor] = {
                        "file.managed": [
                            {"name": apparmor_profile_path},
                            {"user": "root"},
                            {"group": "root"},
                            {"mode": "0644"},
                            {"template": "jinja"},
                            {"source": "salt://redis/files/etc/apparmor.d/redis.d/redis.j2"},
                            {"require": [redis_config]},
                            {"context": context},
                        ]
                    }

                    config[redis_apparmor_load] = {
                        "cmd.run": [
                            {"name": f"/sbin/apparmor_parser -r {apparmor_profile_path}"},
                            {"onchanges": [redis_apparmor]},
                            {"require": [redis_apparmor]},
                        ]
                    }

                    redis_service_deps.append(redis_apparmor)
                    redis_service_deps.append(redis_apparmor_load)

                config[redis_service] = {
                    "service.running": [
                        {"name": f"{redis_implementation}@{instance_name}.service"},
                        {"enable": True},
                        {"require": redis_service_deps},
                        {"watch": [redis_config] },
                    ]
                }

                for dependency in ["require_in", "on_changes", "on_changes_in"]:
                    if dependency in instance_data:
                        config[redis_service]["service.running"].append({dependency: instance_data[dependency]})
            else:
                config[redis_service] = {
                    "service.dead": [
                        {"name": f"{redis_implementation}@{instance_name}.service"},
                        {"enable": False},
                    ]
                }

                if redis_use_apparmor:

                    config[redis_apparmor_load] = {
                        "cmd.run": [
                            {"name": f"/sbin/apparmor_parser -R {apparmor_profile_path}"},
                            {"require_in": [redis_service]},
                        ]
                    }

                    config[redis_apparmor] = {
                        "file.absent": [
                            {"name": apparmor_profile_path},
                            {"require": [redis_apparmor_load]},
                        ]
                    }

                config[redis_config] = {
                    "file.absent": [
                        {"name": default_config_file},
                        {"require": [redis_service]}
                    ]
                }

    return config