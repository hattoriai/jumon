defmodule Jumon.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Jumon.Components

  defp jumon(actions) do
    %{
      "v" => 1,
      "actions" => Enum.map(actions, &Jumon.Action.to_client/1),
      "sources" => [],
      "history" => "local"
    }
  end

  defp palette(html, id \\ "jumon") do
    node = html |> LazyHTML.from_fragment() |> LazyHTML.query_by_id(id)
    [config] = LazyHTML.attribute(node, "data-config")
    {node, JSON.decode!(config)}
  end

  test "the palette: the hook, its config and the words of its locale" do
    assigns = %{jumon: jumon([Jumon.action(:home, "Home", navigate: "/", icon: "hero-home")])}

    html =
      rendered_to_string(~H"""
      <Components.command_palette jumon={@jumon} locale="pt-PT" shortcut={["mod+k", "/"]} recent={3} />
      """)

    {node, config} = palette(html)
    assert LazyHTML.attribute(node, "phx-hook") == ["Jumon"]
    assert config["live"] == true
    assert config["locale"] == "pt-PT"
    assert config["messages"]["recent"] == "Recentes"

    assert config["options"] == %{
             "shortcut" => ["mod+k", "/"],
             "recent" => 3,
             "help" => true,
             "linkActions" => true,
             "icons" => false
           }

    assert [%{"id" => "home", "icon" => "hero-home"}] = config["actions"]
    # The palette's own markup is the hook's, under phx-update="ignore".
    assert LazyHTML.attribute(LazyHTML.query(node, ".jumon-ui"), "phx-update") == ["ignore"]
    assert Enum.empty?(LazyHTML.query(node, "template"))
  end

  test "the :icon slot renders each icon once, as a template" do
    assigns = %{
      jumon:
        jumon([
          Jumon.action(:home, "Home", navigate: "/", icon: "hero-home"),
          Jumon.action(:also, "Also home", navigate: "/", icon: "hero-home"),
          Jumon.action(:rocket, "Launch", navigate: "/", icon: "🚀")
        ])
    }

    html =
      rendered_to_string(~H"""
      <Components.command_palette jumon={@jumon} icons={["hero-user"]}>
        <:icon :let={name}><svg class={name}></svg></:icon>
      </Components.command_palette>
      """)

    {node, config} = palette(html)
    assert config["options"]["icons"] == true
    templates = LazyHTML.query(node, "template[data-jumon-icon]")

    assert Enum.map(templates, &(LazyHTML.attribute(&1, "data-jumon-icon") |> hd())) == [
             "hero-home",
             "hero-user"
           ]

    assert LazyHTML.to_html(templates) =~ ~s(<svg class="hero-home">)
  end

  test "a palette with words of its own" do
    assigns = %{jumon: jumon([])}

    html =
      rendered_to_string(~H"""
      <Components.command_palette jumon={@jumon} placeholder="Ask" messages={%{"recent" => "Lately"}} />
      """)

    {_node, config} = palette(html)
    assert config["messages"]["placeholder"] == "Ask"
    assert config["messages"]["recent"] == "Lately"

    assert_raise ArgumentError, ~r/unknown message keys/, fn ->
      rendered_to_string(~H"""
      <Components.command_palette jumon={@jumon} messages={%{"nope" => "x"}} />
      """)
    end
  end

  test "on a page without LiveView: the actions the browser can do alone" do
    assigns = %{conn: %Plug.Conn{assigns: %{user: %{id: 1, admin?: false, name: "Eve"}}}}

    html =
      rendered_to_string(~H"""
      <Components.command_palette commands={JumonTest.Commands} conn={@conn} />
      """)

    {_node, config} = palette(html)
    ids = Enum.map(config["actions"], & &1["id"])
    assert config["live"] == false
    assert ids == ["home", "settings", "theme", "light", "dark"]
  end

  test "the button that opens the palette" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Components.command_button for="jumon" />
      """)

    assert html =~ ~s(data-jumon-open="jumon")
    assert html =~ ~s(data-jumon-keys="mod+k")
    assert html =~ "<kbd>Ctrl</kbd>"
    assert html =~ "<kbd>K</kbd>"
    assert html =~ "Search or jump to…"
    assert html =~ "jumon:open"
  end

  test "the palette needs @jumon, or commands and a conn" do
    assigns = %{}

    assert_raise ArgumentError, ~r/needs jumon=/, fn ->
      rendered_to_string(~H"""
      <Components.command_palette />
      """)
    end
  end
end
