#!/usr/bin/env bash
# Replays the real release history for french-gas-stations-scraper.
# Creates and pushes 41 real tags and publishes 41 real GitHub releases.
# Run from inside a clone of french-gas-stations-scraper.
set -euo pipefail

RELEASE_SH="E:/Git/GitHub/semantic-release-script/scripts/release/release.sh"

# v0.0.1
bash "$RELEASE_SH" -y --to 1ed47cf

# v0.0.2
bash "$RELEASE_SH" -y --since 1ed47cf --to f9146e3

# v0.0.3
bash "$RELEASE_SH" -y --since f9146e3 --to 432eb91

# v0.0.4
bash "$RELEASE_SH" -y --since 432eb91 --to d08c1fa

# v0.1.0
bash "$RELEASE_SH" -y --since d08c1fa --to ed7744a

# v0.2.0
bash "$RELEASE_SH" -y --since ed7744a --to 28354ce

# v0.3.0
bash "$RELEASE_SH" -y --since 28354ce --to e63b868

# v0.4.0
bash "$RELEASE_SH" -y --since e63b868 --to fc9862f

# v0.5.0
bash "$RELEASE_SH" -y --since fc9862f --to 4313ac3

# v0.6.0
bash "$RELEASE_SH" -y --since 4313ac3 --to 8dfbe25

# v0.6.1
bash "$RELEASE_SH" -y --since 8dfbe25 --to 7e151f5

# v0.6.2
bash "$RELEASE_SH" -y --since 7e151f5 --to 9cc6aee

# v0.6.3
bash "$RELEASE_SH" -y --since 9cc6aee --to 6bafa08

# v0.7.0
bash "$RELEASE_SH" -y --since 6bafa08 --to 88d2ee1

# v0.8.0
bash "$RELEASE_SH" -y --since 88d2ee1 --to 75a8198

# v0.9.0
bash "$RELEASE_SH" -y --since 75a8198 --to 24f2ed4

# v0.10.0
bash "$RELEASE_SH" -y --since 24f2ed4 --to 05022b6

# v0.10.1
bash "$RELEASE_SH" -y --since 05022b6 --to 84d89ba

# v0.11.0
bash "$RELEASE_SH" -y --since 84d89ba --to 40c1e64

# v0.11.1
bash "$RELEASE_SH" -y --since 40c1e64 --to d204c81

# v0.12.0
bash "$RELEASE_SH" -y --since d204c81 --to 0fb96ef

# v0.12.1
bash "$RELEASE_SH" -y --since 0fb96ef --to 873ad76

# v0.12.2
bash "$RELEASE_SH" -y --since 873ad76 --to 84a86ff

# v0.12.3
bash "$RELEASE_SH" -y --since 84a86ff --to 83a3b4e

# v0.13.0
bash "$RELEASE_SH" -y --since 83a3b4e --to 2b27a5d

# v0.14.0
bash "$RELEASE_SH" -y --since 2b27a5d --to 37367f2

# v0.15.0
bash "$RELEASE_SH" -y --since 37367f2 --to 615d661

# v0.16.0
bash "$RELEASE_SH" -y --since 615d661 --to fd42116

# v0.17.0
bash "$RELEASE_SH" -y --since fd42116 --to 5163118

# v0.18.0
bash "$RELEASE_SH" -y --since 5163118 --to 9d2d018

# v0.18.1
bash "$RELEASE_SH" -y --since 9d2d018 --to ccf26d1

# v0.19.0
bash "$RELEASE_SH" -y --since ccf26d1 --to 6ea706c

# v0.20.0
bash "$RELEASE_SH" -y --since 6ea706c --to 6cfcba6

# v0.21.0
bash "$RELEASE_SH" -y --since 6cfcba6 --to 6fd73e2

# v0.22.0
bash "$RELEASE_SH" -y --since 6fd73e2 --to b429460

# v0.23.0
bash "$RELEASE_SH" -y --since b429460 --to 5b3762c

# v0.24.0
bash "$RELEASE_SH" -y --since 5b3762c --to 09092fd

# v0.25.0
bash "$RELEASE_SH" -y --since 09092fd --to 0b41795

# v0.26.0
bash "$RELEASE_SH" -y --since 0b41795 --to 8755a44

# v0.27.0
bash "$RELEASE_SH" -y --since 8755a44 --to 5a1c41c

# v0.28.0
bash "$RELEASE_SH" -y --since 5a1c41c --to eaabb21

