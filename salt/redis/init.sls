#!py
from salt.exceptions import SaltConfigurationError

def run():
    config = {}

    if "redis" in __pillar__:
        redis_pillar = __pillar__["redis"]

        redis_packages = ["redis"]
        redis_use_apparmor = redis_pillar.get("use_apparmor", False)

        if redis_use_apparmor:
            redis_packages.append("redis-apparmor")

        config["redis_packages"] = {
            "pkg.installed": [
                {'pkgs': redis_packages},
            ]
        }

        include_files = []
        for daemon in ["redis", "sentinel"]:
            include_files.append(
                {f"/etc/redis/includes/{daemon}.defaults.conf": [
                    {"source": f"salt://redis/files/etc/redis/includes/{daemon}.defaults.conf.j2"}
                ]
                }
            )

        config["redis_include_dir"] = {
            "file.directory": [
                {"user": "root"},
                {"group": "redis"},
                {"mode": "0750"},
                {"name": "/etc/redis/includes"},
                {"require": ["redis_packages"]},
            ]
        }
        config["redis_includes"] = {
            "file.managed": [
                {"user": "root"},
                {"group": "redis"},
                {"mode": "0640"},
                {"template": "jinja"},
                {"names": include_files},
                {"require": ["redis_include_dir"]},
            ]
        }

        for instance_name, instance_data in redis_pillar["instances"].items():
            redis_config = f"redis_config_{instance_name}"
            redis_apparmor = f"redis_apparmor_{instance_name}"
            redis_apparmor_load = f"redis_apparmor_{instance_name}_load"
            redis_datadir = f"redis_datadir_{instance_name}"
            redis_service = f"redis_services_{instance_name}"

            redis_service_deps = [redis_datadir, redis_config]

            default_config_file = f"/etc/redis/{instance_name}.conf"
            default_pidfile = f"/run/redis/{instance_name}.pid"
            default_dir = f"/var/lib/redis/{instance_name}"

            if not("port" in instance_data["config"]):
                raise SaltConfigurationError(f"Must specify 'port' for redis instance {instance_name}")

            context = {
                "instance_name": instance_name,
                "config_file": default_config_file,
                "dir":     instance_data["config"].get("dir",     default_dir),
                "pidfile": instance_data["config"].get("pidfile", default_pidfile),
                "logfile": instance_data["config"].get("logfile", default_pidfile),
            }

            config[redis_config] = {
                "file.managed": [
                    {"name": default_config_file},
                    {"user": "root"},
                    {"group": "redis"},
                    {"mode": "0640"},
                    {"template": "jinja"},
                    {"source": "salt://redis/files/etc/redis/redis.conf.j2"},
                    {"require": ["redis_includes"]},
                    {"context": context},
                ]
            }

            config[redis_datadir] = {
                "file.directory": [
                    {"user": "redis"},
                    {"group": "redis"},
                    {"mode": "0750"},
                    {"name": context["dir"]},
                    {"require": ["redis_packages"]},
                ]
            }

            if redis_use_apparmor:
                apparmor_profile_path = f"/etc/apparmor.d/redis.d/redis.{instance_name}"


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
                    {"name": f"redis@{instance_name}.service"},
                    {"require": redis_service_deps},
                ]
            }

            for dependency in ["require_in", "require", "on_changes", "on_changes_in"]:
                if dependency in instance_data:
                    config[redis_service]["service.running"][dependency] = instance_data["require_in"]

    return config