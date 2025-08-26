https://forgejo.org/docs/latest/admin/actions/runner-installation/

# register runner to forgejo

```sh
bash runner.sh --build

# Get the runner's token from forgejo web ui.
export FORGEJO_RUNNER_TOKEN="MGlqVKv7iOmjYKbswisPxCudgUFD91GeoZySKFz4"
bash runner.sh --register

bash runner.sh --start
```

TODOs

- cache issue.