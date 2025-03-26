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

#!py
from salt.exceptions import SaltConfigurationError

def run():
    config = {}

    if "redis" in __pillar__:
        redis_pillar = __pillar__["redis"]

        redis_implementation = redis_pillar.get("redis_implementation", "redis")

        redis_packages = [redis_implementation]
        redis_use_apparmor = redis_pillar.get("use_apparmor", False) and redis_implementation == "redis"

        if redis_use_apparmor:
            redis_packages.append("redis-apparmor")

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
            apparmor_profile_path = f"/etc/apparmor.d/redis.d/redis.{instance_name}"

            instance_is_enabled = instance_data.get("enable", True)

            if instance_is_enabled:
                if not("port" in instance_data["config"]):
                    raise SaltConfigurationError(f"Must specify 'port' for redis instance {instance_name}")

                context = {
                    "instance_name": instance_name,
                    "config_file": default_config_file,
                    "dir":     instance_data["config"].get("dir",     default_dir),
                    "pidfile": instance_data["config"].get("pidfile", default_pidfile),
                    "logfile": instance_data["config"].get("logfile", default_pidfile),
                    "redis_implementation": redis_implementation,
                }

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
                    ]
                }

                for dependency in ["require_in", "require", "on_changes", "on_changes_in"]:
                    if dependency in instance_data:
                        config[redis_service]["service.running"][dependency] = instance_data["require_in"]
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