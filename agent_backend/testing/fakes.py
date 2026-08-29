"""In-memory stand-ins for Firestore and the Google Calendar API, implementing
only the surface the tools in welwi_agent/tools actually call. Lets the demo
script exercise real Gemini + real ADK tool-calling end-to-end without a GCP
project — this verifies agent *logic*, not cloud plumbing (that's a separate,
manual setup step covered in README.md).
"""
import itertools
import uuid


class _FakeDocSnapshot:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = data

    def to_dict(self):
        return dict(self._data)


class _FakeDocRef:
    def __init__(self, collection, doc_id):
        self._collection = collection
        self.id = doc_id

    def set(self, data):
        self._collection._docs[self.id] = dict(data)


class _FakeQuery:
    def __init__(self, collection, filters=None, order=None, limit_n=None):
        self._collection = collection
        self._filters = filters or []
        self._order = order
        self._limit = limit_n

    def where(self, field, op, value):
        assert op == "==", f"fake only supports '==', got {op}"
        return _FakeQuery(self._collection, self._filters + [(field, value)], self._order, self._limit)

    def order_by(self, field, direction="ASCENDING"):
        return _FakeQuery(self._collection, self._filters, (field, direction), self._limit)

    def limit(self, n):
        return _FakeQuery(self._collection, self._filters, self._order, n)

    def stream(self):
        items = list(self._collection._docs.items())
        for field, value in self._filters:
            items = [(k, v) for k, v in items if v.get(field) == value]
        if self._order:
            field, direction = self._order
            items.sort(key=lambda kv: kv[1].get(field, ""), reverse=("DESC" in direction))
        if self._limit:
            items = items[: self._limit]
        return [_FakeDocSnapshot(k, v) for k, v in items]


class _FakeCollection:
    def __init__(self, name):
        self.name = name
        self._docs = {}
        self._id_counter = itertools.count(1)

    def document(self):
        return _FakeDocRef(self, f"{self.name}-{next(self._id_counter)}")

    def add(self, data):
        doc_id = f"{self.name}-{next(self._id_counter)}"
        self._docs[doc_id] = dict(data)
        return (None, _FakeDocRef(self, doc_id))

    def where(self, field, op, value):
        return _FakeQuery(self).where(field, op, value)

    def order_by(self, field, direction="ASCENDING"):
        return _FakeQuery(self).order_by(field, direction)

    def limit(self, n):
        return _FakeQuery(self).limit(n)


class FakeFirestore:
    """Drop-in for `firestore.Client` covering .collection(name).{document,add,where,order_by,limit}"""

    def __init__(self):
        self._collections = {}

    def collection(self, name):
        if name not in self._collections:
            self._collections[name] = _FakeCollection(name)
        return self._collections[name]

    def dump(self):
        return {name: dict(col._docs) for name, col in self._collections.items()}


class FakeCalendarEvents:
    def __init__(self, store):
        self._store = store

    def insert(self, calendarId, body):
        event_id = f"evt-{uuid.uuid4().hex[:8]}"
        event = {"id": event_id, "htmlLink": f"https://calendar.google.com/event?eid={event_id}", **body}
        self._store.setdefault(calendarId, {})[event_id] = event
        return _Execute(event)

    def list(self, calendarId, timeMin=None, maxResults=10, singleEvents=True, orderBy="startTime"):
        events = list(self._store.get(calendarId, {}).values())
        events.sort(key=lambda e: e.get("start", {}).get("dateTime", ""))
        return _Execute({"items": events[:maxResults]})


class _Execute:
    def __init__(self, result):
        self._result = result

    def execute(self):
        return self._result


class FakeCalendarService:
    """Drop-in for the googleapiclient Calendar resource: `.events().insert/list(...).execute()`"""

    def __init__(self):
        self._store = {}

    def events(self):
        return FakeCalendarEvents(self._store)
