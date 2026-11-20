from datetime import date, timedelta

from eth_account import Account

from tests.test_api import API, login


def test_club_board_scopes_dates_and_upserts_hour(harness):
    client, *_ = harness
    headers = login(client, Account.create())
    entry = {
        "kind": "attendance",
        "branch": "Studio A",
        "day": "2026-01-01",
        "minute": 133,
        "amount": 4,
    }
    path = API + "/merchant/club-entries"
    assert client.post(path, json=entry, headers=headers).status_code == 403
    merchant = client.post(
        API + "/merchants", json={"business_name": "Club"}, headers=headers
    ).json()
    for count in [4, 0]:
        assert (
            client.post(
                path, json=dict(entry, amount=count), headers=headers
            ).status_code
            == 201
        )
    assert (
        client.post(
            path,
            json=dict(entry, day=str(date.today() + timedelta(days=2))),
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.post(
            path,
            json=dict(entry, kind="class", title="Yoga", amount=45),
            headers=headers,
        ).status_code
        == 201
    )
    board = API + f"/clubs/{merchant['id']}/board"
    data = client.get(board, params={"branch": "Studio A", "day": entry["day"]}).json()
    assert [(r["kind"], r["minute"], r["amount"]) for r in data] == [
        ("attendance", 120, 0),
        ("class", 133, 45),
    ]
    assert (
        client.get(board, params={"branch": "Studio B", "day": entry["day"]}).json()
        == []
    )
    assert (
        client.get(board, params={"branch": "Studio A", "day": "2026-01-02"}).json()
        == []
    )


def test_buddy_connection_requires_consent_and_one_use(harness):
    client, *_ = harness
    a, b = login(client, Account.create()), login(client, Account.create())
    code = client.post(API + "/me/buddy-invites", headers=a).json()["code"]
    assert (
        client.post(API + "/me/buddies", json={"code": code}, headers=a).status_code
        == 422
    )
    assert client.get(API + "/me/buddies", headers=b).json() == []
    assert (
        client.post(API + "/me/buddies", json={"code": code}, headers=b).status_code
        == 200
    )
    assert (
        client.post(API + "/me/buddies", json={"code": code}, headers=b).status_code
        == 422
    )
    assert len(client.get(API + "/me/buddies", headers=a).json()) == 1
