#!/usr/bin/python3 -u

# -*- coding: utf-8 -*-
#
# Copyright 2020, Timofey Titovets and the systemd-swap contributors
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import argparse
import glob
import os
import pickle
import re
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time
import types
from typing import List, Dict, Type, Optional, Tuple, NoReturn

import systemd.daemon
import sysv_ipc


def get_mem_stats(fields: List[str]) -> Dict[str, int]:
    stats = {}
    with open("/proc/meminfo") as meminfo:
        for line in meminfo:
            items = line.split()
            key = items[0][:-1]
            if items[2] == "kB" and key in fields:
                fields.remove(key)
                stats[key] = int(items[1]) * 1024
            if not fields:
                break
    assert len(fields) == 0
    return stats


# Global variables.
# NCPU and RAM_SIZE are referenced inside of `swap-default.conf`.
NCPU = os.cpu_count() or 1
RUN_SYSD = "/run/systemd"
ETC_SYSD = "/etc/systemd"
VEN_SYSD = "/usr/lib/systemd"
DEF_CONFIG = "/usr/share/systemd-swap/swap-default.conf"
ETC_CONFIG = f"{ETC_SYSD}/swap.conf"
RAM_SIZE = get_mem_stats(["MemTotal"])["MemTotal"]
PAGE_SIZE = int(
    subprocess.run(
        ["getconf", "PAGESIZE"], check=True, text=True, stdout=subprocess.PIPE
    ).stdout
)
WORK_DIR = "/run/systemd/swap"
LOCK_STARTED = f"{WORK_DIR}/.started"
ZSWAP_M = "/sys/module/zswap"
ZSWAP_M_P = "/sys/module/zswap/parameters"
KMAJOR, KMINOR = [int(v) for v in os.uname().release.split(".")[0:2]]
IS_DEBUG = False
sigterm_event = threading.Event()

# Should not be a global variable, rework necessary
zswap_parameters = {}


class Config:
    def __init__(self):
        os.environ["NCPU"] = str(NCPU)
        os.environ["RAM_SIZE"] = str(RAM_SIZE)
        self.config = {}
        # Load default values.
        if os.path.isfile(DEF_CONFIG):
            try:
                self.config.update(Config.parse_config(DEF_CONFIG))
            except OSError:
                error(f"Error loading {DEF_CONFIG}")
        # Config precedence follows systemd scheme:
        # etc > run > lib for all fragments > /etc/systemd/swap.conf
        if os.path.isfile(ETC_CONFIG):
            try:
                self.config.update(Config.parse_config(ETC_CONFIG))
            except OSError:
                warn(f"Could not load {DEF_CONFIG}")
        config_files = {}
        for path in [VEN_SYSD, RUN_SYSD, ETC_SYSD]:
            path += "/swap.conf.d"
            for file_path in glob.glob(f"{path}/*.conf"):
                if not os.access(file_path, os.R_OK) or os.path.isdir(file_path):
                    if os.path.isfile(file_path):
                        warn(f"Permission denied reading: {file_path}")
                    continue
                config_files[os.path.basename(file_path)] = file_path
                debug(f"Found {file_path}")
        debug(f"Selected configuration artifacts: {list(config_files.values())}")
        # Sort lexicographically.
        config_files = dict(sorted(config_files.items()))
        for config_file in config_files.values():
            info(f"Load: {config_file}")
            self.config.update(Config.parse_config(config_file))

    def get(self, key: str, as_type: Type = str) -> as_type:
        if as_type is bool:
            return self.config[key].lower() in ["yes", "y", "1", "true"]
        return as_type(self.config[key])

    @staticmethod
    def parse_config(file: str) -> Dict[str, str]:
        config = {}
        lines = None
        with open(file) as f:
            lines = f.read().splitlines()
        for line in lines:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            config[key] = subprocess.run(
                [f"echo {value}"],
                shell=True,
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout.rstrip()
        return config


class DestroyInfo:
    pickle_path = f"{WORK_DIR}/destroy_info.pickle"

    def __init__(self, zswap_parameters: Dict[str, str]):
        self.zswap_parameters = zswap_parameters

    def get_zswap_parameters(self) -> Dict[str, str]:
        return self.zswap_parameters

    def save(self) -> None:
        with open(self.pickle_path, "wb") as f:
            pickle.dump(self, f)

    @classmethod
    def load(cls) -> Optional[cls]:
        try:
            with open(cls.pickle_path, "rb") as f:
                return pickle.load(f)
        except:
            return None


class SwapFc:
    def __init__(self, config: Config, sem: sysv_ipc.Semaphore):
        self.assign_config(config)
        self.sem = sem
        # Validate swapfc_frequency due to possible issues caused if set incorrectly.
        if not 1 <= self.swapfc_frequency <= 24 * 60 * 60:
            warn(
                "swapfc_frequency must be in range of 1..86400: "
                f"{self.swapfc_frequency} - set to 1"
            )
            self.swapfc_frequency = 1
        self.polling_rate = self.swapfc_frequency
        systemd.daemon.notify("STATUS=Monitoring memory status...")
        # Create parent directories for swapfc_path.
        makedirs(os.path.dirname(self.swapfc_path))
        self.fs_type, subvolume = self.get_fs_type()
        if self.fs_type == "btrfs" and self.subvolume_possible(subvolume):
            subprocess.run(
                ["btrfs", "subvolume", "create", self.swapfc_path],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            makedirs(self.swapfc_path)
        self.chunk_size = int(
            subprocess.run(
                ["numfmt", "--to=none", "--from=iec", self.swapfc_chunk_size],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout
        )
        self.block_size = os.statvfs(self.swapfc_path).f_bsize
        if self.fs_type == "btrfs":
            # If btrfs supports regular swap files (kernel version 5+), force disable
            # COW to avoid data corruption. If it doesn't, use the old swap-through-loop
            # workaround.
            if KMAJOR >= 5:
                self.swapfc_nocow = True
            else:
                self.swapfc_force_use_loop = True
        if not 1 <= self.swapfc_max_count <= 32:
            warn("swapfc_max_count must be in range 1..32, reset to 1")
            self.swapfc_max_count = 1
        makedirs(f"{WORK_DIR}/swapfc")
        self.allocated = 0
        for _ in range(self.swapfc_min_count):
            self.create_swapfile("swapFC: allocate chunk: ")

    def run(self) -> None:
        systemd.daemon.notify("READY=1")
        if self.allocated == 0:
            memory_usage = round(
                RAM_SIZE * (100 - self.swapfc_free_ram_perc) / (1024 * 1024 * 100)
            )
            info(
                f"swapFC: on-demand swap activation at >{memory_usage} MiB memory usage"
            )
        signal.signal(signal.SIGTERM, sigterm_handler)
        while True:
            self.sem.release()
            sigterm_event.wait(self.polling_rate)
            if sigterm_event.is_set():
                break
            try:
                self.sem.acquire(0)
            except sysv_ipc.BusyError:
                break
            if self.allocated == 0:
                curr_free_ram_perc = self.get_free_ram_perc()
                if curr_free_ram_perc < self.swapfc_free_ram_perc:
                    self.create_swapfile(
                        f"swapFC: free ram: {curr_free_ram_perc} < "
                        f"{self.swapfc_free_ram_perc} - allocate chunk: "
                    )
                continue
            curr_free_swap_perc = self.get_free_swap_perc()
            if (
                curr_free_swap_perc < self.swapfc_free_swap_perc
                and self.allocated < self.swapfc_max_count
            ):
                self.create_swapfile(
                    f"swapFC: free swap: {curr_free_swap_perc} < "
                    f"{self.swapfc_free_swap_perc} - allocate chunk: "
                )
                continue
            if self.allocated <= max(self.swapfc_min_count, 2):
                continue
            if curr_free_swap_perc > self.swapfc_remove_free_swap_perc:
                self.destroy_swapfile(
                    f"swapFC: free swap: {curr_free_swap_perc} > "
                    f"{self.swapfc_remove_free_swap_perc} - free up chunk: "
                    + str(self.allocated)
                )

    def get_fs_type(self) -> Tuple[str, bool]:
        subvolume = False
        path = None
        if os.path.isdir(self.swapfc_path):
            path = self.swapfc_path
        elif os.path.isdir(os.path.dirname(self.swapfc_path)):
            path = os.path.dirname(self.swapfc_path)
        else:
            error("swapfc_path is invalid")
        output = subprocess.run(
            ["df", path, "--output=fstype"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout
        fs_type = output.splitlines()[1]
        if fs_type == "-":
            ret_code = subprocess.run(
                ["btrfs", "subvolume", "show", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ).returncode
            if ret_code == 0:
                fs_type = "btrfs"
                if path == self.swapfc_path:
                    subvolume = True
            else:
                error("swapfc_path is located on an unknown filesystem")
        return fs_type, subvolume

    def subvolume_possible(self, subvolume: bool):
        return not subvolume and not os.path.exists(self.swapfc_path)

    def assign_config(self, config: Config) -> None:
        yn = lambda x: config.get(x, bool)
        self.swapfc_chunk_size = config.get("swapfc_chunk_size")
        self.swapfc_directio = yn("swapfc_directio")
        self.swapfc_force_preallocated = yn("swapfc_force_preallocated")
        self.swapfc_force_use_loop = yn("swapfc_force_use_loop")
        self.swapfc_free_ram_perc = config.get("swapfc_free_ram_perc", int)
        self.swapfc_free_swap_perc = config.get("swapfc_free_swap_perc", int)
        self.swapfc_frequency = config.get("swapfc_frequency", int)
        self.swapfc_max_count = config.get("swapfc_max_count", int)
        self.swapfc_min_count = config.get("swapfc_min_count", int)
        self.swapfc_nocow = yn("swapfc_nocow")
        self.swapfc_path = config.get("swapfc_path").rstrip("/")
        self.swapfc_priority = config.get("swapfc_priority", int)
        self.swapfc_remove_free_swap_perc = config.get(
            "swapfc_remove_free_swap_perc", int
        )

    def create_swapfile(self, msg: str) -> None:
        if not self.has_enough_space(self.swapfc_path):
            warn("swapFC: ENOSPC")
            # Prevent spamming the journal.
            self.double_polling_rate()
            systemd.daemon.notify("STATUS=Not enough space for allocating chunk")
            return
        # In case we have adjusted the polling rate, reset it.
        self.reset_polling_rate()
        systemd.daemon.notify("STATUS=Allocating swap file...")
        self.allocated += 1
        info(f"{msg} {self.allocated}")
        swapfile = self.prepare_swapfile(
            os.path.join(self.swapfc_path, str(self.allocated))
        )
        subprocess.run(
            ["mkswap", "-L", f"SWAP_{self.fs_type}_{self.allocated}", swapfile],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        options = "discard" if not self.swapfc_force_preallocated else None
        unit_name = gen_swap_unit(
            what=swapfile,
            priority=self.swapfc_priority,
            options=options,
            tag=f"swapfc_{self.allocated}",
        )
        self.swapfc_priority -= 1
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "start", unit_name], check=True)
        mode = os.stat(swapfile).st_mode
        if stat.S_ISBLK(mode):
            subprocess.run(["losetup", "-d", swapfile])
        systemd.daemon.notify("STATUS=Monitoring memory status...")

    def has_enough_space(self, path: str) -> bool:
        # Check free space to avoid problems on swap IO + ENOSPC.
        free_blocks = os.statvfs(path).f_bavail
        free_bytes = free_blocks * self.block_size
        # Also try leaving some free space.
        free_bytes -= self.chunk_size
        return free_bytes >= self.chunk_size

    def double_polling_rate(self) -> None:
        new_rate = self.polling_rate * 2
        # Do not double, interval is long enough.
        if new_rate > 86400 or new_rate > self.swapfc_frequency * 1000:
            return
        self.polling_rate = new_rate
        warn(f"swapFC: polling rate doubled to {self.polling_rate}s")

    def reset_polling_rate(self) -> None:
        if self.polling_rate > self.swapfc_frequency:
            self.polling_rate = self.swapfc_frequency
            info(f"swapFC: polling rate reset to {self.polling_rate}s")

    def prepare_swapfile(self, path: str) -> str:
        # Delete file if it already exists.
        force_remove(path)
        os.mknod(path)
        if self.fs_type == "btrfs" and self.swapfc_nocow:
            subprocess.run(["chattr", "+C", path], check=True)
        zeros = b"\x00" * 1024 * 1024
        with open(path, "wb") as swapfile:
            for _ in range(round(self.chunk_size / (1024 * 1024))):
                swapfile.write(zeros)
                swapfile.flush()
        return path if not self.swapfc_force_use_loop else self.losetup_w(path)

    def losetup_w(self, path: str) -> str:
        directio = "on" if self.swapfc_directio else "off"
        file = subprocess.run(
            ["losetup", "-f", "--show", f"--direct-io={directio}", path],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.rstrip()
        # Loop uses a file descriptor - if the file still exists, but does not have a
        # path like O_TMPFILE. When loop detaches a file, the file will be deleted.
        os.remove(path)
        return file

    def destroy_swapfile(self, msg: str) -> None:
        systemd.daemon.notify("STATUS=Deallocating swap file...")
        info(msg)
        for unit_path in find_swap_units():
            content = None
            with open(unit_path) as f:
                content = f.read()
            if f"swapfc_{self.allocated}" in content:
                dev = get_what_from_swap_unit(unit_path)
                unit_name = os.path.basename(unit_path)
                ret_code = subprocess.run(["systemctl", "stop", unit_name]).returncode
                if ret_code != 0:
                    subprocess.run(["swapoff", dev], check=True)
                force_remove(unit_path, verbose=True)
                if os.path.isfile(dev):
                    force_remove(dev)
                break
        self.allocated -= 1
        systemd.daemon.notify("STATUS=Monitoring memory status...")

    @staticmethod
    def get_free_ram_perc() -> int:
        ram_stats = get_mem_stats(["MemTotal", "MemFree"])
        return round((ram_stats["MemFree"] * 100) / ram_stats["MemTotal"])

    @staticmethod
    def get_free_swap_perc() -> int:
        swap_stats = get_mem_stats(["SwapTotal", "SwapFree"])
        # Minimum for total is 1 to prevent divide by zero.
        return round((swap_stats["SwapFree"] * 100) / max(swap_stats["SwapTotal"], 1))


def debug(msg: str) -> None:
    if IS_DEBUG:
        print("DEBUG:", msg, file=sys.stderr)


def info(msg: str) -> None:
    print("INFO:", msg)


def warn(msg: str) -> None:
    print("WARN:", msg, file=sys.stderr)


def error(msg: str) -> NoReturn:
    print("ERRO:", msg, file=sys.stderr)
    sys.exit(1)


def force_remove(file: str, verbose: bool = False) -> None:
    try:
        os.remove(file)
        if verbose:
            info(f"Removed {file}")
    except OSError:
        if verbose:
            warn(f"Cannot remove {file}")


def relative_symlink(target: str, link_name: str) -> None:
    if os.path.lexists(link_name):
        force_remove(link_name)
    os.symlink(os.path.relpath(target, os.path.dirname(link_name)), link_name)


def write(data: str, file: str) -> None:
    with open(file, "w") as f:
        f.write(data)


def read(file: str) -> str:
    with open(file) as f:
        return f.read()


def am_i_root(exit_on_error: bool = True) -> bool:
    if os.getuid() == 0:
        return True
    if exit_on_error:
        error("Script must be run as root!")
    else:
        return False


def find_swap_units() -> List[str]:
    swap_units = []
    for path in ["/run/systemd/system", "/run/systemd/generator"]:
        for file_path in glob.glob(f"{path}/**/*.swap", recursive=True):
            if os.path.isfile(file_path) and not os.path.islink(file_path):
                swap_units.append(file_path)
    return swap_units


def get_what_from_swap_unit(file: str) -> str:
    with open(file) as file:
        for line in file.read().splitlines():
            if line.startswith("What="):
                return line[len("What=") :]


def gen_swap_unit(
    what: str, tag: str, priority: Optional[int] = None, options: Optional[str] = None
) -> str:
    what = os.path.realpath(what)
    # Assume it's a file by default.
    _type = "File"
    mode = os.stat(what).st_mode
    if stat.S_ISBLK(mode):
        _type = "Block/Partition"
        if "loop" in what:
            _type = "File"
    unit_name = subprocess.run(
        ["systemd-escape", "-p", "--suffix=swap", what],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.rstrip()
    unit_path = f"{RUN_SYSD}/system/{unit_name}"
    content = (
        "[Unit]\n"
        f"Description=Swap {_type}\n"
        "Documentation=https://github.com/Nefelim4ag/systemd-swap\n"
        "\n"
        "# Generated by systemd-swap\n"
        f"# Tag={tag}\n"
        "\n"
        "[Swap]\n"
        f"What={what}\n"
        "TimeoutSec=1h\n"
    )
    if priority:
        content += f"Priority={priority}\n"
    if options:
        content += f"Options={options}\n"
    write(content, unit_path)
    relative_symlink(unit_path, f"{RUN_SYSD}/system/swap.target.wants/{unit_name}")
    if _type == "File":
        relative_symlink(
            unit_path, f"{RUN_SYSD}/system/local-fs.target.wants/{unit_name}"
        )
    return unit_name


def swapoff(unit_path: str, subsystem: str) -> None:
    dev = get_what_from_swap_unit(unit_path)
    info(f"{subsystem}: swapoff {dev}")
    subprocess.run(["swapoff", dev])
    force_remove(unit_path, verbose=True)
    if subsystem == "swapFC":
        if os.path.isfile(dev):
            force_remove(dev, verbose=True)
    elif subsystem == "Zram":
        subprocess.run(["zramctl", "-r", dev])


def makedirs(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def sigterm_handler(signum: int, frame: Optional[types.FrameType]) -> None:
    sigterm_event.set()


def get_sem_id() -> int:
    sysv_id = sysv_ipc.ftok(__file__, 1, silence_warning=True)
    debug(f"ftok() returned this ID: {sysv_id}")
    return sysv_id


def init_directories() -> None:
    makedirs(WORK_DIR)
    makedirs(f"{RUN_SYSD}/system/local-fs.target.wants")
    makedirs(f"{RUN_SYSD}/system/swap.target.wants")


def start() -> None:
    def start_swapd() -> None:
        systemd.daemon.notify("STATUS=Activating swap units...")
        info("swapD: pick up devices from systemd-gpt-auto-generator")
        for unit_path in find_swap_units():
            if "systemd-gpt-auto-generator" in read(unit_path):
                dev = get_what_from_swap_unit(unit_path)
                subprocess.run(["swapoff", dev], check=True)
                force_remove(unit_path, verbose=True)
        info("swapD: searching swap devices")
        makedirs(f"{WORK_DIR}/swapd")
        swapd_prio = config.get("swapd_prio", int)
        # blkid returns 2 if nothing was found.
        devices = subprocess.run(
            ["blkid", "-t", "TYPE=swap", "-o", "device"],
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.splitlines()
        for device in devices:
            if "zram" in device or "loop" in device:
                continue
            used_devices = subprocess.run(
                ["swapon", "--show=NAME", "--noheadings"],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout.splitlines()
            for used_device in used_devices:
                if device == used_device:
                    device = None
            if device is None:
                continue
            mode = os.stat(device).st_mode
            if not stat.S_ISBLK(mode):
                continue
            unit_name = gen_swap_unit(
                what=device, options="discard", priority=swapd_prio, tag="swapd"
            )
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            ret_code = subprocess.run(["systemctl", "start", unit_name]).returncode
            if ret_code != 0:
                continue
            info(f"swapD: enabled device: {device}")
            swapd_prio -= 1
        systemd.daemon.notify("STATUS=Swap unit activation finished")

    def start_zswap() -> None:
        systemd.daemon.notify("STATUS=Setting up Zswap...")
        if not os.path.isdir(ZSWAP_M):
            error("Zswap - not supported on current kernel")
        info("Zswap: backup current configuration: start")
        makedirs(f"{WORK_DIR}/zswap")
        for file in os.listdir(ZSWAP_M_P):
            file_path = os.path.join(ZSWAP_M_P, file)
            zswap_parameters[file_path] = read(file_path)
        info("Zswap: backup current configuration: complete")
        info("Zswap: set new parameters: start")
        info(
            f'Zswap: Enable: {config.get("zswap_enabled")}, Comp: '
            f'{config.get("zswap_compressor")}, Max pool %: '
            f'{config.get("zswap_max_pool_percent")}, Zpool: '
            f'{config.get("zswap_zpool")}'
        )
        write(config.get("zswap_enabled"), f"{ZSWAP_M_P}/enabled")
        write(config.get("zswap_compressor"), f"{ZSWAP_M_P}/compressor")
        write(config.get("zswap_max_pool_percent"), f"{ZSWAP_M_P}/max_pool_percent")
        write(config.get("zswap_zpool"), f"{ZSWAP_M_P}/zpool")
        info("Zswap: set new parameters: complete")

    def start_zram() -> None:
        systemd.daemon.notify("STATUS=Setting up Zram...")
        info("Zram: check module availability")
        if not os.path.isdir("/sys/module/zram"):
            error("Zram: module not availible")
        else:
            info("Zram: module found!")

        def zram_init() -> None:
            info("Zram: trying to initialize free device")
            output = None
            success = False
            for n in range(3):
                if n > 0:
                    warn(f"Zram: device or resource was busy, retry #{n}")
                    time.sleep(1)
                # zramctl is an external program -> return path to first free device.
                output = subprocess.run(
                    [
                        "zramctl",
                        "-f",
                        "-a",
                        config.get("zram_alg"),
                        "-s",
                        str(zram_size),
                    ],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                ).stdout.rstrip()
                if "failed to reset: Device or resource busy" in output:
                    continue
                success = True
                break
            # Try limit reached.
            if not success:
                warn("Zram: device or resource was busy too many times")
                return
            zram_dev = None
            if "zramctl: no free zram device found" in output:
                warn("Zram: zramctl can't find free device")
                info("Zram: using workaround hook for hot add")
                if not os.path.isfile("/sys/class/zram-control/hot_add"):
                    error(
                        "Zram: this kernel does not support hot adding zram devices, "
                        "please use a 4.2+ kernel or see 'modinfo zram´ and create a "
                        "modprobe rule"
                    )
                new_zram = read("/sys/class/zram-control/hot_add").rstrip()
                zram_dev = f"/dev/zram{new_zram}"
                info(f"Zram: success: new device {zram_dev}")
            elif "/dev/zram" in output:
                mode = os.stat(output).st_mode
                if not stat.S_ISBLK(mode):
                    return
                zram_dev = output
            else:
                error(f"Zram: unexpected output from zramctl: {output}")

            mode = os.stat(zram_dev).st_mode
            if stat.S_ISBLK(mode):
                info(f"Zram: initialized: {zram_dev}")
                ret_code = subprocess.run(
                    ["mkswap", zram_dev],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                ).returncode
                if ret_code == 0:
                    unit_name = gen_swap_unit(
                        what=zram_dev,
                        options="discard",
                        priority=config.get("zram_prio"),
                        tag="zram",
                    )
                    subprocess.run(["systemctl", "daemon-reload"], check=True)
                    subprocess.run(["systemctl", "start", unit_name], check=True)
            else:
                warn("Zram: can't get free zram device")

        if KMAJOR <= 4 and KMINOR <= 7:
            zram_size = round(
                config.get("zram_size", int) / config.get("zram_count", int)
            )
            for _ in range(config.get("zram_count", int)):
                zram_init()
        else:
            zram_size = config.get("zram_size", int)
            zram_init()
        systemd.daemon.notify("STATUS=Zram setup finished")

    am_i_root()
    # Clean up in case a previous instance did not exit cleanly.
    stop(on_init=True)
    init_directories()
    sem = None
    try:
        # Semaphore guarding against running more than one instance and signalling if
        # cleanup can start.
        sem = sysv_ipc.Semaphore(get_sem_id(), flags=sysv_ipc.IPC_CREX)
    except sysv_ipc.ExistentialError:
        error(f"{sys.argv[0]} already started")
    config = Config()
    yn = lambda x: config.get(x, bool)
    if yn("zram_enabled") and (
        yn("zswap_enabled") or yn("swapfc_enabled") or yn("swapd_auto_swapon")
    ):
        warn(
            "Combining zram with zswap/swapfc/swapd_auto_swapon can lead to LRU "
            "inversion and is strongly recommended against"
        )
    if yn("zswap_enabled"):
        start_zswap()
    if yn("zram_enabled"):
        start_zram()
    info("Writing destroy info...")
    DestroyInfo(zswap_parameters).save()
    if yn("swapd_auto_swapon"):
        start_swapd()
    if yn("swapfc_enabled"):
        swap_fc = SwapFc(config, sem)
        swap_fc.run()
    else:
        systemd.daemon.notify("READY=1")
        # Done setting up. Allow cleanup to take place.
        sem.release()


def stop(on_init: bool = False) -> None:
    am_i_root()
    config = Config()
    sem = None
    sem_id = get_sem_id()
    try:
        sem = sysv_ipc.Semaphore(sem_id)
        if not on_init:
            try:
                sem.acquire(60)
            except sysv_ipc.BusyError:
                warn("Could not acquire semaphore, commencing stop action anyway...")
            systemd.daemon.notify("STOPPING=1")
    except sysv_ipc.ExistentialError:
        # Prevent systemd-swap from starting/stopping while cleaning up.
        sem = sysv_ipc.Semaphore(sem_id, flags=sysv_ipc.IPC_CREX)
        if not on_init:
            warn(f"{sys.argv[0]} might not be running")
    destroy_info = DestroyInfo.load()
    swap_units = find_swap_units()
    swap_unit_found = None
    for i in ["swapD", "swapFC", "Zram"]:
        for unit_path in filter(lambda u, ix=i: ix.lower() in read(u), swap_units):
            swapoff(unit_path, i)
            swap_unit_found = True
        if swap_unit_found:
            swap_units = find_swap_units()
            swap_unit_found = False
    if destroy_info:
        if os.path.isdir(f"{WORK_DIR}/zswap"):
            info("Zswap: restore configuration: start")
            for zswap_parameter, value in destroy_info.zswap_parameters.items():
                write(value, zswap_parameter)
            info("Zswap: restore configuration: complete")
    info("Removing working directory...")
    shutil.rmtree(WORK_DIR, ignore_errors=True)
    swapfc_path = config.get("swapfc_path")
    info(f"Removing files in {swapfc_path}...")
    try:
        for file in os.listdir(swapfc_path):
            force_remove(os.path.join(swapfc_path, file), verbose=True)
    except OSError:
        pass
    sem.remove()


def status() -> None:
    if not am_i_root(exit_on_error=False):
        warn("Not root! Some output might be missing.")
    swap_stats = get_mem_stats(["SwapTotal", "SwapFree"])
    swap_used = swap_stats["SwapTotal"] - swap_stats["SwapFree"]
    try:
        if os.path.isdir("/sys/module/zswap"):
            used_bytes = int(read("/sys/kernel/debug/zswap/pool_total_size"))
            used_pages = used_bytes / PAGE_SIZE
            stored_pages = int(read("/sys/kernel/debug/zswap/stored_pages"))
            stored_bytes = stored_pages * PAGE_SIZE
            ratio = 0
            if stored_pages > 0:
                ratio = used_pages * 100 / stored_pages
            zswap_info = ""
            for file in sorted(os.listdir("/sys/module/zswap/parameters")):
                zswap_info += (
                    f'. {file} {read(f"/sys/module/zswap/parameters/{file}")}\n'
                )
            subprocess.run(["column", "-t"], input=zswap_info, text=True)
            zswap_info = ""
            for file in sorted(os.listdir("/sys/kernel/debug/zswap")):
                zswap_info += f'. . {file} {read(f"/sys/kernel/debug/zswap/{file}")}\n'
            zswap_info += f". . compress_ratio {round(ratio)}%\n"
            if swap_used > 0:
                zswap_info += (
                    f". . zswap_store/swap_store {stored_bytes}/{swap_used} "
                    f"{round(stored_bytes * 100 / swap_used)}%\n"
                )
            print("Zswap:")
            subprocess.run(["column", "-t"], input=zswap_info, text=True)
    except:
        warn("Zswap info inaccesible")
    zramctl = subprocess.run(
        ["zramctl"], check=True, text=True, stdout=subprocess.PIPE
    ).stdout
    if "[SWAP]" in zramctl:  # pylint: disable=unsupported-membership-test
        zramctl = zramctl.splitlines()
        zram_info = ""
        for line in zramctl:
            if line.startswith("NAME") or "[SWAP]" in line:
                if line.endswith("MOUNTPOINT"):
                    line = line[: -len("MOUNTPOINT")]
                elif line.endswith("[SWAP]"):
                    line = line[: -len("[SWAP]")]
                zram_info += f". {line}\n"
        print("Zram:")
        subprocess.run(["column -t | uniq"], input=zram_info, text=True, shell=True)
    if os.path.isdir(f"{WORK_DIR}/swapd"):
        swapon = subprocess.run(
            ["swapon", "--raw"], check=True, text=True, stdout=subprocess.PIPE
        ).stdout.splitlines()
        swapd_info = "".join(
            [f". {line}\n" for line in swapon if not re.search("zram|file|loop", line)]
        )
        print("swapD:")
        subprocess.run(["column", "-t"], input=swapd_info, text=True)
    if os.path.isdir(f"{WORK_DIR}/swapfc"):
        swapon = subprocess.run(
            ["swapon", "--raw"], check=True, text=True, stdout=subprocess.PIPE
        ).stdout.splitlines()
        swapfc_info = "".join(
            [f". {line}\n" for line in swapon if re.search("NAME|file|loop", line)]
        )
        print("swapFC:")
        subprocess.run(["column", "-t"], input=swapfc_info, text=True)


def compression() -> None:
    proc_crypto = None
    with open("/proc/crypto") as f:
        proc_crypto = f.read()
    matches = re.finditer(  # pylint: disable=no-member
        r"name\s*:\s*(\S*).*?type\s*:\s*(\S*)",
        proc_crypto,
        re.DOTALL,  # pylint: disable=no-member
    )
    print("Found loaded compression algorithms: ", end="")
    first = True
    for match in matches:
        algo, _type = match.groups()
        if _type == "compression":
            if first:
                first = False
            else:
                print(", ", end="")
            print(algo, end="")
    print()


def main() -> None:
    argparser = argparse.ArgumentParser()
    argparser.add_argument(
        "command",
        choices=["start", "stop", "status", "compression"],
        default="status",
        nargs="?",
        help="`start' the daemon, `stop' it, show some swap `status' info, or display "
        "the loaded `compression' algorithms",
    )
    args = argparser.parse_args()
    if args.command == "start":
        start()
    elif args.command == "stop":
        stop()
    elif args.command == "status":
        status()
    elif args.command == "compression":
        compression()
    else:
        raise RuntimeError


if __name__ == "__main__":
    main()
