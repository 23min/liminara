for dir <- [Path.join(System.tmp_dir!(), "liminara_test_radar_lancedb")] do
	if File.dir?(dir), do: File.rm_rf!(dir)
end

ExUnit.start()
