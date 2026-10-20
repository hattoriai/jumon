# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/jumon/security/advisories/new).

Say what an attacker can do, and how: the action, the source or the
event, and the steps or the payload. We answer within a week, agree on a
fix and a date, and credit you in the advisory unless you ask us not to.

## Supported versions

Security fixes are made to the latest release. Jumon is before 1.0, so a
fix is not backported to an earlier minor version.

## What is in scope

Jumon runs actions in your LiveView on events from the browser, which any
person can craft. A problem is in scope when such an event can:

- run an action that the LiveView did not give the person, or one that
  its `:allow` or `:disabled` refuses;
- run an action with an argument that its checks refuse: a `:choice`
  outside its options, a `:search` value its search did not give, a
  `:text` too long, or one that `:validate` turns down;
- read or change another person's history, or its results;
- put HTML or script into the page through the text of an action, a
  result or a message;
- crash the LiveView, or make the server or the database do unbounded
  work.

What a person may see and run is decided by your commands module: leaving
out of `actions/1` what a person may not see, giving `:allow` to the
rest, and scoping each source and the history key to the person is the
app's job (see the guides on actions, searching and history).
