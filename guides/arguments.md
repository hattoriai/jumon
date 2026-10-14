# Arguments

An action with `:args` asks for values before it runs: "Assign to…" asks
for a person, "Rename…" for a name. The palette asks for each argument in
turn, on a page with the action's name and the values chosen so far as
its breadcrumb, then sends the values to `:run`:

```elixir
action(:assign, "Assign to…",
  icon: "hero-user-plus",
  args: [
    issue: [label: "Issue", search: &issue_values/1, placeholder: "Which issue?"],
    person: [label: "Person", search: &people/2, async: true, placeholder: "Assign to whom?"],
    note: [type: :text, placeholder: "A note for them", optional: true, max_length: 200]
  ],
  run: fn %{issue: issue_id, person: person_id, note: note}, socket ->
    Issues.assign!(socket.assigns.current_scope, issue_id, person_id, note)
    Phoenix.LiveView.put_flash(socket, :info, "Assigned")
  end
)
```

`Jumon.Arg` lists every option.

## Kinds

* `:choice` - one of a list of `:options`, which the palette filters as
  the person types. The kind when `:options` are given.

  ```elixir
  priority: [options: [{"high", "High"}, {"medium", "Medium"}, {"low", "Low"}]]
  ```

* `:search` - one of the results of `:search`, a function of the query
  (or of the query and the socket), as a [source](searching.md). The kind
  when `:search` is given. `async: true` runs it in a task, `min_length`
  waits for some characters ("Keep typing to search").

* `:text` - what the person types, sent with Enter. The kind otherwise.
  `:max_length` (500 by default) and `optional: true` (an empty text is
  `nil`).

Options and results are actions, maps with `:id` and `:name`, or
`{id, name}` tuples, with icons, subtitles and avatars as any action.

## What `:run` gets

A map keyed by the arguments' names: the id of the chosen option or
result, as a string, or the text (trimmed). The function is
`fn args, socket -> ... end`, and returns what any `:run` returns.

## Checked on the server

The values come from the browser, so the hook checks each before `:run`
gets it:

* a `:choice` must be one of the options;
* a `:search` value must be one of the results that its search gave this
  socket;
* a `:text` must be a string of at most `:max_length` characters (and not
  empty, unless `:optional`);
* then `:validate`, when given: a function of the value (and the socket)
  that returns `:ok`, `{:ok, value}` (a value of its own, such as a
  record), or `{:error, message}`.

A value that fails goes back to its page, with the message ("That value
cannot be used", or yours), to choose again. `:allow` and `:disabled` are
checked too, as for any action.

```elixir
email: [
  type: :text,
  placeholder: "Their email",
  validate: fn email ->
    if email =~ ~r/^[^@\s]+@[^@\s]+$/, do: :ok, else: {:error, "That is not an email"}
  end
]
```

## With a question to confirm

`confirm:` on an action with arguments asks after the last value, before
`:run`.

## From a shortcut

The shortcut of an action with arguments opens the palette on its first
argument's page.
