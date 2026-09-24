#!/usr/bin/env python3
"""Audit the actual release compile commands and describe their CPU target."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import xml.etree.ElementTree as ET
from pathlib import Path


def cache_value(build: Path, key: str) -> str:
    for line in (build / "CMakeCache.txt").read_text(encoding="utf-8").splitlines():
        if line.startswith(key + ":"):
            return line.partition("=")[2]
    if key == "CMAKE_C_COMPILER":
        for compiler_file in (build / "CMakeFiles").rglob("CMakeCCompiler.cmake"):
            for line in compiler_file.read_text(encoding="utf-8").splitlines():
                match = re.match(r'set\(CMAKE_C_COMPILER "([^"]+)"\)', line)
                if match:
                    return match.group(1)
    raise RuntimeError(f"{key} is missing from {build / 'CMakeCache.txt'}")


def unix_commands(build: Path) -> list[str]:
    entries = json.loads((build / "compile_commands.json").read_text(encoding="utf-8"))
    if not entries:
        raise RuntimeError(f"no compile commands in {build}")
    return [entry.get("command") or shlex.join(entry["arguments"]) for entry in entries]


def audit_unix(build: Path, name: str, portable_x86: bool) -> list[str]:
    commands = unix_commands(build)
    for command in commands:
        args = shlex.split(command)
        for arg in args:
            if arg in ("-march=native", "-mtune=native", "-xHost") or arg.startswith("-mcpu="):
                raise RuntimeError(f"{name} uses host CPU targeting: {command}")
            if portable_x86 and arg.startswith("-m") and not (
                arg in ("-march=x86-64", "-mtune=generic", "-m64")
                or arg.startswith(("-mno-", "-mmacosx-version-min="))
            ):
                raise RuntimeError(f"{name} uses a nonbaseline CPU flag: {command}")
        if portable_x86 and (args.count("-march=x86-64") != 1 or args.count("-mtune=generic") != 1):
            raise RuntimeError(f"{name} lacks exactly one portable CPU target: {command}")
    return [
        f"{name}_CMAKE_C_COMPILER={cache_value(build, 'CMAKE_C_COMPILER')}",
        f"{name}_CMAKE_C_FLAGS={cache_value(build, 'CMAKE_C_FLAGS')}",
        f"{name}_CMAKE_C_FLAGS_RELEASE={cache_value(build, 'CMAKE_C_FLAGS_RELEASE')}",
        f"{name}_EFFECTIVE_COMPILE_COMMAND={commands[0]}",
        f"{name}_AUDITED_TRANSLATION_UNITS={len(commands)}",
    ]


def audit_windows(build: Path, name: str) -> list[str]:
    projects = list(build.rglob("*.vcxproj"))
    if not projects:
        raise RuntimeError(f"no Visual Studio projects in {build}")
    for project in projects:
        data = project.read_text(encoding="utf-8-sig")
        if re.search(r"(?:/arch:|<EnableEnhancedInstructionSet>)(?:AVX|SSE|AdvancedVector)", data, re.I):
            raise RuntimeError(f"{name} enables a nonbaseline instruction set in {project}")
    flags = [cache_value(build, key) for key in ("CMAKE_C_FLAGS", "CMAKE_C_FLAGS_RELEASE")]
    if re.search(r"/arch:|[-/]Q[a-z]*|[-/]xHost", " ".join(flags), re.I):
        raise RuntimeError(f"{name} sets an explicit CPU target: {flags}")
    source_project = build / ("GKlib.vcxproj" if name == "GKLIB" else "libmetis/qmetis_objs.vcxproj")
    if not source_project.is_file():
        raise RuntimeError(f"missing compiler project: {source_project}")
    tree = ET.parse(source_project)
    release_options: dict[str, str] = {}
    for group in tree.getroot():
        if group.tag.endswith("ItemDefinitionGroup") and "Release|x64" in group.attrib.get("Condition", ""):
            for section in group:
                if section.tag.endswith("ClCompile"):
                    release_options = {item.tag.rsplit("}", 1)[-1]: item.text or "" for item in section}
                    break
    if not release_options:
        raise RuntimeError(f"missing Release|x64 compiler settings in {source_project}")
    selected_options = {key: release_options.get(key, "") for key in (
        "Optimization", "FavorSizeOrSpeed", "AdditionalOptions", "EnableEnhancedInstructionSet"
    )}
    return [
        f"{name}_CMAKE_C_COMPILER={cache_value(build, 'CMAKE_C_COMPILER')}",
        f"{name}_CMAKE_C_FLAGS={flags[0]}",
        f"{name}_CMAKE_C_FLAGS_RELEASE={flags[1]}",
        f"{name}_RELEASE_CL_COMPILE_OPTIONS={selected_options}",
        f"{name}_AUDITED_VCXPROJ_FILES={len(projects)}",
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform")
    parser.add_argument("gklib_build", type=Path)
    parser.add_argument("qmetis_build", type=Path)
    args = parser.parse_args()

    if args.platform == "windows-x86_64":
        lines = ["CPU_TARGET=x86-64 (MSVC x64 default; no /arch override)"]
        lines += audit_windows(args.gklib_build, "GKLIB")
        lines += audit_windows(args.qmetis_build, "QMETIS")
    else:
        portable_x86 = args.platform in ("linux-x86_64", "macos-x86_64")
        lines = [f"CPU_TARGET={'x86-64 -mtune=generic' if portable_x86 else 'arm64'}"]
        lines += audit_unix(args.gklib_build, "GKLIB", portable_x86)
        lines += audit_unix(args.qmetis_build, "QMETIS", portable_x86)
    print("\n".join(lines))


if __name__ == "__main__":
    main()
