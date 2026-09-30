# contacts-mirror

Refreshes the vault's 27.20 Contacts mirror (`20-29 People/27 PRM/27.20 Contacts/`) from Apple Contacts. Nelson ruled it on 2026-09-30 ("a plus job"). The job ships with `status: disabled`. The macOS ship owns the job, the obsidian ship owns the note shape and the write rules, and the people ship names the keys the mirror carries and who is in it.

## Files

- `run.sh`: the tickle entry point. It runs the gates (fleet pause, fleet load, a fresh vault backup), then `mirror.py`.
- `mirror.py`: the job. It reads the cards, matches them to the notes and rewrites the keys it owns. Standard library only, `/usr/bin/python3`.
- `config.json`: the reader command, the folder, the key families the mirror carries (`keys`), and the create rule (`create`, `none` until the people ship rules).
- `tests/test_mirror.py`: tests on made-up cards only. Run them with `/usr/bin/python3 -m unittest discover -s tickle/scripts/contacts-mirror/tests`.

## The reader's JSON

The reader is any command that prints one JSON object on stdout and exits 0. It is set in `config.json` as `reader`. The one planned is a one-shot Contacts-reader app in macos-tools with a Contacts-only grant: it starts, reads, writes the JSON and exits.

```json
{
  "cards": [
    {
      "id": "<CNContact identifier, e.g. 1A2B…:ABPerson>",
      "uid": "<optional vCard UID>",
      "fn": "Ada Example",
      "n": {"given": "Ada", "middle": "Q", "family": "Example"},
      "org": "Example Co",
      "title": "Engineer",
      "tel": [{"label": "_$!<Mobile>!$_", "value": "+1 555 0100"}],
      "email": [{"label": "home", "value": "ada@example.com"}],
      "adr": [{"label": "home", "street": "1 Main St", "locality": "Springfield", "region": "XX", "postal": "00000", "country": "Nowhere"}],
      "url": [{"label": "homepage", "value": "https://example.com"}],
      "bday": "1990-01-02",
      "dates": [{"label": "_$!<Anniversary>!$_", "value": "2015-06-07"}]
    }
  ]
}
```

Only `id` is required. A birthday with no year is written `--MM-DD`. Labels may be Contacts' raw form (`_$!<Mobile>!$_`) or plain words. They become vCard tags (`CELL`, `HOME`, `WORK`, `OTHER` and so on), and a second value with the same label gets a number (`TEL[CELL2]`).

## Keys

The job owns the vCard keys of the families in `keys`: `FN`, `N.GN`, `N.MN`, `N.FN`, `ORG`, `ROLE`, `TEL[…]`, `EMAIL[…]`, `ADR[…].STREET/LOCALITY/REGION/POSTAL/COUNTRY`, `URL[…]`, `BDAY` and `ANNIVERSARY`. It also owns `modified` and the two status keys. It never writes `uid`, `title`, `aliases`, `tags`, `source`, `UID`, `VERSION`, `messages`, `last-contacted`, `photos-faces` or the body. An unchanged key keeps its line exactly as it was. A key the card no longer has is removed.

A note whose card is gone gets `contact-status: missing-from-contacts` and `contact-missing-since: <date>`, and nothing else changes. The job never deletes, trashes or moves a note. If the card comes back, it removes both keys.

## Dry run

Copy the folder to /tmp and point the job at the copy. The job refuses a target inside the vault.

```bash
mkdir -p /tmp/cm/"20-29 People/27 PRM"
cp -R ~/obsidian/"20-29 People/27 PRM/27.20 Contacts" /tmp/cm/"20-29 People/27 PRM/"
tickle/scripts/contacts-mirror/run.sh --target-dir /tmp/cm --reader cat /tmp/cards.json --show 5
```
