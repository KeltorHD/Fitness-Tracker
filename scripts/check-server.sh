#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-$PWD/.build/dotnet-home}"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$PWD/.build/nuget}"
export DOTNET_NOLOGO=1
dotnet restore FitLife.Server.sln --locked-mode
dotnet build FitLife.Server.sln --no-restore --disable-build-servers -m:1
test_flags=(--filter 'Category!=PostgreSQL')
if [[ -n "${FITNESS_TRACKER_TEST_POSTGRES:-}" ]]; then test_flags=(); fi
dotnet test FitLife.Server.sln --no-build --no-restore -m:1 "${test_flags[@]}"
dotnet format FitLife.Server.sln --verify-no-changes --no-restore
bash -n scripts/setup-server.sh scripts/check-server.sh
python3 -m unittest discover -s Tests/Scripts -p 'test_server_network.py'
python3 -m py_compile scripts/setup-backend-keys.py
