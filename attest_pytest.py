import json
import os
import sys

_rootdir = None


def _emit(event):
    sys.__stderr__.write(json.dumps(event) + "\n")
    sys.__stderr__.flush()


def _relative(path):
    if _rootdir and os.path.isabs(path) and path.startswith(_rootdir + os.sep):
        return os.path.relpath(path, _rootdir)
    return path


def pytest_configure(config):
    global _rootdir
    _rootdir = str(config.rootpath)


def pytest_runtest_logreport(report):
    if report.when == "call" or (report.when == "setup" and report.outcome != "passed"):
        event = {
            "nodeid": report.nodeid,
            "outcome": report.outcome,
            "when": report.when,
            "rootdir": _rootdir,
            "location": list(report.location),
            "duration": report.duration,
        }
        longrepr = getattr(report, "longrepr", None)
        crash = getattr(longrepr, "reprcrash", None)
        if crash is not None:
            event["crash"] = {"path": _relative(crash.path), "lineno": crash.lineno, "message": crash.message}
        elif isinstance(longrepr, tuple) and len(longrepr) == 3:
            event["message"] = longrepr[2]
        elif longrepr is not None:
            event["message"] = str(longrepr)
        _emit(event)
