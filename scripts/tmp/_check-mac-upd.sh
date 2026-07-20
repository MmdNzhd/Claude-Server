f=scripts/client/mac/connect-update.sh
grep -q 'IdentityAgent=none' "$f" && echo has_IA || echo miss_IA
grep -q '_run_timed' "$f" && echo has_timeout || echo miss_timeout
grep -q '_verify_checksums' "$f" && echo has_checksum || echo miss_checksum
grep -q '_swap_dir' "$f" && echo has_swap || echo miss_swap
bash -n "$f" && echo bash_n_ok
wc -l < "$f"
