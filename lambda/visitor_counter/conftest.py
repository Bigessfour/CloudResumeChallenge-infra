"""Pytest bootstrap for the visitor counter Lambda.

The handler reads env vars at module-import time (`TABLE_NAME` is required), so
these must be set BEFORE `handler.py` is imported by any test module. pytest
loads `conftest.py` first, which is the canonical place to do this.

These values are intentionally cheap fakes; moto-mocked AWS clients
created in test fixtures ignore them but boto3 still requires *something* to
be set so it does not look up real credentials/region.
"""

import os

os.environ.setdefault("TABLE_NAME", "visitor-counter-test")
os.environ.setdefault("COUNTER_KEY", "visitor-counter")
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_SESSION_TOKEN", "testing")
