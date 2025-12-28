defmodule Cascade.DagLoaderTest do
  use Cascade.DataCase, async: false

  alias Cascade.DagLoader
  alias Cascade.DagLoader.{LocalSource, Validator}
  alias Cascade.Workflows

  describe "Validator" do
    test "validates valid DAG" do
      dag = %{
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"}
        ]
      }

      assert :ok = Validator.validate_dag(dag)
    end

    test "rejects DAG with missing nodes field" do
      dag = %{"edges" => []}

      assert {:error, message} = Validator.validate_dag(dag)
      assert message =~ "Missing required fields"
    end

    test "rejects DAG with duplicate node IDs" do
      dag = %{
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task1", "type" => "local", "config" => %{}}
        ],
        "edges" => []
      }

      assert {:error, message} = Validator.validate_dag(dag)
      assert message =~ "Duplicate node IDs"
    end

    test "rejects DAG with circular dependency" do
      dag = %{
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"},
          %{"from" => "task2", "to" => "task1"}
        ]
      }

      assert {:error, message} = Validator.validate_dag(dag)
      assert message =~ "cycle"
    end

    test "rejects DAG with edge referencing non-existent node" do
      dag = %{
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task_nonexistent"}
        ]
      }

      assert {:error, message} = Validator.validate_dag(dag)
      assert message =~ "valid 'from' and 'to' node IDs"
    end

    test "accepts DAG with no edges" do
      dag = %{
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}}
        ],
        "edges" => []
      }

      assert :ok = Validator.validate_dag(dag)
    end

    test "accepts DAG with complex dependency graph" do
      dag = %{
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}},
          %{"id" => "task3", "type" => "local", "config" => %{}},
          %{"id" => "task4", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task3"},
          %{"from" => "task2", "to" => "task3"},
          %{"from" => "task3", "to" => "task4"}
        ]
      }

      assert :ok = Validator.validate_dag(dag)
    end
  end

  describe "LocalSource" do
    setup do
      # Create temporary directory for test DAGs
      test_dir = Path.join(System.tmp_dir!(), "dag_loader_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "loads JSON DAG files", %{test_dir: test_dir} do
      dag_content = Jason.encode!(%{
        "nodes" => [%{"id" => "task1", "type" => "local", "config" => %{}}],
        "edges" => []
      })

      File.write!(Path.join(test_dir, "test_dag.json"), dag_content)

      source = %{type: :local, path: test_dir}
      dags = LocalSource.load_dags(source)

      assert length(dags) == 1
      [{name, content, source_info}] = dags
      assert name == "test_dag"
      assert content == dag_content
      assert source_info.extension == ".json"
    end

    test "loads Elixir .exs DAG files", %{test_dir: test_dir} do
      dag_content = """
      %{
        "nodes" => [%{"id" => "task1", "type" => "local", "config" => %{}}],
        "edges" => []
      }
      """

      File.write!(Path.join(test_dir, "test_dag.exs"), dag_content)

      source = %{type: :local, path: test_dir}
      dags = LocalSource.load_dags(source)

      assert length(dags) == 1
      [{name, content, source_info}] = dags
      assert name == "test_dag"
      assert content == dag_content
      assert source_info.extension == ".exs"
    end

    test "ignores non-DAG files", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "README.md"), "# Not a DAG")
      File.write!(Path.join(test_dir, "script.sh"), "#!/bin/bash")

      source = %{type: :local, path: test_dir}
      dags = LocalSource.load_dags(source)

      assert dags == []
    end

    test "loads multiple DAG files", %{test_dir: test_dir} do
      dag1 = Jason.encode!(%{"nodes" => [], "edges" => []})
      dag2 = Jason.encode!(%{"nodes" => [], "edges" => []})

      File.write!(Path.join(test_dir, "dag1.json"), dag1)
      File.write!(Path.join(test_dir, "dag2.json"), dag2)

      source = %{type: :local, path: test_dir}
      dags = LocalSource.load_dags(source)

      assert length(dags) == 2
      names = Enum.map(dags, fn {name, _, _} -> name end)
      assert "dag1" in names
      assert "dag2" in names
    end
  end

  describe "DagLoader integration" do
    @tag :skip
    test "loads DAG from default directory on startup" do
      # This test would require controlling the DagLoader lifecycle
      # Skipping for now as it requires more setup
    end
  end
end
