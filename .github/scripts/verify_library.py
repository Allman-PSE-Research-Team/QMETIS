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

    partition = dll.METIS_PartGraphKway
    partition.argtypes = [
        idx_p, idx_p, idx_p, idx_p, idx_p, idx_p, idx_p,
        idx_p, real_p, real_p, idx_p, idx_p, idx_p,
    ]
    partition.restype = ctypes.c_int

    nvtxs = idx_t(4)
    ncon = idx_t(1)
    xadj = (idx_t * 5)(0, 1, 2, 3, 4)
    adjncy = (idx_t * 4)(1, 0, 3, 2)
    nparts = idx_t(2)
    objective = idx_t()
    parts = (idx_t * 4)()

    result = partition(
        ctypes.byref(nvtxs), ctypes.byref(ncon), xadj, adjncy,
        None, None, None, ctypes.byref(nparts), None, None,
        options, ctypes.byref(objective), parts,
    )
    if result != 1:
        raise RuntimeError(f"METIS_PartGraphKway returned {result}, expected METIS_OK")
    if any(part < 0 or part >= nparts.value for part in parts):
        raise RuntimeError(f"QMETIS returned an invalid partition: {list(parts)}")

    print(
        f"verified {library.name}: idx={args.idx_width}, real={args.real_width}, "
        f"objective={objective.value}, partition={list(parts)}"
    )


if __name__ == "__main__":
    main()