# Clean up stale test artifacts from previous runs
for dir <- [
      Path.join(System.tmp_dir!(), "liminara_runs"),
      Path.join(System.tmp_dir!(), "liminara_store")
    ] do
  if File.dir?(dir), do: File.rm_rf!(dir)
end

ExUnit.start(exclude: [deferred_stored_plan: true])
