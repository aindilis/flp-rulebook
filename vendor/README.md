# vendor/

Third-party code bundled with flp-rulebook so the repository is
self-contained.

## pyhop.py

`pyhop.py` is **PyHOP**, a simple SHOP-like Hierarchical Task Network
(HTN) planner written in Python by Dana S. Nau.

- **Author:** Dana S. Nau, University of Maryland
- **Version:** Pyhop 2.0 (2013)
- **License:** Apache License 2.0 (see the header inside `pyhop.py`)
- **Upstream:** https://bitbucket.org/dananau/pyhop (original);
  widely mirrored, e.g. https://github.com/dananau/pyhop

It is vendored here, rather than installed via `pip`, for two
reasons. First, the name `pyhop` on PyPI refers to an unrelated
network utility — installing "pyhop" from PyPI does **not** get you
this planner. Second, vendoring makes the planner round-trip
(`flp_planner.pl`) work from a fresh clone with no installation step:
only a `python3` interpreter is required.

### Local modification

The upstream file begins with `from pyhop.helpers import (...)`,
which assumes PyHOP is installed as a multi-file package. Those
helpers are debug-printing functions only, used nowhere in the
planning algorithm. To keep `pyhop.py` a single self-contained file,
that import was replaced with four no-op stub definitions
(`print_state`, `print_goal`, `print_methods`, `print_operators`).
No planning behaviour is affected.

`flp_planner.pl` adds this directory to `PYTHONPATH` when it invokes
the planner, so no system-wide installation is needed.
