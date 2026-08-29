"""Lazy, process-wide Firestore client.

Kept in one place so every tool module shares a connection instead of
opening a new one per call, and so tests can monkeypatch `get_db()`.
"""
import os
from functools import lru_cache

from google.auth.exceptions import DefaultCredentialsError
from google.cloud import firestore


class FirestoreUnavailable(Exception):
    """Raised when Firestore can't be reached — no credentials, wrong project,
    etc. Tool functions catch this and return a spoken/typed error instead of
    crashing the whole agent turn."""


@lru_cache(maxsize=1)
def get_db() -> firestore.Client:
    database = os.environ.get("FIRESTORE_DATABASE", "(default)")
    try:
        return firestore.Client(database=database)
    except DefaultCredentialsError as e:
        raise FirestoreUnavailable(
            "Firestore isn't reachable (no Application Default Credentials). "
            "Run `gcloud auth application-default login` locally, or make "
            "sure the deployed service has a service account attached."
        ) from e
