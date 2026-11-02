#!/bin/zsh

print 'Before the first run, authenticate and clear the cache: sudo -v && sudo purge'
read 'reply?Press Enter to run that command, or Ctrl-C to cancel: '
sudo -v && sudo purge || exit 1

typeset -a results
for concurrency in 2 4 8 16; do
    for bucket in 5 10 25; do
        if (( ${#results} > 0 )); then
            sudo -n purge || exit 1
        fi

        print "\nConcurrency: $concurrency | FFmpeg bucket: $bucket"
        output=$(/Users/francois/.swiftpm/bin/test-hash \
            /Volumes/Ext-6TB-2/HashTestVids "$concurrency" "$bucket" 2>&1)
        run_status=$?
        print -r -- "$output"
        last_line=${${(f)output}[-1]}
        if (( run_status != 0 )); then
            last_line="FAILED (exit $run_status)"
        fi
        results+=("$(printf '%-14s %-14s %s' "$concurrency" "$bucket" "$last_line")")
    done
done

print '\nResults'
printf '%-14s %-14s %s\n' 'Concurrency' 'FFmpeg bucket' 'Total time'
printf '%s\n' "${results[@]}"
