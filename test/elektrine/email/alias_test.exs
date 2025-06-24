defmodule Elektrine.Email.AliasTest do
  use Elektrine.DataCase

  alias Elektrine.Email.Alias

  describe "changeset/2" do
    test "with valid attributes" do
      attrs = %{
        alias_email: "test@elektrine.com",
        target_email: "user@example.com",
        user_id: 1,
        enabled: true,
        description: "Test alias"
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert changeset.valid?
    end

    test "requires alias_email and user_id" do
      changeset = Alias.changeset(%Alias{}, %{})

      assert %{alias_email: ["can't be blank"]} = errors_on(changeset)
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email format for alias_email" do
      attrs = %{
        alias_email: "invalid-email",
        target_email: "user@example.com",
        user_id: 1
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert %{alias_email: ["must be a valid email format"]} = errors_on(changeset)
    end

    test "validates email format for target_email" do
      attrs = %{
        alias_email: "test@elektrine.com",
        target_email: "invalid-email",
        user_id: 1
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert %{target_email: ["must be a valid email format"]} = errors_on(changeset)
    end

    test "prevents alias_email and target_email from being the same" do
      attrs = %{
        alias_email: "test@elektrine.com",
        target_email: "test@elektrine.com",
        user_id: 1
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert %{target_email: ["cannot be the same as the alias email"]} = errors_on(changeset)
    end

    test "validates length constraints" do
      attrs = %{
        alias_email: String.duplicate("a", 250) <> "@elektrine.com",
        target_email: String.duplicate("b", 250) <> "@example.com",
        description: String.duplicate("c", 501),
        user_id: 1
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert %{alias_email: ["should be at most 255 character(s)"]} = errors_on(changeset)
      assert %{target_email: ["should be at most 255 character(s)"]} = errors_on(changeset)
      assert %{description: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end

    test "allows alias without target_email" do
      attrs = %{
        alias_email: "test@elektrine.com",
        user_id: 1,
        enabled: true,
        description: "Test alias without forwarding"
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert changeset.valid?
    end

    test "allows alias with empty target_email" do
      attrs = %{
        alias_email: "test@elektrine.com",
        target_email: "",
        user_id: 1,
        enabled: true
      }

      changeset = Alias.changeset(%Alias{}, attrs)

      assert changeset.valid?
    end

    test "validates allowed domains for alias_email" do
      # Valid domains
      for domain <- ["elektrine.com", "z.org"] do
        attrs = %{
          alias_email: "test@#{domain}",
          user_id: 1
        }

        changeset = Alias.changeset(%Alias{}, attrs)
        assert changeset.valid?, "#{domain} should be a valid domain"
      end
    end

    test "rejects invalid domains for alias_email" do
      invalid_domains = ["gmail.com", "example.com", "mydomain.org", "test.net"]

      for domain <- invalid_domains do
        attrs = %{
          alias_email: "test@#{domain}",
          user_id: 1
        }

        changeset = Alias.changeset(%Alias{}, attrs)
        refute changeset.valid?, "#{domain} should be rejected"
        assert %{alias_email: [error]} = errors_on(changeset)
        assert String.contains?(error, "must use one of the allowed domains")
      end
    end

    test "domain validation is case insensitive" do
      # Mixed case domains should work
      for domain <- ["ELEKTRINE.COM", "Z.ORG", "Elektrine.Com", "z.Org"] do
        attrs = %{
          alias_email: "test@#{domain}",
          user_id: 1
        }

        changeset = Alias.changeset(%Alias{}, attrs)
        assert changeset.valid?, "#{domain} should be valid (case insensitive)"
      end
    end
  end
end
