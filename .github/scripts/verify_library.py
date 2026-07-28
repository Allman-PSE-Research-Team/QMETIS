#!/usr/bin/env python3
"""Load a QMETIS library and verify its configured ABI and public API."""

from __future__ import annotations

import argparse
import ctypes
import os
import re
from pathlib import Path


def configured_width(header: Path, macro: str) -> int:
    pattern = re.compile(rf"^\s*#define\s+{macro}\s+(32|64)\s*$")
    for line in header.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            return int(match.group(1))
    raise RuntimeError(f"{macro} is not defined as 32 or 64 in {header}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("library", type=Path)
    parser.add_argument("header", type=Path)
    parser.add_argument("idx_width", type=int, choices=(32, 64))
    parser.add_argument("real_width", type=int, choices=(32, 64))
    args = parser.parse_args()

    library = args.library.resolve()
    header = args.header.resolve()
    if configured_width(header, "IDXTYPEWIDTH") != args.idx_width:
        raise RuntimeError("installed IDXTYPEWIDTH does not match the requested ABI")
    if configured_width(header, "REALTYPEWIDTH") != args.real_width:
        raise RuntimeError("installed REALTYPEWIDTH does not match the requested ABI")

    if os.name == "nt":
        os.add_dll_directory(str(library.parent))
    dll = ctypes.CDLL(str(library))

    idx_t = ctypes.c_int64 if args.idx_width == 64 else ctypes.c_int32
    real_t = ctypes.c_double if args.real_width == 64 else ctypes.c_float
    idx_p = ctypes.POINTER(idx_t)
    real_p = ctypes.POINTER(real_t)

    defaults = dll.METIS_SetDefaultOptions
    defaults.argtypes = [idx_p]
    defaults.restype = ctypes.c_int

    options = (idx_t * 40)()
    if defaults(options) != 1:
        raise RuntimeError("METIS_SetDefaultOptions did not return METIS_OK")

    partition_args = [
        idx_p, idx_p, idx_p, idx_p, idx_p, idx_p, idx_p,
        idx_p, real_p, real_p, idx_p, idx_p, idx_p,
    ]
    partition_kway = dll.METIS_PartGraphKway
    partition_kway.argtypes = partition_args
    partition_kway.restype = ctypes.c_int
    partition_recursive = dll.METIS_PartGraphRecursive
    partition_recursive.argtypes = partition_args
    partition_recursive.restype = ctypes.c_int

    nvtxs = idx_t(4)
    ncon = idx_t(1)
    xadj = (idx_t * 5)(0, 1, 2, 3, 4)
    adjncy = (idx_t * 4)(1, 0, 3, 2)
    nparts = idx_t(2)
    option_objtype = 1
    option_modresolution = 30
    resolution_scale = 1_000_000

    def run_partition(function, resolution: float | None) -> tuple[int, list[int]]:
        if defaults(options) != 1:
            raise RuntimeError("METIS_SetDefaultOptions did not return METIS_OK")
        if resolution is not None:
            options[option_modresolution] = round(resolution * resolution_scale)

        objective = idx_t()
        parts = (idx_t * 4)()
        result = function(
            ctypes.byref(nvtxs), ctypes.byref(ncon), xadj, adjncy,
            None, None, None, ctypes.byref(nparts), None, None,
            options, ctypes.byref(objective), parts,
        )
        if result != 1:
            raise RuntimeError(
                f"{function.__name__} returned {result}, expected METIS_OK"
            )
        if any(part < 0 or part >= nparts.value for part in parts):
            raise RuntimeError(f"QMETIS returned an invalid partition: {list(parts)}")
        return objective.value, list(parts)

    expected = {None: 500_000, 0.0: 1_000_000, 0.5: 750_000, 2.0: 0}
    verified: list[str] = []
    for function in (partition_kway, partition_recursive):
        for resolution, expected_objective in expected.items():
            objective, parts = run_partition(function, resolution)
            if objective != expected_objective:
                raise RuntimeError(
                    f"{function.__name__} at gamma="
                    f"{1.0 if resolution is None else resolution} returned "
                    f"{objective}, expected {expected_objective}"
                )
            verified.append(
                f"{function.__name__}(gamma="
                f"{1.0 if resolution is None else resolution})={objective}"
            )

    vertex_weights = (idx_t * 4)(1, 1, 2, 2)
    target_weights = (real_t * 2)(1.0 / 3.0, 2.0 / 3.0)
    imbalance = (real_t * 1)(1.001)
    for function in (partition_kway, partition_recursive):
        if defaults(options) != 1:
            raise RuntimeError("METIS_SetDefaultOptions did not return METIS_OK")
        objective = idx_t()
        parts_array = (idx_t * 4)()
        result = function(
            ctypes.byref(nvtxs), ctypes.byref(ncon), xadj, adjncy,
            vertex_weights, None, None, ctypes.byref(nparts),
            target_weights, imbalance, options,
            ctypes.byref(objective), parts_array,
        )
        part_weights = [0, 0]
        for vertex, part in enumerate(parts_array):
            part_weights[part] += vertex_weights[vertex]
        if result != 1 or part_weights != [2, 4]:
            raise RuntimeError(
                f"{function.__name__} did not preserve weighted target balance: "
                f"status={result}, weights={part_weights}"
            )
        verified.append(f"{function.__name__}(weighted-balance)={part_weights}")

    if defaults(options) != 1:
        raise RuntimeError("METIS_SetDefaultOptions did not return METIS_OK")
    options[option_objtype] = 0
    objective = idx_t()
    parts_array = (idx_t * 4)()
    result = partition_recursive(
        ctypes.byref(nvtxs), ctypes.byref(ncon), xadj, adjncy,
        None, None, None, ctypes.byref(nparts), None, None,
        options, ctypes.byref(objective), parts_array,
    )
    if result != 1 or objective.value != 0:
        raise RuntimeError(
            "explicit recursive METIS_OBJTYPE_CUT did not retain edge-cut behavior"
        )
    verified.append("METIS_PartGraphRecursive(cut)=0")

    if defaults(options) != 1:
        raise RuntimeError("METIS_SetDefaultOptions did not return METIS_OK")
    options[option_objtype] = 3
    options[option_modresolution] = -2
    objective = idx_t()
    parts_array = (idx_t * 4)()
    result = partition_recursive(
        ctypes.byref(nvtxs), ctypes.byref(ncon), xadj, adjncy,
        None, None, None, ctypes.byref(nparts), None, None,
        options, ctypes.byref(objective), parts_array,
    )
    if result != -2:
        raise RuntimeError(
            "negative modularity resolution was not rejected with METIS_ERROR_INPUT"
        )

    print(
        f"verified {library.name}: idx={args.idx_width}, real={args.real_width}, "
        + ", ".join(verified)
    )


if __name__ == "__main__":
    main()
